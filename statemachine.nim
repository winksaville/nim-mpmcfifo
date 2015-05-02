import msg, msgarena, msglooper, mpscfifo, fifoutils

type
  StateMachine*[TypeState] = object of Component
    protocols: seq[int]
    curState: TypeState

proc dispatcher[TypeStateMachine](cp: ComponentPtr, msg: MsgPtr) =
  var sm = cast[ptr TypeStateMachine](cp)
  sm.curState(sm, msg)

proc initStateMachine*[TypeState](sm: ptr StateMachine[TypeState], name: string,
    dispatcher: ProcessMsg, initialState: TypeState, rcvq: QueuePtr) =
  sm.name = name
  sm.pm = dispatcher
  sm.curState = initialState
  sm.rcvq = rcvq

proc transitionTo[TypeState](sm: ptr StateMachine[TypeState], state: TypeState) =
  sm.curState = state

when isMainModule:
  import unittest

  suite "t1":
    type
      MlSmBase[TypeState] = object of StateMachine[TypeState]
        ma: MsgArenaPtr
        ml: MsgLooperPtr

      ## SmT1 is a statemachine with 2 states s0 and s1
      SmT1State = proc(sm: ptr SmT1, msg: MsgPtr)
      SmT1 = object of MlSmBase[SmT1State]
        count: int

    proc s1(sm: ptr SmT1, msg: MsgPtr)

    proc s0(sm: ptr SmT1, msg: MsgPtr) =
      sm.count += 1
      echo "s0: count=", sm.count
      transitionTo[SmT1State](sm, s1)
      msg.rspq.add(msg)

    proc s1(sm: ptr SmT1, msg: MsgPtr) =
      sm.count += 1
      echo "s1: count=", sm.count
      transitionTo[SmT1State](sm, s0)
      msg.rspq.add(msg)

    proc newSmT1(): ptr SmT1 =
      result = allocObject[SmT1]()
      result.ma = newMsgArena()
      result.ml = newMsgLooper("ml1")
      result.rcvq = newMpscFifo("fifo", result.ma, result.ml)
      initStateMachine[SmT1State](result, "smt1", dispatcher[SmT1], s0, result.rcvq)
      result.ml.addProcessMsg(result)

    var
      smT1: ptr SmT1

    setup:
      smT1 = newSmT1()

    test "transition":
      var
        rcvq = newMpscFifo("rcvq", smT1.ma)
        msg: MsgPtr

      msg = smT1.ma.getMsg(rcvq, 1)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 1
      msg = smT1.ma.getMsg(rcvq, 2)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 2
