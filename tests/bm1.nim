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
    mq = newMpscFifo("fifo", ma, blockIfEmpty)
    msg = ma.getMsg(1, 0)
    ln = ma.getLinkNode(nil, msg)
  teardown:
    msg = toMsg(ln.extra)
    ma.retMsg(msg)
    ma.retLinkNode(ln)
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.test add/rmvNode blocking: ts={min=67cy mean=82cy minC=364 n=5375265}
  test "test add/rmvNode blocking", 5.0, tsa:
    mq.addNode(ln)
    ln = mq.rmvNode()


  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma, nilIfEmpty)
    msg = ma.getMsg(1, 0)
    ln = ma.getLinkNode(nil, msg)
  teardown:
    msg = toMsg(ln.extra)
    ma.retMsg(msg)
    ma.retLinkNode(ln)
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.test add/rmvNode non-blocking: ts={min=10cy mean=29cy minC=7763 n=5480653}
  test "test add/rmvNode non-blocking", 5.0, tsa:
    mq.addNode(ln)
    ln = mq.rmvNode()


  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma, blockIfEmpty)
    msg = ma.getMsg(2, 0)
  teardown:
    ma.retMsg(msg)
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.bm add/rmv blocking: ts={min=118cy mean=197cy minC=21 n=5193334}
  test "bm add/rmv blocking", 5.0, tsa:
    mq.add(msg)
    msg = mq.rmv()


  setup:
    ma = newMsgArena()
    mq = newMpscFifo("fifo", ma, nilIfEmpty)
    msg = ma.getMsg(2, 0)
  teardown:
    ma.retMsg(msg)
    mq.delMpscFifo()
    ma.delMsgArena()

  # mpscfifo.bm add/rmv non-blocking: ts={min=67cy mean=93cy minC=6 n=5362014}
  test "bm add/rmv non-blocking", 5.0, tsa:
    mq.add(msg)
    msg = mq.rmv()
