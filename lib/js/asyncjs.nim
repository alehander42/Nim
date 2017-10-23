import jsffi
import macros

when not defined(js):
  {.error "asyncjs is only available for javascript"}


type
  FutureJs*[T] = ref object of js
    future*: T

  PromiseJs* {.importcpp: "Promise".} = ref object

  SpecialJsObject* = ref object

proc generateJsasync(arg: NimNode): NimNode

proc generateJsobject(args: varargs[NimNode]): NimNode

macro jsasync*(arg: untyped): untyped =
  generateJsasync(arg)

macro jsobject*(args: varargs[untyped]): untyped =
  generateJsobject(args)

proc jsnew*(v: js): js {.importcpp: "(new #)".}

proc jsawait*[T](f: FutureJs[T]): T {.importcpp: "(await #)".}

proc jspromise*[T](f: proc(resolve: proc(res: T): void): FutureJs[T]): FutureJs[T] {.importcpp: "new Promise(#)".}

proc jspromise*(f: proc(resolve: proc(): void): FutureJs[void]): FutureJs[void] {.importcpp: "new Promise(#)".}


proc `$`*[T](future: FutureJs[T]): string =
  result = "FutureJs"

proc replaceReturn(node: var NimNode): bool =
  var z = 0
  for s in node:
    var son = node[z]
    if son.kind == nnkReturnStmt:
      var resolve = newIdentNode(!"resolve")
      var child = son[0]
      node[z] = nnkCall.newTree(resolve, child)
      result = true
    elif son.kind == nnkAsgn and son[0].kind == nnkIdent and $son[0] == "result":
      var resolve = newIdentNode(!"resolve")
      var child = son[1]
      node[z] = nnkCall.newTree(resolve, child)
      result = true
    else:
      var replaced = replaceReturn(son)
      if replaced:
        result = true
    inc z

proc replaceResolve(node: var NimNode, sym: NimNode) =
  var z = 0
  for s in node:
    var son = node[z]
    if son.kind == nnkCall and son[0].kind == nnkIdent and $son[0] == "resolve":
      son[0] = sym
    else:
      replaceResolve(son, sym)
    inc z

proc generateJsasync(arg: NimNode): NimNode =
  assert arg.kind == nnkProcDef
  var id = arg[0]
  var ret: NimNode
  if arg[3][0].kind == nnkEmpty:
    ret = newIdentNode(!"void")
  else:
    ret = arg[3][0]
  var resolve = newIdentNode(!"resolve")
  var code = arg[^1]
  var replaced = replaceReturn(code)
  var newRet = nnkBracketExpr.newTree(newIdentNode(!"FutureJs"), ret)
  var resolveType: NimNode 
  if $ret != "void":
    resolveType = quote:
      (proc(res: `ret`): void)
  else:
    resolveType = quote:
      (proc(): void)
  resolveType = resolveType[0]
  result = arg
  result[3][0] = newRet
  result[^1] = quote:
    proc insideFunction(`resolve`: `resolveType`): FutureJs[`ret`] =
      `code`
    var promise = jspromise(insideFunction)
    return promise
  var inside = result[^1][0][^1][0][0]
  if not replaced:
    var afterCode = nnkCall.newTree(resolve) #result[^1][0][3][1][0])
    result[^1][0][^1].add(afterCode)
  # echo repr(result)

proc generateJsobject(args: varargs[NimNode]): NimNode =
  var properties = @args[0]

  result = nnkTupleTy.newTree()
  result.add(nnkIdentDefs.newTree(
    newIdentNode(!"jsobject"),
    newIdentNode(!"SpecialJsObject"),
    newEmptyNode()))

  for property in properties:
    assert property.kind == nnkExprEqExpr
    result.add(nnkIdentDefs.newTree(
      property[0],
      property[1],
      newEmptyNode()))

