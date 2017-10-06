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

type
  Line {.unchecked.} = array[50, char]

proc sprintf(dest: Line, format: cstring, arg: int) {.
  importc: "sprintf", header: "<stdio.h>".}

proc printf(format: cstring, a: untyped) {.
  importc: "printf", header: "<stdio.h>".}

# proc printf2(format: cstring, b: uint, c: Ticks) {.
#   importc: "printf", header: "<stdio.h>".}

type
  Stream = ref object

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

var lineNodes: array[MAX, uint]
# type 
#   elementArray{.unchecked.} = array[2000, uint16]

var lines: array[6000, array[7000, uint16]]





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

proc callGraph(function: int): uint {.exportc: "callGraph".}=
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
  sprintf(nodes[clocksLen], cstring"%d", function)
  clocksLen += 1
  # echo clocksLen
  emit()
  return functionCallID

proc exitGraph {.exportc: "exitGraph".} =
  nodes[clocksLen][0] = 'e'
  nodes[clocksLen][1] = '\0'
  clocksLen += 1
  emit()

proc displayGraph {.exportc: "displayGraph".} =
  for z in 0..<clocksLen:
    if lineNodes[z] == 0:
      printf("%s\n", nodes[z])
    else:
      printf("l %u ", lineNodes[z])
      printf("%ld\n", clocks[z])
    
proc logGraph =
  freopen(cstring"gdb.txt", cstring"a", stdout)
  displayGraph()
  fclose(stdout)
  memset(lineNodes, 0, 1_000_000 * sizeof(uint))
  clocksLen = 0

addQuitProc(logGraph)

