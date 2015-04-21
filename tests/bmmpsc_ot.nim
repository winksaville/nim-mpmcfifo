## Benchmark multiple producer single consumer
## with one thread.
import msg, mpscfifo, msgarena, msglooper, math, os, locks

# include bmSuite so we can use it inside t(name: string)
include "bmsuite"

const
  DBG = true
  #runTime = 60.0 * 60.0 * 2.0
  runTime = 0.25
  warmupTime = 0.25
  producerCount = 1
  testStatsCount = 1
  START_CMD = -1
  STOP_CMD = -2

var
  ma: MsgArenaPtr
  ml1: MsgLooperPtr
  consumerRcvq: QueuePtr

var ml1ConsumerCount = 0
proc ml1Consumer(cp: ComponentPtr, msg: MsgPtr) =
  echo "ml1Consumer: **** msg=", msg
  ml1ConsumerCount += 1
  msg.rspq.add(msg)

ma = newMsgArena()
ml1 = newMsgLooper("ml1")
consumerRcvq = newMpscFifo("consumerRcvq", ma, ml1)
ml1.addProcessMsg(ml1Consumer, consumerRcvq)

type
  ProducerStates = enum
    idle, running, stopped

  ProducerPtr = ptr Producer
  Producer = object of Component
    state: ProducerStates
    # current state

    index: int32
    # Index number of the producer

    consumerq: QueuePtr
    # Receive Queue for the consumer

proc newProducer(name: string, pm: ProcessMsg, rcvq: QueuePtr,
    consumerq: QueuePtr, index: int): ProducerPtr =
  result = cast[ProducerPtr](allocShared(sizeof(Producer)))
  result.name = name
  result.pm = pm
  result.rcvq = rcvq
  result.state = idle
  result.consumerq = consumerq
  result.index = cast[int32](index and 0xFFFFFFFF)
  echo "newProducer: name=" & result.name & " index=" & $result.index

proc producerPm(cp: ComponentPtr, msg: MsgPtr) =
  when DBG: echo cp.name & ": msg=" & $msg
  var producer = cast[Producer](cp)
  echo "after cast"

  # If command is top just respond and do nothing else
  if msg.cmd == STOP_CMD:
    echo producer.name & ": stopped msg=" & $msg
    producer.state = stopped
    msg.rspq.add(msg)
  else:
    case producer.state:
    of idle:
      case msg.cmd:
      of START_CMD:
        # On START_CMD forward the msg to consumer with the index
        echo producer.name & ": idle: transition to running msg=" & $msg
        msg.cmd = producer.index
        producer.consumerq.add(msg)
        producer.state = running
      else:
        echo producer.name & ": idle: ignore non START_CMD msg=" & $msg
    of running:
      when DBG: echo producer.name & ": running: $$$$ msg=" & $msg
      msg.rspq.add(msg)
    of stopped:
      echo producer.name & ": stopped: ignore msg=" & $msg
    else:
      echo producer.name & ": Unknown state=" & $producer.state &
          " msg=" & $msg

var
  idx = 0
  producers: array[0..producerCount-1, ProducerPtr]
  controlq = newMpscFifo("controlq", ma, blockIfEmpty)

for idx in 0..producers.len-1:
  var producerName = "producer" & $idx
  var producerRcvq = newMpscFifo(producerName, ma, ml1)
  var producer = newProducer(producerName, producerPm, producerRcvq,
                    consumerRcvq, idx)
  producers[idx] = producer
  ml1.addProcessMsg(producer)

sleep(round(((runTime * 1000.0) * 1.1) + 2000.0))

echo "cleanup ml1ConsumerCount=", ml1ConsumerCount

## Tell all producers to stop
for idx in 0..producers.len-1:
  var msg = ma.getMsg(nil, controlq, STOP_CMD, 0)
  echo "Issue STOP_CMD to   " & producers[idx].name
  producers[idx].rcvq.add(msg)
  msg = controlq.rmv()
  echo "Resp  STOP_CMD from " & producers[idx].name
  echo producers[idx].name & ": STOPPED"

## TODO: send a message to each producer to tell them to stop?
## Clean up producers and consumer

consumerRcvq.delMpscFifo()
ml1.delMsgLooper()
ma.delMsgArena()
