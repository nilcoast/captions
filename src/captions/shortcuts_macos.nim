## macOS global keyboard shortcut via CGEventTap.
## Requires Accessibility permission (System Settings > Privacy > Accessibility).

import std/[strutils, logging]
import ./config

{.passL: "-framework ApplicationServices -framework CoreGraphics".}

type
  CGEventType = uint32
  CGEventRef = pointer
  CGEventTapLocation = uint32
  CGEventTapPlacement = uint32
  CGEventTapOptions = uint32
  CGEventMask = uint64
  CGEventFlags = uint64
  CFMachPortRef = pointer
  CFRunLoopSourceRef = pointer
  CFRunLoopRef = pointer

const
  kCGEventKeyDown = 10'u32
  kCGHIDEventTap = 0'u32
  kCGHeadInsertEventTap = 0'u32
  kCGEventTapOptionDefault = 0'u32

  # Modifier flags
  kCGEventFlagMaskShift = 0x00020000'u64
  kCGEventFlagMaskControl = 0x00040000'u64
  kCGEventFlagMaskAlternate = 0x00080000'u64
  kCGEventFlagMaskCommand = 0x00100000'u64

  # Key codes
  kVK_C = 8'i64  # 'C' key

type
  CGEventTapCallBack = proc(proxy: pointer, eventType: CGEventType,
                             event: CGEventRef, userInfo: pointer): CGEventRef {.cdecl.}

proc CGEventTapCreate(tap: CGEventTapLocation, place: CGEventTapPlacement,
                       options: CGEventTapOptions, eventsOfInterest: CGEventMask,
                       callback: CGEventTapCallBack, userInfo: pointer): CFMachPortRef
  {.importc, header: "<CoreGraphics/CoreGraphics.h>".}

proc CFMachPortCreateRunLoopSource(allocator: pointer, port: CFMachPortRef,
                                    order: clong): CFRunLoopSourceRef
  {.importc, header: "<CoreFoundation/CoreFoundation.h>".}

proc CFRunLoopGetMain(): CFRunLoopRef
  {.importc, header: "<CoreFoundation/CoreFoundation.h>".}

proc CFRunLoopAddSource(rl: CFRunLoopRef, source: CFRunLoopSourceRef,
                         mode: pointer)
  {.importc, header: "<CoreFoundation/CoreFoundation.h>".}

proc CGEventGetFlags(event: CGEventRef): CGEventFlags
  {.importc, header: "<CoreGraphics/CoreGraphics.h>".}

proc CGEventGetIntegerValueField(event: CGEventRef, field: uint32): int64
  {.importc, header: "<CoreGraphics/CoreGraphics.h>".}

proc AXIsProcessTrusted(): bool
  {.importc, header: "<ApplicationServices/ApplicationServices.h>".}

# Common RunLoop mode constant
var kCFRunLoopCommonModes {.importc, header: "<CoreFoundation/CoreFoundation.h>".}: pointer

const kCGKeyboardEventKeycode = 9'u32  # CGEventField for keycode

type
  Shortcut* = ref object
    tapPort: CFMachPortRef
    onActivated*: proc()
    requiredFlags: CGEventFlags
    keyCode: int64

  ParsedBinding = object
    flags: CGEventFlags
    keyCode: int64

var gShortcut: Shortcut = nil

proc parseKeybinding(binding: string): ParsedBinding =
  ## Parse "Cmd+Shift+C" into modifier flags + key code.
  var flags: CGEventFlags = 0
  var keyChar = ""

  for part in binding.split("+"):
    let p = part.strip().toLowerAscii()
    case p
    of "cmd", "command", "meta", "super":
      flags = flags or kCGEventFlagMaskCommand
    of "shift":
      flags = flags or kCGEventFlagMaskShift
    of "ctrl", "control":
      flags = flags or kCGEventFlagMaskControl
    of "alt", "option":
      flags = flags or kCGEventFlagMaskAlternate
    else:
      keyChar = p

  # Map character to keycode (common keys)
  var keyCode: int64 = -1
  if keyChar.len == 1:
    case keyChar[0]
    of 'c': keyCode = kVK_C
    of 'a': keyCode = 0
    of 's': keyCode = 1
    of 'd': keyCode = 2
    of 'f': keyCode = 3
    of 'h': keyCode = 4
    of 'g': keyCode = 5
    of 'z': keyCode = 6
    of 'x': keyCode = 7
    of 'v': keyCode = 9
    of 'b': keyCode = 11
    of 'q': keyCode = 12
    of 'w': keyCode = 13
    of 'e': keyCode = 14
    of 'r': keyCode = 15
    of 't': keyCode = 17
    of 'y': keyCode = 16
    of 'u': keyCode = 32
    of 'i': keyCode = 34
    of 'o': keyCode = 31
    of 'p': keyCode = 35
    of 'l': keyCode = 37
    of 'j': keyCode = 38
    of 'k': keyCode = 40
    of 'n': keyCode = 45
    of 'm': keyCode = 46
    else: discard

  result = ParsedBinding(flags: flags, keyCode: keyCode)

proc eventTapCallback(proxy: pointer, eventType: CGEventType,
                       event: CGEventRef, userInfo: pointer): CGEventRef {.cdecl.} =
  if eventType != kCGEventKeyDown:
    return event

  let flags = CGEventGetFlags(event)
  let keyCode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode)

  if gShortcut != nil and gShortcut.keyCode >= 0:
    # Check modifier mask (ignore caps lock and other non-modifier bits)
    let modifierMask = kCGEventFlagMaskCommand or kCGEventFlagMaskShift or
                       kCGEventFlagMaskControl or kCGEventFlagMaskAlternate
    let activeModifiers = flags and modifierMask
    if activeModifiers == gShortcut.requiredFlags and keyCode == gShortcut.keyCode:
      if gShortcut.onActivated != nil:
        gShortcut.onActivated()
      return nil  # consume the event

  return event

proc initShortcut*(cfg: ShortcutConfig): Shortcut =
  result = Shortcut()
  gShortcut = result

  let parsed = parseKeybinding(cfg.keybinding)
  result.requiredFlags = parsed.flags
  result.keyCode = parsed.keyCode

  if parsed.keyCode < 0:
    warn "Could not parse keybinding: " & cfg.keybinding
    return

  # Check accessibility permission
  if not AXIsProcessTrusted():
    warn "Accessibility permission not granted. " &
         "Enable in System Settings > Privacy & Security > Accessibility " &
         "to use global keyboard shortcuts."
    # Continue anyway — the event tap will just fail silently

  # Create event tap for keyDown events
  let eventMask = 1'u64 shl kCGEventKeyDown
  let tap = CGEventTapCreate(
    kCGHIDEventTap, kCGHeadInsertEventTap,
    kCGEventTapOptionDefault, eventMask,
    eventTapCallback, nil
  )

  if tap == nil:
    warn "Failed to create CGEventTap — accessibility permission may be required"
    return

  result.tapPort = tap

  # Add to main run loop
  let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
  if source != nil:
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes)
    info "Global shortcut registered: " & cfg.keybinding

proc destroy*(s: Shortcut) =
  # Event tap is cleaned up when the process exits.
  # CGEventTapEnable could be used to disable, but not critical.
  s.tapPort = nil
  if gShortcut == s:
    gShortcut = nil
