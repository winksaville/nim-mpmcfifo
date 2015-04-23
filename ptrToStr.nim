import strutils

proc ptrToStr(p: pointer): string =
  if p == nil:
    result = "<nil>"
  else:
    result = "0x" & toHex(cast[int](p), sizeof(p)*2)

