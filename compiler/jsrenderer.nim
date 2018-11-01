#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This is the JavaScript code generator.


import
  ast, astalgo, strutils, hashes, trees, platform, magicsys, extccomp, options,
  nversion, nimsets, msgs, std / sha1, bitsets, idents, types, os, tables,
  times, ropes, math, passes, ccgutils, wordrecg, renderer,
  intsets, cgmeth, lowerings, sighashes, lineinfos, rodutils, pathutils, transf, strformat

import macros 

from modulegraphs import ModuleGraph, PPassContext

type
  RendererObj = object of PPassContext
    module: PSym
    graph: ModuleGraph
    config: ConfigRef
    backend: Code

  Renderer = ref RendererObj

  Code = ref object of RootObj
    raw:            string
    tokens:         seq[TokenPosition]
    currentIndent:  int
    indentSize:     int
    line:           int
    col:            int

  TokenKind = enum TCode, TFormatting, TName

  TokenPosition = object
    start:       int
    until:       int
    kind:        TokenKind
    jsLocation:  tuple[line: int, col: int]
    nimLocation: TLineInfo

var code = Code()

using
  node: PNode

# helpers

template incIndent =
  code.currentIndent += 1

template decIndent =
  code.currentIndent -= 1

proc newToken(start: int, until: int, kind: TokenKind, jsLocation: tuple[line: int, col: int]): TokenPosition =
  TokenPosition(
    start: start,
    until: until,
    kind: kind,
    jsLocation: jsLocation)

template genToken(t: string, kind: TokenKind = TCode) =
  code.raw.add(t)
  code.tokens.add(
    newToken(
      code.raw.len - t.len,
      code.raw.len,
      kind,
      (
        line: code.line,
        col: code.col)))
      

template nl =
  code.raw.add("\n")
  code.tokens.add(TokenPosition(start: code.raw.len - 1, until: code.raw.len, kind: TFormatting))
  code.line += 1
  code.col = 0

proc gen(t: string) =
  var last = 0
  for i, c in t:
    if c in NewLines:
      if last != i:
        genToken(t[last .. i - 1])
      nl()
      last = i + 1
  if last != t.len:
    genToken(t[last .. ^1])

template genName(t: string) =
  genToken(t, TName)

template gen(t: string, t2: string) =
  gen(t)
  gen(t2)

proc line(t: string) =
  code.raw.add(repeat(' ', code.currentIndent * code.indentSize))
  code.tokens.add(TokenPosition(start: code.raw.len - code.currentIndent * code.indentSize, until: code.raw.len, jsLocation: (line: code.line, col: 0), kind: TFormatting))
  code.col = code.currentIndent * code.indentSize
  gen(t)
  nl()

# node

proc render(node)

proc renderNone(node) =
  discard

proc renderCall(node) =
  render node[0]
  gen "("
  render node[1]
  gen ")"

proc renderForRange(node; name: string) =
  if node.kind == nkInfix and $node[0] == "..<":
    gen "var "
    genName name
    gen " = "
    render node[1]
    gen "; "
    genName name
    gen " < "
    render node[2]
    gen "; "
    genName name
    gen "+=1"

proc renderForStmt(node) =
  gen "for ("
  renderForRange(node[1], $node[0])
  gen ") {\n"
  incIndent()
  render node[2]
  decIndent()
  gen "}"

proc renderIfStmt(node; inElse: bool = false) =
  if inElse:
    gen "else "
  gen "if", " ("
  render node[0]
  gen ") {"
  nl()
  render node[1]
  gen "\n}\n"
  if node.len > 2 and not node[2].isNil:
    if node[2].kind == nkIfStmt:
      renderIfStmt(node[2], inElse=true)
    else:
      render(node[2])

proc renderProcDef(node) =
  assert node[1].kind == nkVerbatim
  let a = node[1].strVal
  echo a
  line a & " {"
  incIndent()
  for child in node[^1]:
    render(child)
    gen ";\n"  
  decIndent()
  line "}"

proc renderAsgn(node) =
  render(node[0])
  gen " = "
  render(node[1])

proc renderVerbatim(node) =
  gen node.strVal

proc renderStmtList(node) =
  for child in node:
    render(child)

macro genCase(t: TNodeKind, name: untyped, args: varargs[untyped]): untyped =
  result = nnkCaseStmt.newTree(nnkDotExpr.newTree(args[0], ident"kind"))
  for a in TNodeKind.low .. TNodeKind.high:
    let aNode = ident($a)
    let callName = ident(name.repr & ($a)[2 .. ^1].capitalizeAscii)
    var call = nnkCall.newTree(callName)
    for arg in args:
      call.add(arg)
    let code = quote:
      when declared(`callName`):
        `call`
      else:
        discard
    result.add(nnkOfBranch.newTree(aNode, code))

proc render(node: PNode) =
  if not node.isNil:
    echo node.kind
    genCase(TNodeKind.low, render, node)


proc newRenderer(graph: ModuleGraph, module: PSym): Renderer =
  if graph.backend.isNil:
    graph.backend = Code()
  Renderer(graph: graph, module: module, config: graph.config)


proc myProcess(b: PPassContext, n: PNode): PNode =
  # var renderer = Renderer(b)
  # if renderer.backend.isNil:
  #   renderer.backend = initCode()
  # echo "MY PROCESS RENDER"
  result = n

proc myClose(graph: ModuleGraph, b: PPassContext, n: PNode): PNode =
  result = myProcess(b, n)
  var renderer = Renderer(b)

  if sfMainModule in renderer.module.flags:
    var node = n
    render(node)
    
    result = n

  # result = myProcess(b, n)
  # var renderer = Renderer(b)
  # # var code = Code(renderer.backend)
  let f = $toFilename(renderer.config, FileIndex renderer.module.position)
  let ext = "js"
  let outfile =
    if not renderer.config.outFile.isEmpty:
      if renderer.config.outFile.string.isAbsolute: renderer.config.outFile
      else: AbsoluteFile(getCurrentDir() / renderer.config.outFile.string)
    else:
      changeFileExt(completeCFilePath(renderer.config, AbsoluteFile f), ext)
  let (outDir, _, _) = splitFile(outfile)
  if not outDir.isEmpty:
    createDir(outDir)
  writeFile(outfile, code.raw)
  # echo "MY CLOSE RENDER"

proc myOpen(graph: ModuleGraph, s: PSym): PPassContext =
  # echo "MY OPEN RENDER"
  result = newRenderer(graph, s)
  code.indentSize = 2
  # discard

const JSrenderPass* = makePass(myOpen, myProcess, myClose)

