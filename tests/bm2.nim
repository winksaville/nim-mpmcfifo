import msg, msgarena, mpscfifo, msglooper, benchmark, os, locks

var
  ma: MsgArenaPtr
  ml1: MsgLooperPtr
  ml1RsvQ: QueuePtr

var ml1PmCount = 0
proc ml1Pm(msg: MsgPtr) =
  echo "ml1Pm: **** msg=", msg
  ml1PmCount += 1
  msg.rspq.add(msg)

ma = newMsgArena()
ml1 = newMsgLooper("ml1")
ml1RsvQ = newMpscFifo("ml1RsvQ", ma, false, ml1.condBool, ml1.cond, ml1.lock, blockIfEmpty)
ml1.addProcessMsg(ml1Pm, ml1RsvQ)

suite "msglooper", 0.0:
  var
    msg: MsgPtr
    tsa: array[0..0, TestStats]
    rspQ1: QueuePtr

  setup:
    echo suiteObj.suiteName & " setup:+"
    rspQ1 = newMpscFifo("rspQ1", ma, blockIfEmpty)
    msg = ma.getMsg(1, 0)
    msg.rspQ = rspQ1
    echo suiteObj.suiteName & " setup:-"

  teardown:
    echo suiteObj.suiteName & " teardown+"
    ma.retMsg(msg)
    rspQ1.delMpscFifo()
    echo suiteObj.suiteName & " teardown-"

  test "test1", 1, tsa:
    echo suiteObj.fullName & " call add msg=" & $msg
    ml1RsvQ.add(msg)
    echo suiteObj.fullName & " call rmv"
    msg = rspQ1.rmv()
    echo suiteObj.fullName & " ret  rmv msg=" & $msg

echo "cleanup"

ml1RsvQ.delMpscFifo()
ml1.delMsgLooper()
ma.delMsgArena()
