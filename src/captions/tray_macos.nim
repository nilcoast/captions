## macOS system tray (NSStatusBar) — Nim bindings.
## Creates a menu bar status item with toggle/quit/preferences actions.

{.compile("tray_macos.m", "-fobjc-arc").}
{.passL: "-framework Cocoa".}

type
  TrayCallback = proc(userData: pointer) {.cdecl.}

proc tray_create(toggleCb, quitCb, prefsCb: TrayCallback,
                 userData: pointer): pointer {.importc.}
proc tray_set_status(handle: pointer, isActive: cint) {.importc.}
proc tray_destroy(handle: pointer) {.importc.}

type
  Tray* = ref object
    handle: pointer
    onToggle*: proc()
    onQuit*: proc()
    onPrefs*: proc()

var gTray: Tray = nil

proc toggleCb(userData: pointer) {.cdecl.} =
  if gTray != nil and gTray.onToggle != nil:
    gTray.onToggle()

proc quitCb(userData: pointer) {.cdecl.} =
  if gTray != nil and gTray.onQuit != nil:
    gTray.onQuit()

proc prefsCb(userData: pointer) {.cdecl.} =
  if gTray != nil and gTray.onPrefs != nil:
    gTray.onPrefs()

proc initTray*(): Tray =
  result = Tray()
  gTray = result
  result.handle = tray_create(toggleCb, quitCb, prefsCb, nil)

proc setStatus*(t: Tray, isActive: bool) =
  if t.handle != nil:
    tray_set_status(t.handle, if isActive: 1 else: 0)

proc destroy*(t: Tray) =
  if t.handle != nil:
    tray_destroy(t.handle)
    t.handle = nil
  if gTray == t:
    gTray = nil
