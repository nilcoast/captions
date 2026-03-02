## macOS preferences window — Nim bindings.
## Wraps the Cocoa-based preferences_macos.m C API.

import std/[strutils, logging]
import ./config
import ./hardware
import ./model_download

{.compile("preferences_macos.m", "-fobjc-arc").}
{.passL: "-framework Cocoa".}

type
  PrefsCallback = proc(userData: pointer, key, value: cstring) {.cdecl.}
  PrefsDownloadCallback = proc(userData: pointer, tier: cint) {.cdecl.}

proc prefs_create(onChanged: PrefsCallback, onDownload: PrefsDownloadCallback,
                  userData: pointer): pointer {.importc.}
proc prefs_show(handle: pointer) {.importc.}
proc prefs_set_hardware(handle: pointer, gpu: cstring, vram, ram: cint,
                        tier: cstring) {.importc.}
proc prefs_set_model_status(handle: pointer, tier: cint, downloaded: cint,
                             path: cstring) {.importc.}
proc prefs_set_external(handle: pointer, enabled: cint, apiUrl, apiKey,
                         model: cstring) {.importc.}
proc prefs_set_general(handle: pointer, trayEnabled, shortcutEnabled: cint,
                        keybinding: cstring) {.importc.}
proc prefs_set_download_progress(handle: pointer, fraction: cdouble) {.importc.}
proc prefs_destroy(handle: pointer) {.importc.}

type
  PrefsWindow* = ref object
    handle: pointer
    onSave*: proc(cfg: AppConfig)

var gPrefs: PrefsWindow = nil
var gConfig: AppConfig

proc onChangedCb(userData: pointer, key, value: cstring) {.cdecl.} =
  let k = $key
  let v = $value

  case k
  of "summary.backend":
    gConfig.summary.backend = v
  of "summary.external.api_url":
    gConfig.summary.external.apiUrl = v
  of "summary.external.api_key":
    gConfig.summary.external.apiKey = v
  of "summary.external.model":
    gConfig.summary.external.model = v
  of "tray.enabled":
    gConfig.tray.enabled = v == "true"
  of "shortcut.enabled":
    gConfig.shortcut.enabled = v == "true"
  of "shortcut.keybinding":
    gConfig.shortcut.keybinding = v
  of "summary.model_tier":
    # Map tier to model path
    let tier = case v
      of "14b": mt14B
      of "32b": mt32B
      else: mt7B
    gConfig.summary.modelPath = modelPath(tier)
  of "_save":
    if gPrefs != nil and gPrefs.onSave != nil:
      gPrefs.onSave(gConfig)
  else:
    discard

proc onDownloadCb(userData: pointer, tier: cint) {.cdecl.} =
  let mt = case tier
    of 1: mt14B
    of 2: mt32B
    else: mt7B

  if isModelDownloaded(mt):
    info "Model already downloaded: " & modelPath(mt)
    return

  info "Starting download for tier: " & $mt
  if gPrefs != nil and gPrefs.handle != nil:
    prefs_set_download_progress(gPrefs.handle, 0.0)

  proc progressCb(downloaded, total: int64) =
    if total > 0 and gPrefs != nil and gPrefs.handle != nil:
      let fraction = downloaded.float / total.float
      prefs_set_download_progress(gPrefs.handle, fraction)

  spawnDownload(mt, progressCb)

var gPrefsWindow*: PrefsWindow = nil

proc initPrefsWindow*(cfg: AppConfig): PrefsWindow =
  result = PrefsWindow()
  gPrefs = result
  gPrefsWindow = result
  gConfig = cfg
  result.handle = prefs_create(onChangedCb, onDownloadCb, nil)

proc showPreferences*(pw: PrefsWindow, cfg: AppConfig) =
  if pw.handle == nil: return
  gConfig = cfg

  # Set hardware info
  let hw = detectHardware()
  let tier = recommendTier(hw)
  prefs_set_hardware(pw.handle, hw.gpu.name.cstring, hw.gpu.vramMb.cint,
                      hw.totalRamMb.cint, ($tier).cstring)

  # Set model download status
  for t in ModelTier:
    let downloaded = isModelDownloaded(t)
    let path = if downloaded: modelPath(t) else: ""
    prefs_set_model_status(pw.handle, t.ord.cint, if downloaded: 1 else: 0,
                            path.cstring)

  # Set external API config
  let extEnabled = cfg.summary.backend == "external"
  prefs_set_external(pw.handle,
    if extEnabled: 1 else: 0,
    cfg.summary.external.apiUrl.cstring,
    cfg.summary.external.apiKey.cstring,
    cfg.summary.external.model.cstring)

  # Set general config
  prefs_set_general(pw.handle,
    if cfg.tray.enabled: 1 else: 0,
    if cfg.shortcut.enabled: 1 else: 0,
    cfg.shortcut.keybinding.cstring)

  prefs_show(pw.handle)

proc destroy*(pw: PrefsWindow) =
  if pw.handle != nil:
    prefs_destroy(pw.handle)
    pw.handle = nil
  if gPrefs == pw:
    gPrefs = nil
