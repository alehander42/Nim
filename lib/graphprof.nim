#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# when not defined(graphProfiler):
#   {.error: "Profiling support is turned off! Enable profiling by passing `--graphProfiler:on` to the compiler".}
# include "system/timers"

# I don't wanna depend on anyting

type
  Ticks = distinct int64

type  
  Clockid {.importc: "clockid_t", header: "<time.h>", final.} = object

  TimeSpec {.importc: "struct timespec", header: "<time.h>",
             final, pure.} = object ## struct timespec
    tv_sec: int  ## Seconds.
    tv_nsec: int ## Nanoseconds.
  
var
  CLOCK_REALTIME {.importc: "CLOCK_REALTIME", header: "<time.h>".}: Clockid

proc clock_gettime(clkId: Clockid, tp: var Timespec) {.
    importc: "clock_gettime", header: "<time.h>".}

proc getTicks(): Ticks {.exportc: "getTicks2".} =
  var t {.noInit.}: Timespec
  clock_gettime(CLOCK_REALTIME, t)
  result = Ticks(int64(t.tv_sec) * 1000000000'i64 + int64(t.tv_nsec))

proc memset[T: static[int], U](s: array[T, U], value: int, size: uint) {.
  importc: "memset", header: "<string.h>".}

proc memcpy(s: ptr char, i: ptr int, c: int) {.
  importc: "memcpy", header: "<string.h>".}

type
  Line {.unchecked.} = array[50, char]

type
  Stream = ref object

proc fwrite[T](source: T, size: int, count: int, z: Stream) {.
  importc: "fwrite", header: "<stdio.h>".}

proc sprintf(dest: Line, format: cstring, arg: int) {.
  importc: "sprintf", header: "<stdio.h>".}

proc freopen(filename: cstring, mode: cstring, stream: Stream) {.
  importc: "freopen", header: "<stdio.h>".}

proc fclose(stream: Stream) {.
  importc: "fclose", header: "<stdio.h>".}

var stdin {.importc: "stdin", header: "<unistd.h>".}: Stream 
var stdout {.importc: "stdout", header: "<unistd.h>".}: Stream

var calls: array[65_000, uint]
var callLen: uint = 0
var functionNames {.importc: "functionNames".}: array[65_000, cstring]

const MAX = 1_000_000
var nodes: array[MAX, Line] # no allocations
var clocks: array[MAX, Ticks]
var clocksLen: uint = 0

var lineNodes: array[MAX, uint16]
# type 
#   elementArray{.unchecked.} = array[2000, uint16]

var lines {.exportc: "lines__codetracer".}: array[6000, array[7000, uint16]]

var records: int64 = 0



proc logGraph: void {.exportc: "logGraph", noconv.}

template emit: untyped =
  if clocksLen == 1_000_000:
    logGraph()

proc lineProfile(line: uint16, function: int16): uint16 {.exportc: "lineProfile".} =
  var functionLine = lines[function][line]
  lines[function][line] += 1
  lineNodes[clocksLen] = line
  clocks[clocksLen] = getTicks()
  clocksLen += 1
  # optimize, just save here
  # we have to expand emit here too because we have loop with many lines
  emit()
  # // sprintf(nodes[nodesLen], "l %u %.0Lf", line, (long double)begin);
  # sprintf(nodes[nodesLen], "l %u", line);
  # nodesLen += 1;
  return functionLine

proc callGraph(function: int16): uint {.exportc: "callGraph".}=
  var functionCallID: uint = 0;
  if callLen == 0:
    for z in 0..<6_000:
      memset(lines[z], 0, 2_000 * sizeof(uint))
    
  if cast[int](callLen) <= cast[int](function):
    callLen += 1
    calls[callLen] = functionCallID
  else:
    functionCallID = calls[function] + 1
    calls[function] = functionCallID
  nodes[clocksLen][0] = '0'
  var f = function
  memcpy(nodes[clocksLen][1].addr, f.addr, 2)
  # sprintf(nodes[clocksLen], cstring"0%d", function)
  clocksLen += 1
  # echo clocksLen
  emit()
  return functionCallID

proc exitGraph {.exportc: "exitGraph".} =
  nodes[clocksLen][0] = '2'
  clocksLen += 1
  emit()

proc displayGraph {.exportc: "displayGraph".} =
  # <<KIND::1, LEFT::n>>
  #   KIND is CALL/LINE/EXIT
  #   CALL
  #     <<KIND::1, FUNCTIONID::2>>
  #   LINE
  #     <<KIND::1, LINE::2, CLOCK::8>>
  #   EXIT
  #     <<KIND::1>
  # can be even more optimal
  for z in 0..<clocksLen:
    if lineNodes[z] == 0:
      if nodes[z][0] == '0':
        fwrite(nodes[z], 1, 3, stdout)
      else:
        fwrite(nodes[z], 1, 1, stdout)
    else:
      var c = '1'
      fwrite(c.addr, 1, 1, stdout)
      fwrite(lineNodes[z].addr, sizeof(uint16), 1, stdout)
      fwrite(clocks[z].addr, sizeof(Ticks), 1, stdout)
    
var version: uint16 = 2

proc logGraph =
  records += int64(clocksLen)
  var r = records
  var v = 2
  freopen(cstring"gdb.txt", cstring"a", stdout)
  displayGraph()
  if clocksLen < 1_000_000:
    fwrite(r.addr, sizeof(int64), 1, stdout)
    fwrite(v.addr, sizeof(uint16), 1, stdout)
    fclose(stdout)
  else:
    fclose(stdout)
    memset(lineNodes, 0, 1_000_000 * sizeof(uint))
  clocksLen = 0

addQuitProc(logGraph)

