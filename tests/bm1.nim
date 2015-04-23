# Simple benchmarks
import msg, mpscfifo, msgarena, benchmark

const
  timeLoops = 5.0

suite "mpscfifo", 0.25:
  var
    ma: MsgArenaPtr
    mq: MsgQueuePtr
    msg: MsgPtr
    tsa: array[0..0, TestStats]

  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma, blockIfEmpty)
    msg = ma.getMsg(nil, nil, 2, 0)
  teardown:
    ma.retMsg(msg)
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.bm add/rmv blocking: ts={min=290cy mean=311cy minC=189 n=10443614}
  test "bm add/rmv blocking", timeLoops, tsa:
    mq.add(msg)
    msg = mq.rmv()


  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma, blockIfEmpty)
  teardown:
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.bm get/add/rmv/ret blocking: ts={min=318cy mean=347cy minC=674 n=10181401}
  test "bm get/add/rmv/ret blocking", timeLoops, tsa:
    msg = ma.getMsg(nil, nil, 2, 0)
    mq.add(msg)
    msg = mq.rmv()
    ma.retMsg(msg)


  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma, nilIfEmpty)
    msg = ma.getMsg(2)
  teardown:
    ma.retMsg(msg)
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.bm add/rmv non-blocking: ts={min=20cy mean=50cy minC=62575 n=12255097}
  test "bm add/rmv non-blocking", timeLoops, tsa:
    mq.add(msg)
    msg = mq.rmv()


  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma, nilIfEmpty)
  teardown:
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.bm get/add/rmv/ret non-blocking: ts={min=74cy mean=85cy minC=29 n=12491402}
  test "bm get/add/rmv/ret non-blocking", timeLoops, tsa:
    msg = ma.getMsg(2)
    mq.add(msg)
    msg = mq.rmv()
    ma.retMsg(msg)
