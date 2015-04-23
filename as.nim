import locks

type
  MsgQueuePtr* = ptr MsgQueue
  MsgQueue* = object of RootObj
    name*: string
    cond*: ptr TCond
echo "sizeof(MsgQueue)=", sizeof(MsgQueue)
proc newMpscFifo*(name: string, blocking: bool): MsgQueuePtr =
  var
    mq: MsgQueuePtr = nil
    cond: ptr TCond = nil

  if blocking:
    cond = cast[ptr TCond](allocShared(sizeof(TCond)))
    cond[].initCond()

  mq = cast[MsgQueuePtr](allocShared(sizeof(MsgQueue)))

  mq.name = name
  GC_ref(mq.name)
  mq.cond = cond

  result = mq

proc delMpscFifo*(mq: MsgQueuePtr) =
  if mq.cond != nil:
    mq.cond[].deinitCond()
    deallocShared(mq.cond)
  GC_unref(mq.name)
  deallocShared(mq)

var mq = newMpscFifo("mq", true)
mq.delMpscFifo()

mq = newMpscFifo("mq", false)
mq.delMpscFifo()
