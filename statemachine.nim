import msg, msgarena, msglooper, mpscfifo, fifoutils

type
  StateMachinePtr = ptr StateMachine
  StateMachine* = object of Component
    protocols: seq[int]
    curState: ProcessMsg

proc dispatcher(cp: ComponentPtr, msg: MsgPtr) =
  var sm = cast[StateMachinePtr](cp)
  sm.curState(sm, msg)

proc initStateMachine*(sm: StateMachinePtr, name: string, initialState: ProcessMsg,
      rcvq: QueuePtr) =
  sm.name = name
  sm.pm = dispatcher
  sm.curState = initialState
  sm.rcvq = rcvq

proc transitionTo(cp: ComponentPtr, pm: ProcessMsg) =
  var sm = cast[StateMachinePtr](cp)
  sm.curState = pm

when isMainModule:
  import unittest

  suite "t1":
    type
      SmT1 = object of StateMachine
        count: int
        ma: MsgArenaPtr
        ml: MsgLooperPtr

    proc s1(sm: ComponentPtr, msg: MsgPtr)

    proc s0(sm: ComponentPtr, msg: MsgPtr) =
      echo "s0"
      sm.transitionTo(s1)
      msg.rspq.add(msg)

    proc s1(sm: ComponentPtr, msg: MsgPtr) =
      echo "s1"
      sm.transitionTo(s0)
      msg.rspq.add(msg)

    proc newSmT1(): ptr SmT1 =
      result = allocObject[SmT1]()
      result.ma = newMsgArena()
      result.ml = newMsgLooper("ml1")
      result.rcvq = newMpscFifo("fifo", result.ma, result.ml)
      result.initStateMachine("smt1", s0, result.rcvq)
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
