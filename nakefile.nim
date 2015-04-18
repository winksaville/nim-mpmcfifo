import nake

var
  buildArtifacts = @["nimcache", "mpscfifo", "mpmcstack",
    "tests/nimcache", "tests/testatomics",
    "tests/bm1", "tests/bm2"]
  #buildFlags = "--verbosity:1 --listCmd --embedsrc --threads:on --hints:off --warnings:off --lineDir:off --lineTrace=off --stackTrace:off -d:release"
  buildFlags = "--verbosity:1 --listCmd --embedsrc --threads:on --hints:off --warnings:off --lineDir:on  --lineTrace=on  --stackTrace:on"
  #buildFlags = "--verbosity:1 --listCmd --embedsrc --threads:on --hints:off --warnings:off --lineDir:on  --lineTrace=on  --stackTrace:on --parallelBuild:1"

  docFlags = ""
  docFiles: seq[string] = @[]
  exampleFiles: seq[string] = @[]

proc compileNim(fullPath: string) =
  echo "nim c: ", fullPath
  if not shell(nimExe, "c",  buildFlags, fullPath):
    echo "error compiling"
    quit 1

proc runNim(fullPath: string) =
  echo "run: ", fullPath
  if not shell(fullPath):
    echo "error running: file=", fullPath
    quit 1

proc compileRun(fullPath: string) =
  compileNim(fullPath)
  runNim(fullPath)

proc cleanCompileRun(fullPath: string) =
  runTask "clean"
  compileNim(fullPath)
  runNim(fullPath)

proc fullCompileRun(fullPath: string) =
  runTask "clean"
  runTask "docs"
  compileNim(fullPath)
  runNim(fullPath)

task "mpscfifo", "compile and run mpscfifo":
  compileRun("./mpscfifo")

task "mpmcstack", "compile and run mpmcstack":
  compileRun("./mpmcstack")

task "testatomics", "compile and run testatomics":
  compileRun("tests/testatomics")

task "bm1", "compile and run bm1":
  compileRun("tests/bm1")

task "bm2", "compile and run bm2":
  compileRun("tests/bm2")

task "bm3", "compile and run bm3":
  compileRun("tests/bm3")

task "mpscfifo", "build, run mpscfifo":
  compileNim("./mpscfifo")
  runNim("./mpscfifo")

task "docs", "Buiild the documents":
  for file in docFiles:
    if not shell(nimExe, "doc", docFlags, file):
      echo "error generating docs"
      quit 1

task "exmpl", "Build and run the exmpl":
  for file in exampleFiles:
    compileNim(file)
    runNim(file)

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

