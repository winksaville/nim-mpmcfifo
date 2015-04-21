## Benchmark multiple producer single consumer
## with one thread.
import msg, mpscfifo, msgarena, msglooper, benchmark, os, locks

# include bmSuite so we can use it inside t(name: string)
include "bmsuite"

const
  #runTime = 60.0 * 60.0 * 2.0
  runTime = 30.0
  warmupTime = 0.25
  producerCount = 96
  testStatsCount = 1

var
  ma: MsgArenaPtr
  ml1: MsgLooperPtr
  consumerRcvq: QueuePtr

var ml1ConsumerCount = 0
proc ml1Consumer(msg: MsgPtr) =
  # echo "ml1Consumer: **** msg=", msg
  ml1ConsumerCount += 1
  msg.rspq.add(msg)

ma = newMsgArena()
ml1 = newMsgLooper("ml1")
consumerRcvq = newMpscFifo("consumerRcvq", ma, ml1)
ml1.addProcessMsg(ml1Consumer, consumerRcvq)

type
  Producer = object of Component
    name: string
    # Name of the producer

    index: int32
    # Index number of the producer

    rcvq: QueuePtr
    # Receive Queue for this producer

    consumerq: QueuePtr
    # Receive Queue for the consumer

proc newProducer(name: string, index: int,
    rcvq: QueuePtr, consumerq: QueuePtr): Producer =
  result.name = name
  result.index = cast[int32](index and 0xFFFFFFFF)
  result.rcvq = rcvq
  result.consumerq = consumerq

proc producerPm(component: Component, msg: MsgPtr) =
  switch msg.cmd:
    case 0:
    case 1:
    else:
      echo 

proc t(msg: MsgPtr) =
  #echo "t+ tobj=", tobj

#  bmSuite tobj.name, warmupTime:
#    echo suiteObj.suiteName & ".suiteObj=" & $suiteObj
#    var
#      msg: MsgPtr
#      rspq: MsgQueuePtr
#      tsa: array[0..testStatsCount-1, TestStats]
#      cmd: int32 = 0
#
#    setup:
#      rspq = newMpscFifo("rspq-" & suiteObj.suiteName, ma, blockIfEmpty)
#
#    teardown:
#      rspq.delMpscFifo()
#
#    # One loop for the moment
#    test "ping-pong", runTime, tsa:
#      cmd += 1
#      msg = ma.getMsg(nil, rspq, cmd, 0)
#      consumerRcvq.add(msg)
#      msg = rspq.rmv()
#      doAssert(msg.cmd == cmd)
#      ma.retMsg(msg)
#      # echo rspq.name & ": $$$$ msg=" & $msg

  #echo "t:- tobj=", tobj

var
  idx = 0
  producers: array[0..producerCount-1, Producer]

for idx in 0..producers.len-1:
  var producerName = "producer" & $idx
  var producerRcvq = newMpscFifo(producerName, ma, blockIfEmpty) ## ???
  var producer = newProducer(producerName, idx, producerRcvq, consumerRcvq)
  producers[idx] = producer
  ml1.addProcessMsg(producerPm, producerRcvq)

sleep(round(((runTime * 1000.0) * 1.1) + 2000.0))

echo "cleanup ml1ConsumerCount=", ml1ConsumerCount

## TODO: send a message to each producer to tell them to stop?
## Clean up producers and consumer

consumerRcvq.delMpscFifo()
ml1.delMsgLooper()
ma.delMsgArena()
