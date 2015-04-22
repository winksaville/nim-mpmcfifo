import nake

var
  buildArtifacts = @["nimcache", "mpscfifo", "mpmcstack",
    "tests/nimcache", "tests/testatomics",
    "tests/bm1", "tests/bmmpsc_otp", "tests/bmmpsc_ot"]

  typicalFlags = "--verbosity:1 --listCmd --embedsrc" &
    " --threads:on --hints:off --warnings:on"
  releaseFlags = typicalFlags &
    " --lineDir:off --lineTrace=off --stackTrace:off -d:release"
  debugFlags   = typicalFlags &
    " --lineDir:on  --lineTrace=on  --stackTrace:on"
  parallel1Flags = debugFlags & " --parallelBuild:1"

  buildFlags = debugFlags

  docFlags = ""
  docFiles: seq[string] = @[]
  exampleFiles: seq[string] = @[]

proc compileNim(fullPath: string, flags: string) =
  echo "nim c: ", fullPath
  if not shell(nimExe, "c", flags, fullPath):
    echo "error compiling"
    quit 1

proc runNim(fullPath: string) =
  echo "run: ", fullPath
  if not shell(fullPath):
    echo "error running: file=", fullPath
    quit 1

proc compileRun(fullPath: string, flags: string = buildFlags) =
  compileNim(fullPath, flags)
  runNim(fullPath)

proc cleanCompileRun(fullPath: string, flags: string = buildFlags) =
  runTask "clean"
  compileNim(fullPath, flags)
  runNim(fullPath)

proc fullCompileRun(fullPath: string, flags: string = buildFlags) =
  runTask "clean"
  runTask "docs"
  compileNim(fullPath, flags)
  runNim(fullPath)

task "mpscfifo", "compile and run mpscfifo":
  compileRun("./mpscfifo")

task "mpmcstack", "compile and run mpmcstack":
  compileRun("./mpmcstack")

task "testatomics", "compile and run testatomics":
  compileRun("tests/testatomics")

task "bm1", "compile and run bm1":
  compileRun("tests/bm1", releaseFlags)

task "bm1-d", "compile and run bm1":
  compileRun("tests/bm1", debugFlags)

task "bmmpsc_otp", "compile and run bmmpsc_otp":
  compileRun("tests/bmmpsc_otp", releaseFlags)

task "bmmpsc_otp-d", "compile and run bmmpsc_otp":
  compileRun("tests/bmmpsc_otp", debugFlags)

task "bmmpsc_ot", "compile and run bmmpsc_ot":
  compileRun("tests/bmmpsc_ot", releaseFlags)

task "bmmpsc_ot-d", "compile and run bmmpsc_ot":
  compileRun("tests/bmmpsc_ot", debugFlags)

task "docs", "Buiild the documents":
  for file in docFiles:
    if not shell(nimExe, "doc", docFlags, file):
      echo "error generating docs"
      quit 1

task "exmpl", "Build and run the exmpl":
  for file in exampleFiles:
    compileRun(file)

task "clean", "clean build artifacts":
  proc removeFileOrDir(file: string) =
    try:
      removeFile(file)
    except OSError:
      try:
        removeDir(file)
      except OSError:
        echo "Could not remove: ", file, " ", getCurrentExceptionMsg()

  for file in buildArtifacts:
    removeFileOrDir(file)

