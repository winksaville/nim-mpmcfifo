import msg, linknode, mpscfifo, msgarena, lnlooper, benchmark, os, locks

# include bmSuite so we can use it inside t(name: string)
include "bmsuite"

const
  #runTime = 60.0 * 60.0 * 2.0
  runTime = 30.0
  warmupTime = 0.25
  threadCount = 1
  testStatsCount = 1

var
  ma: MsgArenaPtr
  ml1: MsgLooperPtr
  ml1RsvQ: QueuePtr

var ml1ConsumerCount = 0
proc ml1Consumer(ln: LinkNodePtr) =
  ml1ConsumerCount += 1
  var msg = cast[MsgPtr](ln.extra)
  #echo "ml1Consumer: **** msg.cmd=" & $msg.cmd & " ln=", ln
  msg.rspq.addNode(ln)

ma = newMsgArena()
ml1 = newMsgLooper("ml1")
ml1RsvQ = newMpscFifo("ml1RsvQ", ma, false, ml1.condBool, ml1.cond, ml1.lock, blockIfEmpty)
ml1.addProcessMsg(ml1Consumer, ml1RsvQ)

type
  TObj = object
    name: string
    index: int32

proc newTObj(name: string, index: int): TObj =
  result.name = name
  result.index = cast[int32](index and 0xFFFFFFFF)

proc t(tobj: TObj) {.thread.} =
  #echo "t+ tobj=", tobj

  bmSuite tobj.name, warmupTime:
    echo suiteObj.suiteName & ".suiteObj=" & $suiteObj
    var
      msg: MsgPtr
      ln: LinkNodePtr
      rspq: MsgQueuePtr
      tsa: array[0..testStatsCount-1, TestStats]
      cmd: int32 = 2

    setup:
      rspq = newMpscFifo("rspq-" & suiteObj.suiteName, ma, blockIfEmpty)
      msg = ma.getMsg(tobj.index, 0)
      msg.rspq = rspq
      ln = ma.getLinkNode(nil, msg)

    teardown:
      ma.retMsg(msg)
      ma.retLinkNode(ln)
      #rspq.delMpscFifo()

    # One loop for the moment
    test "ping-pong", runTime, tsa:
      cmd += 1
      msg.cmd = cmd
      ml1RsvQ.addNode(ln)
      ln = rspq.rmvNode()
      #echo rspq.name & ": $$$$ msg.cmd=" & $msg.cmd & " ln=" & $ln


  #echo "t:- tobj=", tobj

var
  idx = 0
  threads: array[0..threadCount-1, TThread[TObj]]

for idx in 0..threads.len-1:
  var tobj = newTObj("Producer" & $idx, idx)
  createThread[TObj](threads[idx], t, tobj)

sleep(round(((runTime * 1000.0) * 1.1) + 2000.0))

echo "cleanup ml1ConsumerCount=", ml1ConsumerCount

# TODO: We're not ending cleanly so these can cause assertions.
ml1RsvQ.delMpscFifo()
ml1.delMsgLooper()
ma.delMsgArena()
