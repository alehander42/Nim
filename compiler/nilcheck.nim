#
#
#           The Nim Compiler
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import ast, renderer, intsets, tables, msgs, options, lineinfos, strformat, idents, treetab, hashes, sequtils, varpartitions
import astalgo

# 
# notes:
# 
# Env: int => nilability
# a = b
#   nilability a <- nilability b
# deref a
#   if Nil error is nil
#   if MaybeNil error might be nil, hint add if isNil
#   if Safe fine
# fun(arg: A)
#   nilability arg <- for ref MaybeNil, for not nil or others Safe
# map is env?
# a or b
#   each one forks a different env
#   result = union(envL, envR)
# a and b
#   b forks a's env
# if a: code
#   result = union(previousEnv after not a, env after code)
# if a: b else: c
#   result = union(env after b, env after c)
# result = b
#   nilability result <- nilability b, if return type is not nil and result not safe, error
# return b
#   as result = b
# try: a except: b finally: c
#   in b and c env is union of all possible try first n lines, after union of a and b and c
#   keep in mind canRaise and finally
# case a: of b: c
#   similar to if
# call(arg)
#   if it returns ref, assume it's MaybeNil: hint that one can add not nil to the return type
# call(var arg) # zahary comment
#   if arg is ref, assume it's MaybeNil after call
# loop
#   union of env for 0, 1, 2 iterations as Herb Sutter's paper
# return
#   if something: stop (break return etc)
#   is equivalent to if something: .. else: remain
# new(ref)
#   ref becomes Safe
# objConstr(a: b)
#   returns safe
# each check returns its nilability and map

type
  Symbol = int

  TransitionKind = enum TArg, TAssign, TType, TNil, TVarArg, TResult, TSafe, TPotentialAlias
  
  History = object
    info: TLineInfo
    nilability: Nilability
    kind: TransitionKind    

  NilCheckerContext = ref object
    abstractTime: AbstractTime
    partitions: Partitions
    config: ConfigRef

  NilMap* = ref object
    locals*:   Table[Symbol, Nilability]
    history*:  Table[Symbol, seq[History]]
    # aliases*:  Table[Symbol, Symbol]
    # aliasNodes*: Table[Symbol, PNode]
    previous*: NilMap
    base*:     NilMap
    top*:      NilMap

  Nilability* = enum Safe, MaybeNil, Nil

  Check = tuple[nilability: Nilability, map: NilMap]


# useful to have known resultId so we can set it in the beginning and on return
const resultId = -1

proc check(n: PNode, ctx: NilCheckerContext, map: NilMap): Check
proc checkCondition(n: PNode, ctx: NilCheckerContext, map: NilMap, isElse: bool, base: bool): NilMap

# the NilMap structure

proc newNilMap(previous: NilMap = nil, base: NilMap = nil): NilMap =
  result = NilMap(
    previous: previous,
    base: base)
  result.top = if previous.isNil: result else: previous.top

proc `[]`(map: NilMap, name: Symbol): Nilability =
  var now = map
  while not now.isNil:
    if now.locals.hasKey(name):
      return now.locals[name]
    now = now.previous
  return Safe

proc history(map: NilMap, name: Symbol): seq[History] =
  var now = map
  var h: seq[History] = @[]
  while not now.isNil:
    if now.history.hasKey(name):
      # h = h.concat(now.history[name])
      return now.history[name]
    now = now.previous
  return @[]

# helpers for debugging

import macros

# echo-s only when nilDebugInfo is defined
macro aecho*(a: varargs[untyped]): untyped =
  var e = nnkCall.newTree(ident"echo")
  for b in a:
    e.add(b)
  result = quote:
    when defined(nilDebugInfo):
      `e`

# end of helpers for debugging

proc parentSubExprs(node: PNode): seq[PNode] =
  if node.isNil:
    return @[]
  # echo "parent ", node.kind
  case node.kind:
  of nkSym:
    @[node]
  of nkDotExpr:
    parentSubExprs(node[0]).concat(@[node[1]])
  of nkHiddenDeref:
    parentSubExprs(node[0])
  else:
    @[]

proc symbol(n: PNode): Symbol

# proc makeAlias(map: NilMap, a: PNode, b: PNode) =
#   let aSymbol = symbol(a)
#   let bSymbol = symbol(b)
#   map.aliases[aSymbol] = bSymbol
#   map.aliases[bSymbol] = aSymbol
#   map.aliasNodes[aSymbol] = b
#   map.aliasNodes[bSymbol] = a

# proc replaceAlias(node: PNode, original: PNode, alias: PNode): PNode =
#   case node.kind:
#   of nkSym:
#     if original.kind == nkSym and $node == $original:
#       return alias
#     else:
#       return node
#   of nkDotExpr:
#     if original.kind == nkDotExpr and $node == $original:
#       return alias
#     else:
#       return nkDotExpr.newTree(replaceAlias(node[0], original, alias), node[1])
#   else:
#     return node

# proc loadAliasNode(map: NilMap, symbol: Symbol): PNode =
#   var now = map
#   while not now.isNil:
#     if now.aliasNodes.hasKey(symbol):
#       return now.aliasNodes[symbol]
#     now = now.previous
    
proc store(map: NilMap, symbol: Symbol, value: Nilability, kind: TransitionKind, info: TLineInfo, node: PNode = nil) =
  let text = if node.isNil: "?" else: $node
  # echo "store " & text & " " & $symbol & " " & $value
  # if value == Nil:
  #   echo "store " & text & " " & $symbol
  # find out aliases
  # alias.field 
  # for e in parentSubExprs(node):
  #   # echo "parent sub ", e
  #   let eSymbol = symbol(e)
  #   # echo "symbol ", eSymbol
  #   echo map.aliasNodes
  #   let aliasNode = loadAliasNode(map, eSymbol)
  #   if not aliasNode.isNil:
  #     let aliasExpr = replaceAlias(node, e, aliasNode)
  #     let aliasSymbol = symbol(aliasExpr)
  #     # echo "alias expr ", aliasNode, " ", aliasExpr
  #     map.locals[aliasSymbol] = value
  #     map.history.mgetOrPut(aliasSymbol, @[]).add(History(info: info, kind: TAlias, nilability: value))
  map.locals[symbol] = value
  map.history.mgetOrPut(symbol, @[]).add(History(info: info, kind: kind, nilability: value))

proc hasKey(map: NilMap, name: Symbol): bool =
  var now = map
  result = false
  while not now.isNil:
    if now.locals.hasKey(name):
      return true
    now = now.previous

iterator pairs(map: NilMap): (Symbol, Nilability) =
  var now = map
  while not now.isNil:
    for name, value in now.locals:
      yield (name, value)
    now = now.previous

proc copyMap(map: NilMap): NilMap =
  if map.isNil:
    return nil
  result = newNilMap(map.previous.copyMap())
  for name, value in map.locals:
    result.locals[name] = value
  for name, value in map.history:
    result.history[name] = value
  # for a, b in map.aliases:
  #   result.aliases[a] = b
  # for a, b in map.aliasNodes:
  #   result.aliasNodes[a] = b

proc `$`(map: NilMap): string =
  var now = map
  var stack: seq[NilMap] = @[]
  while not now.isNil:
    stack.add(now)
    now = now.previous
  for i in countdown(stack.len - 1, 0):
    now = stack[i]
    result.add("###\n")
    for name, value in now.locals:
      result.add(&"  {name} {value}\n")
    # for a, b in now.aliasNodes:
    #   result.add(&"  alias {a} {b}\n")


# symbol(result) -> resultId
# symbol(result[]) -> resultId
# symbol(result.a) -> !$(resultId !& a)
# symbol(result.b) -> !$(resultId !& b)
# what is sym id?

# resultId vs result.sym.id : different ??
# but the same actually
# what about var result ??


proc symbol(n: PNode): Symbol =
  ## returns a Symbol for each expression
  ## the goal is to get an unique Symbol
  ## but we have to ensure hashTree does it as we expect
  case n.kind:
  of nkIdent:
    # echo "ident?", $n
    result = 0
  of nkSym:
    if n.sym.kind == skResult: # credit to disruptek for showing me that
      result = resultId
    else:
      result = n.sym.id
  of nkHiddenAddr, nkAddr:
    result = symbol(n[0])
  else:
    result = hashTree(n)
  # echo result

using
  n: PNode
  conf: ConfigRef
  ctx: NilCheckerContext
  map: NilMap

proc typeNilability(typ: PType): Nilability

# maybe: if canRaise, return MaybeNil ?
# no, because the target might be safe already
# with or without an exception
proc checkCall(n, ctx, map): Check =
  # checks each call
  # special case for new(T) -> result is always Safe
  # for the others it depends on the return type of the call
  # check args and handle possible mutations

  var isNew = false
  result.map = map
  for i, child in n:
    discard check(child, ctx, map)
    if i > 0 and child.kind == nkHiddenAddr:
      # var args make a new map with MaybeNil for our node
      # as it might have been mutated
      # TODO similar for normal refs and fields: find dependent exprs
      if child.typ.kind == tyVar and child.typ[0].kind == tyRef:
        # yes
        if not isNew:
          result.map = newNilMap(map)
          isNew = true
        # result.map[$child] = MaybeNil
        # echo "MaybeNil arg"
        # echo "  ", child
        # echo "  ", symbol(child)
        let a = symbol(child)
        result.map.store(a, MaybeNil, TVarArg, n.info, child)
        # echo result.map

  if n[0].kind == nkSym and n[0].sym.magic == mNew:
    let b = symbol(n[1])
    result.map.store(b, Safe, TAssign, n[1].info, n[1])
    result.nilability = Safe
  else:
    result.nilability = typeNilability(n.typ)
  # echo result.map

template event(b: History): string =
  case b.kind:
  of TArg: "param with nilable type"
  of TNil: "it returns true for isNil"
  of TAssign: "assigns a value which might be nil"
  of TVarArg: "passes it as a var arg which might change to nil"
  of TResult: "it is nil by default"
  of TType: "it has ref type"
  of TSafe: "it is safe here as it returns false for isNil"
  of TPotentialAlias: "it might be changed directly or through an alias"
  
proc derefWarning(n, ctx, map; maybe: bool) =
  ## a warning for potentially unsafe dereference
  var a = history(map, symbol(n))
  var res = ""
  res.add("can't deref " & $n & ", it " & (if maybe: "might be" else: "is") & " nil")
  if a.len > 0:
    res.add("\n")
  for b in a:
    res.add("  " & event(b) & " on line " & $b.info.line & ":" & $b.info.col)
  message(ctx.config, n.info, warnStrictNotNil, res)

proc handleNilability(check: Check; n, ctx, map) =
  ## handle the check:
  ##   register a warning(error?) for Nil/MaybeNil
  case check.nilability:
  of Nil:
    derefWarning(n, ctx, map, false)
  of MaybeNil:
    derefWarning(n, ctx, map, true)
  else:
    when defined(nilDebugInfo):
      message(ctx.config, n.info, hintUser, "can deref " & $n)
    
proc checkDeref(n, ctx, map): Check =
  ## check dereference: deref n should be ok only if n is Safe
  result = check(n[0], ctx, map)
  
  handleNilability(result, n, ctx, map)

    
proc checkRefExpr(n, ctx; check: Check): Check =
  ## check ref expressions: TODO not sure when this happens
  result = check
  if n.typ.kind != tyRef:
    # echo "not tyRef ", n.typ.kind
    result.nilability = typeNilability(n.typ)
  elif tfNotNil notin n.typ.flags:
    let key = symbol(n)
    if result.map.hasKey(key):
      # echo "ref expr ", n, " ", key, " ", result.map[key]
      echo result.map
      result.nilability = result.map[key]
    else:
      # echo "maybe nil ref expr ", key, " ", MaybeNil
      # result.map[key] = MaybeNil
      result.map.store(key, MaybeNil, TType, n.info, n)
      result.nilability = MaybeNil

proc checkDotExpr(n, ctx, map): Check =
  ## check dot expressions: make sure we can dereference the base
  result = check(n[0], ctx, map)
  result = checkRefExpr(n, ctx, result)

proc checkBracketExpr(n, ctx, map): Check =
  ## check bracket expressions: make sure we can dereference the base
  result = check(n[0], ctx, map)
  # if might be deref: [] == *(a + index) for cstring
  handleNilability(result, n[0], ctx, map)
  result = check(n[1], ctx, result.map)
  result = checkRefExpr(n, ctx, result)

template union(l: Nilability, r: Nilability): Nilability =
  ## unify two states
  # echo "union ", l, " ", r
  if l == r:
    l
  else:
    MaybeNil

proc union(l: NilMap, r: NilMap): NilMap =
  ## unify two maps from different branches
  ## combine their locals
  if l.isNil:
    return r
  elif r.isNil:
    return l
  result = newNilMap(l.base)
  for name, value in l:
    if r.hasKey(name) and not result.locals.hasKey(name):
      var h = history(r, name)
      assert h.len > 0
      # echo "history", name, value, r[name], h[^1].info.line
      result.store(name, union(value, r[name]), TAssign, h[^1].info)

# a = b
# a = c
#
# b -> a c -> a
# a -> @[b, c]
# {b, c, a}
# a = e
# a -> @[e]

proc checkAsgn(target: PNode, assigned: PNode; ctx, map): Check =
  ## check assignment
  ##   update map based on `assigned`
  if assigned.kind != nkEmpty:
    result = check(assigned, ctx, map)
  else:
    result = (typeNilability(target.typ), map)
  if result.map.isNil:
    result.map = map
  let t = symbol(target)
  case assigned.kind:
  of nkNilLit:
    result.map.store(t, Nil, TAssign, target.info, target)
  else:
    result.map.store(t, result.nilability, TAssign, target.info, target)
    # if target.kind in {nkSym, nkDotExpr}:
    #  result.map.makeAlias(assigned, target)

proc checkReturn(n, ctx, map): Check =
  ## check return
  # return n same as result = n; return ?
  result = check(n[0], ctx, map)
  result.map.store(resultId, result.nilability, TAssign, n.info)


proc checkFor(n, ctx, map): Check =
  ## check for loops
  ##   try to repeat the unification of the code twice
  ##   to detect what can change after a several iterations
  ##   approach based on discussions with Zahary/Araq
  ##   similar approach used for other loops
  var m = map
  var map0 = map.copyMap()
  m = check(n.sons[2], ctx, map).map.copyMap()
  if n[0].kind == nkSym:
    m.store(symbol(n[0]), typeNilability(n[0].typ), TAssign, n[0].info)
  var map1 = m.copyMap()
  var check2 = check(n.sons[2], ctx, m)
  var map2 = check2.map
  
  result.map = union(map0, map1)
  result.map = union(result.map, map2)
  result.nilability = Safe

# while code:
#   code2

# if code:
#   code2
# if code:
#   code2

# if code:
#   code2

# check(code), check(code2 in code's map)

proc checkWhile(n, ctx, map): Check =
  ## check while loops
  ##   try to repeat the unification of the code twice
  var m = checkCondition(n[0], ctx, map, false, false)
  var map0 = map.copyMap()
  m = check(n.sons[1], ctx, m).map
  var map1 = m.copyMap()
  var check2 = check(n.sons[1], ctx, m)
  var map2 = check2.map
  
  result.map = union(map0, map1)
  result.map = union(result.map, map2)
  result.nilability = Safe

proc checkInfix(n, ctx, map): Check =
  ## check infix operators
  ##   a and b : map is based on a; next b
  ##   a or b : map is an union of a and b's
  ##   a == b : use checkCondition
  ##   else: no change, just check args
  if n[0].kind == nkSym:
    var mapL: NilMap
    var mapR: NilMap
    if n[0].sym.magic notin {mAnd, mEqRef}:
      mapL = checkCondition(n[1], ctx, map, false, false)
      mapR = checkCondition(n[2], ctx, map, false, false)
    case n[0].sym.magic:
    of mOr:
      result.map = union(mapL, mapR)
    of mAnd:
      result.map = checkCondition(n[1], ctx, map, false, false)
      result.map = checkCondition(n[2], ctx, result.map, false, false)
    of mEqRef:
      if n[2].kind == nkIntLit:
        if $n[2] == "true":
          result.map = checkCondition(n[1], ctx, map, false, false)
        elif $n[2] == "false":
          result.map = checkCondition(n[1], ctx, map, true, false)
      elif n[1].kind == nkIntLit:
        if $n[1] == "true":
          result.map = checkCondition(n[2], ctx, map, false, false)
        elif $n[1] == "false":
          result.map = checkCondition(n[2], ctx, map, true, false)
      if result.map.isNil:
        result.map = map
    else:
      result.map = map
  else:
    result.map = map
  result.nilability = Safe

proc checkIsNil(n, ctx, map; isElse: bool = false): Check =
  ## check isNil calls
  ## update the map depending on if it is not isNil or isNil
  result.map = newNilMap(map)
  let value = n[1]
  let value2 = symbol(value)
  result.map.store(symbol(n[1]), if not isElse: Nil else: Safe, TArg, n.info, n)

proc infix(l: PNode, r: PNode, magic: TMagic): PNode =
  var name = case magic:
    of mEqRef: "=="
    of mAnd: "and"
    of mOr: "or"
    else: ""

  var cache = newIdentCache()
  var op = newSym(skVar, cache.getIdent(name), nil, r.info)

  op.magic = magic
  result = nkInfix.newTree(
    newSymNode(op, r.info),
    l,
    r)
  result.typ = newType(tyBool, nil)

proc prefixNot(node: PNode): PNode =
  var cache = newIdentCache()
  var op = newSym(skVar, cache.getIdent("not"), nil, node.info)

  op.magic = mNot
  result = nkPrefix.newTree(
    newSymNode(op, node.info),
    node)
  result.typ = newType(tyBool, nil)

proc infixEq(l: PNode, r: PNode): PNode =
  infix(l, r, mEqRef)

proc infixOr(l: PNode, r: PNode): PNode =
  infix(l, r, mOr)

proc checkBranch(condition: PNode, n, ctx, map; isElse: bool = false): Check

proc checkCase(n, ctx, map): Check =
  # case a:
  #   of b: c
  #   of b2: c2
  # is like
  # if a == b:
  #   c
  # elif a == b2:
  #   c2
  # also a == true is a , a == false is not a
  let base = n[0]
  result.map = map.copyMap()
  result.nilability = Safe
  var a: PNode
  for child in n:
    case child.kind:
    of nkOfBranch:
      let branchBase = child[0]
      let code = child[1]
      let test = infixEq(base, branchBase)
      if a.isNil:
        a = test
      else:
        a = infixOr(a, test)
      let (newNilability, newMap) = checkBranch(test, code, ctx, map.copyMap())
      result.map = union(result.map, newMap)
      result.nilability = union(result.nilability, newNilability)
    of nkElse:
      let (newNilability, newMap) = checkBranch(prefixNot(a), child[0], ctx, map.copyMap())
      result.map = union(result.map, newMap)
      result.nilability = union(result.nilability, newNilability)
    else:
      discard

# notes
# try:
#   a
#   b
# except:
#   c
# finally:
#   d
#
# if a doesnt raise, this is not an exit point:
#   so find what raises and update the map with that
# (a, b); c; d
# if nothing raises, except shouldn't happen
# .. might be a false positive tho, if canRaise is not conservative?
# so don't visit it
#
# nested nodes can raise as well: I hope nim returns canRaise for
# their parents
#
# a lot of stuff can raise
proc checkTry(n, ctx, map): Check =
  var newMap = map.copyMap()
  var currentMap = map
  # we don't analyze except if nothing canRaise in try
  var canRaise = false
  var hasFinally = false
  # var tryNodes: seq[PNode]
  # if n[0].kind == nkStmtList:
  #   tryNodes = toSeq(n[0])
  # else:
  #   tryNodes = @[n[0]]
  # for i, child in tryNodes:
  #   let (childNilability, childMap) = check(child, conf, currentMap)
  #   echo childMap
  #   currentMap = childMap
  #   # TODO what about nested
  #   if child.canRaise:
  #     newMap = union(newMap, childMap)
  #     canRaise = true
  #   else:
  #     newMap = childMap
  let (tryNilability, tryMap) = check(n[0], ctx, currentMap)
  newMap = union(tryMap, newMap)
  canRaise = n[0].canRaise
  
  var afterTryMap = newMap
  for a, branch in n:
    if a > 0:
      case branch.kind:
      of nkFinally:
        newMap = union(afterTryMap, newMap)
        let (_, childMap) = check(branch[0], ctx, newMap)
        newMap = union(newMap, childMap)
        hasFinally = true
      of nkExceptBranch:        
        if canRaise:
          let (_, childMap) = check(branch[^1], ctx, newMap)
          newMap = union(newMap, childMap)
      else:
        discard
  if not hasFinally:
    # we might have not hit the except branches
    newMap = union(afterTryMap, newMap)
  result = (Safe, newMap)

proc directStop(n): bool =
  case n.kind:
  of nkStmtList:
    for child in n:
      if directStop(child):
        return true
  of nkReturnStmt, nkBreakStmt, nkContinueStmt, nkRaiseStmt:
    return true
  of nkIfStmt, nkElse:
    return false
  else:
    aecho n.kind
  return false

proc checkCondition(n, ctx, map; isElse: bool, base: bool): NilMap =
  ## check conditions : used for if, some infix operators
  ##   isNil(a)
  if base:
    map.base = map
  result = map
  if n.kind == nkCall:
    if n[0].kind == nkSym and n[0].sym.magic == mIsNil:
      result = newNilMap(map, if base: map else: map.base)
      # I assumed n[1] is a sym?
      var nilability: Nilability
      (nilability, result) = check(n[1], ctx, result)

      let a = symbol(n[1])
      result.store(a, if not isElse: Nil else: Safe, if not isElse: TNil else: TSafe, n.info, n)
    else:
      discard
  elif n.kind == nkPrefix and n[0].kind == nkSym and n[0].sym.magic == mNot:
    result = checkCondition(n[1], ctx, map, not isElse, false)
  elif n.kind == nkInfix:
    result = checkInfix(n, ctx, map).map
  else:
    discard

proc checkResult(n, ctx, map) =
  let resultNilability = map[resultId]
  case resultNilability:
  of Nil:
    message(ctx.config, n.info, warnStrictNotNil, "return value is nil")
  of MaybeNil:
    message(ctx.config, n.info, warnStrictNotNil, "return value might be nil")
  of Safe:
    discard    

proc checkBranch(condition: PNode, n, ctx, map; isElse: bool = false): Check =
  let childMap = checkCondition(condition, ctx, map, isElse, base=true)
  result = check(n, ctx, childMap)

proc checkElseBranch(condition: PNode, n, ctx, map): Check =
  checkBranch(condition, n, ctx, map, isElse=true)

# Faith!

proc check(n: PNode, ctx: NilCheckerContext, map: NilMap): Check =
  # echo "n", n, " ", n.kind
  if map.isNil:
    echo "map nil ", n.kind
    writeStackTrace()
    quit 1
  # look in varpartitions: imporant to change abstractTime in
  # compatible way
  var oldAbstractTime = ctx.abstractTime
  inc ctx.abstractTime
  case n.kind:
  of nkSym:
    aecho symbol(n), map
    dec ctx.abstractTime
    result = (nilability: map[symbol(n)], map: map)
  of nkCallKinds:
    aecho "call", n
    if n.sons[0].kind == nkSym:
      let callSym = n.sons[0].sym
      case callSym.magic:
      of mAnd, mOr:
        result = checkInfix(n, ctx, map)
      of mIsNil:
        result = checkIsNil(n, ctx, map)
      else:
        result = checkCall(n, ctx, map)
    else:
      result = checkCall(n, ctx, map)
  of nkHiddenStdConv, nkHiddenSubConv, nkConv, nkExprColonExpr, nkExprEqExpr,
     nkCast:
    result = check(n.sons[1], ctx, map)
  of nkStmtList, nkStmtListExpr, nkChckRangeF, nkChckRange64, nkChckRange,
     nkBracket, nkCurly, nkPar, nkTupleConstr, nkClosure, nkObjConstr, nkElse:
    result.map = map
    for child in n:
      result = check(child, ctx, result.map)
    if n.kind in {nkObjConstr, nkTupleConstr}:
      result.nilability = Safe
  of nkDotExpr:
    result = checkDotExpr(n, ctx, map)
  of nkDerefExpr, nkHiddenDeref:
    result = checkDeref(n, ctx, map)
  of nkAddr, nkHiddenAddr:
    result = check(n.sons[0], ctx, map)
  of nkIfStmt, nkIfExpr:
    var mapR: NilMap = map.copyMap()
    var nilabilityR: Nilability = Safe
    let (nilabilityL, mapL) = checkBranch(n.sons[0].sons[0], n.sons[0].sons[1], ctx, map.copyMap())
    # echo "if ", n.sons[0].sons[1]
    var isDirect = false
    if n.sons.len > 1:
      (nilabilityR, mapR) = checkElseBranch(n.sons[0].sons[0], n.sons[1], ctx, map.copyMap())
    else:
      mapR = checkCondition(n.sons[0].sons[0], ctx, mapR, true, true)
      nilabilityR = Safe
      if directStop(n[0][1]):
        isDirect = true
        result.map = mapR
        result.nilability = nilabilityR

    #echo "other", mapL, mapR
    if not isDirect:
      result.map = union(mapL, mapR)
      result.nilability = if n.kind == nkIfStmt: Safe else: union(nilabilityL, nilabilityR)
    #echo "result", result
  of nkAsgn:
    result = checkAsgn(n[0], n[1], ctx, map)
  of nkVarSection:
    result.map = map
    for child in n:
      aecho child.kind
      result = checkAsgn(child[0], child[2], ctx, result.map)
  of nkForStmt:
    result = checkFor(n, ctx, map)
  of nkCaseStmt:
    result = checkCase(n, ctx, map)
  of nkReturnStmt:
    result = checkReturn(n, ctx, map)
  of nkBracketExpr:
    result = checkBracketExpr(n, ctx, map)
  of nkTryStmt:
    result = checkTry(n, ctx, map)
  of nkWhileStmt:
    result = checkWhile(n, ctx, map)
  of nkNilLit:
    result = (Nil, map)
  of nkIntLit:
    result = (Safe, map)
  of nkNone, #..pred(nkSym), succ(nkSym)..pred(nkNilLit):
   nkTypeSection, nkProcDef, nkConverterDef,
      nkMethodDef, nkIteratorDef, nkMacroDef, nkTemplateDef, nkLambda, nkDo,
      nkFuncDef, nkConstSection, nkConstDef, nkIncludeStmt, nkImportStmt,
      nkExportStmt, nkPragma, nkCommentStmt, nkBreakState, nkTypeOfExpr:
  
    # TODO check if those are the same nodes as in varpartitions
    dec ctx.abstractTime
    # echo n.kind
    result = (Nil, map)
  else:
    result = (Nil, map)

  var isMutating = false
  var mutatingGraphIndices: seq[GraphIndex] = @[]
  # set: we should have most 1 of each index
  if ctx.abstractTime != oldAbstractTime:
    for i, graph in ctx.partitions.graphs:
      for m in graph.mutations:
        if m >= ctx.abstractTime and oldAbstractTime < m:
          mutatingGraphIndices.add(i)
          break
        elif m > ctx.abstractTime:
          break
  
  echo "nilcheck : abstractTime " & $ctx.abstractTime & " mutating " & $mutatingGraphIndices & " node " & $n.kind
  for graphIndex in mutatingGraphIndices:
    var graph = ctx.partitions.graphs[graphIndex]
    # update all potential aliases to MaybeNil
    # because they might not be always aliased:
    # we might have false positive in a liberal analysis
    for element in graph.elements:
      let elementSymbol = symbol(element)
      map.store(
        elementSymbol,
        MaybeNil,
        TPotentialAlias,
        n.info,
        element)


  
  # echo map

proc typeNilability(typ: PType): Nilability =
  #if not typ.isNil:
  #  echo ("type ", typ, " ", typ.flags, " ", typ.kind)
  if typ.isNil: # TODO is it ok
    Safe
  elif tfNotNil in typ.flags:
    Safe
  elif typ.kind in {tyRef, tyCString, tyPtr, tyPointer}:
    # 
    # tyVar ? tyVarargs ? tySink ? tyLent ?
    # TODO spec? tests? 
    MaybeNil
  else:
    Safe

proc checkNil*(s: PSym; body: PNode; conf: ConfigRef, partitions: Partitions) =
  var map = newNilMap()
  let line = s.ast.info.line
  let fileIndex = s.ast.info.fileIndex.int
  var filename = conf.m.fileInfos[fileIndex].fullPath.string

  echo toTextGraph(conf, partitions)
  # TODO
  var context = NilCheckerContext(partitions: partitions, config: conf)
  for i, child in s.typ.n.sons:
    if i > 0:
      if child.kind != nkSym:
        continue
      map.store(symbol(child), typeNilability(child.typ), TArg, child.info, child)

  map.store(resultId, if not s.typ[0].isNil and s.typ[0].kind == tyRef: Nil else: Safe, TResult, s.ast.info)
  echo "checking ", s.name.s, " ", filename
  # var par = loadPartitions(s, body, conf) 
  let res = check(body, context, map)
  if res.nilability == Safe and (not res.map.history.hasKey(resultId) or res.map.history[resultId].len <= 1):
    res.map.store(resultId, Safe, TAssign, s.ast.info)
  if not s.typ[0].isNil and s.typ[0].kind == tyRef and tfNotNil in s.typ[0].flags:
    checkResult(s.ast, context, res.map)