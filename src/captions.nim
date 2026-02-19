## captions — Real-time audio transcription overlay for Sway.
##
## Usage:
##   captions              Start the daemon
##   captions toggle       Toggle capture on/off
##   captions stop         Stop current capture session
##   captions status       Query daemon status
##   captions quit         Shut down daemon

import std/[os, strutils, logging, atomics, posix]
import captions/[config, daemon]

# Platform-specific overlay imports
when defined(macosx):
  import captions/overlay_macos as overlay
else:
  import captions/[overlay, gtk4_bindings]

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

  # Signal handling — set atomic flag
  gShutdown.store(false, moRelaxed)
  signal(SIGINT, handleSignal)
  signal(SIGTERM, handleSignal)

  # Init overlay
  let ov = initOverlay(cfg.overlay)

  # Platform-specific timer setup for shutdown checking
  when defined(macosx):
    # Use dispatch timer for macOS
    type DispatchQueue {.importc: "dispatch_queue_t", header: "<dispatch/dispatch.h>".} = pointer
    type DispatchSource {.importc: "dispatch_source_t", header: "<dispatch/dispatch.h>".} = pointer

    proc dispatch_get_main_queue(): DispatchQueue {.
      importc: "dispatch_get_main_queue",
      header: "<dispatch/dispatch.h>".}

    proc dispatch_source_create(stype: pointer, handle: culong, mask: culong,
                                queue: DispatchQueue): DispatchSource {.
      importc: "dispatch_source_create",
      header: "<dispatch/dispatch.h>".}

    proc dispatch_source_set_event_handler_f(source: DispatchSource,
                                            handler: proc(ctx: pointer) {.cdecl.}) {.
      importc: "dispatch_source_set_event_handler_f",
      header: "<dispatch/dispatch.h>".}

    proc dispatch_source_set_timer(source: DispatchSource, start: uint64,
                                  interval: uint64, leeway: uint64) {.
      importc: "dispatch_source_set_timer",
      header: "<dispatch/dispatch.h>".}

    proc dispatch_resume(obj: pointer) {.
      importc: "dispatch_resume",
      header: "<dispatch/dispatch.h>".}

    var DISPATCH_SOURCE_TYPE_TIMER {.importc: "_dispatch_source_type_timer",
                                    header: "<dispatch/dispatch.h>".}: pointer

    const NSEC_PER_MSEC = 1_000_000'u64

    proc checkShutdown(data: pointer) {.cdecl.} =
      if gShutdown.load(moRelaxed):
        let daemon = cast[Daemon](data)
        shutdownDaemon(daemon)
        quitApp(ov)

    let mainQueue = dispatch_get_main_queue()
    let timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, mainQueue)
    dispatch_source_set_event_handler_f(timer, checkShutdown)
    dispatch_source_set_timer(timer, 200 * NSEC_PER_MSEC, 200 * NSEC_PER_MSEC, 0)
    dispatch_resume(timer)
  else:
    # Use GLib timer for Linux
    proc checkShutdown(data: pointer): cint {.cdecl.} =
      if gShutdown.load(moRelaxed):
        let daemon = cast[Daemon](data)
        shutdownDaemon(daemon)
        return 0  # stop timer
      return 1  # keep running
    discard g_timeout_add(200, checkShutdown, cast[pointer](d))

  # Start daemon (sets up socket + polling)
  startDaemon(d)

  # Run application main loop (blocks until quit)
  runApp(ov)

  # Cleanup
  stopDaemon(d)
  info "Daemon stopped"

when isMainModule:
  main()
