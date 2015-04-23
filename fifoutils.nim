import strutils

proc ptrToStr*(p: pointer): string =
  ## print hexadecimal representation of p with leading "0x" or "<nil>"
  if p == nil:
    result = "<nil>"
  else:
    result = "0x" & toHex(cast[int](p), sizeof(p)*2)

proc ptrToStr*(label: string, p: pointer): string =
  ## print label & ptrToStr(p)
  result = label & ptrToStr(p)

proc echoBytes*(address: pointer, count: int) =
  ## print bytes to stdout
  var p = cast[ptr array[0..1_000_000_000, int8]](address)
  echo "address=", ptrToStr(p)
  for i in 0..count-1:
    var v = p[i]
    write(stdout, toHex((cast[int](v) and 0xff), 2))
  writeln(stdout, "")

proc initializer*[T](dest: pointer) {.inline.} =
  ## initializer initializes items on the shared heap
  ## which are allocated with alloc/create 
  var prototype: T
  copyMem(dest, addr prototype, sizeof(prototype))

proc allocObject*[T](): ptr T =
  ## Allocate T using allocShared and initialize as
  ## a default object. You must use deallocShared
  ## to return to the shared heap and not leak the
  ## memory.
  result = cast[ptr T](allocShared(sizeof(T)))
  initializer[T](result)
