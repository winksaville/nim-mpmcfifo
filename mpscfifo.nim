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
  MsgQueue* = object of Queue
    name*: string
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
  ## Check if empty is only useful if its known that
  ## no other threads are using the queue. Therefore
  ## this is private and only used in delMpscFifo and
  ## testing.
  result = mq.head.next == nil

proc newMpscFifo*(name: string, arena: MsgArenaPtr): MsgQueuePtr =
  ## Create a new Fifo
  var mq = cast[MsgQueuePtr](allocShared(sizeof(MsgQueue)))
  proc dbg(s:string) = echo name & ".newMpscFifo(name,ma):" & s
  when DBG: dbg "+"

  mq.name = name
  mq.arena = arena
  var ln = mq.arena.getLinkNode(nil, nil)
  mq.head = ln
  mq.tail = ln
  result = mq

  when DBG: dbg "- mq=" & $mq

proc delMpscFifo*(qp: QueuePtr) =
  var mq = cast[MsgQueuePtr](qp)
  proc dbg(s:string) = echo mq.name & ".delMpscFifo:" & s
  when DBG: dbg "+ mq=" & $mq

  doAssert(mq.isEmpty())
  mq.arena.retLinkNode(mq.head)
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

    when DBG: dbg "- mq=" & $mq

proc add*(q: QueuePtr, msg: MsgPtr) =
  ## Add msg to the fifo
  if msg != nil:
    var mq = cast[MsgQueuePtr](q)
    var ln = mq.arena.getLinkNode(nil, msg)
    addNode(q, ln)

proc rmvNode*(q: QueuePtr): LinkNodePtr =
  ## Return the next fifo link node or nil if empty
  ## May only be called from consumer.
  var mq = cast[MsgQueuePtr](q)
  proc dbg(s:string) = echo mq.name & ".rmvNode:" & s
  when DBG: dbg "+ mq=" & $mq

  var head = mq.head
  when DBG: dbg " head=" & $head
  # serialization-point wrt producers, acquire
  var next = cast[LinkNodePtr](atomicLoadN(addr head.next, ATOMIC_ACQUIRE))
  when DBG: dbg " next=" & $next
  if next != nil:
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
    # Empty
    result = nil
  when DBG: dbg "- ln=" & $result & " mq=" & $mq

proc rmv*(q: QueuePtr): MsgPtr =
  ## Return the next msg from the fifo or nil if empty
  ## May only be called from the consumer
  var mq = cast[MsgQueuePtr](q)
  var ln = mq.rmvNode()
  if ln == nil:
    result = nil
  else:
    result = toMsg(ln.extra)
    mq.arena.retLinkNode(ln)

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

    #test "test new queue is empty":
    #  var mq = newMpscFifo("mq", ma)
    #  var msg: MsgPtr

    #  # rmv from empty queue
    #  msg = mq.rmv()
    #  check(mq.isEmpty())

    #  mq.delMpscFifo()

    #test "test new queue is empty twice":
    #  var mq = newMpscFifo("mq", ma)
    #  var msg: MsgPtr

    #  # rmv from empty queue
    #  msg = mq.rmv()
    #  check(mq.isEmpty())

    #  # rmv from empty queue
    #  msg = mq.rmv()
    #  check(mq.isEmpty())

    #  mq.delMpscFifo()

    #test "test add, rmv":
    #  var mq = newMpscFifo("mq", ma)
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

    #  mq.delMpscFifo()

    #test "test add, rmv node":
    #  var mq = newMpscFifo("mq", ma)
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

    test "test reusing node":
      var mq = newMpscFifo("mq", ma)
      var msg: MsgPtr
      var ln: LinkNodePtr

      msg = ma.getMsg(1, 0)
      ln = ma.getLinkNode(nil, msg)
      mq.addNode(ln)
      ln = mq.rmvNode()
      msg = toMsg(ln.extra)
      check(msg.cmd == 1)
      ma.retMsg(msg)

      when true:
        msg = ma.getMsg(2, 0)
        ln.initLinkNode(nil, msg)
        mq.addNode(ln)
        ln = mq.rmvNode()
        msg = toMsg(ln.extra)
        check(msg.cmd == 2)

      ma.retLinkNode(ln)

      mq.delMpscFifo()

    #test "test add, rmv, add, rmv":
    #  var mq = newMpscFifo("mq", ma)
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

    #test "test add, rmv, add, rmv node":
    #  var mq = newMpscFifo("mq", ma)
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

    #test "test add, rmv, add, add, rmv, rmv":
    #  var mq = newMpscFifo("mq", ma)
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

    #  # rmv 2, rmv 3
    #  msg = mq.rmv()
    #  check(msg.cmd == 2)
    #  check(not mq.isEmpty())
    #  ma.retMsg(msg)
    #  msg = mq.rmv()
    #  check(msg.cmd == 3)
    #  check(mq.isEmpty())
    #  ma.retMsg(msg)

    #  mq.delMpscFifo()

    #test "test add, rmv, add, add, rmv, rmv node":
    #  var mq = newMpscFifo("mq", ma)
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

    #  ln = mq.rmvNode()
    #  check(mq.isEmpty())
    #  msg = toMsg(ln.extra)
    #  check(msg.cmd == 3)
    #  ma.retMsg(msg)
    #  ma.retLinkNode(ln)

    #  mq.delMpscFifo()

