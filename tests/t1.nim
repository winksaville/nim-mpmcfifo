## msglooper tests
import msg, mpscfifo, msgarena, msglooper
import unittest

suite "test msglooper":
  var
    ma: MsgArenaPtr
    ml1: MsgLooperPtr
    ml1Pm1q: QueuePtr
    ml1Pm2q: QueuePtr

  proc ml1Pm1(msg: MsgPtr) =
    echo "ml1Pm2: ++++ msg=", msg
    msg.rspq.add(msg)

  proc ml1Pm2(msg: MsgPtr) =
    echo "ml1Pm2: ---- msg=", msg
    msg.rspq.add(msg)

  ma = newMsgArena()
  ml1 = newMsgLooper("ml1")

  ml1Pm1q = newMpscFifo("ml1Pm1q", ma, ml1)
  ml1.addProcessMsg(ml1Pm1, ml1Pm1q)

  ml1Pm2q = newMpscFifo("ml1Pm2q", ma, ml1)
  ml1.addProcessMsg(ml1Pm2, ml1Pm2q)

  test "one-looper-multiple-ProcessMsgs":
    var
      rspq: QueuePtr
      smsg: MsgPtr
      rmsg1: MsgPtr
      rmsg2: MsgPtr

    # The response queue that the test will use to receive responses
    rspq = newMpscFifo("rsvq", ma)

    # Send a message to ml1Pm1
    smsg = ma.getMsg(nil, rspq, 1, 0)
    ml1Pm1q.add(smsg)

    # Send a message to ml1Pm2
    smsg = ma.getMsg(nil, rspq, 2, 0)
    ml1Pm2q.add(smsg)

    # The response order is not guaranteed because we're sending
    # the message to two different components, but we will receive
    # both messages
    rmsg1 = rspq.rmv()
    rmsg2 = rspq.rmv()
    if rmsg1.cmd == 1:
      check(rmsg2.cmd == 2)
    else:
      check(rmsg1.cmd == 2)
      check(rmsg2.cmd == 1)

    rspq.delMpscFifo()
