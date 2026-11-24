import Android

@inline(never) func level3(_ mode: String) {
  switch mode {
  case "fatal": fatalError("CRASHME from Swift")
  case "segv":
    let p = UnsafeMutablePointer<Int>(bitPattern: 8)!
    p.pointee = 42
  case "abort": abort()
  default: print("usage: crash fatal|segv|abort")
  }
}
@inline(never) func level2(_ m: String) { level3(m) }
@inline(never) func level1(_ m: String) { level2(m) }
level1(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "")
