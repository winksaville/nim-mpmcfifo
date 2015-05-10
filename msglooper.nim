import os, locks
import msg, mpscfifo, msgarena, fifoutils, strutils

import msgloopertypes
export msgloopertypes

const
  DBG = false

# Global itnitialization lock and cond use to have newMsgLooper not return
# until looper has startend and MsgLooper is completely initialized.
var
  gInitLock: TLock
  gInitCond: TCond

gInitLock.initLock()
gInitCond.initCond()

proc looper(ml: MsgLooperPtr) {.thread.} =
  when DBG:
    proc dbg(s: string) = echo ml.name & ".looper" & s
    dbg "+"

  gInitLock.acquire()
  block:
    when DBG: dbg "initializing"
    # initialize MsgLooper
    ml.listMsgProcessorLen = 0
    ml.listMsgProcessor = cast[ptr array[0..listMsgProcessorMaxLen-1,
              MsgProcessorPtr]](allocShared(sizeof(MsgProcessorPtr) *
                                                  listMsgProcessorMaxLen))
    for idx in 0..listMsgProcessorMaxLen-1:
      var mp = allocObject[MsgProcessor]()
      mp.state = empty
      ml.listMsgProcessor[idx] = mp
    ml.condBool = cast[ptr bool](allocShared(sizeof(bool)))
    ml.condBool[] = false
    ml.cond = allocObject[TCond]()
    ml.cond[].initCond()
    ml.lock = allocObject[TLock]()
    ml.lock[].initLock()
    ml.ma = newMsgArena()
    when DBG: dbg "signal gInitCond"
    ml.initialized = true;
    gInitCond.signal()
  gInitLock.release()

  # BUG: What happens when the list changes while we're iterating
  # in these loops!

  while not ml.done:
    when DBG: dbg "TOL ml.listMsgProcessorLen=" & $ml.listMsgProcessorLen
    # Check if there are any messages to process
    #
    # BUG: This loop can be inefficient. For example when
    # running bmmpsc_ot.nim there is one consumer and N
    # producers. In this scenario there will only be typically
    # two messages processed when iterating over the
    # listMsgProcessor array.
    var processedAtLeastOneMsg = false
    for idx in 0..ml.listMsgProcessorLen-1:
      var mp = ml.listMsgProcessor[idx]
      case atomicLoadN[MsgProcessorState](addr mp.state, ATOMIC_ACQUIRE)
      of empty, busy:
        when DBG: dbg " empty/busy idx=" & $idx
      of adding:
        when DBG: dbg " adding idx=" & $idx
        var cp = mp.newComponent(ml)
        mp.cp = cp
        mp.mq = cp.rcvq
        mp.pm = cp.pm
        mp.state = full
        var msg = ml.ma.getMsg(1)
        msg.extra = cast[int](mp.cp)
        mp.rspq.add(msg)
        atomicStoreN(ml.condBool, false, ATOMIC_RELEASE)
        when DBG: dbg " added  idx=" & $idx
      of full:
        var msg = mp.mq.rmv(nilIfEmpty)
        if msg != nil:
          processedAtLeastOneMsg = true
          when DBG: dbg " full processing msg=" & $msg
          mp.pm(mp.cp, msg)
          # Cannot assume msg is valid here
        else:
          when DBG: dbg " full no msgs idx=" & $idx
      of deleting:
        when DBG: dbg " deleting idx=" & $idx
        mp.delComponent(mp.cp)
        mp.state = empty
        mp.rspq.add(ml.ma.getMsg(1))
        atomicStoreN(ml.condBool, false, ATOMIC_RELEASE)
        when DBG: dbg " deleted  idx=" & $idx

    if not processedAtLeastOneMsg:
      # No messages to process so wait
      ml.lock[].acquire
      while not ml.condBool[]:
        when DBG: dbg " waiting"
        ml.cond[].wait(ml.lock[])
        when DBG: dbg " done-waiting"
      ml.lock[].release
  when DBG: dbg "-"


proc newMsgLooper*(name: string): MsgLooperPtr =
  ## Create a newMsgLooper. This does not return until the looper
  ## has started and everything is initialized.
  when DBG:
    proc dbg(s: string) = echo name & ".newMsgLooper:" & s
    dbg "+"

  # Use a global to coordinate initialization of the looper
  # We may want to make a MsgLooper an untracked structure
  # in the future.
  gInitLock.acquire()
  block:
    result = allocObject[MsgLooper]()
    result.name = name
    result.initialized = false;

    when DBG: dbg " Using createThread"
    result.thread = allocObject[TThread[MsgLooperPtr]]()
    createThread(result.thread[], looper, result)

    while (not result.initialized):
      when DBG: dbg " waiting on gInitCond"
      gInitCond.wait(gInitLock)
    when DBG: dbg " looper is initialized"
  gInitLock.release()

  when DBG: dbg "-"

proc delMsgLooper*(ml: MsgLooperPtr) =
  ## Delete the message looper.
  ## This causes the msg looper to terminate and message processors
  ## associated with the looper will not receive any additonal
  ## messages. All queued up message are lost, use with care.
  when DBG:
    proc dbg(s:string) = echo ml.name & ".delMsgLooper:" & s
    dbg "DOES NOTHING YET"

proc ping(ml: MsgLooperPtr) =
  ml.lock[].acquire()
  ml.condBool[] = true
  ml.cond[].signal()
  ml.lock[].release()

proc addProcessMsg*(ml: MsgLooperPtr, pm: ProcessMsg, q: QueuePtr,
    cp: ComponentPtr) =
  ## Add the ProcessMsg funtion and its associated Queue to this looper.
  ## Messages received on q will be dispacted to pm.
  var mq = cast[MsgQueuePtr](q)
  when DBG:
    proc dbg(s:string) = echo ml.name & ".addMsgProcessor:" & s
    dbg "+"

  # See if there is an empty slot
  var added = false
  for idx in 0..listMsgProcessorMaxLen-1:
    var mp = ml.listMsgProcessor[idx]
    var emptyState = empty
    if atomicCompareExchangeN[MsgProcessorState](addr mp.state,
        addr emptyState, busy, true, ATOMIC_ACQ_REL, ATOMIC_ACQUIRE):
      if idx >= ml.listMsgProcessorLen:
        ml.listMsgProcessorLen += 1
      mp.cp = cp
      mp.mq = mq
      mp.pm = pm
      mp.state = full
      ping(ml)
      added = true

  if not added:
      doAssert(ml.listMsgProcessorLen < listMsgProcessorMaxLen,
        "Attempted to add too many ProcessMsg, maximum is " &
        $listMsgProcessorMaxLen)

  when DBG: dbg "-"

proc addProcessMsg*(ml: MsgLooperPtr, pm: ProcessMsg, q: QueuePtr) =
  addProcessMsg(ml, pm, q, nil)

proc addProcessMsg*(ml: MsgLooperPtr, cp: ComponentPtr) =
  addProcessMsg(ml, cp.pm, cp.rcvq, cp)

proc addComponent(ml: MsgLooperPtr,
    newComponent: NewComponent, rspq: MsgQueuePtr) =
  ## Add a component to this looper. The newComponent proc is called
  ## from within the looper thread and thus all allocation is done
  ## in the context of its thread. When operation is complete
  ## a message is sent to rspq
  when DBG:
    proc dbg(s:string) = echo ml.name & ".addComponent:" & s
    dbg "+"
  var mp: MsgProcessorPtr

  # See if there is an empty slot
  var added = false
  for idx in 0..listMsgProcessorMaxLen-1:
    mp = ml.listMsgProcessor[idx]
    var emptyState = empty
    if atomicCompareExchangeN[MsgProcessorState](addr mp.state,
        addr emptyState, busy, true, ATOMIC_ACQ_REL, ATOMIC_ACQUIRE):
      if idx >= ml.listMsgProcessorLen:
        when DBG:
          dbg " idx=" & $idx & " ml.listMsgProcessorLen=" &
            $ml.listMsgProcessorLen
        ml.listMsgProcessorLen += 1
      mp.newComponent = newComponent
      mp.rspq = rspq
      mp.state = adding
      ping(ml)
      added = true
      break

  if not added:
      doAssert(ml.listMsgProcessorLen < listMsgProcessorMaxLen,
        "Attempted to add too many ProcessMsg, maximum is " &
        $listMsgProcessorMaxLen)

  when DBG: dbg "-"

proc addComponent*[ComponentType](ml: MsgLooperPtr,
    newComp: NewComponent): ptr ComponentType =
  ## Add a component to this looper. The newComponent proc is called
  ## from within the looper thread and thus all allocation is done
  ## in the context of its thread.
  var rspq = newMpscFifo("", ml.ma, ml)
  addComponent(ml, newComp, rspq)
  var msg = rspq.rmv()
  ml.ma.retMsg(msg)
  result = cast[ptr ComponentType](msg.extra)

proc delComponent(ml: MsgLooperPtr, cp: ComponentPtr,
    delComponent: DelComponent, rspq: MsgQueuePtr) =
  ## Delete a component. As with addComponent the delComponent
  ## proc is called in the context of its thread. When complete
  ## a message is sent to rspq.
  when DBG:
    proc dbg(s:string) = echo ml.name & ".delComponent:" & s
    dbg "+"
  var deletn = false
  for idx in 0..listMsgProcessorMaxLen-1:
    var mp = ml.listMsgProcessor[idx]
    if mp.state == full and mp.cp == cp:
      var fullState = full
      if atomicCompareExchangeN[MsgProcessorState](addr mp.state,
          addr fullState, busy, true, ATOMIC_ACQ_REL, ATOMIC_ACQUIRE):
        when DBG: dbg " deleting idx=" & $idx
        mp.delComponent = delComponent
        mp.state = deleting
        mp.rspq = rspq
        ping(ml)
        deletn = true
        break

  if not deletn:
    rspq.add(ml.ma.getMsg(1))
  when DBG: dbg "-"

proc delComponent*(ml: MsgLooperPtr, cp: ComponentPtr, delComp: DelComponent) =
  ## Delete a component. As with addComponent the delComponent
  ## proc is called in the context of its thread.
  var rspq = newMpscFifo("", ml.ma, ml)
  delComponent(ml, cp, delComp, rspq)
  var msg = rspq.rmv()
  ml.ma.retMsg(msg)
