## Cocoa/AppKit bindings for macOS overlay implementation.

{.pragma: objc, cdecl, dynlib: "/System/Library/Frameworks/AppKit.framework/AppKit".}
{.pragma: cf, cdecl, dynlib: "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation".}

type
  Id* {.importc: "id", header: "<objc/objc.h>", final.} = distinct pointer
  SEL* {.importc: "SEL", header: "<objc/objc.h>", final.} = distinct pointer
  Class* {.importc: "Class", header: "<objc/objc.h>", final.} = distinct pointer

  CGFloat* {.importc: "CGFloat", header: "<CoreGraphics/CGBase.h>".} = cdouble

  NSRect* {.importc: "NSRect", header: "<Foundation/NSGeometry.h>", bycopy.} = object
    origin*: NSPoint
    size*: NSSize

  NSPoint* {.importc: "NSPoint", header: "<Foundation/NSGeometry.h>", bycopy.} = object
    x*: CGFloat
    y*: CGFloat

  NSSize* {.importc: "NSSize", header: "<Foundation/NSGeometry.h>", bycopy.} = object
    width*: CGFloat
    height*: CGFloat

  NSUInteger* = culong
  NSInteger* = clong

  # NSWindow style masks
  NSWindowStyleMask* = distinct NSUInteger

const
  NSWindowStyleMaskBorderless*: NSWindowStyleMask = 0.NSWindowStyleMask
  NSWindowStyleMaskTitled*: NSWindowStyleMask = (1 shl 0).NSWindowStyleMask
  NSWindowStyleMaskClosable*: NSWindowStyleMask = (1 shl 1).NSWindowStyleMask
  NSWindowStyleMaskMiniaturizable*: NSWindowStyleMask = (1 shl 2).NSWindowStyleMask
  NSWindowStyleMaskResizable*: NSWindowStyleMask = (1 shl 3).NSWindowStyleMask

# NSWindow level constants
const
  NSNormalWindowLevel*: NSInteger = 0
  NSFloatingWindowLevel*: NSInteger = 3
  NSStatusWindowLevel*: NSInteger = 25
  NSPopUpMenuWindowLevel*: NSInteger = 101

# NSWindow collection behavior
type NSWindowCollectionBehavior* = distinct NSUInteger

const
  NSWindowCollectionBehaviorDefault*: NSWindowCollectionBehavior = 0.NSWindowCollectionBehavior
  NSWindowCollectionBehaviorCanJoinAllSpaces*: NSWindowCollectionBehavior = (1 shl 0).NSWindowCollectionBehavior
  NSWindowCollectionBehaviorMoveToActiveSpace*: NSWindowCollectionBehavior = (1 shl 1).NSWindowCollectionBehavior
  NSWindowCollectionBehaviorStationary*: NSWindowCollectionBehavior = (1 shl 4).NSWindowCollectionBehavior
  NSWindowCollectionBehaviorTransient*: NSWindowCollectionBehavior = (1 shl 3).NSWindowCollectionBehavior
  NSWindowCollectionBehaviorIgnoresCycle*: NSWindowCollectionBehavior = (1 shl 6).NSWindowCollectionBehavior

# Text alignment
type NSTextAlignment* = distinct NSInteger

const
  NSTextAlignmentLeft*: NSTextAlignment = 0.NSTextAlignment
  NSTextAlignmentCenter*: NSTextAlignment = 1.NSTextAlignment
  NSTextAlignmentRight*: NSTextAlignment = 2.NSTextAlignment
  NSTextAlignmentJustified*: NSTextAlignment = 3.NSTextAlignment

# Backing store type
type NSBackingStoreType* = distinct NSUInteger

const
  NSBackingStoreRetained*: NSBackingStoreType = 0.NSBackingStoreType
  NSBackingStoreNonretained*: NSBackingStoreType = 1.NSBackingStoreType
  NSBackingStoreBuffered*: NSBackingStoreType = 2.NSBackingStoreType

# Objective-C runtime
proc objc_getClass*(name: cstring): Class {.importc, header: "<objc/objc.h>".}
proc sel_registerName*(name: cstring): SEL {.importc, header: "<objc/objc.h>".}
proc objc_msgSend*(obj: Id, sel: SEL): Id {.importc, varargs, header: "<objc/message.h>".}
proc objc_msgSend_stret*(ret: pointer, obj: Id, sel: SEL) {.importc, varargs, header: "<objc/message.h>".}

# NSApplication
proc NSApp*(): Id {.importc: "NSApp", header: "<AppKit/NSApplication.h>".}

proc NSApplicationLoad*(): bool {.
  importc: "NSApplicationLoad",
  header: "<AppKit/NSApplication.h>".}

# NSString
proc CFSTR*(str: cstring): Id {.importc: "CFSTR", header: "<CoreFoundation/CFString.h>".}

# NSColor
proc NSColor_colorWithRed_green_blue_alpha*(r, g, b, a: CGFloat): Id {.
  importc: "objc_msgSend",
  header: "<objc/message.h>".}

proc NSColor_clearColor*(): Id {.
  importc: "objc_msgSend",
  header: "<objc/message.h>".}

# NSFont
proc NSFont_systemFontOfSize*(size: CGFloat): Id {.
  importc: "objc_msgSend",
  header: "<objc/message.h>".}

proc NSFont_fontWithName_size*(name: Id, size: CGFloat): Id {.
  importc: "objc_msgSend",
  header: "<objc/message.h>".}

# Helper procs for message sending with specific signatures
proc msgSend*(obj: Id, sel: SEL): Id {.importc: "objc_msgSend", header: "<objc/message.h>".}
proc msgSend*(obj: Id, sel: SEL, arg1: Id): Id {.importc: "objc_msgSend", header: "<objc/message.h>".}
proc msgSend*(obj: Id, sel: SEL, arg1: cint): Id {.importc: "objc_msgSend", header: "<objc/message.h>".}
proc msgSend*(obj: Id, sel: SEL, arg1: bool): Id {.importc: "objc_msgSend", header: "<objc/message.h>".}
proc msgSend*(obj: Id, sel: SEL, arg1: CGFloat): Id {.importc: "objc_msgSend", header: "<objc/message.h>".}
proc msgSend*(obj: Id, sel: SEL, arg1: NSInteger): Id {.importc: "objc_msgSend", header: "<objc/message.h>".}
proc msgSend*(obj: Id, sel: SEL, arg1: NSUInteger): Id {.importc: "objc_msgSend", header: "<objc/message.h>".}
proc msgSend*(obj: Id, sel: SEL, arg1, arg2: Id): Id {.importc: "objc_msgSend", header: "<objc/message.h>".}
proc msgSend*(obj: Id, sel: SEL, arg1: Id, arg2: NSUInteger): Id {.importc: "objc_msgSend", header: "<objc/message.h>".}

proc msgSend_stret*(ret: pointer, obj: Id, sel: SEL) {.importc: "objc_msgSend_stret", header: "<objc/message.h>".}
proc msgSend_stret*(ret: pointer, obj: Id, sel: SEL, arg1: NSRect) {.importc: "objc_msgSend_stret", header: "<objc/message.h>".}

proc msgSend_fpret*(obj: Id, sel: SEL): CGFloat {.importc: "objc_msgSend_fpret", header: "<objc/message.h>".}

# Selectors
template sel*(name: string): SEL = sel_registerName(name.cstring)

# Class helpers
template cls*(name: string): Class = objc_getClass(name.cstring)

# NSAutoreleasePool
proc newAutoreleasePool*(): Id =
  let poolClass = cls("NSAutoreleasePool")
  let allocSel = sel("alloc")
  let initSel = sel("init")
  let pool = msgSend(cast[Id](poolClass), allocSel)
  msgSend(pool, initSel)

proc drain*(pool: Id) =
  discard msgSend(pool, sel("drain"))

# Dispatch queue (for thread safety)
type DispatchQueue* {.importc: "dispatch_queue_t", header: "<dispatch/dispatch.h>".} = pointer

proc dispatch_get_main_queue*(): DispatchQueue {.
  importc: "dispatch_get_main_queue",
  header: "<dispatch/dispatch.h>".}

proc dispatch_async_f*(queue: DispatchQueue, context: pointer, work: proc(ctx: pointer) {.cdecl.}) {.
  importc: "dispatch_async_f",
  header: "<dispatch/dispatch.h>".}

# Dispatch timer
type DispatchSource* {.importc: "dispatch_source_t", header: "<dispatch/dispatch.h>".} = pointer

proc dispatch_source_create*(stype: pointer, handle: culong, mask: culong, queue: DispatchQueue): DispatchSource {.
  importc: "dispatch_source_create",
  header: "<dispatch/dispatch.h>".}

proc dispatch_source_set_event_handler_f*(source: DispatchSource, handler: proc(ctx: pointer) {.cdecl.}) {.
  importc: "dispatch_source_set_event_handler_f",
  header: "<dispatch/dispatch.h>".}

proc dispatch_source_set_timer*(source: DispatchSource, start: uint64, interval: uint64, leeway: uint64) {.
  importc: "dispatch_source_set_timer",
  header: "<dispatch/dispatch.h>".}

proc dispatch_resume*(obj: pointer) {.
  importc: "dispatch_resume",
  header: "<dispatch/dispatch.h>".}

proc dispatch_suspend*(obj: pointer) {.
  importc: "dispatch_suspend",
  header: "<dispatch/dispatch.h>".}

proc dispatch_source_cancel*(source: DispatchSource) {.
  importc: "dispatch_source_cancel",
  header: "<dispatch/dispatch.h>".}

{.emit: """
static const void* _nim_dispatch_timer_ptr4 = DISPATCH_SOURCE_TYPE_TIMER;
""".}
var DISPATCH_SOURCE_TYPE_TIMER* {.importc: "_nim_dispatch_timer_ptr4", nodecl.}: pointer

proc DISPATCH_TIME_NOW*(): uint64 {.importc: "DISPATCH_TIME_NOW", header: "<dispatch/dispatch.h>".}

# NSRunLoop
proc NSRunLoop_currentRunLoop*(): Id {.
  importc: "objc_msgSend",
  header: "<objc/message.h>".}

proc NSRunLoop_run*(runLoop: Id) {.
  importc: "objc_msgSend",
  header: "<objc/message.h>".}

# Constants for selector names
const
  SelAlloc* = "alloc"
  SelInit* = "init"
  SelInitWithContentRect* = "initWithContentRect:styleMask:backing:defer:"
  SelSetTitle* = "setTitle:"
  SelSetBackgroundColor* = "setBackgroundColor:"
  SelSetOpaque* = "setOpaque:"
  SelSetLevel* = "setLevel:"
  SelSetCollectionBehavior* = "setCollectionBehavior:"
  SelSetIgnoresMouseEvents* = "setIgnoresMouseEvents:"
  SelSetFrame* = "setFrame:display:"
  SelMakeKeyAndOrderFront* = "makeKeyAndOrderFront:"
  SelOrderOut* = "orderOut:"
  SelContentView* = "contentView"
  SelAddSubview* = "addSubview:"
  SelSetWantsLayer* = "setWantsLayer:"
  SelLayer* = "layer"
  SelSetCornerRadius* = "setCornerRadius:"
  SelSetString* = "setString:"
  SelSetFont* = "setFont:"
  SelSetTextColor* = "setTextColor:"
  SelSetAlignment* = "setAlignment:"
  SelSetEditable* = "setEditable:"
  SelSetSelectable* = "setSelectable:"
  SelSetDrawsBackground* = "setDrawsBackground:"
  SelFrame* = "frame"
  SelSetFrame* = "setFrame:"
  SelStringWithUTF8String* = "stringWithUTF8String:"
  SelRun* = "run"
  SelSharedApplication* = "sharedApplication"
  SelActivateIgnoringOtherApps* = "activateIgnoringOtherApps:"
  SelScreen* = "screen"
  SelMainScreen* = "mainScreen"
  SelVisibleFrame* = "visibleFrame"
