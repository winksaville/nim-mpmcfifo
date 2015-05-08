## A state machine where the current state is defined as
## a process to exeucte. This will evolve into a hierarchical
## state machine with enter and exit methods and problably
## using templates or macros to make it easy to use.
import msg, msgarena, msglooper, mpscfifo, fifoutils, tables, typeinfo

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
  if parent != nil and hasKey[TypeState, ref StateInfo[TypeState]](sm.states, parent):
    echo "parent exists"
    parentStateInfo = mget[TypeState, ref StateInfo[TypeState]](sm.states, parent)
  else:
    echo "parent not in table"
    parentStateInfo = nil
  result.state = state
  result.parentStateInfo = parentStateInfo

proc `$`*(si: ref StateInfo): string =
  result = "{state=" # & si.state

#proc initStateMachine*[TypeStateMachine, TypeState](sm: ref StateMachine[TypeState],
#    name: string) =
#  ## Initialize StateMachine
#  sm.states = newTable[TypeState, ref StateInfo[TypeState]]()
#  sm.name = name
#  sm.pm = dispatcher[TypeStateMachine]
#  sm.ma = newMsgArena()
#  sm.ml = newMsgLooper("ml_" & name)
#  sm.rcvq = newMpscFifo("fifo_" & name, sm.ma, sm.ml)
#  sm.curState = nil
#  sm.ml.addProcessMsg(sm)

proc initStateMachineX*[TypeStateMachine, TypeState](sm: ref StateMachine[TypeState],
    name: string, ml: MsgLooperPtr) =
  ## Initialize StateMachine
  echo "initStateMacineX: e"
  sm.states = newTable[TypeState, ref StateInfo[TypeState]]()
  sm.name = name
  sm.pm = dispatcher[TypeStateMachine]
  sm.ma = newMsgArena()
  sm.ml = ml
  sm.rcvq = newMpscFifo("fifo_" & name, sm.ma, sm.ml)
  sm.curState = nil
  echo "initStateMacineX: x sm.ma=", sm.ma

proc deinitStateMachine*[TypeState](sm: ref StateMachine[TypeState]) =
  ## deinitialize StateMachine
  sm.ml.delMsgLooper()
  sm.rcvq.delMpscFifo()
  sm.ma.delMsgArena()

proc startStateMachine*[TypeState](sm: ref StateMachine[TypeState], initialState: TypeState) =
  ## Start the state machine at initialState
  ## TODO: More to do when hierarchy is implemented
  sm.curState = initialState

proc addState*[TypeState](sm: ref StateMachine[TypeState], state: TypeState, parent: TypeState = nil) =
  ## Add a new state to the hierarchy. The parent argument may be nil
  ## if the state has no parent.
  if hasKey[TypeState, ref StateInfo[TypeState]](sm.states, state):
    echo "addState: state already added"
  else:
    echo "addState: adding state"
    var stateInfo = newStateInfo[TypeState](sm, state, parent)
    add[TypeState, ref StateInfo[TypeState]](sm.states, state, stateInfo)

proc transitionTo*[TypeState](sm: ref StateMachine[TypeState], state: TypeState) =
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

    proc newSmT1X(ml: MsgLooperPtr): ptr Component =
      echo "newSmT1X: e"
      ## Create a new SmT1 state machine
      var
        smT1: ref SmT1
      new(smT1)
      #smT1 = allocObject[SmT1]()
      initStateMachineX[SmT1, SmT1State](smT1, "smt1", ml)

      addState[SmT1State](smT1, default)
      startStateMachine[SmT1State](smT1, default)
      # TODO: DANGEROUS, but addComponent requires this to return a ptr
      result = cast[ptr Component](smT1)
      echo "newSmT1X: x"

    proc delSmT1(sm: ref SmT1) =
      deinitStateMachine[SmT1State](sm)

    var
      smT1: ptr SmT1
      msg: MsgPtr
      ma = newMsgArena()
      rcvq = newMpscFifo("rcvq", ma)

    # Tests default as the one and only state
    setup:
      var ml = newMsgLooper("ml_smt1")
      smT1 = addComponent[SmT1](ml, newSmT1X)

    teardown:
      #delComponent[SmT1](ml, delSmT1)
      smT1 = nil

    test "test-one-state":
      echo "test-one-state"

      # Send first message, should be processed by default
      msg = smT1.ma.getMsg(rcvq, 1)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 1
      check smt1.count == 1
      check smt1.defaultCount == 1
      check smt1.s0Count == 0
      check smt1.s1Count == 0

      # Send second message, should be processed by default
      msg = smT1.ma.getMsg(rcvq, 2)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 2
      check smt1.count == 2
      check smt1.defaultCount == 2
      check smt1.s0Count == 0
      check smt1.s1Count == 0

    ## Test with two states s0, s1
    #setup:
    #  smT1 = newSmT1()
    #  addState[SmT1State](smT1, s0)
    #  addState[SmT1State](smT1, s1)
    #  startStateMachine[SmT1State](smT1, s0)

    #teardown:
    #  smT1.delSmt1()

    #test "test-two-states":
    #  var
    #    rcvq = newMpscFifo("rcvq", smT1.ma)
    #    msg: MsgPtr

    #  # Send first message, should be processed by S0
    #  msg = smT1.ma.getMsg(rcvq, 1)
    #  smT1.rcvq.add(msg)
    #  msg = rcvq.rmv()
    #  check msg.cmd == 1
    #  check smt1.count == 1
    #  check smt1.defaultCount == 0
    #  check smt1.s0Count == 1
    #  check smt1.s1Count == 0

    #  # Send second message, should be processed by S1
    #  msg = smT1.ma.getMsg(rcvq, 2)
    #  smT1.rcvq.add(msg)
    #  msg = rcvq.rmv()
    #  check msg.cmd == 2
    #  check smt1.count == 2
    #  check smt1.defaultCount == 0
    #  check smt1.s0Count == 1
    #  check smt1.s1Count == 1

    ## Test with default and two child states s0, s1
    ## TODO: Add passing of unhandled message and verify
    ## TODO: that default is invoked
    #setup:
    #  smT1 = newSmT1()
    #  addState[SmT1State](smT1, default)
    #  addState[SmT1State](smT1, s0, default)
    #  addState[SmT1State](smT1, s1, default)
    #  addState[SmT1State](smT1, s1, default)

    #  startStateMachine[SmT1State](smT1, s0)

    #teardown:
    #  smT1.delSmt1()

    #test "test-default-and-two-child-states":
    #  var
    #    rcvq = newMpscFifo("rcvq", smT1.ma)
    #    msg: MsgPtr

    #  # Send first message, should be processed by S0
    #  msg = smT1.ma.getMsg(rcvq, 1)
    #  smT1.rcvq.add(msg)
    #  msg = rcvq.rmv()
    #  check msg.cmd == 1
    #  check smt1.count == 1
    #  check smt1.defaultCount == 0
    #  check smt1.s0Count == 1
    #  check smt1.s1Count == 0

    #  # Send second message, should be processed by S1
    #  msg = smT1.ma.getMsg(rcvq, 2)
    #  smT1.rcvq.add(msg)
    #  msg = rcvq.rmv()
    #  check msg.cmd == 2
    #  check smt1.count == 2
    #  check smt1.defaultCount == 0
    #  check smt1.s0Count == 1
    #  check smt1.s1Count == 1
