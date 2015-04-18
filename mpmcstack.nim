## Lock free stack of LinkNode's
##
## This implemenation uses a linked list of LinkNode's
import linknode, typeinfo, strutils

const
  DBG = false

type
  StackPtr* = ptr Stack
  Stack* = object
    name*: string
    tos*: LinkNode

iterator items*(stk: StackPtr): LinkNodePtr {.inline.} =
  var cur = stk.tos.next
  while cur != addr stk.tos:
    yield cur
    cur = cur.next

proc ptrToStr(label: string, p: pointer): string =
  if p == nil:
    result = label & "<nil>"
  else:
    result = label & "0x" & toHex(cast[int](p), sizeof(p)*2)

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

proc isEmpty(stk): bool {.inline.} =
  result = stk.tos.next == addr stk.tos

proc newMpmcStack*(name: string): StackPtr =
  ## Create a new Fifo
  var stk = cast[StackPtr](allocShared(sizeof(Stack)))
  proc dbg(s:string) = echo name & ".newMpmcStack(name)" & s
  when DBG: dbg "+"

  stk.name = name
  stk.tos.next = addr stk.tos
  result = stk

  when DBG: dbg "- stk=" & $stk

proc delMpmcStack*(stk: StackPtr) =
  proc dbg(s:string) = echo stk.name & ".delMpmcStack:" & s
  when DBG: dbg "+ stk=" & $stk

  doAssert(stk.isEmpty())
  GcUnref(stk.name)
  deallocShared(stk)

  when DBG: dbg "-"

proc push*(stk: StackPtr,  node: LinkNodePtr) =
  ## Push node to top of stack
  proc dbg(s:string) = echo stk.name & ".push:" & s
  when DBG: dbg "+ stk=" & $stk & ptrToStr(" node=", node)

  if node != nil:
    # Playing it safe using MemModel ACQ_REL
    var oldTos = stk.tos.next
    node.next = oldTos
    while not atomicCompareExchangeN[LinkNodePtr](addr stk.tos.next, addr oldTos, node,
        false, ATOMIC_ACQ_REL, ATOMIC_ACQUIRE):
      oldTos = stk.tos.next
      node.next = oldTos

  when DBG: dbg "- stk=" & $stk

proc pop*(stk: StackPtr): LinkNodePtr =
  ## Pop top of stack or nil if stack is empty
  proc dbg(s:string) = echo stk.name & ".pop:" & s
  when DBG: dbg " + stk=" & $stk

  # Playing it safe using MemModel ACQ_REL
  result = stk.tos.next
  var newTos = result.next
  while not atomicCompareExchangeN[LinkNodePtr](addr stk.tos.next, addr result, newTos,
      false, ATOMIC_ACQ_REL, ATOMIC_ACQUIRE):
    result = stk.tos.next
    newTos = result.next
  if result == addr stk.tos:
    result = nil

  when DBG: dbg " - " & ptrToStr("result=", result) & " stk=" & $stk

when isMainModule:
  import unittest

  type
    TestObjPtr = ptr TestObj
    TestObj = object of LinkNode
      id: int

  proc newTestObj(id: int): TestObjPtr =
    result = cast[TestObjPtr](allocShared(sizeof(TestObj)))
    result.next = nil
    result.id = id

  converter toTestObjPtr(node: LinkNodePtr): TestObjPtr =
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
