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

  test "atomicCompareExchangeN ...":
    type
      O = object
        i: int

    var
      i1: int
      i2: int
      i3: int

    i1 = 1
    i2 = 1
    i3 = 3

    echo "i1=", i1
    echo "i2=", i2
    echo "i3=", i3
    check(i1 == 1 and i2 == 1 and i3 == 3)
    # mpmcstack.c fails to compile with error:
    #  error: incompatible type for argument 1 of ‘__atomic_compare_exchange_n’
    var r = atomicCompareExchangeN[int](addr i1, addr i2, i3, false, ATOMIC_ACQ_REL, ATOMIC_ACQUIRE)
    echo " r=", r
    echo "i1=", i1
    echo "i2=", i2
    echo "i3=", i3
    #check(o1.i == 3 and o2.i == 1 and o3.i == 3)
