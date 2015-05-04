## A state machine where the current state is defined as
## a process to exeucte. This will evolve into a hierarchical
## state machine with enter and exit methods and problably
## using templates or macros to make it easy to use.
import msg, msgarena, msglooper, mpscfifo, fifoutils

type
  StateMachine*[TypeState] = object of Component
    protocols*: seq[int]
    curState*: TypeState
    ma*: MsgArenaPtr
    ml*: MsgLooperPtr

proc dispatcher[TypeStateMachine](cp: ComponentPtr, msg: MsgPtr) =
  ## dispatcher cast cp to a TypeStateMachine and call current state
  var sm = cast[ptr TypeStateMachine](cp)
  sm.curState(sm, msg)

proc initStateMachine*[TypeStateMachine, TypeState](sm: ptr StateMachine[TypeState],
    name: string, initialState: TypeState) =
  ## Initialize StateMachine
  sm.name = name
  sm.pm = dispatcher[TypeStateMachine]
  sm.ma = newMsgArena()
  sm.ml = newMsgLooper("ml_" & name)
  sm.rcvq = newMpscFifo("fifo_" & name, sm.ma, sm.ml)
  sm.curState = initialState
  sm.ml.addProcessMsg(sm)

proc deinitStateMachine*[TypeState](sm: ptr StateMachine[TypeState]) =
  ## deinitialize StateMachine
  sm.ml.delMsgLooper()
  sm.rcvq.delMpscFifo()
  sm.ma.delMsgArena()

proc transitionTo*[TypeState](sm: ptr StateMachine[TypeState], state: TypeState) =
  ## Transition to a new state
  sm.curState = state

when isMainModule:
  import unittest

  suite "t1":
    type
      SmT1State = proc(sm: ptr SmT1, msg: MsgPtr)
      SmT1 = object of StateMachine[SmT1State]
        ## SmT1 is a statemachine with a counter
        count: int
        s0Count: int
        s1Count: int

    ## Forward declare states
    proc s1(sm: ptr SmT1, msg: MsgPtr)
    proc s0(sm: ptr SmT1, msg: MsgPtr)

    proc s0(sm: ptr SmT1, msg: MsgPtr) =
      ## S0 state transitions to S1 increments counter
      sm.count += 1
      sm.s0Count += 1
      echo "s0: count=", sm.count
      transitionTo[SmT1State](sm, s1)
      msg.rspq.add(msg)

    proc s1(sm: ptr SmT1, msg: MsgPtr) =
      ## S1 state transitions to S0 and increments counter
      sm.count += 1
      sm.s1Count += 1
      echo "s1: count=", sm.count
      transitionTo[SmT1State](sm, s0)
      msg.rspq.add(msg)

    proc newSmT1(): ptr SmT1 =
      ## Create a new SmT1 state machine
      result = allocObject[SmT1]()
      initStateMachine[SmT1, SmT1State](result, "smt1", s0)

    proc delSmT1(sm: ptr SmT1) =
      deinitStateMachine[SmT1State](sm)

    var
      smT1: ptr SmT1

    setup:
      smT1 = newSmT1()

    teardown:
      smT1.delSmt1()

    test "transition":
      var
        rcvq = newMpscFifo("rcvq", smT1.ma)
        msg: MsgPtr

      # Send first message, should be processed by S0
      msg = smT1.ma.getMsg(rcvq, 1)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 1
      check smt1.count == 1
      check smt1.s0Count == 1
      check smt1.s1Count == 0

      # Send second message, should be processed by S1
      msg = smT1.ma.getMsg(rcvq, 2)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 2
      check smt1.count == 2
      check smt1.s0Count == 1
      check smt1.s1Count == 1
