#define NIM_INTBITS 64
#include "nimbase.h"
#include <stdio.h>
#include <stdlib.h>

int callGraph(int function) {
  if (globalGraph == NULL) {
    globalGraph = (CallGraph*)malloc(sizeof(CallGraph));
    globalGraph->root = NULL;
    globalGraph->program = "nim";    
    globalGraph->framesLen = 0;
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
  CallNode* node = (CallNode*)malloc(sizeof(CallNode));
  node->function = function;
  node->callID = functionCallID;
  node->childrenLen = 0;

  // displayNode(node, 0);
  globalGraph->framesLen += 1;
  globalGraph->frames[globalGraph->framesLen - 1] = node;
  if (globalGraph->root == NULL) {
    globalGraph->root = node;
  } else {
    CallNode* base = globalGraph->frames[globalGraph->framesLen - 2];
    base->childrenLen += 1;
    if (base->childrenLen == 1) {
      base->children = (CallNode**)malloc(sizeof(CallNode*) * 4);
    } else if (base->childrenLen >= 4 && (base->childrenLen && !(base->childrenLen & (base->childrenLen - 1)))) {
      // printf("  bytes %d\n", base->childrenLen * 2 * sizeof(CallNode*));
      // displayGraph();
      CallNode** t = realloc(base->children, base->childrenLen * 2 * sizeof(CallNode*));
      if (t == NULL) {
        return functionCallID;
      } else {
        base->children = t;
      }
    }      
    base->children[base->childrenLen - 1] = node;
  }
  // displayGraph();
  return functionCallID;
}

void exitGraph() {
  globalGraph->framesLen -= 1;
}

void displayNode(CallNode* node, size_t depth) {
  for(size_t z = 0; z < depth; z += 1) {
    printf(" ");
  }
  printf("%s %d:\n", functionNames[node->function], node->callID);
  // printf("%d\n", node->childrenLen == NULL);
  // printf("%d\n", node->childrenLen);
  for(size_t z = 0;z < node->childrenLen; z += 1) {
    displayNode(node->children[z], depth + 1);
  }
}

void displayGraph() {
  displayNode(globalGraph->root, 0);
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

