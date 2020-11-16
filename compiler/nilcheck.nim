#
#
#           The Nim Compiler
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import ast, renderer, intsets, tables, msgs, options, lineinfos, strformat, idents, treetab, hashes, varpartitions

# IMPORTANT: notes not up to date, i'll update this comment again
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
  ## a hashed representation of a node: should be equal for structurally equal nodes
  Symbol = int

  ## the index of an expression in the pre-indexed sequence of those
  ExprIndex = int

  ## transition kind:
  ##   what was the reason for changing the nilability of an expression
  ##   useful for error messages and showing why an expression is being detected as nil / maybe nil
  TransitionKind = enum TArg, TAssign, TType, TNil, TVarArg, TResult, TSafe, TPotentialAlias
  

  ## keep history for each transition
  History = object
    info: TLineInfo ## the location
    nilability: Nilability ## the nilability
    kind: TransitionKind ## what kind of transition was that
    node: PNode ## the node of the expression

  ## the context for the checker: an instance for each procedure
  NilCheckerContext = ref object
    # abstractTime: AbstractTime
    # partitions: Partitions 
    # symbolGraphs: Table[Symbol, ]
    symbolIndices: Table[Symbol, ExprIndex] ## index for each symbol
    expressions: seq[PNode] ## a sequence of pre-indexed expressions
    config: ConfigRef ## the config of the compiler

  ## a map that is containing the current nilability for usually a branch
  ## and is pointing optionally to a parent map: they make a stack of maps
  NilMap* = ref object
    expressions*:  seq[Nilability] ## the expressions with the same order as in NilCheckerContext
    history*:  seq[seq[History]] ## history for each of them
    sets*:     seq[set[ExprIndex]] ## disjoint sets with the aliased expressions
    parent*:   NilMap ## the parent map
    base*:     NilMap ## the root map


    

# NilMap: 
# zahary:
#   global variables
#   hm: detect those? keep in mind every non-func call might mutate them?
#   and that we can alias through them some args?
#   maybe huh
#   preindex gives index
#   seq with several elements
#   each has those
#   10: 20: 3 bytes 
#   how deep tho: for each branch we might have a new one?
#   3 * 1000 (we can just warn: limit reached)
#   and just a stack, and copy on local if needed
#   alloca some amount
#   or just preallocate a single seq of those
#   but what about history: ok it can be optional and also a simple seq mapping to each level
#   sets as well
#   but optional parents a bit harder
# iterate through it
# just iterating through them
# if we have 20-30 hm might be still too slow
# but we can just have a seq of sets ok
# 
# but also updating expr-s ?
# we just preindex all the expressions
# and update only those, not all possible
# so we do keep dependent , not only sets
# and we can maybe reuse it for initialization
# so we don't visit the other ones
# now we have invisible ones!
# a <- b # a.field1 ? b.field1 unknown? so depends on type!
# but first look for a set ..
# iterate through their children, those who have equal paths
# unify sets
# if no existing other expr: just based on type
  
  ## Nilability : if a value is nilable.
  ## we have maybe nil and nil, so we can differentiate between
  ## cases where we know for sure a value is nil and not
  ## otherwise we can have Safe, MaybeNil
  Nilability* = enum Safe, MaybeNil, Nil

  ## check
  Check = object
    nilability: Nilability
    map: NilMap


# useful to have known resultId so we can set it in the beginning and on return
const resultId = -1

proc check(n: PNode, ctx: NilCheckerContext, map: NilMap): Check
proc checkCondition(n: PNode, ctx: NilCheckerContext, map: NilMap, reverse: bool, base: bool): NilMap

# the NilMap structure

proc newNilMap(parent: NilMap = nil, count: int = -1): NilMap =
  var expressionsCount = 0
  if count != -1:
    expressionsCount = count
  elif not parent.isNil:
    expressionsCount = parent.expressions.len
  result = NilMap(
    expressions: newSeq[Nilability](count),
    history: newSeq[History](count),
    sets: newSeq[SetIndex](count),
    parent: parent)
  result.base = if parent.isNil: result else: parent.base

proc `[]`(map: NilMap, index: ExprIndex): Nilability =
  if index < map.expressions.len:
    map.expressions[index]
  else:
    # TODO what if it's bigger? assert?
    Safe
  # var now = map
  # while not now.isNil:
  #   if now.locals.hasKey(graphIndex):
  #     return now.locals[graphIndex]
  #   now = now.previous
  # return Safe

proc history(map: NilMap, index: ExprIndex): seq[History] =
  if index < map.expressions.len:
    map.history[index]
  else:
    @[]
  # var now = map
  # var h: seq[History] = @[]
  # while not now.isNil:
  #   if now.history.hasKey(graphIndex):
  #     # h = h.concat(now.history[name])
  #     return now.history[graphIndex]
  #   now = now.previous
  # return @[]

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

# proc timeNode(n: PNode): bool =
#   ## based on varpartitions
#   n.kind notin {nkSym, nkNone..pred(nkSym), succ(nkSym)..nkNilLit, nkTypeSection, nkProcDef, nkConverterDef,
#       nkMethodDef, nkIteratorDef, nkMacroDef, nkTemplateDef, nkLambda, nkDo,
#       nkFuncDef, nkConstSection, nkConstDef, nkIncludeStmt, nkImportStmt,
#       nkExportStmt, nkPragma, nkCommentStmt, nkBreakState, nkTypeOfExpr}

proc symbol(n: PNode): Symbol
proc `$`(map: NilMap): string
    
proc store(map: NilMap, index: ExprIndex, value: Nilability, kind: TransitionKind, info: TLineInfo, node: PNode = nil) =
  let text = if node.isNil: "?" else: $node
  # echo "store " & $graphIndex & " " & text & " " & $value & " " & $kind
  map.expressions[index] = value
  map.history[index].add(History(info: info, kind: kind, node: node, nilability: value))
  

# proc hasKey(map: NilMap, ): bool =
#   var now = map
#   result = false
#   while not now.isNil:
#     if now.locals.hasKey(graphIndex):
#       return true
#     now = now.previous

iterator pairs(map: NilMap): (ExprIndex, Nilability) =
  for index, value in now.expressions:
    yield (index, value)
  # var now = map
  # while not now.isNil:
  #   for graphIndex, value in now.locals:
  #     yield (graphIndex, value)
  #   now = now.previous

proc copyMap(map: NilMap): NilMap =
  if map.isNil:
    return nil
  result = newNilMap(map.parent) # no need for copy? if we change only this
  result.expressions = map.expressions
  result.history = map.history
  result.sets = map.sets
  # for graphIndex, value in map.locals:
  #   result.locals[graphIndex] = value
  # for graphIndex, value in map.history:
  #   result.history[graphIndex] = value

proc `$`(map: NilMap): string =
  var now = map
  var stack: seq[NilMap] = @[]
  while not now.isNil:
    stack.add(now)
    now = now.parent
  for i in 0 .. stack.len - 1:
    now = stack[i]
    result.add("###\n")
    for index, value in now.expressions:
      result.add(&"  {index} {value}\n")
  result.add "### end\n"

# symbol(result) -> resultId
# symbol(result[]) -> resultId
# symbol(result.a) -> !$(resultId !& a)
# symbol(result.b) -> !$(resultId !& b)
# what is sym id?

# resultId vs result.sym.id : different ??
# but the same actually
# what about var result ??

const noExprIndex = -1

# proc graph(ctx: NilCheckerContext, symbol: Symbol): GraphIndex =
#   if ctx.symbolGraphs.hasKey(symbol):
#     return ctx.symbolGraphs[symbol]
#   else:
#     # TODO: maybe index all in partitions
#     # or is this faster/smaller
#     # a unique non-real graph index for symbols which are not in graph
#     return noGraphIndex - 1 - symbol

proc index(ctx: NilCheckerContext, n: PNode): ExprIndex =
  ctx.symbolIndices[symbol(n)]

proc aliasSet(ctx: NilCheckerContext, map: NilMap, n: PNode): set[ExprIndex] =
  result = map.sets[ctx.index(n)]

proc symbol(n: PNode): Symbol =
  ## returns a Symbol for each expression
  ## the goal is to get an unique Symbol
  ## but we have to ensure hashTree does it as we expect
  case n.kind:
  of nkIdent:
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
        let a = ctx.index(child)
        result.map.store(a, MaybeNil, TVarArg, n.info, child)
    
  if n[0].kind == nkSym and n[0].sym.magic == mNew:
    let b = ctx.index(n[1])
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
  var a = history(map, ctx.index(n))
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
    result.nilability = typeNilability(n.typ)
  elif tfNotNil notin n.typ.flags:
    let key = ctx.index(n)
    result.nilability = result.map[key]
      # result.map.store(key, MaybeNil, TType, n.info, n)
      # result.nilability = MaybeNil

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
  ## what if they are from different parts of the same tree
  ## e.g.
  ## a -> b -> c
  ##   -> 
  ## for now assume same
  if l.isNil:
    return r
  elif r.isNil:
    return l
  
  result = newNilMap(common)
    
  # TODO locals ?
  for index, value in l.expressions:
    #if r.hasKey(graphIndex) and not result.locals.hasKey(graphIndex):
    var h = history(r, index)
    assert h.len > 0
    # echo "history", name, value, r[name], h[^1].info.line
    result.store(graphIndex, union(value, r[graphIndex]), TAssign, h[^1].info)

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
  
  # we need to visit and check those, but we don't use the result for now
  # is it possible to somehow have another event happen here?
  discard check(target, ctx, map)
  
  if result.map.isNil:
    result.map = map
  let t = ctx.index(target)
  case assigned.kind:
  of nkNilLit:
    result.map.store(t, Nil, TAssign, target.info, target)
  else:
    # echo "nilability ", $target, " ", $result.nilability
    result.map.store(t, result.nilability, TAssign, target.info, target)
    # if target.kind in {nkSym, nkDotExpr}:
    #  result.map.makeAlias(assigned, target)

proc checkReturn(n, ctx, map): Check =
  ## check return
  # return n same as result = n; return ?
  result = check(n[0], ctx, map)
  result.map.store(ctx.index(resultId), result.nilability, TAssign, n.info)


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
    m.store(ctx.index(n[0]), typeNilability(n[0].typ), TAssign, n[0].info)
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
  ## check infix operators in condition
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
  # let value2 = symbol(value)
  result.map.store(ctx.index(n[1]), if not isElse: Nil else: Safe, TArg, n.info, n)

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

proc checkBranch(n, ctx, map): Check

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
      let conditionMap = checkCondition(test, ctx, map.copyMap(), false, false)
      let newCheck = checkBranch(code, ctx, conditionMap)
      result.map = union(result.map, newCheck.map)
      result.nilability = union(result.nilability, newCheck.nilability)
    of nkElse:
      let mapElse = checkCondition(prefixNot(a), ctx, map.copyMap(), false, false)
      let newCheck = checkBranch(child[0], ctx, mapElse)
      result.map = union(result.map, newCheck.map)
      result.nilability = union(result.nilability, newCheck.map)
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
  let tryCheck = check(n[0], ctx, currentMap)
  newMap = union(tryMap, tryCheck.map)
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

proc direcStop(n): bool =
  ## if the node contains a direct stop
  ## as a continue/break/raise/return: then it means
  ## it is possible ..
  ## lets ignore this for now?
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

proc reverse(value: Nilability): Nilability =
  case value:
  of Nil: Safe
  of MaybeNil: MaybeNil
  of Safe: Nil

proc reverse(kind: TransitionKind): TransitionKind =
  case kind:
  of TNil: TSafe
  of TSafe: TNil
  else: raise newException(ValueError, "expected TNil or TSafe")

proc reverseDirect(map: NilMap): NilMap =
  result = map.copyMap()
  for index, value in result.expressions:
    result.expressions[index] = reverse(value)
    result.history[index][^1].kind = reverse(result.history[index][^1].kind)
    result.history[index][^1].nilability = result.expressions[index]

proc checkCondition(n, ctx, map; reverse: bool, base: bool): NilMap =
  ## check conditions : used for if, some infix operators
  ##   isNil(a)
  ##   it returns a new map: you need to reverse all the direct elements for else

  if n.kind == nkCall:
    result = newNilMap(map)
    for element in n:
      result = check(element, ctx, result).map

    if n[0].kind == nkSym and n[0].sym.magic == mIsNil:
      let a = ctx.index(n[1])
      result.store(a, if not reverse: Nil else: Safe, if not reverse: TNil else: TSafe, n.info, n[1])
    else:
      discard
  elif n.kind == nkPrefix and n[0].kind == nkSym and n[0].sym.magic == mNot:
    result = checkCondition(n[1], ctx, map, not reverse, false)
  elif n.kind == nkInfix:
    result = newNilMap(map)
    result = checkInfix(n, ctx, result).map
  else:
    result = check(n, ctx, map).map
    result = newNilMap(map)
  assert not result.isNil
  assert not result.previous.isNil

proc checkResult(n, ctx, map) =
  let resultNilability = map[ctx.index(resultId)]
  case resultNilability:
  of Nil:
    message(ctx.config, n.info, warnStrictNotNil, "return value is nil")
  of MaybeNil:
    message(ctx.config, n.info, warnStrictNotNil, "return value might be nil")
  of Safe:
    discard    

proc checkBranch(n, ctx, map): Check =
  result = check(n, ctx, map)


# Faith!

proc check(n: PNode, ctx: NilCheckerContext, map: NilMap): Check =
  if map.isNil:
    internalError(ctx.config, n.info, "map is nil: something went wrong in nilcheck")
  
  # var oldAbstractTime = ctx.abstractTime
  # if timeNode(n):
  #   inc ctx.abstractTime

  # var isMutating = false
  # var mutatingGraphIndices: seq[GraphIndex] = @[]
  
  # ok so mutating should include re-assignment?
  # and just
  # echo "nilcheck : abstractTime " & $ctx.abstractTime & " mutating " & $mutatingGraphIndices & " node " & $n.kind & " " & $n
  # for graphIndex in mutatingGraphIndices:
  #   var graph = ctx.partitions.graphs[graphIndex]
  #   # update all potential aliases to MaybeNil
  #   # because they might not be always aliased:
  #   # we might have false positive in a liberal analysis
  #   #for element in graph.elements:
  #   # let elementGraph = 
  #   assert graph.elements.len > 0
  #   let element = graph.elements[0]
  #   map.store(
  #     graphIndex,
  #     MaybeNil,
  #     TPotentialAlias,
  #     n.info,
  #     element)

  case n.kind:
  of nkSym:
    aecho symbol(n), map
    # echo "sym ", n
    result = (nilability: map[ctx.index(n)], map: map)
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
    ## check branches based on condition
    var mapIf: NilMap = map.copyMap()
    
    # first visit the condition
    # echo "nilcheck : abstractTime " & $ctx.abstractTime & " " & $n.kind & " " & $n[0]

    var mapCondition = checkCondition(n.sons[0].sons[0], ctx, mapIf, false, true)

    if n.sons.len > 1:
      let l = checkBranch(n.sons[0].sons[1], ctx, mapCondition.copyMap())
      let mapElse = reverseDirect(mapCondition)
      let r = checkBranch(n.sons[1], ctx, mapElse)
      result.map = union(l.map, r.map)
      result.nilability = if n.kind == nkIfStmt: Safe else: union(l.nilability, r.nilability)
    else:
      let l = checkBranch(n.sons[0].sons[1], ctx, mapCondition.copyMap())
      let mapNoIf = reverseDirect(mapCondition)
      result.map = union(mapNoIf, l.map)
      result.nilability = Safe
      #if directStop(n[0][1]):
      #  result.map = mapR
      #  result.nilability = nilabilityR
      #echo "if one branch " & " " & $mapCondition & " " & $mapIf & " " & $mapL & " " & $result.map & " " & $mapL.previous


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
  of nkNone..pred(nkSym), succ(nkSym)..nkNilLit, nkTypeSection, nkProcDef, nkConverterDef,
      nkMethodDef, nkIteratorDef, nkMacroDef, nkTemplateDef, nkLambda, nkDo,
      nkFuncDef, nkConstSection, nkConstDef, nkIncludeStmt, nkImportStmt,
      nkExportStmt, nkPragma, nkCommentStmt, nkBreakState, nkTypeOfExpr:
    
    discard "don't follow this : same as varpartitions"
    result = Check(nilablity: Nil, map: map)
  else:
    var elementMap = map.copyMap()
    var nilability = Safe
    for element in n:
      (nilability, elementMap) = check(element, ctx, elementMap)

    result = Check(nilability: Nil, map: elementMap)

  


  
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

proc checkNil*(s: PSym; body: PNode; conf: ConfigRef) =
  let line = s.ast.info.line
  let fileIndex = s.ast.info.fileIndex.int
  var filename = conf.m.fileInfos[fileIndex].fullPath.string

  var context = NilCheckerContext(config: conf)
  context.preVisit(body)
  var map = newNilMap(nil, context.symbolIndices.len)
  
  # TODO
  for i, child in s.typ.n.sons:
    if i > 0:
      if child.kind != nkSym:
        continue
      map.store(context.index(child), typeNilability(child.typ), TArg, child.info, child)

  map.store(context.index(resultId), if not s.typ[0].isNil and s.typ[0].kind == tyRef: Nil else: Safe, TResult, s.ast.info)
    
  # echo "checking ", s.name.s, " ", filename

  let res = check(body, context, map)
  let resultIndex = context.index(resultId)
  if res.nilability == Safe and res.map.history[resultIndex].len <= 1:
    res.map.store(resultIndex, Safe, TAssign, s.ast.info)
  
  # check for nilability result
  # (ANotNil, BNotNil) : 
  # do we check on asgn nilability at all?

  if not s.typ[0].isNil and s.typ[0].kind == tyRef and tfNotNil in s.typ[0].flags:
    checkResult(s.ast, context, res.map)
