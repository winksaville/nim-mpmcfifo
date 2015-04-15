# The performance comments below where using my Ubuntu linux desktop
# compiled with nim 0.10.3 sha1: 4b98768a and buildFlags:
# "-d:release --verbosity:1 --hints:off --warnings:off --threads:on --embedsrc --lineDir:on"
import msg, msgarena, mpscfifo, benchmark

suite "bm msgareana", 0.25:
  var
    ma: MsgArenaPtr
    mq: MsgQueuePtr
    msg: MsgPtr
    mn: MsgNodePtr
    tsa: array[0..0, TestStats]

  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma)
    msg = ma.getMsg(1, 0)
    mn = ma.getMsgNode(nil, msg)
  teardown:
    mq.delMpscFifo()
    ma.delMsgArena()
    ma.retMsg(mn.msg)
    ma.retMsgNode(mn)


  #bm msgareana.test add/rmvNode: ts={min=10cy mean=34cy minC=222 n=4310836}
  test "test add/rmvNode", 4.0, tsa:
    mq.addNode(mn)
    mn = mq.rmvNode()

  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma)
    msg = ma.getMsg(1, 0)
  teardown:
    mq.delMpscFifo()
    ma.delMsgArena()
    ma.retMsg(msg)

  #bm msgareana.test add/rmv: ts={min=121cy mean=142cy minC=1 n=4184734}
  test "test add/rmv", 4.0, tsa:
    mq.add(msg)
    msg = mq.rmv()
