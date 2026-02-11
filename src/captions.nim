## captions — Real-time audio transcription overlay for Sway.
##
## Usage:
##   captions              Start the daemon
##   captions toggle       Toggle capture on/off
##   captions stop         Stop current capture session
##   captions status       Query daemon status
##   captions quit         Shut down daemon

import std/[os, strutils, logging, atomics, posix]
import captions/[config, daemon, overlay, gtk4_bindings]

var gShutdown: Atomic[bool]

proc handleSignal(sig: cint) {.noconv.} =
  gShutdown.store(true, moRelaxed)

proc main() =
  let logger = newConsoleLogger(fmtStr = "$datetime [$levelname] ", levelThreshold = lvlInfo)
  addHandler(logger)

  let cfg = loadConfig()
  let args = commandLineParams()

  # CLI subcommands — send to running daemon
  if args.len > 0:
    let cmd = args[0].toLowerAscii()
    if cmd in ["toggle", "stop", "status", "quit"]:
      let resp = sendCommand(cfg.daemon.socketPath, cmd)
      echo resp
      quit(0)
    elif cmd == "help" or cmd == "--help" or cmd == "-h":
      echo "Usage:"
      echo "  captions              Start the daemon"
      echo "  captions toggle       Toggle capture on/off"
      echo "  captions stop         Stop current capture session"
      echo "  captions status       Query daemon status"
      echo "  captions quit         Shut down daemon"
      quit(0)
    else:
      echo "Unknown command: " & cmd
      quit(1)

  # Daemon mode
  info "Starting captions daemon"

  # Check if already running
  if fileExists(cfg.daemon.socketPath):
    let resp = sendCommand(cfg.daemon.socketPath, "status")
    if not resp.startsWith("error"):
      echo "Daemon already running (status: " & resp & ")"
      quit(1)
    else:
      # Stale socket
      removeFile(cfg.daemon.socketPath)

  var d = newDaemon(cfg)

  # Signal handling — set atomic flag, GLib poll picks it up
  gShutdown.store(false, moRelaxed)
  signal(SIGINT, handleSignal)
  signal(SIGTERM, handleSignal)

  # GLib timer checks the shutdown flag
  proc checkShutdown(data: pointer): cint {.cdecl.} =
    if gShutdown.load(moRelaxed):
      let daemon = cast[Daemon](data)
      shutdownDaemon(daemon)
      return 0  # stop timer
    return 1  # keep running
  discard g_timeout_add(200, checkShutdown, cast[pointer](d))

  # Init overlay
  let ov = initOverlay(cfg.overlay)

  # Start daemon (sets up socket + GLib polling)
  startDaemon(d)

  # Run GTK application main loop (blocks until quit)
  runApp(ov)

  # Cleanup
  stopDaemon(d)
  info "Daemon stopped"

when isMainModule:
  main()
