import jsffi, os

writeFile("e", "write")
var e = readFile("e")
echo e

for path in walkDir("../tests"):
  echo path
