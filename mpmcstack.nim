# Wait free/Thread safe stack
import typeinfo, strutils

const DBG = false

type
  StackNodePtr = ptr StackNode
  StackNode = object of RootObj
    next: StackNodePtr
    id: int

  StackPtr* = ptr Stack
  Stack* = object
    name*: string
    tos*: StackNode

proc newStackNode(id: int): StackNodePtr =
  result = cast[StackNodePtr](allocShared(sizeof(StackNode)))
  result.next = nil
  result.id = id

proc ptrToStr(label: string, p: StackNodePtr): string =
  if p == nil:
    result = label & "<nil>"
  else:
    result = label & "0x" & toHex(cast[int](p), sizeof(p)*2)

proc `$`*(stk: StackPtr): string =
    if stk == nil:
      result = "<nil>"
    else:
      result = "{" & stk.name & ":" & ptrToStr(" tos.next=", stk.tos.next) &
        " tos.id=" & $stk.tos.id

      var firstTime = true
      var cur = stk.tos.next
      var sep = " "
      while cur != nil:
        result &= ptrToStr(sep, cur) & " id=" & $cur.id
        if firstTime:
          firstTime = false
          sep= ", "
        cur = cur.next

      result &= "}"

proc newMpmcStack*(name: string): StackPtr =
  ## Create a new Fifo
  var stk = cast[StackPtr](allocShared(sizeof(Stack)))
  proc dbg(s:string) = echo name & ".newMpmcStack(name)" & s
  when DBG: dbg "+"

  stk.name = name
  stk.tos.next = nil 
  stk.tos.id = -1
  result = stk

  when DBG: dbg "- stk=" & $stk

proc delMpmcStack*(stk: StackPtr) =
  proc dbg(s:string) = echo stk.name & ".delMpmcStack:" & s
  when DBG: dbg "+"

  doAssert(stk.tos.next == nil)
  GcUnref(stk.name)
  deallocShared(stk)

  when DBG: dbg "-"

proc push*(stk: StackPtr,  node: var StackNodePtr) =
  ## Add msg to top of stack
  proc dbg(s:string) = echo stk.name & ".push:" & s
  when DBG: dbg "+ p=" & ptrToStr(p)

  var curTosNext = stk.tos.next
  node.next = curTosNext
  while not atomicCompareExchangeN[StackNodePtr](addr stk.tos.next,
    addr curTosNext, node, true, ATOMIC_ACQ_REL, ATOMIC_ACQUIRE):
    curTosNext = stk.tos.next
    node.next = curTosNext

  when DBG: dbg "- stk=" & $stk

proc pop*(stk: StackPtr): StackNodePtr =
  ## Remove msg from top of stack or nil if the stack is empty
  proc dbg(s:string) = echo stk.name & ".push:" & s
  when DBG: dbg "+ p=" & ptrToStr(p)

  result = stk.tos.next
  if result != nil:
    var newTosNext = result.next
    while not atomicCompareExchange[StackNodePtr](addr stk.tos.next,
      addr result, addr newTosNext, true, ATOMIC_ACQ_REL, ATOMIC_ACQUIRE):
      result = stk.tos.next
      newTosNext = result.next

  when DBG: dbg "- stk=" & $stk

when isMainModule:
  import unittest

  suite "test mpmcstack":

    test "newMpcStack":
      var stk = newMpmcStack("stk")
      echo "stk=", stk
      check(stk.tos.next == nil)
    
    test "pop from empty stk":
      var stk = newMpmcStack("stk")
      echo "stk=", stk
      var sn = stk.pop()
      check(sn == nil)
    
    test "push pop":
      var stk = newMpmcStack("stk")
      echo "stk=", stk
      var sn = newStackNode(1)
      check(sn != nil)
      check(sn.id == 1)
      stk.push(sn)
      echo "stk=", stk
      var snr = stk.pop()
      echo "stk=", stk
      check(sn != nil)
      check(sn.id == 1)
    
