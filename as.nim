import locks, strutils

proc initializer[T](dest: pointer) {.inline.} =
    var prototype: T
    copyMem(dest, addr prototype, sizeof(prototype))

type
  MsgQueuePtr* = ptr MsgQueue
  MsgQueue* = object of RootObj
    name*: string
    cond*: ptr TCond

proc newMpscFifo*(name: string, blocking: bool): MsgQueuePtr =
  var
    q: MsgQueue
    mq: MsgQueuePtr = nil
    cond: ptr TCond = nil

  if blocking:
    cond = cast[ptr TCond](allocShared(sizeof(TCond)))
    cond[].initCond()

  mq = cast[MsgQueuePtr](allocShared(sizeof(MsgQueue)))
  initializer[MsgQueue](mq)

  mq.name = name # increments ref, must use GC_unfre in delMpscFifo
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
