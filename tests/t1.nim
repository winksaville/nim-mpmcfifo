# The performance comments below where using my Ubuntu linux desktop
# compiled with nim 0.10.3 sha1: 4b98768a and buildFlags:
# "-d:release --verbosity:1 --hints:off --warnings:off --threads:on --embedsrc --lineDir:on"
import msg, linknode, mpscfifo, msgarena, benchmark

suite "mpscfifo", 0.25:
  var
    ma: MsgArenaPtr
    mq: MsgQueuePtr
    msg: MsgPtr
    ln: LinkNodePtr
    tsa: array[0..0, TestStats]

  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma)
    msg = ma.getMsg(1, 0)
    ln = ma.getLinkNode(nil, msg)
  teardown:
    msg = toMsg(ln.extra)
    ma.retMsg(msg)
    ma.retLinkNode(ln)
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.test add/rmvNode: ts={min=7cy mean=29cy minC=12 n=5337444}
  test "test add/rmvNode", 5.0, tsa:
    mq.addNode(ln)
    ln = mq.rmvNode()

  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma)
    msg = ma.getMsg(2, 0)
  teardown:
    ma.retMsg(msg)
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.test add/rmv: ts={min=67cy mean=89cy minC=1 n=5250375}
  test "test add/rmv", 5.0, tsa:
    mq.add(msg)
    msg = mq.rmv()
