# Package

version       = "0.1.0"
author        = "Gordon Stein"
description   = "Main server for RoboScape Online"
license       = "MIT"
srcDir        = "src"
bin           = @["RoboScapeSimulatorMainServer"]
binDir        = "build"

# Dependencies

requires "nim >= 1.0.6", "httpbeast#head", "jester#head"
