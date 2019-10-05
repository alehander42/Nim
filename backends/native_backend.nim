# import compiler / [
#     parser, vmdef, vm,
#     ast, modules, idents, passes, condsyms,
#     options, sem, llstream, vm, vmdef, commands, msgs,
#     wordrecg, modulegraphs,
#     lineinfos, pathutils, configuration, nimconf, extccomp
#   ], strutils, sequtils, os, times, osproc, strtabs

type
  NativeBackend* = ref object
    filename*: string

proc initNative*: NativeBackend=
  result = NativeBackend()
  
proc run*(backend: NativeBackend, code: string): string =
  ""

