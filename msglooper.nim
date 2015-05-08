import os, locks
import msg, mpscfifo, msgarena, fifoutils

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
    ml.condBool = cast[ptr bool](allocShared(sizeof(bool)))
    ml.condBool[] = false
    ml.cond = allocObject[TCond]()
    ml.cond[].initCond()
    ml.lock = allocObject[TLock]()
    ml.lock[].initLock()
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
      if mp.cp == nil:
        mp.cp = mp.newComponent(ml)
        mp.mq = mp.cp.rcvq
        mp.pm = mp.cp.pm
        ml.condBool[] = false
      var msg = mp.mq.rmv(nilIfEmpty)
      if msg != nil:
        processedAtLeastOneMsg = true
        when DBG: dbg "processing msg=" & $msg
        mp.pm(mp.cp, msg)
        # Cannot assume msg is valid here

    if not processedAtLeastOneMsg:
      # No messages to process so wait
      # TODO: A message may have arrived since we last checked
      # and since we're not using a lock we don't know. One
      # solution would be to have a timeout and POLL, YECK!
      #
      # Seems like we need an atomic event here associated with
      # adding an element to an empty queue and removing the
      # last element. But its tricky since the looper can be
      # managing mutliple queues.
      ml.lock[].acquire
      while not ml.condBool[]:
        when DBG: dbg "waiting"
        ml.cond[].wait(ml.lock[])
        when DBG: dbg "done-waiting"
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

    when DBG: dbg "Using createThread"
    result.thread = allocObject[TThread[MsgLooperPtr]]()
    createThread(result.thread[], looper, result)

    while (not result.initialized):
      when DBG: dbg "waiting on gInitCond"
      gInitCond.wait(gInitLock)
    when DBG: dbg "looper is initialized"
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

proc addProcessMsg*(ml: MsgLooperPtr, pm: ProcessMsg, q: QueuePtr,
    cp: ComponentPtr) =
  ## Add the ProcessMsg funtion and its associated Queue to this looper.
  ## Messages received on q will be dispacted to pm.
  var mq = cast[MsgQueuePtr](q)
  when DBG:
    proc dbg(s:string) = echo ml.name & ".addMsgProcessor:" & s
    dbg "+"
  ml.lock[].acquire()
  when DBG: dbg "acquired"
  if ml.listMsgProcessorLen < listMsgProcessorMaxLen:
    var mp = allocObject[MsgProcessor]()
    mp.cp = cp
    mp.mq = mq
    mp.pm = pm
    ml.listMsgProcessor[ml.listMsgProcessorLen] = mp
    ml.listMsgProcessorLen += 1
    ml.condBool[] = false
    ml.cond[].signal()
  else:
    doAssert(ml.listMsgProcessorLen < listMsgProcessorMaxLen,
      "Attempted to add too many ProcessMsg, maximum is " &
      $listMsgProcessorMaxLen)

  ml.lock[].release()
  when DBG: dbg "-"

proc addProcessMsg*(ml: MsgLooperPtr, pm: ProcessMsg, q: QueuePtr) =
  addProcessMsg(ml, pm, q, nil)

proc addProcessMsg*(ml: MsgLooperPtr, cp: ComponentPtr) =
  addProcessMsg(ml, cp.pm, cp.rcvq, cp)

proc addComponent*[ComponentType](ml: MsgLooperPtr,
    newComponent: NewComponent): ptr ComponentType =
  ## Add a component to this looper. The newComponent proc is called
  ## from within the looper thread and thus all allocation is done
  ## in that thread allowing the component to be gcsafe and use the
  ## threads heap.
  ##
  ## TODO: This must block until newComponent completes!!!!
  ## What I'd like to do is send a message to looper with a
  ## rspq that this will wait on.
  ##
  when DBG:
    proc dbg(s:string) = echo ml.name & ".addComponent:" & s
    dbg "+"
  ml.lock[].acquire()
  var mp: MsgProcessorPtr
  when DBG: dbg "acquired"
  if ml.listMsgProcessorLen < listMsgProcessorMaxLen:
    mp = allocObject[MsgProcessor]()
    mp.mq = nil
    mp.pm = nil
    mp.newComponent = newComponent
    ml.listMsgProcessor[ml.listMsgProcessorLen] = mp
    ml.listMsgProcessorLen += 1
    #var rcvq = newMpscFifo("x", ma)
    #var msg = ma.getMsg(rcvq, 0)
    ml.condBool[] = true
    ml.cond[].signal()
  else:
    doAssert(ml.listMsgProcessorLen < listMsgProcessorMaxLen,
      "Attempted to add too many ProcessMsg, maximum is " &
      $listMsgProcessorMaxLen)

  ml.lock[].release()
  when DBG: dbg " sleeping.."
  # TODO: This needs to be done correctly!!!!
  sleep(100)
  result = cast[ptr ComponentType](mp.cp)
  when DBG: dbg "-"
