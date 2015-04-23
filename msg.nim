import fifoutils, locks, strutils

type
  QueuePtr* = ptr Queue
  Queue* = object of RootObj

  ComponentPtr* = ptr Component
  Component* = object of RootObj
    name*: string
    # Name of the producer

    pm*: ProcessMsg
    # ProcessMsg proc

    rcvq*: QueuePtr
    # receive queue pointer

  ProcessMsg* = proc(cp: ComponentPtr, msg: MsgPtr)

  MsgPtr* = ptr Msg
  Msg* = object of RootObj
    next*: MsgPtr
    rspq*: QueuePtr
    cmd*: int32

proc `$`*(msg: MsgPtr): string =
  if msg == nil:
    result = "<nil>"
  else:
    result = "{" &
                ptrToStr("msg:", msg) &
                ptrToStr(" rspQ=", msg.rspQ) &
                " cmd=" & $msg.cmd &
              "}"

