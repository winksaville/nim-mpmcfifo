## The MsgArena manages getting and returning message from memory
## in a thread safe manner and so maybe shared by multipel threads.
import msg, linknode, mpmcstack, locks, strutils

const
  DBG = true
  msgArenaSize = 32

type
  MsgArenaPtr* = ptr MsgArena
  MsgArena* = object
    lock: TLock
    msgCount: int
    msgArray: ptr array[msgArenaSize, MsgPtr]
    linkNodeStack: StackPtr

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
  when DBG: echo(ptrToStr("getMsgArrayPtr:+ ma=", ma))
  ## Assume ma.lock is acquired
  if ma.msgArray == nil:
    when DBG: echo "getMsgArrayPtr: 1"
    ma.msgArray = cast[ptr array[msgArenaSize, MsgPtr]]
                    (allocShared0(sizeof(MsgPtr) * msgArenaSize))
    when DBG: echo "getMsgArrayPtr: 2"
  result = ma.msgArray
  when DBG: echo "getMsgArrayPtr:- msgArray=" & ptrToStr("", result)

proc newMsgArena*(): MsgArenaPtr =
  when DBG: echo "newMsgArena:+"
  result = cast[MsgArenaPtr](allocShared0(sizeof(MsgArena)))
  result.lock.initLock()
  result.msgCount = 0;
  result.linkNodeStack = newMpmcStack("linkNodeStack")
  when DBG: echo "newMsgArena:-"

proc delMsgArena*(ma: MsgArenaPtr) =
  when DBG: echo "delMsgArena:+"
  ma.lock.acquire()
  when DBG: echo "delMsgArena: lock accquired"
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
  echo "delMsgArena: releasing lock"
  ma.lock.release()
  echo "delMsgArena: lock released"
  ma.lock.deinitLock()
  deallocShared(ma)
  echo "delMsgArena:-"

proc getMsg*(ma: MsgArenaPtr, cmd: int32, dataSize: int): MsgPtr =
  when DBG: echo "getMsg:+"
  ma.lock.acquire()
  when DBG: echo "getMsg: lock acquired"
  block:
    var msgA = ma.getMsgArrayPtr()
    if ma.msgCount > 0:
      ma.msgCount -= 1
      result = msgA[ma.msgCount]
      result.cmd = cmd
    else:
      result = newMsg(cmd, dataSize)
  when DBG: echo "getMsg: releasing lock"
  ma.lock.release()
  when DBG: echo "getMsg:- lock released msg=", result

proc retMsg*(ma: MsgArenaPtr, msg: MsgPtr) =
  when DBG: echo "retMsg:+ msg=", msg
  ma.lock.acquire()
  when DBG: echo "retMsg: lock acquired"
  block:
    # TODO: Fix bug!
    # On line below got an SIGSEGV maybe because we've executed delMsgArena
    # asynchronously to executing this method. Although I haven't been
    # able to prove that:
    #   "SIGSEGV: Illegal storate access. (Attempt to read from nil?)"
    echo ptrToStr("retMsg: 1 ma=", ma)
    var msgA = ma.getMsgArrayPtr()
    echo ptrToStr("retMsg: 2 msgA=", msgA)
    echo "retMsg: ma.msgCount=", ma.msgCount
    var len = msgA[].len()
    echo "retMsg: msgA[].len=", len
    if ma.msgCount < len:
      echo "retMsg: add to msgA msg=", msg
      msg.rspQ = nil
      msg.cmd = -1
      msgA[ma.msgCount] = msg
      ma.msgCount += 1
    else:
      echo "retMsg: delmsg"
      delMsg(msg)
      
  when DBG: echo "retMsg: releasing lock"
  ma.lock.release()
  when DBG: echo "retMsg:- lock released"

proc getLinkNode*(ma: MsgArenaPtr, next: LinkNodePtr, extra: pointer): LinkNodePtr =
  result = ma.linkNodeStack.pop()
  if result == nil:
    result = newLinkNode(next, extra)
  else:
    result.next = next
    result.extra = extra

proc retLinkNode*(ma: MsgArenaPtr, ln: LinkNodePtr) =
  ma.linkNodeStack.push(ln)
