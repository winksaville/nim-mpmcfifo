# Wait free/Thread safe Msg Queue modeled after Dimitry Vyukov's non intrusive
# MPSC algorithm here:
#   http://www.1024cores.net/home/lock-free-algorithms/queues/non-intrusive-mpsc-node-based-queue
#
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
  var head = mq.head
  var next = atomicLoadN(addr head.next, ATOMIC_ACQUIRE)
  result = next == nil

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
  when DBG: dbg "+"

  #TODO: not working with add/rmvNode!
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
    when DBG: dbg "  prevTail=" & $prevTail
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
  ## May only be called from consumer
  var mq = cast[MsgQueuePtr](q)
  proc dbg(s:string) = echo mq.name & ".rmvNode:" & s
  when DBG: dbg "+ mq=" & $mq

  var head = mq.head
  when DBG: dbg " head=" & $head
  # serialization-point wrt producers, acquire
  var next = cast[LinkNodePtr](atomicLoadN(addr head.next, ATOMIC_ACQUIRE))
  when DBG: dbg " next=" & $next
  if next != nil:
    result = head
    result.extra = next.extra
    when DBG: dbg " next != nil result = next.msg result=" & $result
    mq.head = next
    when DBG: dbg " next != nil mq.head = next mq=" & $mq
  else:
    when DBG: dbg " next == nil result=nil, mq=" & $mq
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

    test "test we can create and delete fifo":
      var mq = newMpscFifo("mq", ma)
      mq.delMpscFifo()

    test "test new queue is empty":
      var mq = newMpscFifo("mq", ma)
      var msg: MsgPtr

      # rmv from empty queue
      msg = mq.rmv()
      check(mq.isEmpty())

      mq.delMpscFifo()

    test "test new queue is empty twice":
      var mq = newMpscFifo("mq", ma)
      var msg: MsgPtr

      # rmv from empty queue
      msg = mq.rmv()
      check(mq.isEmpty())

      # rmv from empty queue
      msg = mq.rmv()
      check(mq.isEmpty())

      mq.delMpscFifo()

    test "test add, rmv":
      var mq = newMpscFifo("mq", ma)
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

    test "test add, rmv node":
      var mq = newMpscFifo("mq", ma)
      var msg = ma.getMsg(1, 0)
      var ln = ma.getLinkNode(nil, msg)
      mq.addNode(ln)
      check(not mq.isEmpty())

      ln = mq.rmvNode()
      check(mq.isEmpty())
      msg = toMsg(ln.extra)
      check(msg.cmd == 1)
      ma.retMsg(msg)
      ma.retLinkNode(ln)

    test "test add, rmv, add, rmv":
      var mq = newMpscFifo("mq", ma)
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

      # add 2
      msg = ma.getMsg(2, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 2
      msg = mq.rmv()
      check(mq.isEmpty())
      check(msg.cmd == 2)
      ma.retMsg(msg)

    test "test add, rmv, add, rmv node":
      var mq = newMpscFifo("mq", ma)
      var msg: MsgPtr
      var ln: LinkNodePtr

      # add 1
      msg = ma.getMsg(1, 0)
      ln = ma.getLinkNode(nil, msg)
      mq.addNode(ln)
      check(not mq.isEmpty())

      # rmv 1
      ln = mq.rmvNode()
      check(mq.isEmpty())
      msg = toMsg(ln.extra)
      check(msg.cmd == 1)
      ma.retMsg(msg)
      ma.retLinkNode(ln)

      # add 2
      msg = ma.getMsg(2, 0)
      ln = ma.getLinkNode(nil, msg)
      mq.addNode(ln)
      check(not mq.isEmpty())

      # rmv 2
      ln = mq.rmvNode()
      check(mq.isEmpty())
      msg = toMsg(ln.extra)
      check(msg.cmd == 2)
      ma.retMsg(msg)
      ma.retLinkNode(ln)

    test "test add, rmv, add, add, rmv, rmv":
      var mq = newMpscFifo("mq", ma)
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

      # add 2, add 3
      msg = ma.getMsg(2, 0)
      mq.add(msg)
      check(not mq.isEmpty())
      msg = ma.getMsg(3, 0)
      mq.add(msg)
      check(not mq.isEmpty())

      # rmv 2, rmv 3
      msg = mq.rmv()
      check(msg.cmd == 2)
      check(not mq.isEmpty())
      ma.retMsg(msg)
      msg = mq.rmv()
      check(msg.cmd == 3)
      check(mq.isEmpty())
      ma.retMsg(msg)

    test "test add, rmv, add, add, rmv, rmv node":
      var mq = newMpscFifo("mq", ma)
      var msg: MsgPtr
      var ln: LinkNodePtr

      # add 1
      msg = ma.getMsg(1, 0)
      ln = ma.getLinkNode(nil, msg)
      mq.addNode(ln)
      check(not mq.isEmpty())

      # rmv 1
      ln = mq.rmvNode()
      check(mq.isEmpty())
      msg = toMsg(ln.extra)
      check(msg.cmd == 1)
      ma.retMsg(msg)
      ma.retLinkNode(ln)

      # add 2, add 3
      msg = ma.getMsg(2, 0)
      ln = ma.getLinkNode(nil, msg)
      mq.addNode(ln)
      check(not mq.isEmpty())
      msg = ma.getMsg(3, 0)
      ln = ma.getLinkNode(nil, msg)
      mq.addNode(ln)
      check(not mq.isEmpty())

      # rmv 2
      ln = mq.rmvNode()
      check(not mq.isEmpty())
      msg = toMsg(ln.extra)
      check(msg.cmd == 2)
      ma.retMsg(msg)
      ma.retLinkNode(ln)

      ln = mq.rmvNode()
      check(mq.isEmpty())
      msg = toMsg(ln.extra)
      check(msg.cmd == 3)
      ma.retMsg(msg)
      ma.retLinkNode(ln)

