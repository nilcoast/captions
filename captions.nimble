# Package
version       = "0.2.0"
author        = "nilcoast"
description   = "Real-time audio transcription overlay"
license       = "MIT"
srcDir        = "src"
bin           = @["captions"]

# Dependencies
requires "nim >= 2.0.0"
requires "parsetoml >= 0.7.0"

# Build config
task build, "Build captions":
  exec "nim c --threads:on --mm:orc -d:release -o:captions src/captions.nim"

task debug, "Build captions (debug)":
  exec "nim c --threads:on --mm:orc -o:captions src/captions.nim"
