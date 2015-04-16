## LinkNode for linked lists
import msg, strutils

const
  DBG = false

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

when true: #defined MsgPtr:
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

proc initLinkNode*(ln: LinkNodePtr, next: LinkNodePtr, extra: pointer) {.inline.} =
  ## Initialize a link node
  ln.next = next
  ln.extra = extra
  when DBG: echo "initLinkNode: ln=", ln

proc newLinkNode*(next: LinkNodePtr, extra: pointer): LinkNodePtr {.inline.} =
  ## Allocate a new LinkNode.
  result = cast[LinkNodePtr](allocShared(sizeof(LinkNode)))
  result.initLinkNode(next, extra)
  when DBG: echo "newLinkNode: ln=", result

proc delLinkNode*(ln: LinkNodePtr) {.inline.} =
  ## Deallocate a LinkNode
  when DBG: echo "delLinkNode: ln=", ln
  freeShared(ln)
