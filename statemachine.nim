## A state machine where the current state is defined as
## a process to exeucte. This will evolve into a hierarchical
## state machine with enter and exit methods and problably
## using templates or macros to make it easy to use.
import msg, msgarena, msglooper, mpscfifo, fifoutils, tables, typeinfo, os

type
  StateInfo[TypeState] = object of RootObj
    state: TypeState
    parentStateInfo: ref StateInfo[TypeState]

  StateMachine*[TypeState] = object of Component
    protocols*: seq[int]
    curState*: TypeState
    ma*: MsgArenaPtr
    ml*: MsgLooperPtr
    states: TableRef[TypeState, ref StateInfo[TypeState]]


proc dispatcher[TypeStateMachine](cp: ComponentPtr, msg: MsgPtr) =
  ## dispatcher cast cp to a TypeStateMachine and call current state
  var sm = cast[ref TypeStateMachine](cp)
  sm.curState(sm, msg)

proc newStateInfo[TypeState](sm: ref StateMachine[TypeState],
    state: TypeState, parent: TypeState): ref StateInfo[TypeState] =
  var
    parentStateInfo: ref StateInfo[TypeState]

  new(result)
  if parent != nil and hasKey[TypeState, ref StateInfo[TypeState]](
      sm.states, parent):
    echo "parent exists"
    parentStateInfo = mget[TypeState, ref StateInfo[TypeState]](
      sm.states, parent)
  else:
    echo "parent not in table"
    parentStateInfo = nil
  result.state = state
  result.parentStateInfo = parentStateInfo

proc `$`*(si: ref StateInfo): string =
  result = "{state=" # & si.state

#proc initStateMachine*[TypeStateMachine, TypeState](
#    sm: ref StateMachine[TypeState], name: string) =
#  ## Initialize StateMachine
#  sm.states = newTable[TypeState, ref StateInfo[TypeState]]()
#  sm.name = name
#  sm.pm = dispatcher[TypeStateMachine]
#  sm.ma = newMsgArena()
#  sm.ml = newMsgLooper("ml_" & name)
#  sm.rcvq = newMpscFifo("fifo_" & name, sm.ma, sm.ml)
#  sm.curState = nil
#  sm.ml.addProcessMsg(sm)

proc initStateMachineX*[TypeStateMachine, TypeState](
    sm: ref StateMachine[TypeState], name: string, ml: MsgLooperPtr) =
  ## Initialize StateMachine
  echo "initStateMacineX: e"
  sm.states = newTable[TypeState, ref StateInfo[TypeState]]()
  sm.name = name
  sm.pm = dispatcher[TypeStateMachine]
  sm.ma = newMsgArena()
  sm.ml = ml
  sm.rcvq = newMpscFifo("fifo_" & name, sm.ma, sm.ml)
  sm.curState = nil
  echo "initStateMacineX: x"

proc deinitStateMachine*[TypeState](sm: ref StateMachine[TypeState]) =
  ## deinitialize StateMachine
  sm.rcvq.delMpscFifo()
  sm.ma.delMsgArena()

proc startStateMachine*[TypeState](sm: ref StateMachine[TypeState],
    initialState: TypeState) =
  ## Start the state machine at initialState
  ## TODO: More to do when hierarchy is implemented
  sm.curState = initialState

proc addState*[TypeState](sm: ref StateMachine[TypeState], state: TypeState,
    parent: TypeState = nil) =
  ## Add a new state to the hierarchy. The parent argument may be nil
  ## if the state has no parent.
  if hasKey[TypeState, ref StateInfo[TypeState]](sm.states, state):
    echo "addState: state already added"
  else:
    echo "addState: adding state"
    var stateInfo = newStateInfo[TypeState](sm, state, parent)
    add[TypeState, ref StateInfo[TypeState]](sm.states, state, stateInfo)

proc transitionTo*[TypeState](sm: ref StateMachine[TypeState],
    state: TypeState) =
  ## Transition to a new state
  sm.curState = state

when isMainModule:
  import unittest

  suite "t1":
    type
      SmT1State = proc(sm: ref SmT1, msg: MsgPtr)
      SmT1 = object of StateMachine[SmT1State]
        ## SmT1 is a statemachine with a counter
        count: int
        defaultCount: int
        s0Count: int
        s1Count: int

    ## Forward declare states
    proc default(sm: ref SmT1, msg: MsgPtr)
    proc s1(sm: ref SmT1, msg: MsgPtr)
    proc s0(sm: ref SmT1, msg: MsgPtr)

    proc default(sm: ref SmT1, msg: MsgPtr) =
      ## default state no transition increments counters
      sm.count += 1
      sm.defaultCount += 1
      echo "default: count=", sm.count
      msg.rspq.add(msg)

    proc s0(sm: ref SmT1, msg: MsgPtr) =
      ## S0 state transitions to S1 increments counter
      sm.count += 1
      sm.s0Count += 1
      echo "s0: count=", sm.count
      transitionTo[SmT1State](sm, s1)
      msg.rspq.add(msg)

    proc s1(sm: ref SmT1, msg: MsgPtr) =
      ## S1 state transitions to S0 and increments counter
      sm.count += 1
      sm.s1Count += 1
      echo "s1: count=", sm.count
      transitionTo[SmT1State](sm, s0)
      msg.rspq.add(msg)

    #proc newSmT1(): ref SmT1 =
    #  ## Create a new SmT1 state machine
    #  result = allocObject[SmT1]()
    #  initStateMachine[SmT1, SmT1State](result, "smt1")

    proc newSmT1NonState(ml: MsgLooperPtr): ref SmT1 =
      echo "initSmT1NonState:+"
      ## Create a new SmT1 state machine
      new(result)
      initStateMachineX[SmT1, SmT1State](result, "smt1", ml)
      result.count = 0
      result.defaultCount = 0
      result.s0Count = 0
      result.s1Count = 0

    proc newSmT1OneState(ml: MsgLooperPtr): ptr Component =
      var smT1 = newSmT1NonState(ml)

      addState[SmT1State](smT1, default)
      startStateMachine[SmT1State](smT1, default)
      # TODO: DANGEROUS, but addComponent requires this to return a ptr
      result = cast[ptr Component](smT1)
      echo "newSmT1X:-"

    proc newSmT1TwoStates(ml: MsgLooperPtr): ptr Component =
      var smT1 = newSmT1NonState(ml)

      addState[SmT1State](smT1, s0)
      addState[SmT1State](smT1, s1)
      startStateMachine[SmT1State](smT1, s0)
      # TODO: DANGEROUS, but addComponent requires this to return a ptr
      result = cast[ptr Component](smT1)
      echo "newSmT1X:-"

    proc newSmT1TriangleStates(ml: MsgLooperPtr): ptr Component =
      var smT1 = newSmT1NonState(ml)

      addState[SmT1State](smT1, default)
      addState[SmT1State](smT1, s0, default)
      addState[SmT1State](smT1, s1, default)
      startStateMachine[SmT1State](smT1, s0)
      # TODO: DANGEROUS, but addComponent requires this to return a ptr
      result = cast[ptr Component](smT1)
      echo "newSmT1X:-"

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

      addComponent[SmT1](ml, newSmT1OneState, rcvq)
      msg = rcvq.rmv()
      var sm1 = cast[ptr SmT1](msg.extra)
      check(msg.cmd == 1)
      checkSendingTwoMsgs(sm1, ma, rcvq)

      addComponent[SmT1](ml, newSmT1OneState, rcvq)
      msg = rcvq.rmv()
      check(msg.cmd == 1)
      var sm2 = cast[ptr SmT1](msg.extra)
      checkSendingTwoMsgs(sm2, ma, rcvq)

      # delete the first one added
      delComponent(ml, sm1, delSmT1, rcvq)
      msg = rcvq.rmv()
      check(msg.cmd == 1)
      # delete it again, be sure nothing blows up
      delComponent(ml, sm1, delSmT1, rcvq)
      msg = rcvq.rmv()
      check(msg.cmd == 1)
      #sleep(100)
      #
      ## Add first one back, this will use the first slot
      addComponent[SmT1](ml, newSmT1OneState, rcvq)
      msg = rcvq.rmv()
      check(msg.cmd == 1)
      sm1 = cast[ptr SmT1](msg.extra)
      checkSendingTwoMsgs(sm1, ma, rcvq)

      ## delete both
      delComponent(ml, sm1, delSmT1, rcvq)
      msg = rcvq.rmv()
      check(msg.cmd == 1)
      delComponent(ml, sm2, delSmT1, rcvq)
      msg = rcvq.rmv()
      check(msg.cmd == 1)

    # Tests default as the one and only state
    setup:
      addComponent[SmT1](ml, newSmT1OneState, rcvq)
      msg = rcvq.rmv()
      smT1 = cast[ptr SmT1](msg.extra)
      check(msg.cmd == 1)

    teardown:
      delComponent(ml, smT1, delSmT1, rcvq)
      msg = rcvq.rmv()
      check(msg.cmd == 1)
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

    ## Test with two states s0, s1
    setup:
      addComponent[SmT1](ml, newSmT1TwoStates, rcvq)
      msg = rcvq.rmv()
      smT1 = cast[ptr SmT1](msg.extra)
      check(msg.cmd == 1)

    teardown:
      delComponent(ml, smT1, delSmT1, rcvq)
      msg = rcvq.rmv()
      check(msg.cmd == 1)
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

    # Test with default and two child states s0, s1 in a triangle
    # TODO: Add passing of unhandled message and verify
    # TODO: that default is invoked
    setup:
      addComponent[SmT1](ml, newSmT1TriangleStates, rcvq)
      msg = rcvq.rmv()
      smT1 = cast[ptr SmT1](msg.extra)
      check(msg.cmd == 1)

    teardown:
      delComponent(ml, smT1, delSmT1, rcvq)
      msg = rcvq.rmv()
      check(msg.cmd == 1)
      smT1 = nil

    test "test-trinagle-states":
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
