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
# At this time I couldn't figure out a good way for
# addTail to return a boolean indicating if the msg
# was added to an empty queue. The problem is empty
# is defined by head.next == nil but we add to the
# tail and in this MPSC queue we can't make two items
# atomic at the same time. So for now we'll not
# have that information.

import msg, msgarena, linknode, locks, strutils

const DBG = false

type
  Blocking* = enum
    blockIfEmpty, nilIfEmpty

  MsgQueue* = object of Queue
    name*: string
    blocking*: Blocking
    empty*: bool
    ownsCondAndLock*: bool
    cond*: ptr TCond
    lock*: ptr TLock
    arena: MsgArenaPtr
    head*: LinkNodePtr
    tail*: LinkNodePtr
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
  ## TODO: Use mq.empty???
  ## Check if empty is only useful if its known that
  ## no other threads are using the queue. Therefore
  ## this is private and only used in delMpscFifo and
  ## testing.
  result = mq.head.next == nil

proc newMpscFifo*(name: string, arena: MsgArenaPtr,
    owner: bool, cond: ptr TCond, lock: ptr TLock,
    blocking: Blocking): MsgQueuePtr =
  ## Create a new Fifo
  var mq = cast[MsgQueuePtr](allocShared(sizeof(MsgQueue)))
  proc dbg(s:string) = echo name & ".newMpscFifo(name,ma):" & s
  when DBG: dbg "+"

  mq.name = "heck"
  echo "mq=", mq
  mq.name = name
  mq.arena = arena
  mq.blocking = blocking
  mq.empty = true
  mq.ownsCondAndLock = owner
  mq.cond = cond
  mq.lock = lock
  var ln = mq.arena.getLinkNode(nil, nil)
  mq.head = ln
  mq.tail = ln
  result = mq

  when DBG: dbg "- mq=" & $mq

proc newMpscFifo*(name: string, arena: MsgArenaPtr, blocking: Blocking):
    MsgQueuePtr =
  ## Create a new Fifo
  var
    owned = false
    cond: ptr TCond = nil
    lock: ptr TLock = nil

  if blocking == blockIfEmpty:
    owned = true
    cond = cast[ptr TCond](allocShared(sizeof(TCond)))
    lock = cast[ptr TLock](allocShared(sizeof(TLock)))
    cond[].initCond()
    lock[].initLock()

  newMpscFifo(name, arena, owned, cond, lock, blocking)

proc newMpscFifo*(name: string, arena: MsgArenaPtr): MsgQueuePtr =
  ## Create a new Fifo will block on rmv's if empty
  newMpscFifo(name, arena, blockIfEmpty)

proc delMpscFifo*(qp: QueuePtr) =
  var mq = cast[MsgQueuePtr](qp)
  proc dbg(s:string) = echo mq.name & ".delMpscFifo:" & s
  when DBG: dbg "+ mq=" & $mq

  doAssert(mq.isEmpty())
  mq.arena.retLinkNode(mq.head)
  if mq.ownsCondAndLock:
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

proc addNode*(q: QueuePtr, ln: LinkNodePtr) =
  ## Add the link node to the fifo
  if ln != nil:
    var mq = cast[MsgQueuePtr](q)
    proc dbg(s:string) = echo mq.name & ".addNode:" & s
    when DBG: dbg "+ ln=" & $ln & " mq=" & $mq

    # serialization-piont wrt to the single consumer, acquire-release
    var prevTail = atomicExchangeN(addr mq.tail, ln, ATOMIC_ACQ_REL)
    atomicStoreN(addr prevTail.next, ln, ATOMIC_RELEASE)
    if mq.blocking == blockIfEmpty:
      var prevEmpty = atomicExchangeN(addr mq.empty, false, ATOMIC_RELEASE)
      if prevEmpty and mq.cond != nil:
        when DBG: dbg "  signal cond"
        mq.cond[].signal()

    when DBG: dbg "- mq=" & $mq

proc add*(q: QueuePtr, msg: MsgPtr) =
  ## Add msg to the fifo
  if msg != nil:
    var mq = cast[MsgQueuePtr](q)
    var ln = mq.arena.getLinkNode(nil, msg)
    addNode(q, ln)

proc rmvNode*(q: QueuePtr, blocking: Blocking): LinkNodePtr =
  ## Return the next msg from the fifo if the queue is
  ## empty block of blockOnEmpty is true else return nil
  ##
  ## May only be called from the consumer
  var mq = cast[MsgQueuePtr](q)
  proc dbg(s:string) = echo mq.name & ".rmvNode:" & s
  when DBG: dbg "+ mq=" & $mq

  block retry:
    var head = mq.head
    when DBG: dbg " head=" & $head
    # serialization-point wrt producers, acquire
    var next = cast[LinkNodePtr](atomicLoadN(addr head.next, ATOMIC_ACQUIRE))

    when DBG: dbg " next=" & $next
    if next != nil:
      # If mq.head.next.next == nil we are getting the last
      # node so we're empty.
      # TODO: There is a race but ignore for the moment
      atomicStoreN(addr mq.empty, next.next == nil, ATOMIC_RELEASE)

      # Guess that it will be empty

      # Not empty mq.head.next.extra is the users data
      # and it will be returned in the stub LinkNode
      # pointed to by mq.head.

      # next (aka mq.head.next) is the new stub LinkNode
      mq.head = next
      # And head, the old stub LinkNode aka mq.head is result
      # and we set result.next to nil so the link node is
      # ready to be reused and result.extra contains the
      # users data i.e. mq.head.next.extra.
      result = head
      result.next = nil
      result.extra = next.extra
    else:
      if blocking == blockIfEmpty and mq.lock != nil and mq.cond != nil:
        mq.lock[].acquire()
        atomicStoreN(addr mq.empty, true, ATOMIC_RELEASE)
        while mq.empty:
          when DBG: dbg "waiting"
          mq.cond[].wait(mq.lock[])
          when DBG: dbg "DONE waiting"
        mq.lock[].release()
        break retry

  when DBG: dbg "- ln=" & $result & " mq=" & $mq

proc rmvNode*(q: QueuePtr): LinkNodePtr {.inline.} =
  ## Return the next link node from the fifo or if empty and
  ## this is a non-blocking queue then returns nil.
  ##
  ## May only be called from the consumer
  var mq = cast[MsgQueuePtr](q)
  result = rmvNode(q, mq.blocking)

proc rmv*(q: QueuePtr, blocking: Blocking): MsgPtr {.inline.} =
  ## Return the next msg from the fifo if the queue is
  ## empty block of blockOnEmpty is true else return nil
  ##
  ## May only be called from the consumer
  var mq = cast[MsgQueuePtr](q)
  var ln = mq.rmvNode(blocking)
  if ln == nil:
    result = nil
  else:
    result = toMsg(ln.extra)
    mq.arena.retLinkNode(ln)

proc rmv*(q: QueuePtr): MsgPtr {.inline.} =
  ## Return the next msg from the fifo or if empty and
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
      msg = ma.getMsg(1, 0)
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
    #  var msg: MsgPtr

    #   add 1
    #  msg = ma.getMsg(1, 0)
    #  mq.add(msg)
    #  check(not mq.isEmpty())

    #   rmv 1
    #  msg = mq.rmv()
    #  check(mq.isEmpty())
    #  check(msg.cmd == 1)
    #  ma.retMsg(msg)

    #  mq.delMpscFifo()

    #test "test add, rmv node blocking 0":
    #  var mq = newMpscFifo("mq", ma, blockIfEmpty)
    #  var msg: MsgPtr
    #  var ln: LinkNodePtr

    #  msg = ma.getMsg(1, 0)
    #  ln = ma.getLinkNode(nil, msg)
    #  mq.addNode(ln)
    #  check(not mq.isEmpty())

    #  ln = mq.rmvNode()
    #  check(mq.isEmpty())
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 1)
    #  ma.retLinkNode(ln)
    #  ma.retMsg(msg)

    #  mq.delMpscFifo()

    #test "test add, rmv node blocking 1":
    #  var mq = newMpscFifo("mq", ma, blockIfEmpty)
    #  var msg: MsgPtr
    #  var ln: LinkNodePtr

    #  msg = ma.getMsg(1, 0)
    #  ln = ma.getLinkNode(nil, msg)
    #  mq.addNode(ln)
    #  check(not mq.isEmpty())

    #  ln = mq.rmvNode()
    #  check(mq.isEmpty())
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 1)
    #  ma.retMsg(msg)
    #  ma.retLinkNode(ln)

    #  mq.delMpscFifo()

    #test "test add, rmv node non-blocking":
    #  var mq = newMpscFifo("mq", ma, nilIfEmpty)
    #  var msg = ma.getMsg(1, 0)
    #  var ln = ma.getLinkNode(nil, msg)
    #  mq.addNode(ln)
    #  check(not mq.isEmpty())

    #  ln = mq.rmvNode()
    #  check(mq.isEmpty())
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 1)
    #  ma.retMsg(msg)
    #  ma.retLinkNode(ln)

    #  mq.delMpscFifo()

    #test "test reusing node non-blocking":
    #  var mq = newMpscFifo("mq", ma, nilIfEmpty)
    #  var msg: MsgPtr
    #  var ln: LinkNodePtr

    #  msg = ma.getMsg(1, 0)
    #  ln = ma.getLinkNode(nil, msg)
    #  mq.addNode(ln)
    #  ln = mq.rmvNode()
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 1)
    #  ma.retMsg(msg)

    #  when true:
    #    msg = ma.getMsg(2, 0)
    #    ln.initLinkNode(nil, msg)
    #    mq.addNode(ln)
    #    ln = mq.rmvNode()
    #    msg = toMsg(ln.extra)
    #    check(msg.cmd == 2)

    #  ma.retLinkNode(ln)

    #  mq.delMpscFifo()

    #test "test add, rmv, add, rmv, blocking":
    #  var mq = newMpscFifo("mq", ma, blockIfEmpty)
    #  var msg: MsgPtr

    #  # add 1
    #  msg = ma.getMsg(1, 0)
    #  mq.add(msg)
    #  check(not mq.isEmpty())

    #  # rmv 1
    #  msg = mq.rmv()
    #  check(mq.isEmpty())
    #  check(msg.cmd == 1)
    #  ma.retMsg(msg)

    #  # add 2
    #  msg = ma.getMsg(2, 0)
    #  mq.add(msg)
    #  check(not mq.isEmpty())

    #  # rmv 2
    #  msg = mq.rmv()
    #  check(mq.isEmpty())
    #  check(msg.cmd == 2)
    #  ma.retMsg(msg)

    #test "test add, rmv, add, rmv, non-blocking":
    #  var mq = newMpscFifo("mq", ma, nilIfEmpty)
    #  var msg: MsgPtr

    #  # add 1
    #  msg = ma.getMsg(1, 0)
    #  mq.add(msg)
    #  check(not mq.isEmpty())

    #  # rmv 1
    #  msg = mq.rmv()
    #  check(mq.isEmpty())
    #  check(msg.cmd == 1)
    #  ma.retMsg(msg)

    #  # add 2
    #  msg = ma.getMsg(2, 0)
    #  mq.add(msg)
    #  check(not mq.isEmpty())

    #  # rmv 2
    #  msg = mq.rmv()
    #  check(mq.isEmpty())
    #  check(msg.cmd == 2)
    #  ma.retMsg(msg)

    #test "test add, rmv, add, rmv node, blocking":
    #  var mq = newMpscFifo("mq", ma, blockIfEmpty)
    #  var msg: MsgPtr
    #  var ln: LinkNodePtr

    #  # add 1
    #  msg = ma.getMsg(1, 0)
    #  ln = ma.getLinkNode(nil, msg)
    #  mq.addNode(ln)
    #  check(not mq.isEmpty())

    #  # rmv 1
    #  ln = mq.rmvNode()
    #  check(mq.isEmpty())
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 1)
    #  ma.retMsg(msg)
    #  ma.retLinkNode(ln)

    #  # add 2
    #  msg = ma.getMsg(2, 0)
    #  ln = ma.getLinkNode(nil, msg)
    #  mq.addNode(ln)
    #  check(not mq.isEmpty())

    #  # rmv 2
    #  ln = mq.rmvNode()
    #  check(mq.isEmpty())
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 2)
    #  ma.retMsg(msg)
    #  ma.retLinkNode(ln)

    #  mq.delMpscFifo()

    #test "test add, rmv, add, rmv node, non-blocking":
    #  var mq = newMpscFifo("mq", ma, nilIfEmpty)
    #  var msg: MsgPtr
    #  var ln: LinkNodePtr

    #  # add 1
    #  msg = ma.getMsg(1, 0)
    #  ln = ma.getLinkNode(nil, msg)
    #  mq.addNode(ln)
    #  check(not mq.isEmpty())

    #  # rmv 1
    #  ln = mq.rmvNode()
    #  check(mq.isEmpty())
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 1)
    #  ma.retMsg(msg)
    #  ma.retLinkNode(ln)

    #  # add 2
    #  msg = ma.getMsg(2, 0)
    #  ln = ma.getLinkNode(nil, msg)
    #  mq.addNode(ln)
    #  check(not mq.isEmpty())

    #  # rmv 2
    #  ln = mq.rmvNode()
    #  check(mq.isEmpty())
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 2)
    #  ma.retMsg(msg)
    #  ma.retLinkNode(ln)

    #  mq.delMpscFifo()

    #test "test add, rmv, add, add, rmv, rmv, blocking":
    #  var mq = newMpscFifo("mq", ma, blockIfEmpty)
    #  var msg: MsgPtr

    #  # add 1
    #  msg = ma.getMsg(1, 0)
    #  mq.add(msg)
    #  check(not mq.isEmpty())

    #  # rmv 1
    #  msg = mq.rmv()
    #  check(mq.isEmpty())
    #  check(msg.cmd == 1)
    #  ma.retMsg(msg)

    #  # add 2, add 3
    #  msg = ma.getMsg(2, 0)
    #  mq.add(msg)
    #  check(not mq.isEmpty())
    #  msg = ma.getMsg(3, 0)
    #  mq.add(msg)
    #  check(not mq.isEmpty())

    #  # rmv 2
    #  msg = mq.rmv()
    #  check(msg.cmd == 2)
    #  check(not mq.isEmpty())
    #  ma.retMsg(msg)

    #  # rmv 3
    #  msg = mq.rmv()
    #  check(msg.cmd == 3)
    #  check(mq.isEmpty())
    #  ma.retMsg(msg)

    #  mq.delMpscFifo()

    #test "test add, rmv, add, add, rmv, rmv node, blocking":
    #  var mq = newMpscFifo("mq", ma, blockIfEmpty)
    #  var msg: MsgPtr
    #  var ln: LinkNodePtr

    #  # add 1
    #  msg = ma.getMsg(1, 0)
    #  ln = ma.getLinkNode(nil, msg)
    #  mq.addNode(ln)
    #  check(not mq.isEmpty())

    #  # rmv 1
    #  ln = mq.rmvNode()
    #  check(mq.isEmpty())
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 1)
    #  ma.retMsg(msg)
    #  ma.retLinkNode(ln)

    #  # add 2, add 3
    #  msg = ma.getMsg(2, 0)
    #  ln = ma.getLinkNode(nil, msg)
    #  mq.addNode(ln)
    #  check(not mq.isEmpty())
    #  msg = ma.getMsg(3, 0)
    #  ln = ma.getLinkNode(nil, msg)
    #  mq.addNode(ln)
    #  check(not mq.isEmpty())

    #  # rmv 2
    #  ln = mq.rmvNode()
    #  check(not mq.isEmpty())
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 2)
    #  ma.retMsg(msg)
    #  ma.retLinkNode(ln)

    #  # rmv 3
    #  ln = mq.rmvNode()
    #  check(mq.isEmpty())
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 3)
    #  ma.retMsg(msg)
    #  ma.retLinkNode(ln)

    #  mq.delMpscFifo()

