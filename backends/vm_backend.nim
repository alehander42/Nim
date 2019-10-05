import compiler / [
    parser, vmdef, vm,
    ast, modules, idents, passes, condsyms,
    options, sem, llstream, vm, vmdef, commands, msgs,
    wordrecg, modulegraphs,
    lineinfos, pathutils, configuration, nimconf, extccomp, renderer
  ], strutils, sequtils, os, times, osproc, strtabs

type
  VmBackend* = ref object
    c*: PCtx
    module*: PSym
    cache*: IdentCache
    config*: ConfigRef
    graph*: ModuleGraph
    history*: seq[string]

proc init*: VmBackend=
  var backend = VmBackend()
  backend.cache = newIdentCache()
  backend.config = newConfigRef()
  # condsyms.initDefines(backend.symbols)
  backend.config.projectName = "stdinfile"
  backend.config.projectFull = AbsoluteFile"stdinfile"
  backend.config.projectPath = canonicalizePath(backend.config, AbsoluteFile(getCurrentDir())).AbsoluteDir
  backend.config.projectIsStdin = true
  backend.config.searchPaths = @[AbsoluteDir"/home/al/nim/lib", AbsoluteDir"/home/al/nim/lib/pure"]
  # backend.config.libpath = AbsoluteDir"/home/al/nim/"
  loadConfigs(DefaultConfig, backend.cache, backend.config)
  extccomp.initVars(backend.config)

  backend.graph = newModuleGraph(backend.cache, backend.config)
  initDefines(backend.config.symbols)
  defineSymbol(backend.config.symbols, "nimscript")
  defineSymbol(backend.config.symbols, "nimrepl")
  registerPass(backend.graph, semPass)
  registerPass(backend.graph, evalPass)
  undefSymbol(backend.config.symbols, "nimv2")

  backend.module = backend.graph.makeModule("/home/al/stdin.nim")
  incl(backend.module.flags, sfMainModule)
  backend.c = newCtx(backend.module, backend.cache, backend.graph)
  backend.c.mode = emRepl
  backend.graph.compileSystemModule()
  backend

proc parse*(backend: VmBackend, code: string): PNode =
  parseString(code, backend.cache, backend.config)

proc run*(backend: VmBackend, code: string): string =
  var node = backend.parse(code)[0]
  echo "parsed ", node.kind, " ", $node
  backend.c.evalStmt(node)
  let res = newNodeI(nkEmpty, node.info)
  return $res

