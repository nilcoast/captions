## Low-level importc bindings for CoreAudio Taps helper (coreaudio_helper.m).
## These are the raw C function imports.

{.compile("coreaudio_helper.m", "-fobjc-arc").}
{.passl: "-framework Foundation -framework AVFAudio -framework ScreenCaptureKit -framework CoreMedia".}

type
  CaCapturePtr* = pointer

  CaSamplesCallback* = proc(data: ptr cfloat, count: cint, userdata: pointer) {.cdecl.}

proc ca_capture_new*(): CaCapturePtr {.importc, cdecl.}
proc ca_capture_free*(cap: CaCapturePtr) {.importc, cdecl.}
proc ca_capture_start*(cap: CaCapturePtr, sample_rate: cint, channels: cint,
                       callback: CaSamplesCallback, userdata: pointer): cint {.importc, cdecl.}
proc ca_capture_stop*(cap: CaCapturePtr) {.importc, cdecl.}
