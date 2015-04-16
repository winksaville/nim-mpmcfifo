## LinkNode for linked lists
import strutils

type
  LinkNodePtr* = ptr LinkNode
  LinkNode* = object of RootObj
    next*: LinkNodePtr
    extra*: pointer

proc ptrToStr(label: string, p: pointer): string =
  if p == nil:
    result = label & "<nil>"
  else:
    result = label & "0x" & toHex(cast[int](p), sizeof(p)*2)

when defined MsgPtr:
  # TODO: Fix me we should be assuming all extras are MsgPtr's
  # TODO: just because its defined!
  proc `$`*(ln: LinkNodePtr): string =
    if ln == nil:
      result = "<nil>"
    else:
      result = "{" &
                 ptrToStr("ln:", ln) &
                 ptrToStr(" next=", ln.next) &
                 ptrToStr(" ext:", ln.extra) &
                    (if ln.extra != nil: " " & $cast[MsgPtr](ln.extra) else: "") &
               "}"
else:
  proc `$`*(ln: LinkNodePtr): string =
    if ln == nil:
      result = "<nil>"
    else:
      result = "{" &
                 ptrToStr("ln:", ln) &
                 ptrToStr(" next=", ln.next) &
                 ptrToStr(" ext:", ln.extra) &
               "}"

proc newLinkNode*(next: LinkNodePtr, extra: pointer): LinkNodePtr =
  ## Allocate a new LinkNode.
  result = cast[LinkNodePtr](allocShared(sizeof(LinkNode)))
  result.next = next
  result.extra = extra

proc delLinkNode*(mn: LinkNodePtr) =
  ## Deallocate a LinkNode
  freeShared(mn)
