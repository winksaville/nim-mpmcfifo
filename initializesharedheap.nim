## initializer is used to initialize items on the shared head
## which are allocated with alloc/create 

proc initializer*[T](dest: pointer) {.inline.} =
    var prototype: T
    copyMem(dest, addr prototype, sizeof(prototype))

