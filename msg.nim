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

    hipriorityMsgs*: seq[MsgPtr]
    # Hipriority messages are processed first by msglooper

    rcvq*: QueuePtr
    # receive queue pointer

  ProcessMsg* = proc(cp: ComponentPtr, msg: MsgPtr)

  MsgPtr* = ptr Msg
  Msg* = object of RootObj
    next*: MsgPtr
    rspq*: QueuePtr
    cmd*: int32
    extra*: int

proc `$`*(msg: MsgPtr): string =
  if msg == nil:
    result = "<nil>"
  else:
    result = "{" &
                ptrToStr("msg:", msg) &
                ptrToStr(" next:", msg.next) &
                ptrToStr(" rspQ=", msg.rspQ) &
                " cmd=" & $msg.cmd &
                " extra=" & (if msg.extra == 0: "0" else :
                              "0x" & toHex(msg.extra, sizeof(int)*2)) &
              "}"

