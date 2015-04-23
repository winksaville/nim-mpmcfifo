## Lock free stack of LinkNode's
##
## This implemenation uses a linked list of LinkNode's
import msg, fifoutils, typeinfo, strutils

const
  DBG = false

type
  StackPtr* = ptr Stack
  Stack* = object
    name*: string
    tos*: Msg

iterator items*(stk: StackPtr): MsgPtr {.inline.} =
  var cur = stk.tos.next
  while cur != addr stk.tos:
    yield cur
    cur = cur.next

proc `$`*(stk: StackPtr): string =
    if stk == nil:
      result = "<nil>"
    else:
      result = "{" & stk.name & ":" & ptrToStr(" stk.tos=", addr stk.tos) &
        ptrToStr(" tos.next=", stk.tos.next)

      #var firstTime = true
      #var cur = stk.tos.next
      #var sep = " "
      #for cur in stk:
      #  result &= ptrToStr(sep, cur)
      #  if firstTime:
      #    firstTime = false
      #    sep= ", "

      result &= "}"

proc isEmpty(stk: StackPtr): bool {.inline.} =
  result = stk.tos.next == addr stk.tos

proc newMpmcStack*(name: string): StackPtr =
  ## Create a new Fifo
  var stk = allocObject[Stack]()
  when DBG:
    proc dbg(s:string) = echo name & ".newMpmcStack(name)" & s
    dbg "+"

  stk.name = name
  stk.tos.next = addr stk.tos
  result = stk

  when DBG: dbg "- stk=" & $stk

proc delMpmcStack*(stk: StackPtr) =
  when DBG:
    proc dbg(s:string) = echo stk.name & ".delMpmcStack:" & s
    dbg "+ stk=" & $stk

  doAssert(stk.isEmpty())
  GcUnref(stk.name)
  deallocShared(stk)

  when DBG: dbg "-"

proc push*(stk: StackPtr,  node: MsgPtr) =
  ## Push node to top of stack
  when DBG:
    proc dbg(s:string) = echo stk.name & ".push:" & s
    dbg "+ stk=" & $stk & ptrToStr(" node=", node)

  if node != nil:
    # Playing it safe using MemModel ACQ_REL
    var oldTos = stk.tos.next
    node.next = oldTos
    while not atomicCompareExchangeN[MsgPtr](addr stk.tos.next, addr oldTos,
        node, false, ATOMIC_ACQ_REL, ATOMIC_ACQUIRE):
      oldTos = stk.tos.next
      node.next = oldTos

  when DBG: dbg "- stk=" & $stk

proc pop*(stk: StackPtr): MsgPtr =
  ## Pop top of stack or nil if stack is empty
  when DBG:
    proc dbg(s:string) = echo stk.name & ".pop:" & s
    dbg " + stk=" & $stk

  # Playing it safe using MemModel ACQ_REL
  result = stk.tos.next
  var newTos = result.next
  while not atomicCompareExchangeN[MsgPtr](addr stk.tos.next, addr result,
      newTos, false, ATOMIC_ACQ_REL, ATOMIC_ACQUIRE):
    result = stk.tos.next
    newTos = result.next
  if result == addr stk.tos:
    result = nil

  when DBG: dbg " - " & ptrToStr("result=", result) & " stk=" & $stk

when isMainModule:
  import unittest

  type
    TestObjPtr = ptr TestObj
    TestObj = object of Msg
      id: int

  proc newTestObj(id: int): TestObjPtr =
    result = allocObject[TestObj]()
    result.next = nil
    result.id = id

  converter toTestObjPtr(node: MsgPtr): TestObjPtr =
    result = cast[TestObjPtr](node)

  suite "test mpmcstack":

    test "newMpcStack":
      var stk = newMpmcStack("stk")
      check(stk.isEmpty())
      delMpmcStack(stk)
    
    test "pop from empty stk":
      var stk = newMpmcStack("stk")
      var sn = stk.pop()
      check(sn == nil)
      delMpmcStack(stk)
    
    test "push pop":
      
      var stk = newMpmcStack("stk")
      var sn = newTestObj(1)
      check(sn != nil)
      check(sn.id == 1)
      stk.push(sn)
      var snr = stk.pop().toTestObjPtr()
      check(snr != nil)
      check(snr.id == 1)
      delMpmcStack(stk)
    
    test "push push pop push pop pop":
      var stk = newMpmcStack("stk")
      stk.push(newTestObj(1))
      stk.push(newTestObj(2))
      check(stk.pop().toTestObjPtr().id == 2)
      stk.push(newTestObj(3))
      check(stk.pop().toTestObjPtr().id == 3)
      check(stk.pop().toTestObjPtr().id == 1)
      check(stk.isEmpty())
      delMpmcStack(stk)
