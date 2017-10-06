#define NIM_INTBITS 64
#include "nimbase.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <math.h>
#include <string.h>
#include <time.h>

#define displayGraph() {\
  for (size_t z = 0;z < clocksLen; z += 1) {\
    if (clocks[z] == 0) {\
      printf("%s\n", nodes[z]);\
    } else {\
      printf("l %u %.0Lf\n", lineNodes[z], (long double)clocks[z]);\
    }\
  }\
}


#define emit() {\
  if (clocksLen == 1000000) {\
    logGraph();\
  }\
}\


NU lineProfile(NU16 line, NI16 function) {
  NU16 functionLine = lines[function][line];
  lines[function][line] += 1;
  lineNodes[clocksLen] = line;
  clocks[clocksLen] = clock();
  clocksLen += 1;
  // optimize, just save here
  // we have to expand emit here too because we have loop with many lines
  emit();
  // // sprintf(nodes[nodesLen], "l %u %.0Lf", line, (long double)begin);
  // sprintf(nodes[nodesLen], "l %u", line);
  // nodesLen += 1;
  return functionLine;
}

NI callGraph(NI function) {
  char line[20];
  NU functionCallID = 0;
  if (callLen == 0) {
    for(size_t z = 0; z < 5000; z += 1) {
      memset(lines, 0, 2000 * sizeof(NU));
    }
  }
  if (callLen <= function) {
    callLen += 1;
    calls[callLen] = functionCallID;
  } else {
    functionCallID = calls[function] + 1;
    calls[function] = functionCallID;
  }
  sprintf(nodes[clocksLen], "%d", function);
  clocksLen += 1;
  // printf("%d\n", clocksLen);
  emit();
  return functionCallID;
}

void exitGraph() {
  nodes[clocksLen][0] = 'e';
  nodes[clocksLen][1] = '\0';
  clocksLen += 1;
  emit();
}

// void displayNode(CallNode node, size_t depth) {
//   for(size_t z = 0; z < depth; z += 1) {
//     printf(" ");
//   }
//   printf("%s %d:\n", functionNames[node.function], node.callID);
// }

void logGraph() {
  freopen("gdb.txt", "a", stdout);
  displayGraph();
  fclose(stdout);
  memset(lineNodes, 0, 1000000 * sizeof(NU));
  clocksLen = 0;
}

int h() {
  callGraph(3);
  exitGraph();
  return 0;
}

int g() {
  callGraph(2);
  h();
  exitGraph();
  return 2;
}

int f(int x) {
  callGraph(1);
  g();
  g();
  exitGraph();
  return 2;
}
