## The MsgArena manages getting and returning message from memory
## in a thread safe manner and so maybe shared by multipel threads.
import msg, linknode, mpmcstack, locks, strutils

const
  msgArenaSize = 32

type
  MsgArenaPtr* = ptr MsgArena
  MsgArena* = object
    lock: TLock
    msgCount: int
    msgArray: ptr array[msgArenaSize, MsgPtr]
    linkNodeStack: StackPtr


converter toMsg*(p: pointer): MsgPtr {.inline.} =
  result = cast[MsgPtr](p)

proc newMsg(cmdVal: int32, dataSize: int): MsgPtr =
  ## Allocate a new Msg.
  ## TODO: Allow dataSize other than zero
  result = cast[MsgPtr](allocShared(sizeof(Msg)))
  result.cmd = cmdVal

proc delMsg*(msg: MsgPtr) =
  ## Deallocate a Msg
  ## TODO: handle data size
  freeShared(msg)

proc getMsgArrayPtr(ma: MsgArenaPtr): ptr array[msgArenaSize, MsgPtr] =
  ## Assume ma.lock is acquired
  if ma.msgArray == nil:
    ma.msgArray = cast[ptr array[msgArenaSize, MsgPtr]]
                    (allocShared0(sizeof(MsgPtr) * msgArenaSize))
  result = ma.msgArray

proc ptrToStr(label: string, p: pointer): string =
  if p == nil:
    result = label & "<nil>"
  else:
    result = label & "0x" & toHex(cast[int](p), sizeof(p)*2)

proc `$`*(ma: MsgArenaPtr): string =
  if ma == nil:
    result = "<nil>"
  else:
    ma.lock.acquire()
    block:
      var msgStr = "{"
      if ma.msgArray != nil:
        for idx in 0..ma.msgCount-1:
          msgStr &= $ma.msgArray[idx]
          if idx < ma.msgCount-1:
            msgStr &= ", "
      msgStr &= "}"
      var linkNodeStr = "{"
      var firstTime = true
      var sep = ""
      if ma.linkNodeStack != nil:
        for ln in ma.linkNodeStack:
          linkNodeStr &= sep & $ln
          if firstTime:
            firstTime = false
            sep = ", "
      linkNodeStr &= "}"
      result = "{msgArray:" & $ma.msgCount & " " & msgStr &
                " linkNodeStack: " & " " & linkNodeStr & "}"
    ma.lock.release()

proc newMsgArena*(): MsgArenaPtr =
  result = cast[MsgArenaPtr](allocShared0(sizeof(MsgArena)))
  result.lock.initLock()
  result.msgCount = 0;
  result.linkNodeStack = newMpmcStack("linkNodeStack")

proc delMsgArena*(ma: MsgArenaPtr) =
  ma.lock.acquire()
  block:
    if ma.msgArray != nil:
      for idx in 0..ma.msgCount-1:
        var msg = ma.msgArray[idx]
        delMsg(msg)
      deallocShared(ma.msgArray)
    while true:
      var ln = ma.linkNodeStack.pop()
      if ln == nil:
        break;
      delLinkNode(ln)

    ma.linkNodeStack.delMpmcStack()
  ma.lock.release()
  ma.lock.deinitLock()
  deallocShared(ma)

proc getMsg*(ma: MsgArenaPtr, cmd: int32, dataSize: int): MsgPtr =
  ma.lock.acquire()
  block:
    var msgA = ma.getMsgArrayPtr()
    if ma.msgCount > 0:
      ma.msgCount -= 1
      result = msgA[ma.msgCount]
      result.cmd = cmd
    else:
      result = newMsg(cmd, dataSize)
  ma.lock.release()

proc retMsg*(ma: MsgArenaPtr, msg: MsgPtr) =
  ma.lock.acquire()
  block:
    var msgA = ma.getMsgArrayPtr()
    if ma.msgCount < msgA[].len():
      msg.rspQ = nil
      msg.cmd = -1
      msgA[ma.msgCount] = msg
      ma.msgCount += 1
    else:
      delMsg(msg)
      
  ma.lock.release()

proc getLinkNode*(ma: MsgArenaPtr, next: LinkNodePtr, extra: pointer): LinkNodePtr =
  result = ma.linkNodeStack.pop()
  if result == nil:
    result = newLinkNode(next, extra)
  else:
    result.next = next
    result.extra = extra

proc retLinkNode*(ma: MsgArenaPtr, ln: LinkNodePtr) =
  ma.linkNodeStack.push(ln)
