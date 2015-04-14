## Wait free stack of LinkNode's
##
## This implemenation uses a linked list of LinkNode's
import linknode, typeinfo, strutils

const DBG = false

type
  StackPtr* = ptr Stack
  Stack* = object
    name*: string
    tos*: LinkNode

proc ptrToStr(label: string, p: pointer): string =
  if p == nil:
    result = label & "<nil>"
  else:
    result = label & "0x" & toHex(cast[int](p), sizeof(p)*2)

proc `$`*(stk: StackPtr): string =
    if stk == nil:
      result = "<nil>"
    else:
      result = "{" & stk.name & ":" & ptrToStr(" tos.next=", stk.tos.next)

      var firstTime = true
      var cur = stk.tos.next
      var sep = " "
      while cur != addr stk.tos:
        result &= ptrToStr(sep, cur)
        if firstTime:
          firstTime = false
          sep= ", "
        cur = cur.next

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
  when DBG: dbg "+"

  doAssert(stk.isEmpty())
  GcUnref(stk.name)
  deallocShared(stk)

  when DBG: dbg "-"

proc push*(stk: StackPtr,  node: LinkNodePtr) =
  ## Push node to top of stack
  proc dbg(s:string) = echo stk.name & ".push:" & s
  when DBG: dbg "+ stk=" & $stk & ptrToStr(" node=", node)

  # Playing it safe using MemModel ACQ_REL
  node.next = node
  atomicExchange[LinkNodePtr](addr stk.tos.next, addr node.next, addr node.next, ATOMIC_ACQ_REL)

  when DBG: dbg "- stk=" & $stk

proc pop*(stk: StackPtr): LinkNodePtr =
  ## Pop top of stack or nil if stack is empty
  proc dbg(s:string) = echo stk.name & ".pop:" & s
  when DBG: dbg "+ stk=" & $stk

  # Playing it safe using MemModel ACQ_REL
  atomicExchange[LinkNodePtr](addr stk.tos.next, addr stk.tos.next.next, addr result, ATOMIC_ACQ_REL)
  if result == addr stk.tos:
    result = nil

  when DBG: dbg "- " & ptrToStr("result=", result) & " stk=" & $stk

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
    
    test "pop from empty stk":
      var stk = newMpmcStack("stk")
      var sn = stk.pop()
      check(sn == nil)
    
    test "push pop":
      
      var stk = newMpmcStack("stk")
      var sn = newTestObj(1)
      check(sn != nil)
      check(sn.id == 1)
      stk.push(sn)
      var snr = stk.pop().toTestObjPtr()
      check(snr != nil)
      check(snr.id == 1)
    
    test "push push pop push pop pop":
      var stk = newMpmcStack("stk")
      stk.push(newTestObj(1))
      stk.push(newTestObj(2))
      check(stk.pop().toTestObjPtr().id == 2)
      stk.push(newTestObj(3))
      check(stk.pop().toTestObjPtr().id == 3)
      check(stk.pop().toTestObjPtr().id == 1)
      check(stk.isEmpty())
