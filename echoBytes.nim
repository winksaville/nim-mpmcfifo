import strutils

proc echoBytes(address: pointer, count: int) =
  var p = cast[ptr array[0..1_000_000_000, int8]](address)
  echo "address=", ptrToStr(p)
  for i in 0..count-1:
    var v = p[i]
    write(stdout, toHex((cast[int](v) and 0xff), 2))
  writeln(stdout, "")

