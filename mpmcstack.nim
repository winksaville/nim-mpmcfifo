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
  ## Add msg to tail if this was added to an
  ## empty queue return true
  proc dbg(s:string) = echo stk.name & ".push:" & s
  when DBG: dbg "+ p=" & ptrToStr(p)

  var curTosNext = stk.tos.next
  node.next = curTosNext
  while not atomicCompareExchange[StackNodePtr](addr stk.tos.next, addr curTosNext, addr node, true, ATOMIC_RELEASE, ATOMIC_ACQUIRE):
    curTosNext = stk.tos.next
    node.next = curTosNext

  when DBG: dbg "- stk=" & $stk

#proc pop*(stk: StackPtr): StackNodePtr =
#  ## Return head or nil if empty
#  ## May only be called from consumer
#  proc dbg(s:string) = echo stk.name & ".pop:" & s
#  when DBG: dbg "+ mq=" & $mq
#
#  var tos = stk.tos
#  when DBG: dbg " tos=" & $tos
#  # serialization-point wrt producers, acquire
#  var next = atomicLoadN(addr head.next, ATOMIC_ACQUIRE)
#  when DBG: dbg " next=" & $next
#  if next != nil:
#    result = next.msg
#    when DBG: dbg " next != nil result = next.msg result=" & $result
#    mq.head = next
#    when DBG: dbg " next != nil mq.head = next mq=" & $mq
#    mq.arena.retMsgNode(head)
#    when DBG: dbg " next != nil return head to arena mq.arena=" & $mq.arena
#  else:
#    when DBG: dbg " next == nil result=nil, mq=" & $mq
#    result = nil
#  when DBG: dbg "- msg=" & $result & " mq=" & $mq

when isMainModule:
  import unittest

  suite "test atomicCompareExchange":
    test "atomicCompareExchange ...":
      type
        O = object
          i: int

      var
        o1: O
        o2: O
        o3: O

      o1.i = 1
      o2.i = 1
      o3.i = 3

      echo "o1=", o1
      echo "o2=", o2
      echo "o3=", o3
      check(o1.i == 1 and o2.i == 1 and o3.i == 3)
      var r = atomicCompareExchange[O](addr o1, addr o2, addr o3, true, ATOMIC_RELEASE, ATOMIC_ACQUIRE)
      echo " r=", r
      echo "o1=", o1
      echo "o2=", o2
      echo "o3=", o3
      check(o1.i == 3 and o2.i == 1 and o3.i == 3)

    test "newMpcStack":
      var stk = newMpmcStack("stk")
      echo "stk=", stk
      check(stk.tos.next == nil)
    
    test "push":
      var stk = newMpmcStack("stk")
      echo "stk=", stk
      var sn = newStackNode(1)
      stk.push(sn)
      echo "stk=", stk
      sn = newStackNode(2)
      stk.push(sn)
      echo "stk=", stk
    
    #test "atomicCompareExchangeN ...":
    #  type
    #    O = object
    #      i: int

    #  var
    #    o1: O
    #    o2: O
    #    o3: O

    #  o1.i = 1
    #  o2.i = 1
    #  o3.i = 3

    #  echo "o1=", o1
    #  echo "o2=", o2
    #  echo "o3=", o3
    #  check(o1.i == 1 and o2.i == 1 and o3.i == 3)
    #  # mpmcstack.c fails to compile with error:
    #  #  error: incompatible type for argument 1 of ‘__atomic_compare_exchange_n’
    #  var r = atomicCompareExchangeN[O](addr o1, addr o2, o3, true, ATOMIC_RELEASE, ATOMIC_ACQUIRE)
    #  echo " r=", r
    #  echo "o1=", o1
    #  echo "o2=", o2
    #  echo "o3=", o3
    #  #check(p1 == 2 and p2 == 2 and p3 == 1)


  #suite "test atomicExchange":
  #  test "atomicExchange(p1, p2, p3)":
  #    var
  #      p1: int
  #      p2: int
  #      p3: int

  #    p1 = 1
  #    p2 = 2
  #    p3 = 3

  #    echo "p1=", p1
  #    echo "p2=", p2
  #    echo "p3=", p3
  #    check(p1 == 1 and p2 == 2 and p3 == 3)
  #    atomicExchange(addr p1, addr p2, addr p3, ATOMIC_ACQ_REL)
  #    echo "p1=", p1
  #    echo "p2=", p2
  #    echo "p3=", p3
  #    check(p1 == 2 and p2 == 2 and p3 == 1)

  #  test "atomicExchange(p1, p2, p2)":
  #    var
  #      p1: int
  #      p2: int
  #      p3: int

  #    p1 = 1
  #    p2 = 2
  #    p3 = 3

  #    echo "p1=", p1
  #    echo "p2=", p2
  #    echo "p3=", p3
  #    check(p1 == 1 and p2 == 2 and p3 == 3)
  #    atomicExchange(addr p1, addr p2, addr p2, ATOMIC_ACQ_REL)
  #    echo "p1=", p1
  #    echo "p2=", p2
  #    echo "p3=", p3
  #    check(p1 == 2 and p2 == 1 and p3 == 3)

  #  test "atomicExchangeN":
  #    var
  #      p1: int
  #      p2: int
  #      p3: int

  #    p1 = 1
  #    p2 = 2
  #    p3 = 3

  #    echo "p1=", p1
  #    echo "p2=", p2
  #    echo "p3=", p3
  #    var r = atomicExchangeN(addr p1, p2, ATOMIC_ACQ_REL)
  #    echo "p1=", p1
  #    echo "p2=", p2
  #    echo "r =", r
