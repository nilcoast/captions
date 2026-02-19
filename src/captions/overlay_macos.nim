## Pure Cocoa overlay for macOS - matches overlay.nim API

import std/[deques, strformat, strutils]
import ./config

# Import Objective-C helpers
{.compile("overlay_macos.m", "-fobjc-arc").}
{.passL: "-framework Cocoa -framework QuartzCore".}

type
  CaptionWindowHandle = pointer
  TextViewHandle = pointer

# C API from overlay_macos.m
proc createCaptionWindow(width, height, x, y: cdouble): CaptionWindowHandle {.importc.}
proc createTextView(width, height: cdouble,
                    fontName: cstring, fontSize: cdouble,
                    textR, textG, textB, textA: cdouble,
                    bgR, bgG, bgB, bgA: cdouble,
                    cornerRadius, padding: cdouble): TextViewHandle {.importc.}
proc showWindow(handle: CaptionWindowHandle) {.importc.}
proc hideWindow(handle: CaptionWindowHandle) {.importc.}
proc setWindowPosition(handle: CaptionWindowHandle, marginBottom: cdouble) {.importc.}
proc addTextViewToWindow(windowHandle: CaptionWindowHandle, textViewHandle: TextViewHandle,
                         marginSide, marginBottom: cdouble) {.importc.}
proc updateTextViewText(handle: TextViewHandle, text: cstring) {.importc.}
proc releaseWindow(handle: CaptionWindowHandle) {.importc.}
proc releaseTextView(handle: TextViewHandle) {.importc.}
proc runNSApp() {.importc.}
proc stopNSApp() {.importc.}
proc initNSApp() {.importc.}

# Dispatch queue for thread-safe operations
type DispatchQueue* {.importc: "dispatch_queue_t", header: "<dispatch/dispatch.h>".} = pointer

proc dispatch_get_main_queue*(): DispatchQueue {.
  importc: "dispatch_get_main_queue",
  header: "<dispatch/dispatch.h>".}

proc dispatch_async_f*(queue: DispatchQueue, context: pointer,
                       work: proc(ctx: pointer) {.cdecl.}) {.
  importc: "dispatch_async_f",
  header: "<dispatch/dispatch.h>".}

# Dispatch timer
type DispatchSource* {.importc: "dispatch_source_t", header: "<dispatch/dispatch.h>".} = pointer

proc dispatch_source_create*(stype: pointer, handle: culong, mask: culong,
                             queue: DispatchQueue): DispatchSource {.
  importc: "dispatch_source_create",
  header: "<dispatch/dispatch.h>".}

proc dispatch_source_set_event_handler_f*(source: DispatchSource,
                                          handler: proc(ctx: pointer) {.cdecl.}) {.
  importc: "dispatch_source_set_event_handler_f",
  header: "<dispatch/dispatch.h>".}

proc dispatch_source_set_timer*(source: DispatchSource, start: uint64,
                                interval: uint64, leeway: uint64) {.
  importc: "dispatch_source_set_timer",
  header: "<dispatch/dispatch.h>".}

proc dispatch_resume*(obj: pointer) {.
  importc: "dispatch_resume",
  header: "<dispatch/dispatch.h>".}

proc dispatch_source_cancel*(source: DispatchSource) {.
  importc: "dispatch_source_cancel",
  header: "<dispatch/dispatch.h>".}

{.emit: """
static const void* _nim_dispatch_timer_ptr = DISPATCH_SOURCE_TYPE_TIMER;
""".}
var DISPATCH_SOURCE_TYPE_TIMER* {.importc: "_nim_dispatch_timer_ptr", nodecl.}: pointer

const NSEC_PER_SEC = 1_000_000_000'u64

# Memory management
proc c_malloc(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}
proc c_free(p: pointer) {.importc: "free", header: "<stdlib.h>".}

type
  Overlay* = ref object
    window: CaptionWindowHandle
    textView: TextViewHandle
    lines: Deque[string]
    cfg: OverlayConfig
    visible*: bool
    fadeTimer: DispatchSource

var gOverlay*: Overlay = nil

# Color parsing helper
proc parseRGBA(color: string): tuple[r, g, b, a: cdouble] =
  # Parse "rgba(r, g, b, a)" format
  var s = color.strip()
  if s.startsWith("rgba(") and s.endsWith(")"):
    s = s[5..^2]
    let parts = s.split(',')
    if parts.len == 4:
      result.r = parseFloat(parts[0].strip()) / 255.0
      result.g = parseFloat(parts[1].strip()) / 255.0
      result.b = parseFloat(parts[2].strip()) / 255.0
      result.a = parseFloat(parts[3].strip())
      return
  # Fallback to white
  result = (1.0, 1.0, 1.0, 1.0)

# Font parsing helper
proc parseFontName(font: string): tuple[name: string, size: cdouble] =
  # Parse "Sans Bold 24" format - extract size and convert name to macOS font
  let parts = font.split(' ')
  if parts.len > 0:
    # Try to find size (last numeric part)
    for i in countdown(parts.len - 1, 0):
      try:
        result.size = parseFloat(parts[i])
        # Join the rest as font name
        if i > 0:
          result.name = parts[0..<i].join(" ")
        break
      except ValueError:
        discard

  # Convert common Linux font names to macOS equivalents
  if result.name.toLowerAscii().contains("sans"):
    result.name = "Helvetica Neue"
  elif result.name.toLowerAscii().contains("serif"):
    result.name = "Times New Roman"
  elif result.name.toLowerAscii().contains("mono"):
    result.name = "Menlo"

  # Default size if not found
  if result.size == 0.0:
    result.size = 24.0

  # Use system font if name is empty
  if result.name == "":
    result.name = ""

proc updateLabel(o: Overlay) =
  var text = ""
  for i, line in o.lines:
    if i > 0: text.add("\n")
    text.add(line)

  updateTextViewText(o.textView, text.cstring)

proc addLine*(o: Overlay, text: string) =
  if text.len == 0: return

  o.lines.addLast(text)
  while o.lines.len > o.cfg.maxLines:
    discard o.lines.popFirst()

  updateLabel(o)

  # Reset fade timer
  if o.fadeTimer != nil:
    dispatch_source_cancel(o.fadeTimer)
    o.fadeTimer = nil

  if o.cfg.fadeTimeout > 0:
    # Create dispatch timer
    let mainQueue = dispatch_get_main_queue()
    let timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, mainQueue)
    o.fadeTimer = timer

    # Set up timer callback
    proc fadeCallback(ctx: pointer) {.cdecl.} =
      if gOverlay != nil:
        gOverlay.lines.clear()
        updateLabel(gOverlay)
        if gOverlay.fadeTimer != nil:
          dispatch_source_cancel(gOverlay.fadeTimer)
          gOverlay.fadeTimer = nil

    dispatch_source_set_event_handler_f(timer, fadeCallback)

    # Set timer to fire once after fadeTimeout seconds
    proc dispatch_time(when_val: uint64, delta: int64): uint64 {.
      importc: "dispatch_time", header: "<dispatch/dispatch.h>".}
    let DISPATCH_TIME_NOW = 0'u64
    let timeoutNs = int64(o.cfg.fadeTimeout) * int64(NSEC_PER_SEC)
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, timeoutNs), 0, 0)
    dispatch_resume(timer)

proc clearLines*(o: Overlay) =
  o.lines.clear()
  updateLabel(o)

proc showOverlay*(o: Overlay) =
  if o.window != nil:
    showWindow(o.window)
    o.visible = true

proc hideOverlay*(o: Overlay) =
  if o.window != nil:
    o.lines.clear()
    updateLabel(o)
    hideWindow(o.window)
    o.visible = false

# Thread-safe text addition using dispatch queue
type
  TextUpdateObj = object
    text: array[4096, char]
    len: int

proc idleAddText*(text: string) =
  ## Thread-safe: schedule text addition on the main queue.
  let update = cast[ptr TextUpdateObj](c_malloc(csize_t(sizeof(TextUpdateObj))))
  zeroMem(update, sizeof(TextUpdateObj))
  let copyLen = min(text.len, 4095)
  if copyLen > 0:
    copyMem(addr update.text[0], unsafeAddr text[0], copyLen)
  update.text[copyLen] = '\0'
  update.len = copyLen

  proc callback(data: pointer) {.cdecl.} =
    let upd = cast[ptr TextUpdateObj](data)
    if gOverlay != nil and gOverlay.textView != nil:
      var s = newString(upd.len)
      if upd.len > 0:
        copyMem(addr s[0], addr upd.text[0], upd.len)
      gOverlay.addLine(s)
    c_free(data)

  let mainQueue = dispatch_get_main_queue()
  dispatch_async_f(mainQueue, cast[pointer](update), callback)

proc initOverlay*(cfg: OverlayConfig): Overlay =
  # Initialize NSApplication first
  initNSApp()

  result = Overlay(
    cfg: cfg,
    lines: initDeque[string](),
    visible: false,
    fadeTimer: nil,
  )
  gOverlay = result

  # Parse colors
  let textColor = parseRGBA(cfg.textColor)
  let bgColor = parseRGBA(cfg.bgColor)

  # Parse font
  let fontInfo = parseFontName(cfg.font)

  # Calculate window dimensions (approximate based on font size and margins)
  let windowWidth = 800.0
  let windowHeight = 200.0

  # Create window (position will be set later)
  result.window = createCaptionWindow(windowWidth, windowHeight, 0, 0)

  # Create text view
  result.textView = createTextView(
    windowWidth - cdouble(cfg.marginSide * 2),
    windowHeight - cdouble(cfg.marginBottom),
    fontInfo.name.cstring,
    fontInfo.size,
    textColor.r, textColor.g, textColor.b, textColor.a,
    bgColor.r, bgColor.g, bgColor.b, bgColor.a,
    cdouble(cfg.borderRadius),
    cdouble(cfg.padding)
  )

  # Add text view to window
  addTextViewToWindow(result.window, result.textView,
                     cdouble(cfg.marginSide), cdouble(cfg.marginBottom))

  # Position window at bottom-center
  setWindowPosition(result.window, cdouble(cfg.marginBottom))

  # Start hidden
  hideWindow(result.window)

proc runApp*(o: Overlay) =
  ## Run the NSApplication main loop (blocks until quit)
  runNSApp()

proc quitApp*(o: Overlay) =
  ## Stop the NSApplication main loop
  if o.fadeTimer != nil:
    dispatch_source_cancel(o.fadeTimer)
    o.fadeTimer = nil

  stopNSApp()

  # Cleanup
  if o.textView != nil:
    releaseTextView(o.textView)
    o.textView = nil

  if o.window != nil:
    releaseWindow(o.window)
    o.window = nil
