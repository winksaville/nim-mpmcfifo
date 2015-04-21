## Types for msglooper.
##
## This was needed because there is a circular relationship
## between mpscfifo and msglooper.
import msg, locks

const
  listMsgProcessorMaxLen* = 10

type
  MsgProcessorPtr* = ptr MsgProcessor
  MsgProcessor* = object
    pm*: ProcessMsg
    mq*: QueuePtr
    cp*: ComponentPtr

  MsgLooperPtr* = ptr MsgLooper

  MsgLooper* = object
    name*: string
    initialized*: bool
    done*: bool
    condBool* : ptr bool
    cond*: ptr TCond
    lock*: ptr TLock
    listMsgProcessorLen*: int
    listMsgProcessor*: ptr array[0..listMsgProcessorMaxLen-1, MsgProcessorPtr]
    thread*: ptr TThread[MsgLooperPtr]

