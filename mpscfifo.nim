## A MpscFifo is a wait free/thread safe multi-producer
## single consumer first in first out queue. This algorithm
## is from Dimitry Vyukov's non intrusive MPSC code here:
##   http://www.1024cores.net/home/lock-free-algorithms/queues/non-intrusive-mpsc-node-based-queue
##
## The fifo has a head and at tail, the elements are added
## to the tail of the queue and removed from the head.
## Rather than storing the elements directly in the queue
## link nodes are used which have two fields, next and
## extra. The next field point so the next element in the
## list of nil if there no ext element. The extra field
## points to the invokers data.
##
## ....
##

import msg, msgarena, msgloopertypes, locks, strutils

const
  DBG = false

type
  Blocking* = enum
    blockIfEmpty, nilIfEmpty

  MsgQueue* = object of Queue
    name*: string
    blocking*: Blocking
    ownsCondAndLock*: bool
    condBool*: ptr bool
    cond*: ptr TCond
    lock*: ptr TLock
    arena: MsgArenaPtr
    head*: MsgPtr
    tail*: MsgPtr
  MsgQueuePtr* = ptr MsgQueue

proc `$`*(mq: MsgQueuePtr): string =
  result =
    if mq == nil:
      "<nil>"
    else:
      "{" & $mq.name & ":" &
        " head=" & $mq.head &
        " tail=" & $mq.tail &
      "}"

proc isEmpty(mq: MsgQueuePtr): bool {.inline.} =
  ## Check if empty is only useful if its known that
  ## no other threads are using the queue. Therefore
  ## this is private and only used in delMpscFifo and
  ## testing.
  result = mq.head.next == nil

proc newMpscFifo*(name: string, arena: MsgArenaPtr,
    owner: bool, condBool: ptr bool, cond: ptr TCond, lock: ptr TLock,
    blocking: Blocking): MsgQueuePtr =
  ## Create a new Fifo
  var mq = cast[MsgQueuePtr](allocShared(sizeof(MsgQueue)))
  when DBG:
    proc dbg(s:string) = echo name & ".newMpscFifo(name,ma):" & s
    dbg "+"

  mq.name = name
  mq.arena = arena
  mq.blocking = blocking
  mq.ownsCondAndLock = owner
  mq.condBool = condBool
  mq.cond = cond
  mq.lock = lock
  var mn = mq.arena.getMsg(nil, nil, 0, 0)
  mq.head = mn
  mq.tail = mn
  result = mq

  when DBG: dbg "- mq=" & $mq

proc newMpscFifo*(name: string, arena: MsgArenaPtr, blocking: Blocking):
    MsgQueuePtr =
  ## Create a new Fifo
  var
    owned = false
    condBool: ptr bool = nil
    cond: ptr TCond = nil
    lock: ptr TLock = nil

  if blocking == blockIfEmpty:
    owned = true
    condBool = cast[ptr bool](allocShared(sizeof(bool)))
    cond = cast[ptr TCond](allocShared(sizeof(TCond)))
    lock = cast[ptr TLock](allocShared(sizeof(TLock)))
    condBool[] = false
    cond[].initCond()
    lock[].initLock()

  result = newMpscFifo(name, arena, owned, condBool, cond, lock, blocking)

proc newMpscFifo*(name: string, arena: MsgArenaPtr): MsgQueuePtr =
  ## Create a new Fifo will block on rmv's if empty
  newMpscFifo(name, arena, blockIfEmpty)

proc newMpscFifo*(name: string, arena: MsgArenaPtr, lpr: MsgLooperPtr):
      MsgQueuePtr =
  ## Create a new fifo for which lpr receives and dispatchs the msg
  result = newMpscFifo(name, arena, false, lpr.condBool, lpr.cond, lpr.lock,
    blockIfEmpty)

proc delMpscFifo*(qp: QueuePtr) =
  var mq = cast[MsgQueuePtr](qp)
  when DBG:
    proc dbg(s:string) = echo mq.name & ".delMpscFifo:" & s
    dbg "+ mq=" & $mq

  doAssert(mq.isEmpty())
  mq.arena.retMsg(mq.head)
  if mq.ownsCondAndLock:
    if mq.condBool != nil:
      freeShared(mq.condBool)
    if mq.cond != nil:
      mq.cond[].deinitCond()
      freeShared(mq.cond)
    if mq.lock != nil:
      mq.lock[].deinitLock()
      freeShared(mq.lock)
  mq.arena = nil
  mq.head = nil
  mq.tail = nil
  GcUnref(mq.name)
  deallocShared(mq)

  when DBG: dbg "-"

proc add*(q: QueuePtr, msg: MsgPtr) =
  ## Add the link node to the fifo
  if msg != nil:
    var mq = cast[MsgQueuePtr](q)
    when DBG:
      proc dbg(s:string) = echo mq.name & ".addNode:" & s
      dbg "+ msg=" & $msg & " mq=" & $mq

    # Be sure msg.next is nil as it must be
    msg.next =  nil

    # serialization-piont wrt to the single consumer, acquire-release
    var prevTail = atomicExchangeN(addr mq.tail, msg, ATOMIC_ACQ_REL)
    atomicStoreN(addr prevTail.next, msg, ATOMIC_RELEASE)
    if mq.blocking == blockIfEmpty:
      mq.lock[].acquire()
      var prevCondBool = atomicExchangeN(mq.condBool, true, ATOMIC_RELEASE)
      #if not prevCondBool:
      block:
        # We've transitioned from false to true so signal
        when DBG: dbg "  NOT-EMPTY signal cond"
        mq.cond[].signal()
      mq.lock[].release

    when DBG: dbg "- mq=" & $mq

proc rmv*(q: QueuePtr, blocking: Blocking): MsgPtr =
  ## Return the next msg from the fifo if the queue is
  ## empty block of blockOnEmpty is true else return nil
  ##
  ## May only be called from the consumer
  var mq = cast[MsgQueuePtr](q)
  when DBG:
    proc dbg(s:string) = echo mq.name & ".rmv:" & s
    dbg "+ mq=" & $mq

  while true:
    var head = mq.head
    when DBG: dbg " head=" & $head
    # serialization-point wrt producers, acquire
    var next = cast[MsgPtr](atomicLoadN(addr head.next, ATOMIC_ACQUIRE))

    when DBG: dbg " next=" & $next
    if next != nil:
      # Not empty mq.head.next.extra is the users data
      # and it will be returned in the stub LinkNode
      # pointed to by mq.head.

      if mq.blocking == blockIfEmpty:
        # Note: here we check the mq.blocking field not the blocking
        # parameter to this proc. We do this because even if the
        # blocking parameter is nilIfEmpty we must still set mq.condBool
        # properly if the queue itself is blocking. Otherwise addNode
        # won't signal the condition because mq.condBool doesn't change
        # and we'll hang.
        #
        # Here we set mq.condBool to false if we've just taken the last
        # element from the queue.
        mq.lock[].acquire()
        if next.next == nil:
          when DBG: dbg " EMPTY"
          ## TODO: Should we really do this if we're not the owner?
          ## if we're not the owner for instance we're sharing a looper
          ## with other components then it should be set to false when
          ## everyone is EMPTY????
          atomicStoreN(mq.condBool, false, ATOMIC_RELEASE)
        mq.lock[].release()

      # Have head point to next (aka mq.head.next) as it will be the
      # new stub LinkNode
      mq.head = next

      # And head, the old stub LinkNode aka mq.head is result
      # and we set result.next to nil so the link node is
      # ready to be reused and result.extra contains the
      # users data i.e. mq.head.next.extra.
      result = head
      result.next = nil
      result.rspq = next.rspq
      result.cmd = next.cmd

      # We've got a node break out of the loop
      break
    else:
      if blocking == blockIfEmpty:
        # TODO: Maybe throw an exception if lock and or cond are nil?
        mq.lock[].acquire()
        while not mq.condBool[]:
          when DBG: dbg "waiting"
          mq.cond[].wait(mq.lock[])
          when DBG: dbg "DONE waiting"
        mq.lock[].release()

        # Continue in the loop
      else:
        # Do not block so return nil
        result = nil
        break

  when DBG: dbg "- msg=" & $result & " mq=" & $mq

proc rmv*(q: QueuePtr): MsgPtr {.inline.} =
  ## Return the next link node from the fifo or if empty and
  ## this is a non-blocking queue then returns nil.
  ##
  ## May only be called from the consumer
  var mq = cast[MsgQueuePtr](q)
  result = rmv(q, mq.blocking)


when isMainModule:
  import unittest

  suite "test mpscfifo":
    var ma: MsgArenaPtr

    setup:
      ma = newMsgArena()
    teardown:
      ma.delMsgArena()

    #test "test we can create and delete fifo":
    #  var mq = newMpscFifo("mq", ma)
    #  mq.delMpscFifo()

    test "test new queue is empty":
      var mq = newMpscFifo("mq", ma)
      var msg: MsgPtr

      # rmv from empty queue
      msg = mq.rmv(nilIfEmpty)
      check(mq.isEmpty())

      mq.delMpscFifo()

    test "test new queue is empty twice":
      var mq = newMpscFifo("mq", ma)
      var msg: MsgPtr

      # rmv from empty queue
      msg = mq.rmv(nilIfEmpty)
      check(mq.isEmpty())

      # rmv from empty queue
      msg = mq.rmv(nilIfEmpty)
      check(mq.isEmpty())

      mq.delMpscFifo()

    test "test add, rmv blocking":
      var mq = newMpscFifo("mq", ma, blockIfEmpty)
      var msg: MsgPtr

      # add 1
      msg = ma.getMsg(nil, nil, 1, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 1
      msg = mq.rmv()
      check(mq.isEmpty())
      check(msg.cmd == 1)
      ma.retMsg(msg)

      mq.delMpscFifo()

    test "test add, rmv non-blocking":
      var mq = newMpscFifo("mq", ma, nilIfEmpty)
      var msg: MsgPtr

      # add 1
      msg = ma.getMsg(nil, nil, 1, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 1
      msg = mq.rmv()
      check(mq.isEmpty())
      check(msg.cmd == 1)
      ma.retMsg(msg)

      mq.delMpscFifo()

    test "test add, rmv, add, rmv, blocking":
      var mq = newMpscFifo("mq", ma, blockIfEmpty)
      var msg: MsgPtr

      # add 1
      msg = ma.getMsg(nil, nil, 1, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 1
      msg = mq.rmv()
      check(mq.isEmpty())
      check(msg.cmd == 1)
      ma.retMsg(msg)

      # add 2
      msg = ma.getMsg(nil, nil, 2, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 2
      msg = mq.rmv()
      check(mq.isEmpty())
      check(msg.cmd == 2)
      ma.retMsg(msg)

    test "test add, rmv, add, rmv, non-blocking":
      var mq = newMpscFifo("mq", ma, nilIfEmpty)
      var msg: MsgPtr

      # add 1
      msg = ma.getMsg(nil, nil, 1, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 1
      msg = mq.rmv()
      check(mq.isEmpty())
      check(msg.cmd == 1)
      ma.retMsg(msg)

      # add 2
      msg = ma.getMsg(nil, nil, 2, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 2
      msg = mq.rmv()
      check(mq.isEmpty())
      check(msg.cmd == 2)
      ma.retMsg(msg)

    test "test add, rmv, add, add, rmv, rmv, blocking":
      var mq = newMpscFifo("mq", ma, blockIfEmpty)
      var msg: MsgPtr

      # add 1
      msg = ma.getMsg(nil, nil, 1, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 1
      msg = mq.rmv()
      check(mq.isEmpty())
      check(msg.cmd == 1)
      ma.retMsg(msg)

      # add 2, add 3
      msg = ma.getMsg(nil, nil, 2, 0)
      mq.add(msg)
      check(not mq.isEmpty())
      msg = ma.getMsg(nil, nil, 3, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 2
      msg = mq.rmv()
      check(msg.cmd == 2)
      check(not mq.isEmpty())
      ma.retMsg(msg)

      # rmv 3
      msg = mq.rmv()
      check(msg.cmd == 3)
      check(mq.isEmpty())
      ma.retMsg(msg)

      mq.delMpscFifo()

    test "test add, rmv, add, add, rmv, rmv, non-blocking":
      var mq = newMpscFifo("mq", ma, nilIfEmpty)
      var msg: MsgPtr

      # add 1
      msg = ma.getMsg(nil, nil, 1, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 1
      msg = mq.rmv()
      check(mq.isEmpty())
      check(msg.cmd == 1)
      ma.retMsg(msg)

      # add 2, add 3
      msg = ma.getMsg(nil, nil, 2, 0)
      mq.add(msg)
      check(not mq.isEmpty())
      msg = ma.getMsg(nil, nil, 3, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 2
      msg = mq.rmv()
      check(msg.cmd == 2)
      check(not mq.isEmpty())
      ma.retMsg(msg)

      # rmv 3
      msg = mq.rmv()
      check(msg.cmd == 3)
      check(mq.isEmpty())
      ma.retMsg(msg)

      mq.delMpscFifo()
