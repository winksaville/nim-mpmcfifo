## A hierarchical state machine where the current state is defined as
## a process to execute and the states may be arranged in a hierarchy.
##
## TODO: Add many more tests especially up and down the hierarchy
##
## TODO: Return the messsages to the arena
##
## TODO: Check for other memory leaks!
##
## TODO: Add "quiting" which must invoke all of the exit methods.
##
## TODO: One problem is that with the tester running asynchronously
## TODO: with the StateMachine and responding with a message from
## TODO: using the counters in enter/exit doesn't work because the
## TODO: exit/enter procs are called after the response has been
## TODO: sent. We should devise a synchronous test harness which or
## TODO: use a logging technique as in the StateMachine.java code
## TODO: in Android.
import msg, msgarena, msglooper, mpscfifo, fifoutils
import tables, typeinfo, os, sequtils

const
  DBG = false

type
  StateResult = enum
    Handled, NotHandled

  StateInfo[TypeState] = object of RootObj
    name: string
    active: bool
    enter: TypeState
    exit: TypeState
    state: TypeState
    parentStateInfo: ref StateInfo[TypeState]

  StateMachine*[TypeState] = object of Component
    protocols*: seq[int]
    curState*: TypeState
    dstState*: TypeState
    stateStack: seq[ref StateInfo[TypeState]]
    tempStack: seq[ref StateInfo[TypeState]]
    deferredMessages: seq[MsgPtr]
    ma*: MsgArenaPtr
    ml*: MsgLooperPtr
    states: TableRef[TypeState, ref StateInfo[TypeState]]


proc newStateInfo[TypeState](sm: ref StateMachine[TypeState], name: string,
    state: TypeState, enter: TypeState, exit: TypeState, parent: TypeState):
      ref StateInfo[TypeState] =
  var
    parentStateInfo: ref StateInfo[TypeState]

  new(result)
  if parent != nil and hasKey(sm.states, parent):
    parentStateInfo = mget(sm.states, parent)
    when DBG: echo "parent=", parentStateInfo.name
  else:
    when DBG: echo "parent not in table"
    parentStateInfo = nil
  result.name = name
  result.active = false
  result.enter = enter
  result.exit = exit
  result.state = state
  result.parentStateInfo = parentStateInfo

proc moveTempStackToStateStack[TypeStateMachine](sm: ref TypeStateMachine):
    int =
  ## Move the contents of the temporary stack to the state stack
  ## reversing the order of the items which are on the temporary
  ## stack.
  ##
  ## result is the index into sm.stateStack where entering needs to start
  result = sm.stateStack.high + 1
  for i in countdown(sm.tempStack.high, 0):
    var curSi = sm.tempStack[i]
    when DBG: echo "moveTempStackToStateStack: state=", curSi.name
    sm.stateStack.add(curSi)

proc moveDeferredMessagesToHipriorityMsgs[TypeStateMachine](
    sm: ref TypeStateMachine) =
  ## Move the deferred messages to high priority list
  ##
  ## result is the index into sm.stateStack where entering needs to start
  when DBG: echo "moveDeferredMessagesToHipriorityMsgs: len=",
    sm.deferredMessages.len
  if sm.deferredMessages.len > 0:
    for i in countdown(sm.deferredMessages.high, sm.deferredMessages.low):
      var msg = sm.deferredMessages[i]
      when DBG: echo "moveDeferredMessagesToHipriorityMsgs: msg=", msg
      sm.hipriorityMsgs.add(msg)
    sm.deferredMessages.setLen(0)

proc setupTempStackWithStatesToEnter[TypeStateMachine, TypeState](
    sm: ref TypeStateMachine, dstState: TypeState): ref StateInfo[TypeState] =
  ## Setup the tempStack with the states we're going to enter.
  ##
  ## This is found by searching up the dstState's parents for a
  ## state that is already active i.e. stateInfo.active == true.
  ## The state and all of the inactive parents will be placed on
  ## the tempStack as the list of states to enter.
  ##
  ## result is the common ancestor parent or nil if there is none
  sm.tempStack.setLen(0)
  result = sm.states.mget(dstState)

  # Always add the first state as we must always enter the dstState
  # whether its active or not.
  while true:
    when DBG: echo "setupTempStackWithStatesToEnter: will enter state=",
        result.name
    sm.tempStack.add(result)
    result = result.parentStateInfo
    if result == nil or result.active:
      break
  when DBG: echo "setupTempStackWithStatesToEnter: common state=",
      (if result == nil: "<nil>" else: result.name)

proc invokeEnterProcs[TypeStateMachine](sm: ref TypeStateMachine,
    stateStackEnteringIndex: int) =
  ## Invoke the enter procs starting at sm.stateStack[stateStackEnteringIndex].
  ## In addition these are marked active so we can find the common state info
  ## in the future.
  for i in countup(stateStackEnteringIndex, sm.stateStack.high):
    var si = sm.stateStack[i]
    si.active = true
    if si.enter != nil:
      when DBG: echo "invokeEnterProcs: state=", si.name
      discard si.enter(sm, nil)

proc invokeExitProcs[TypeStateMachine, TypeState](
    sm: ref TypeStateMachine, commonSi: ref StateInfo[TypeState]) =
  ## Invoke the exit proc starting at the top of the stateStack downto
  ## the commonSi. If commonSi is nil then we'll be exiting all states.
  ## Also, every state we exit we'll remove from the stateStack and mark
  ## it not active.
  var stateStackLen = sm.stateStack.len
  var count = 0
  for idx in countdown(sm.stateStack.high, sm.stateStack.low):
    var si = sm.stateStack[idx]
    if si != commonSi:
      when DBG: echo "invokeExitProcs: state=", si.name
      count += 1
      if si.exit != nil:
        discard si.exit(sm, nil)
      si.active = false
    else:
      break;
  # Pop the exited states
  sm.stateStack.setLen(stateStackLen - count)

proc performTransitions[TypeStateMachine, TypeState](sm: ref TypeStateMachine,
    msg: MsgPtr) =
  ## Perform any necessary transitions
  if sm.dstState != nil:
    # Loop incase exit or enter methods invoke transitionTo
    var dstState = sm.dstState
    while true:
      # Get the states to enter and place them on the tempStack. Also
      # find the common ancestor state.
      var commonSi = sm.setupTempStackWithStatesToEnter(dstState)

      # Starting at the top of the stateStack down to the common state
      # pop them from the stateStack and invoke the exit proc.
      sm.invokeExitProcs(commonSi)

      # Move the temp stack to state stack and invoke enter on the
      # new entries.
      var startingEnteringIndex = sm.moveTempStackToStateStack()
      sm.invokeEnterProcs(startingEnteringIndex)

      # Since we have transitioned to a new state we need to have
      # any deferred messages move to the front of the message queue
      # so they will be processed before any other messages in the
      # message queue.
      sm.moveDeferredMessagesToHipriorityMsgs()

      # Check if the dstState has changed
      if sm.dstState != nil and sm.dstState != dstState:
        # Did change so continue looping
        dstState = sm.dstState
        when DBG: echo "performTransitions:  new dest=",
          sm.states[dstState].name
      else:
        # Did not change so we're done
        sm.curState = dstState
        sm.dstState = nil
        when DBG: echo "performTransitions:- curState=",
          sm.states[sm.curState].name
        break

proc startStateMachine*[TypeStateMachine, TypeState](sm: ref TypeStateMachine,
    initialState: TypeState) =
  ## Start the state machine at initialState
  sm.curState = initialState

  # Push onto the tempStack current and all its parents.
  var curSi = mget(sm.states, sm.curState)
  while curSi != nil:
    sm.tempStack.add(curSi)
    curSi = curSi.parentStateInfo

  # Start with empty stack
  sm.stateStack.setLen(0)
  invokeEnterProcs(sm, moveTempStackToStateStack(sm))

proc addStateEXP*[TypeState](sm: ref StateMachine[TypeState], name: string,
    state: TypeState, enter: TypeState, exit: TypeState,
    parent: TypeState) =
  ## Add a new state to the hierarchy. The parent argument may be nil
  ## if the state has no parent.
  if hasKey(sm.states, state):
    doAssert(false, "state already added: " & name)
  else:
    var stateInfo = newStateInfo(sm, name, state, enter, exit,
      parent)
    when DBG: echo "addState: state=", stateInfo.name
    var parentName: string
    if stateInfo.parentStateInfo != nil:
      parentName = stateInfo.parentStateInfo.name
    else:
      parentName = "<nil>"
    when DBG: echo "addState: parent=", parentName
    add(sm.states, state, stateInfo)

proc addState*[TypeState](sm: ref StateMachine[TypeState], name: string,
    state: TypeState) =
  ## Add a new state to the hierarchy. The parent argument may be nil
  ## if the state has no parent.
  addStateEXP(sm, name, state, nil, nil, nil)

proc transitionTo*[TypeState](sm: ref StateMachine[TypeState],
    state: TypeState) =
  ## Save the state we're to transition to when processing of the
  ## current state has completed.
  sm.dstState = state

proc deferMessage*[TypeState](sm: ref StateMachine[TypeState],
    msg: MsgPtr) =
  ## Save the message on the deferred list. The deferred list
  ## will be moved to the front of the msg queue after each
  ## transition to a new state in the order they were deferred
  ## with the oldest at the beginning of the queue.
  ##
  ## We assume ownership of the message has been transferred
  ## to the statemachine thus it is not necessary to copy it.
  sm.deferredMessages.add(msg)

proc dispatcher[TypeStateMachine, TypeState](cp: ComponentPtr, msg: MsgPtr) =
  ## dispatcher cast cp to a TypeStateMachine and call current state
  var sm = cast[ref TypeStateMachine](cp)
  var val = sm.curState(sm, msg)
  var curSi: ref StateInfo[TypeState]
  if val != Handled:
    when DBG: echo "dispatcher: ", sm.name, ".", sm.stateStack[sm.stateStack.high].name,
      " !Handled msg:", msg
    curSi = sm.stateStack[sm.stateStack.high].parentStateInfo
    while curSi != nil:
      val = curSi.state(sm, msg)
      if val == Handled:
        break;
      when DBG: echo "dispatcher: ", sm.name, ".", curSi.name,
        " did not handle msg:", msg
      curSi = curSi.parentStateInfo
  else:
    when DBG: curSi = sm.stateStack[sm.stateStack.high]
  when DBG:
    if curSi != nil:
      echo "dispatcher: ", sm.name, ".", curSi.name, " Handled msg:", msg

  performTransitions[TypeStateMachine, TypeState](sm, msg)

proc initStateMachine*[TypeStateMachine, TypeState](
    sm: ref StateMachine[TypeState], name: string, ml: MsgLooperPtr) =
  ## Initialize StateMachine
  when DBG: echo "initStateMacine: e"
  sm.states = newTable[TypeState, ref StateInfo[TypeState]]()
  sm.name = name
  sm.pm = dispatcher[TypeStateMachine, TypeState]
  sm.ma = newMsgArena()
  sm.ml = ml
  sm.hipriorityMsgs = @[]
  sm.rcvq = newMpscFifo("fifo_" & name, sm.ma, sm.ml)
  sm.curState = nil
  sm.stateStack = @[]
  sm.tempStack = @[]
  sm.deferredMessages = @[]
  when DBG: echo "initStateMacine: x"

proc deinitStateMachine*[TypeState](sm: ref StateMachine[TypeState]) =
  ## deinitialize StateMachine
  sm.rcvq.delMpscFifo()
  sm.ma.delMsgArena()

when isMainModule:
  import unittest

  suite "t1":
    type
      SmT1State = proc(sm: ref SmT1, msg: MsgPtr): StateResult
      SmT1 = object of StateMachine[SmT1State]
        ## SmT1 is a statemachine with a counter
        count: int
        defaultCount: int
        s0Count: int
        s1Count: int

    ## Forward declare states
    proc default(sm: ref SmT1, msg: MsgPtr): StateResult
    proc s0(sm: ref SmT1, msg: MsgPtr): StateResult
    proc s0DeferToS1(sm: ref SmT1, msg: MsgPtr): StateResult
    proc s0TransitionToS1NotHandled(sm: ref SmT1, msg: MsgPtr): StateResult
    proc s1(sm: ref SmT1, msg: MsgPtr): StateResult
    proc s1NotHandled(sm: ref SmT1, msg: MsgPtr): StateResult

    proc defaultEnter(sm: ref SmT1, msg: MsgPtr): StateResult =
      echo "defaultEnter"
      result = Handled
    proc defaultExit(sm: ref SmT1, msg: MsgPtr): StateResult =
      echo "defaultExit"
      result = Handled
    proc default(sm: ref SmT1, msg: MsgPtr): StateResult =
      ## default state no transition increments counters
      sm.count += 1
      sm.defaultCount += 1
      echo "default: count=", sm.count
      msg.rspq.add(msg)
      result = Handled

    proc s0Enter(sm: ref SmT1, msg: MsgPtr): StateResult =
      echo "s0Enter"
      result = Handled
    proc s0Exit(sm: ref SmT1, msg: MsgPtr): StateResult =
      echo "s0Exit"
      result = Handled
    proc s0(sm: ref SmT1, msg: MsgPtr): StateResult =
      ## S0 state transitions to S1 increments counter
      sm.count += 1
      sm.s0Count += 1
      echo "s0: count=", sm.count
      transitionTo[SmT1State](sm, s1)
      msg.rspq.add(msg)
      result = Handled
    proc s0DeferToS1(sm: ref SmT1, msg: MsgPtr): StateResult =
      ## S0DeferToS1 processes defers 2 messages and then
      ## transitions to s1
      sm.count += 1
      sm.s0Count += 1
      echo "s0: count=", sm.count
      deferMessage[SmT1State](sm, msg)
      if sm.s0Count >= 2:
        transitionTo[SmT1State](sm, s1)
      result = Handled
    proc s0TransitionToS1NotHandled(sm: ref SmT1, msg: MsgPtr): StateResult =
      ## S0 state transitions to S1 increments counter
      sm.count += 1
      sm.s0Count += 1
      echo "s0: count=", sm.count
      transitionTo[SmT1State](sm, s1NotHandled)
      msg.rspq.add(msg)
      result = Handled


    proc s1Enter(sm: ref SmT1, msg: MsgPtr): StateResult =
      echo "s1Enter"
      result = Handled
    proc s1Exit(sm: ref SmT1, msg: MsgPtr): StateResult =
      echo "s1Exit"
      result = Handled
    proc s1(sm: ref SmT1, msg: MsgPtr): StateResult =
      ## S1 state transitions to S0 and increments counter
      sm.count += 1
      sm.s1Count += 1
      echo "s1: count=", sm.count
      msg.rspq.add(msg)
      result = Handled
    proc s1NotHandled(sm: ref SmT1, msg: MsgPtr): StateResult =
      ## S1 state transitions to S0 and increments counter
      sm.count += 1
      sm.s1Count += 1
      echo "s1: count=", sm.count
      result = NotHandled

    proc newSmT1NonState(ml: MsgLooperPtr): ref SmT1 =
      echo "initSmT1NonState:+"
      ## Create a new SmT1 state machine
      new(result)
      initStateMachine[SmT1, SmT1State](result, "smt1", ml)
      result.count = 0
      result.defaultCount = 0
      result.s0Count = 0
      result.s1Count = 0

    proc newSmT1OneState(ml: MsgLooperPtr): ptr Component =
      var smT1 = newSmT1NonState(ml)

      addState[SmT1State](smT1, "default", default)
      startStateMachine[SmT1, SmT1State](smT1, default)
      # TODO: DANGEROUS, but addComponent requires this to return a ptr
      result = cast[ptr Component](smT1)
      echo "newSmT1OneState:-"

    proc newSmT1TwoStates(ml: MsgLooperPtr): ptr Component =
      var smT1 = newSmT1NonState(ml)

      addState[SmT1State](smT1, "s0", s0)
      addState[SmT1State](smT1, "s1", s1)
      startStateMachine[SmT1, SmT1State](smT1, s0)
      # TODO: DANGEROUS, but addComponent requires this to return a ptr
      result = cast[ptr Component](smT1)
      echo "newSmT1TwoStates:-"

    proc newSmT1TwoStatesS0DeferToS1(ml: MsgLooperPtr): ptr Component =
      var smT1 = newSmT1NonState(ml)

      addState[SmT1State](smT1, "s0DeferToS1", s0DeferToS1)
      addState[SmT1State](smT1, "s1", s1)
      startStateMachine[SmT1, SmT1State](smT1, s0DeferToS1)
      # TODO: DANGEROUS, but addComponent requires this to return a ptr
      result = cast[ptr Component](smT1)
      echo "newSmT1TwoStates:-"

    proc newSmT1TriangleStates(ml: MsgLooperPtr): ptr Component =
      var smT1 = newSmT1NonState(ml)

      addStateEXP[SmT1State](smT1, "default", default, defaultEnter,
        defaultExit, nil)
      addStateEXP[SmT1State](smT1, "s0TransitionToS1NotHandled",
        s0TransitionToS1NotHandled, s0Enter, s0Exit, default)
      addStateEXP[SmT1State](smT1, "s1NotHandled", s1NotHandled, s1Enter, s1Exit, default)
      startStateMachine[SmT1, SmT1State](smT1, s0TransitionToS1NotHandled)
      # TODO: DANGEROUS, but addComponent requires this to return a ptr
      result = cast[ptr Component](smT1)
      echo "newSmT1TringleStates:-"

    proc delSmT1(cp: ptr Component) =
      echo "delSmT1:+"
      deinitStateMachine[SmT1State](cast[ref SmT1](cp))
      echo "delSmT1:-"

    var
      smT1: ptr SmT1
      msg: MsgPtr
      ma = newMsgArena()
      rcvq = newMpscFifo("rcvq", ma)
      ml = newMsgLooper("ml_smt1")

    test "test-add-del-component":
      echo "test-add-del-component"

      proc checkSendingTwoMsgs(sm: ptr SmT1, ma: MsgArenaPtr,
          rcvq: MsgQueuePtr) =
        # Send first message, should be processed by default
        var msg: MsgPtr
        msg = ma.getMsg(rcvq, 1)
        sm.rcvq.add(msg)
        msg = rcvq.rmv()
        check msg.cmd == 1
        check sm.count == 1
        check sm.defaultCount == 1
        check sm.s0Count == 0
        check sm.s1Count == 0

        # Send second message, should be processed by default
        msg = ma.getMsg(rcvq, 2)
        sm.rcvq.add(msg)
        msg = rcvq.rmv()
        check msg.cmd == 2
        check sm.count == 2
        check sm.defaultCount == 2
        check sm.s0Count == 0
        check sm.s1Count == 0

      var sm1 = addComponent[SmT1](ml, newSmT1OneState)
      check sm1.stateStack.low == 0
      check sm1.stateStack.high == 0
      check sm1.stateStack[0].name == "default"
      checkSendingTwoMsgs(sm1, ma, rcvq)

      var sm2 = addComponent[SmT1](ml, newSmT1OneState)
      check sm2.stateStack.low == 0
      check sm2.stateStack.high == 0
      check sm2.stateStack[0].name == "default"
      checkSendingTwoMsgs(sm2, ma, rcvq)

      # delete the first one added
      delComponent(ml, sm1, delSmT1)
      # delete it again, be sure nothing blows up
      delComponent(ml, sm1, delSmT1)

      ## Add first one back, this will use the first slot
      sm1 = addComponent[SmT1](ml, newSmT1OneState)
      checkSendingTwoMsgs(sm1, ma, rcvq)

      ## delete both
      delComponent(ml, sm1, delSmT1)
      delComponent(ml, sm2, delSmT1)

    # Tests default as the one and only state
    setup:
      smT1 = addComponent[SmT1](ml, newSmT1OneState)

    teardown:
      delComponent(ml, smT1, delSmT1)
      smT1 = nil

    test "test-one-state":
      echo "test-one-state"

      proc checkSendingTwoMsgs(sm: ptr SmT1, ma: MsgArenaPtr,
          rcvq: MsgQueuePtr) =
        # Send first message, should be processed by default
        var msg: MsgPtr
        msg = ma.getMsg(rcvq, 1)
        sm.rcvq.add(msg)
        msg = rcvq.rmv()
        check msg.cmd == 1
        check sm.count == 1
        check sm.defaultCount == 1
        check sm.s0Count == 0
        check sm.s1Count == 0

        # Send second message, should be processed by default
        msg = ma.getMsg(rcvq, 2)
        sm.rcvq.add(msg)
        msg = rcvq.rmv()
        check msg.cmd == 2
        check sm.count == 2
        check sm.defaultCount == 2
        check sm.s0Count == 0
        check sm.s1Count == 0

      checkSendingTwoMsgs(smT1, ma, rcvq)

    # Test with two states s0, s1
    setup:
      smT1 = addComponent[SmT1](ml, newSmT1TwoStates)

    teardown:
      delComponent(ml, smT1, delSmT1)
      smT1 = nil

    test "test-two-states":
      var
        rcvq = newMpscFifo("rcvq", smT1.ma)
        msg: MsgPtr

      # Send first message, should be processed by S0
      msg = smT1.ma.getMsg(rcvq, 1)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 1
      check smt1.count == 1
      check smt1.defaultCount == 0
      check smt1.s0Count == 1
      check smt1.s1Count == 0

      # Send second message, should be processed by S1
      msg = smT1.ma.getMsg(rcvq, 2)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 2
      check smt1.count == 2
      check smt1.defaultCount == 0
      check smt1.s0Count == 1
      check smt1.s1Count == 1

    # Test deferred msgs, we have to have at least two states
    # and must do a transition to test the deferred msgs
    setup:
      smT1 = addComponent[SmT1](ml, newSmT1TwoStatesS0DeferToS1)

    teardown:
      delComponent(ml, smT1, delSmT1)
      smT1 = nil

    test "test-deferred-msgs":
      var
        rcvq = newMpscFifo("rcvq", smT1.ma)
        msg: MsgPtr

      # Send three messages first two will be processed by S0DeferToS1
      # but deferred. On the second message to S0DeferToS1 it will
      # transition to S1 which will then process all 3 messages.
      msg = smT1.ma.getMsg(rcvq, 1)
      smT1.rcvq.add(msg)
      msg = smT1.ma.getMsg(rcvq, 2)
      smT1.rcvq.add(msg)
      msg = smT1.ma.getMsg(rcvq, 3)
      smT1.rcvq.add(msg)

      # Get the responses which should be in the proper order
      msg = rcvq.rmv()
      check msg.cmd == 1
      msg = rcvq.rmv()
      check msg.cmd == 2
      msg = rcvq.rmv()
      check msg.cmd == 3
      check smt1.count == 5
      check smt1.defaultCount == 0
      check smt1.s0Count == 2
      check smt1.s1Count == 3

    # Test with default and two child states s0TransitionToS1NotHandled,
    # s1NotHandled in a triangle and default as the base state
    setup:
      smT1 = addComponent[SmT1](ml, newSmT1TriangleStates)

    teardown:
      delComponent(ml, smT1, delSmT1)
      smT1 = nil

    test "test-triangle-hsm":
      var
        rcvq = newMpscFifo("rcvq", smT1.ma)
        msg: MsgPtr

      check smT1.stateStack.low == 0
      check smT1.stateStack.high == 1
      check smT1.stateStack[0].name == "default"
      check smT1.stateStack[1].name == "s0TransitionToS1NotHandled"

      check smt1.count == 0
      check smt1.defaultCount == 0
      check smt1.s0Count == 0
      check smt1.s1Count == 0

      # Send first message, should be processed by S0
      msg = smT1.ma.getMsg(rcvq, 1)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 1
      check smt1.count == 1
      check smt1.defaultCount == 0
      check smt1.s0Count == 1
      check smt1.s1Count == 0

      # Send second message, should be processed by S1
      msg = smT1.ma.getMsg(rcvq, 2)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 2
      check smt1.count == 3
      check smt1.defaultCount == 1
      check smt1.s0Count == 1
      check smt1.s1Count == 1

      check smT1.stateStack.low == 0
      check smT1.stateStack.high == 1
      check smT1.stateStack[0].name == "default"
      check smT1.stateStack[1].name == "s1NotHandled"
