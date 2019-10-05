import rdstdin, os, backends / [vm_backend, native_backend]

proc shell =
  var vmBackend: VmBackend
  var nativeBackend: NativeBackend
  var name = ""
  if paramCount() == 1:
    name = paramStr(1)
    if name != "vm" and name != "native":
      quit(1)
    elif name == "vm":
      vmBackend = init()
    elif name == "native":
      nativeBackend = initNative()
  while true:
    var line = readLineFromStdin "input > "
    if line == "quit":
      quit(0)
    var output = ""
    if name == "vm":
      output = vmBackend.run(line)
    else:
      output = nativeBackend.run(line)
    echo output

shell()
