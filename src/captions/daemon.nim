## Unix socket control server using GLib timeout polling.
## Handles toggle/stop/status commands from the CLI client.

import std/[os, net, nativesockets, atomics, strutils, logging, strformat, locks]
import ./gtk4_bindings
import ./config
import ./audio
import ./transcribe
import ./overlay
import ./recorder
import ./summary

type
  SessionState = object
    ring: ptr RingBuffer
    capture: ptr AudioCapture
    transcriber: ptr Transcriber
    wavRecorder: ptr WavRecorder
    sessionDir: string
    transcript: string
    transcriptLock: Lock
    active: Atomic[bool]

  Daemon* = ref object
    cfg*: AppConfig
    serverSock: Socket
    session: ptr SessionState
    running*: bool

proc newDaemon*(cfg: AppConfig): Daemon =
  result = Daemon(
    cfg: cfg,
    session: nil,
    running: false,
  )

proc isActive*(d: Daemon): bool =
  d.session != nil and d.session.active.load(moRelaxed)

proc startSession(d: Daemon) =
  if d.isActive:
    return

  info "Starting capture session"

  let sess = cast[ptr SessionState](allocShared0(sizeof(SessionState)))
  initLock(sess.transcriptLock)
  sess.active.store(true, moRelaxed)
  sess.transcript = ""
  d.session = sess

  # Create session directory for recording
  let sessDir = sessionDir(d.cfg.recording)
  sess.sessionDir = sessDir

  # Init ring buffer
  sess.ring = initRingBuffer(d.cfg.audio.bufferSeconds, d.cfg.audio.sampleRate)

  # Init audio capture
  sess.capture = newAudioCapture(d.cfg.audio, sess.ring)

  # Set up WAV recording callback
  if d.cfg.recording.saveAudio:
    createDir(sessDir)
    var rec = cast[ptr WavRecorder](allocShared0(sizeof(WavRecorder)))
    rec[] = newWavRecorder(sessDir, d.cfg.audio.sampleRate, d.cfg.audio.channels)
    sess.wavRecorder = rec

    sess.capture.onSamples = proc(data: ptr float32, count: int) {.gcsafe.} =
      if sess.wavRecorder != nil:
        writeSamples(sess.wavRecorder[], data, count)

  # Init transcriber
  sess.transcriber = newTranscriber(d.cfg.whisper, d.cfg.audio, sess.ring, addr sess.active)

  # Transcription callback — sends text to overlay + collects transcript
  sess.transcriber.onText = proc(text: string) {.gcsafe.} =
    idleAddText(text)
    acquire(sess.transcriptLock)
    if sess.transcript.len > 0:
      sess.transcript.add(" ")
    sess.transcript.add(text)
    release(sess.transcriptLock)

  # Start capture and transcription
  start(sess.capture)
  start(sess.transcriber)

  # Show overlay via idle callback
  proc showCb(data: pointer): cint {.cdecl.} =
    if gOverlay != nil: showOverlay(gOverlay)
    return 0
  discard g_idle_add(showCb, nil)

  info "Session started"

proc stopSession(d: Daemon) =
  if not d.isActive:
    return

  info "Stopping capture session"
  let sess = d.session

  # Signal stop
  sess.active.store(false, moRelaxed)

  # Join transcriber thread
  join(sess.transcriber)

  # Stop audio capture
  stop(sess.capture)

  # Finalize WAV
  if sess.wavRecorder != nil:
    finalize(sess.wavRecorder[])
    deallocShared(sess.wavRecorder)
    sess.wavRecorder = nil

  # Save transcript
  if d.cfg.recording.saveTranscript and sess.transcript.len > 0:
    createDir(sess.sessionDir)
    let path = sess.sessionDir / "transcript.txt"
    writeFile(path, sess.transcript)
    info &"Transcript saved: {path}"

  # Spawn summary generation
  spawnSummary(d.cfg.summary, sess.transcript, sess.sessionDir)

  # Hide overlay via idle callback
  proc hideCb(data: pointer): cint {.cdecl.} =
    if gOverlay != nil: hideOverlay(gOverlay)
    return 0
  discard g_idle_add(hideCb, nil)

  # Cleanup
  destroy(sess.transcriber)
  destroy(sess.capture)
  destroyRingBuffer(sess.ring)
  deinitLock(sess.transcriptLock)
  deallocShared(sess)
  d.session = nil

  info "Session stopped"

proc shutdownDaemon*(d: Daemon) =
  ## Graceful shutdown — safe to call from GLib context (e.g. signal check timer).
  if d.isActive:
    stopSession(d)
  d.running = false
  proc quitCb(data: pointer): cint {.cdecl.} =
    if gOverlay != nil:
      quitApp(gOverlay)
    return 0
  discard g_idle_add(quitCb, nil)

proc handleCommand(d: Daemon, cmd: string): string =
  let c = cmd.strip().toLowerAscii()
  case c
  of "toggle":
    if d.isActive:
      stopSession(d)
      "stopped"
    else:
      startSession(d)
      "started"
  of "stop":
    if d.isActive:
      stopSession(d)
    "stopped"
  of "status":
    if d.isActive: "active" else: "idle"
  of "quit":
    shutdownDaemon(d)
    "bye"
  else:
    "unknown command: " & c

proc setupSocket(d: Daemon) =
  let path = d.cfg.daemon.socketPath
  # Always try to remove stale socket (fileExists doesn't reliably detect unix sockets)
  try: removeFile(path)
  except CatchableError: discard

  d.serverSock = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
  d.serverSock.setSockOpt(OptReuseAddr, true)
  bindUnix(d.serverSock, path)
  d.serverSock.listen()
  d.serverSock.getFd().SocketHandle.setBlocking(false)
  info &"Listening on {path}"

# We store the Daemon ref in a global so the GLib callback can access it
var gDaemon: Daemon = nil

proc pollSocketCb(data: pointer): cint {.cdecl.} =
  ## Called periodically from GLib timeout. Returns 1 to continue, 0 to stop.
  let d = gDaemon
  if d == nil or not d.running:
    return 0

  try:
    var client: Socket
    new(client)
    d.serverSock.accept(client, inheritable = false)
    client.getFd().SocketHandle.setBlocking(true)

    var data = ""
    try:
      data = client.recvLine(timeout = 1000)
    except TimeoutError:
      data = ""

    if data.len > 0:
      let response = handleCommand(d, data)
      try:
        client.send(response & "\n")
      except CatchableError:
        discard
    client.close()
  except OSError:
    # No pending connection, that's fine
    discard

  return if d.running: 1.cint else: 0.cint

proc startDaemon*(d: Daemon) =
  d.running = true
  gDaemon = d
  setupSocket(d)

  # Add GLib timeout to poll the Unix socket every 100ms
  discard g_timeout_add(100, pollSocketCb, nil)

proc stopDaemon*(d: Daemon) =
  if d.isActive:
    stopSession(d)
  d.running = false
  gDaemon = nil
  try:
    d.serverSock.close()
  except CatchableError:
    discard
  if fileExists(d.cfg.daemon.socketPath):
    removeFile(d.cfg.daemon.socketPath)

# --- CLI client ---

proc sendCommand*(socketPath: string, command: string): string =
  let sock = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
  defer: sock.close()
  try:
    connectUnix(sock, socketPath)
    sock.send(command & "\n")
    result = sock.recvLine(timeout = 5000)
  except OSError as e:
    result = "error: " & e.msg
  except TimeoutError:
    result = "error: timeout"
