# The performance comments below where using my Ubuntu linux desktop
# compiled with nim 0.10.3 sha1: 4b98768a and buildFlags:
# "-d:release --verbosity:1 --hints:off --warnings:off --threads:on --embedsrc --lineDir:on"
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

  # mpscfifo.bm add/rmv blocking: ts={min=118cy mean=197cy minC=21 n=5193334}
  test "bm add/rmv blocking", timeLoops, tsa:
    mq.add(msg)
    msg = mq.rmv()


  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma, blockIfEmpty)
  teardown:
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.bm get/add/rmv/ret blocking: ts={min=253cy mean=293cy minC=524 n=4878547}
  test "bm get/add/rmv/ret blocking", timeLoops, tsa:
    msg = ma.getMsg(nil, nil, 2, 0)
    mq.add(msg)
    msg = mq.rmv()
    ma.retMsg(msg)


  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma, nilIfEmpty)
    msg = ma.getMsg(nil, nil, 2, 0)
  teardown:
    ma.retMsg(msg)
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.bm add/rmv non-blocking: ts={min=10cy mean=40cy minC=9 Vn=5195976}
  test "bm add/rmv non-blocking", timeLoops, tsa:
    mq.add(msg)
    msg = mq.rmv()


  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma, nilIfEmpty)
  teardown:
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.bm get/add/rmv/ret non-blocking: ts={min=82cy mean=104cy minC=11 n=5084526}
  test "bm get/add/rmv/ret non-blocking", timeLoops, tsa:
    msg = ma.getMsg(nil, nil, 2, 0)
    mq.add(msg)
    msg = mq.rmv()
    ma.retMsg(msg)
