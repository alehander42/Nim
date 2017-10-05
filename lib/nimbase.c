#define NIM_INTBITS 64
#include "nimbase.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <math.h>
#include <string.h>

// int callGraph(int function) {
//   if (globalGraph == NULL) {
//     globalGraph = (CallGraph*)malloc(sizeof(CallGraph));
//     globalGraph->root = NULL;
//     globalGraph->program = "nim";    
//     globalGraph->framesLen = 0;
//     callLen = 0;
//   }
//   NU functionCallID = 0;
//   if (callLen <= function) {
//     callLen += 1;
//     calls[callLen] = functionCallID;
//   } else {
//     functionCallID = calls[function] + 1;
//     calls[function] = functionCallID;
//   }
//   CallNode* node = (CallNode*)malloc(sizeof(CallNode));
//   node->function = function;
//   node->callID = functionCallID;
//   node->childrenLen = 0;

//   // displayNode(node, 0);
//   globalGraph->framesLen += 1;
//   globalGraph->frames[globalGraph->framesLen - 1] = node;
//   if (globalGraph->root == NULL) {
//     globalGraph->root = node;
//   } else {
//     CallNode* base = globalGraph->frames[globalGraph->framesLen - 2];
//     base->childrenLen += 1;
//     if (base->childrenLen == 1) {
//       base->children = (CallNode**)malloc(sizeof(CallNode*) * 4);
//     } else if (base->childrenLen >= 4 && (base->childrenLen && !(base->childrenLen & (base->childrenLen - 1)))) {
//       // printf("  bytes %d\t\t%s %d\n", base->childrenLen * 2 * sizeof(CallNode*), functionNames[base->function], base->function);
//       // if (base->childrenLen * 2 * sizeof(CallNode*) > (1 << 5)) {
//       //   size_t max = 0;
//       //   size_t functionMax = 0;
//       //   for(size_t z = 0; z < callLen; z += 1) {
//       //     if (calls[z] > max) {
//       //       max = calls[z];
//       //       functionMax = z;
//       //     }
//       //   }
//       //   printf("%s: %d\n", functionNames[functionMax], max);
//       // }
//       // displayGraph();
//       CallNode** t = realloc(base->children, base->childrenLen * 2 * sizeof(CallNode*));
//       if (t == NULL) {
//         return functionCallID;
//       } else {
//         base->children = t;
//       }
//     }      
//     base->children[base->childrenLen - 1] = node;
//   }
//   // displayGraph();
//   return functionCallID;
// }


void emit(char* line) {
  nodes[nodesLen] = line;
  nodesLen += 1;
  if (nodesLen > 3) {
    printf("%d %c\n", strlen(nodes[nodesLen - 1]), nodes[nodesLen - 1][0]);
  }
  if (nodesLen == 10000000) {
    logGraph();
    nodesLen = 0;
  }
}

NU16 lineProfile(NU16 line, NI16 function) {
  NU16 functionLine = 0;
  functionLine = lines[framesLen][line];
  lines[framesLen][line] += 1;
  char l[20];
  sprintf("l %d %d", l, functionLine);
  emit(l);
  return functionLine;
}

int callGraph(int function) {
  char line[20];
  NU functionCallID = 0;
  if (callLen <= function) {
    callLen += 1;
    calls[callLen] = functionCallID;
  } else {
    functionCallID = calls[function] + 1;
    calls[function] = functionCallID;
  }
  sprintf(line, "%d %d", function, functionCallID);
  framesLen += 1;
  emit(line); 
}

void exitGraph() {
  if (framesLen > 0) {
    framesLen -= 1;
    memset(lines[framesLen + 1], 0, 65000 * sizeof(NU16));
  } else {
    // exit(1);
  }
  emit("e");
}

// void displayNode(CallNode node, size_t depth) {
//   for(size_t z = 0; z < depth; z += 1) {
//     printf(" ");
//   }
//   printf("%s %d:\n", functionNames[node.function], node.callID);
// }

#define displayGraph() {\
  for (size_t z = 0;z < nodesLen; z += 1) {\
    printf("%s\n", nodes[z]);\
  }\
}

void logGraph() {
  freopen("gdb.txt", "a", stdout);
  displayGraph();
  fclose(stdout);
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

void i() {
  char line[12];
  sprintf(line, "%d\n", 12);
  emit(line);
}

// int main() {
//   i();
//   i();
//   displayGraph();
// }

