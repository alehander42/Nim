type
  Js = JsObject

  JSONLib = ref object
    stringify: proc(c: Js): cstring
    parse: proc(c: cstring): Js
  
  WriteDirEffect* = object of WriteIOEffect

  ReadDirEffect* = object of ReadIOEffect

  FS* = ref object
    readFileSync*: proc(path: cstring, options: Js): cstring {.tags: [ReadIOEffect].}
    writeFileSync*: proc(path: cstring, raw: cstring, options: Js) {.tags: [WriteIOEffect].}
    mkdirSync*: proc(path: cstring) {.tags: [WriteDirEffect].}
    readdirSync*: proc(path: cstring): seq[cstring] {.tags: [ReadDirEffect].}
    existsSync*: proc(path: cstring): bool {.tags: [ReadIOEffect].}

  Process = ref object
    argv*: seq[cstring]

  Path = ref object
    join*: proc: cstring {.varargs.}

  PathComponent* = enum   ## Enumeration specifying a path component.
    pcFile,               ## path refers to a file
    pcLinkToFile,         ## path refers to a symbolic link to a file
    pcDir,                ## path refers to a directory
    pcLinkToDir           ## path refers to a symbolic link to a directory

var require* {.importc.}: proc(lib: cstring): Js {.tags: [].}
var JSON* {.importc.}: JSONLib
var fs*: FS # = cast[FS](require("fs"))

var process* {.importc.}: Process

var path*: Path
var pathRequired* = false

template requireOnce(name: untyped, lib: static[string], libType: typedesc) =
  if `name`.isNil:
    `name` = cast[`libType`](require(`lib`))

proc requireFs =
  requireOnce(fs, "fs", FS)

proc readFile*(path: string): string {.tags: [ReadIOEffect] .} =
  requireFS()
  $fs.readFileSync(cstring(path), js{encoding: cstring"utf8"})

proc writeFile*(path: string, raw: string) {.tags: [WriteIOEffect] .} =
  requireFS()
  fs.writeFileSync(cstring(path), cstring(raw), js{encoding: cstring"utf8"})

proc createDir*(dir: string) {.tags: [WriteDirEffect, ReadDirEffect, ReadIOEffect].} =
  requireFS()
  if not fs.existsSync(cstring(dir)):
    fs.mkdirSync(cstring(dir))

proc paramCount*: int {.tags: [ReadIOEffect].} =
  process.argv.len - 2

proc paramStr*(i: int): TaintedString {.tags: [ReadIOEffect].} =
  $process.argv[i + 1]
