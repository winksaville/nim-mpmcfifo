## LinkNode for linked lists
type
  LinkNodePtr* = ptr LinkNode
  LinkNode* = object of RootObj
    next*: LinkNodePtr
