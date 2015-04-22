## The MsgArena manages getting and returning message from memory
## in a thread safe manner and so maybe shared by multipel threads.
import msg, mpmcstack, locks, strutils

const
  DBG = false
  msgArenaSize = 32

type
  MsgArenaPtr* = ptr MsgArena
  MsgArena* = object
    #lock: TLock
    msgStack: StackPtr

proc ptrToStr(label: string, p: pointer): string =
  if p == nil:
    result = label & "<nil>"
  else:
    result = label & "0x" & toHex(cast[int](p), sizeof(p)*2)

proc `$`*(ma: MsgArenaPtr): string =
  if ma == nil:
    result = "<nil>"
  else:
    #ma.lock.acquire()
    block:
      var msgStr = "{"
      var firstTime = true
      var sep = ""
      if ma.msgStack != nil:
        for ln in ma.msgStack:
          msgStr &= sep & $ln
          if firstTime:
            firstTime = false
            sep = ", "
      msgStr &= "}"
      result = "msgStack: " & " " & msgStr & "}"
    #ma.lock.release()

converter toMsg*(p: pointer): MsgPtr {.inline.} =
  result = cast[MsgPtr](p)

proc initMsg(msg: MsgPtr, next: MsgPtr, rspq: QueuePtr, cmdVal: int32,
    data: pointer) {.inline.} =
  ## init a Msg.
  ## TODO: Allow dataSize other than zero
  msg.next = next
  msg.rspq = rspq
  msg.cmd = cmdVal

proc newMsg(next: MsgPtr, rspq: QueuePtr, cmdVal: int32, dataSize: int): MsgPtr =
  ## Allocate a new Msg.
  ## TODO: Allow dataSize other than zero
  result = cast[MsgPtr](allocShared(sizeof(Msg)))
  result.initMsg(next, rspq, cmdVal, nil)

proc delMsg*(msg: MsgPtr) =
  ## Deallocate a Msg
  ## TODO: handle data size
  freeShared(msg)

proc newMsgArena*(): MsgArenaPtr =
  when DBG: echo "newMsgArena:+"
  result = cast[MsgArenaPtr](allocShared0(sizeof(MsgArena)))
  #result.lock.initLock()
  result.msgStack = newMpmcStack("msgStack")
  when DBG: echo "newMsgArena:-"

proc delMsgArena*(ma: MsgArenaPtr) =
  when DBG: echo "delMsgArena:+"
  #ma.lock.acquire()
  #when DBG: echo "delMsgArena: lock accquired"
  block:
    while true:
      var msg = ma.msgStack.pop()
      if msg == nil:
        break;
      delMsg(msg)

    ma.msgStack.delMpmcStack()
  #ma.lock.release()
  #ma.lock.deinitLock()
  deallocShared(ma)
  when DBG: echo "delMsgArena:-"

proc getMsg*(ma: MsgArenaPtr, next: MsgPtr, rspq: QueuePtr, cmd: int32,
    dataSize: int): MsgPtr =
  ## Get a message from the arena or if none allocate one
  ## TODO: Allow datasize other than zero
  result = ma.msgStack.pop()
  if result == nil:
    result = newMsg(next, rspq, cmd, dataSize)
  else:
    result.initMsg(next, rspq, cmd, nil)

proc retMsg*(ma: MsgArenaPtr, msg: MsgPtr) =
  ## Return a message to the arena
  ma.msgStack.push(msg)
