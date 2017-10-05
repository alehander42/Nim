#define NIM_INTBITS 64
#include "nimbase.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <math.h>

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

const float LOAD_FACTOR = 1.5;

int callGraph(int function) {
  if (globalGraph == NULL) {
    globalGraph = (CallGraph*)malloc(sizeof(CallGraph));
    globalGraph->program = "nim";    
    globalGraph->framesLen = 0;
    globalGraph->nodesLen = 0;
    globalGraph->nodesCap = 4;
    globalGraph->nodes = (CallNode*)malloc(sizeof(CallNode) * 4);
    callLen = 0;
  }
  NU functionCallID = 0;
  if (callLen <= function) {
    callLen += 1;
    calls[callLen] = functionCallID;
  } else {
    functionCallID = calls[function] + 1;
    calls[function] = functionCallID;
  }
  CallNode node;
  node.function = function;
  node.callID = functionCallID;
  
  // displayNode(node, 0);
  globalGraph->framesLen += 1;
  if (globalGraph->nodesLen == 0) {
    globalGraph->root = node;
    node.parentFunction = -1;
    node.parentCallID = 0;
  } else {
    CallNode base = globalGraph->frames[globalGraph->framesLen - 2];
    node.parentFunction = base.function;
    node.parentCallID = base.callID;
  }

  globalGraph->frames[globalGraph->framesLen - 1] = node;
  if (globalGraph->nodesLen >= globalGraph->nodesCap) {
    globalGraph->nodesCap = (int)floor((float)(globalGraph->nodesCap) * LOAD_FACTOR);
    globalGraph->nodes = realloc(globalGraph->nodes, globalGraph->nodesCap * sizeof(CallNode));
  }
  globalGraph->nodesLen += 1;
  globalGraph->nodes[globalGraph->nodesLen - 1] = node;
  if (globalGraph->nodesLen >= 1000000) {
    logGraph();
    globalGraph->nodesLen = 0;
  }
  return functionCallID;
}

void exitGraph() {
  if (globalGraph->framesLen > 0) {
    globalGraph->framesLen -= 1;
  } else {
    // exit(1);
  }
}

void displayNode(CallNode node, size_t depth) {
  for(size_t z = 0; z < depth; z += 1) {
    printf(" ");
  }
  printf("%s %d:\n", functionNames[node.function], node.callID);
}

void displayGraph() {
  for (size_t z = 0;z < globalGraph->nodesLen; z += 1) {
    displayNode(globalGraph->nodes[z], 0);
  }
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

// int main() {
//   callGraph(0);
//   for(size_t z = 0;z < 2000; z+= 1) {
//     f(8);
//   }
//   exitGraph();

//   // displayGraph();
// }

