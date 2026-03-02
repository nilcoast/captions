## Linux preferences window using GTK4.
## Tabbed window with Model, External API, and General settings.

import std/[strutils, strformat, logging]
import ./config
import ./hardware
import ./model_download
import ./gtk4_bindings

# Additional GTK4 bindings not in gtk4_bindings.nim
proc gtk_window_new(): pointer {.importc, header: "<gtk/gtk.h>".}
proc gtk_window_present(window: pointer) {.importc, header: "<gtk/gtk.h>".}
proc gtk_window_close(window: pointer) {.importc, header: "<gtk/gtk.h>".}
proc gtk_window_destroy(window: pointer) {.importc, header: "<gtk/gtk.h>".}

proc gtk_stack_new(): pointer {.importc, header: "<gtk/gtk.h>".}
proc gtk_stack_add_titled(stack, child: pointer, name, title: cstring): pointer {.importc, header: "<gtk/gtk.h>".}
proc gtk_stack_switcher_new(): pointer {.importc, header: "<gtk/gtk.h>".}
proc gtk_stack_switcher_set_stack(switcher, stack: pointer) {.importc, header: "<gtk/gtk.h>".}

proc gtk_entry_new(): pointer {.importc, header: "<gtk/gtk.h>".}
proc gtk_entry_set_placeholder_text(entry: pointer, text: cstring) {.importc, header: "<gtk/gtk.h>".}
proc gtk_editable_set_text(editable: pointer, text: cstring) {.importc, header: "<gtk/gtk.h>".}
proc gtk_editable_get_text(editable: pointer): cstring {.importc, header: "<gtk/gtk.h>".}
proc gtk_entry_set_visibility(entry: pointer, visible: cint) {.importc, header: "<gtk/gtk.h>".}

proc gtk_check_button_new_with_label(label: cstring): pointer {.importc, header: "<gtk/gtk.h>".}
proc gtk_check_button_set_active(button: pointer, setting: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_check_button_get_active(button: pointer): cint {.importc, header: "<gtk/gtk.h>".}
proc gtk_check_button_set_group(button, group: pointer) {.importc, header: "<gtk/gtk.h>".}

proc gtk_button_new_with_label(label: cstring): pointer {.importc, header: "<gtk/gtk.h>".}

proc gtk_progress_bar_new(): pointer {.importc, header: "<gtk/gtk.h>".}
proc gtk_progress_bar_set_fraction(bar: pointer, fraction: cdouble) {.importc, header: "<gtk/gtk.h>".}

proc gtk_box_set_spacing(box: pointer, spacing: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_set_margin_start(widget: pointer, margin: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_set_margin_end(widget: pointer, margin: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_set_margin_top(widget: pointer, margin: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_set_margin_bottom(widget: pointer, margin: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_set_visible(widget: pointer, visible: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_set_sensitive_prefs(widget: pointer, sensitive: cint) {.importc: "gtk_widget_set_sensitive", header: "<gtk/gtk.h>".}

type
  PrefsWindow* = ref object
    window: pointer
    # Model tab
    hwLabel: pointer
    recLabel: pointer
    radio7B: pointer
    radio14B: pointer
    radio32B: pointer
    downloadBtn: pointer
    progressBar: pointer
    status7B: pointer
    status14B: pointer
    status32B: pointer
    # External tab
    extToggle: pointer
    apiUrlEntry: pointer
    apiKeyEntry: pointer
    modelEntry: pointer
    # General tab
    trayToggle: pointer
    shortcutToggle: pointer
    shortcutEntry: pointer
    # State
    onSave*: proc(cfg: AppConfig)

var gPrefs: PrefsWindow = nil
var gConfig: AppConfig

proc setMargins(widget: pointer, m: cint) =
  gtk_widget_set_margin_start(widget, m)
  gtk_widget_set_margin_end(widget, m)
  gtk_widget_set_margin_top(widget, m)
  gtk_widget_set_margin_bottom(widget, m)

proc buildModelTab(pw: PrefsWindow): pointer =
  let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8)
  setMargins(box, 16)

  # Hardware info
  pw.hwLabel = gtk_label_new("Detecting hardware...")
  gtk_widget_set_halign(pw.hwLabel, 1)  # GTK_ALIGN_START
  gtk_box_append(box, pw.hwLabel)

  pw.recLabel = gtk_label_new("")
  gtk_widget_set_halign(pw.recLabel, 1)
  gtk_box_append(box, pw.recLabel)

  # Radio buttons
  pw.radio7B = gtk_check_button_new_with_label("7B — Qwen2.5 7B (Q4_K_M, ~4.4 GB)")
  gtk_box_append(box, pw.radio7B)
  pw.status7B = gtk_label_new("")
  gtk_widget_set_halign(pw.status7B, 1)
  gtk_widget_set_margin_start(pw.status7B, 24)
  gtk_box_append(box, pw.status7B)

  pw.radio14B = gtk_check_button_new_with_label("14B — Qwen2.5 14B (Q4_K_M, ~8.3 GB)")
  gtk_check_button_set_group(pw.radio14B, pw.radio7B)
  gtk_box_append(box, pw.radio14B)
  pw.status14B = gtk_label_new("")
  gtk_widget_set_halign(pw.status14B, 1)
  gtk_widget_set_margin_start(pw.status14B, 24)
  gtk_box_append(box, pw.status14B)

  pw.radio32B = gtk_check_button_new_with_label("32B — Qwen2.5 32B (Q4_K_M, ~18.9 GB)")
  gtk_check_button_set_group(pw.radio32B, pw.radio7B)
  gtk_box_append(box, pw.radio32B)
  pw.status32B = gtk_label_new("")
  gtk_widget_set_halign(pw.status32B, 1)
  gtk_widget_set_margin_start(pw.status32B, 24)
  gtk_box_append(box, pw.status32B)

  # Download button + progress
  let dlBox = gtk_box_new(0, 8)  # horizontal
  pw.downloadBtn = gtk_button_new_with_label("Download Model")
  gtk_box_append(dlBox, pw.downloadBtn)

  pw.progressBar = gtk_progress_bar_new()
  gtk_widget_set_hexpand(pw.progressBar, 1)
  gtk_widget_set_visible(pw.progressBar, 0)
  gtk_box_append(dlBox, pw.progressBar)
  gtk_box_append(box, dlBox)

  # Connect download button
  proc onDownloadClicked(button, data: pointer) {.cdecl.} =
    if gPrefs == nil: return
    var tier = mt7B
    if gtk_check_button_get_active(gPrefs.radio14B) != 0: tier = mt14B
    elif gtk_check_button_get_active(gPrefs.radio32B) != 0: tier = mt32B

    if isModelDownloaded(tier):
      info "Model already downloaded"
      return

    gtk_widget_set_visible(gPrefs.progressBar, 1)
    gtk_progress_bar_set_fraction(gPrefs.progressBar, 0.0)

    proc progressCb(downloaded, total: int64) =
      if total > 0 and gPrefs != nil and gPrefs.progressBar != nil:
        let frac = downloaded.float / total.float
        gtk_progress_bar_set_fraction(gPrefs.progressBar, frac)

    spawnDownload(tier, progressCb)

  discard g_signal_connect(pw.downloadBtn, "clicked", onDownloadClicked, nil)

  result = box

proc buildExternalTab(pw: PrefsWindow): pointer =
  let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8)
  setMargins(box, 16)

  pw.extToggle = gtk_check_button_new_with_label("Use external API instead of local model")
  gtk_box_append(box, pw.extToggle)

  # API URL
  let urlLabel = gtk_label_new("API URL:")
  gtk_widget_set_halign(urlLabel, 1)
  gtk_box_append(box, urlLabel)
  pw.apiUrlEntry = gtk_entry_new()
  gtk_entry_set_placeholder_text(pw.apiUrlEntry, "https://api.openai.com/v1")
  gtk_box_append(box, pw.apiUrlEntry)

  # API Key
  let keyLabel = gtk_label_new("API Key:")
  gtk_widget_set_halign(keyLabel, 1)
  gtk_box_append(box, keyLabel)
  pw.apiKeyEntry = gtk_entry_new()
  gtk_entry_set_visibility(pw.apiKeyEntry, 0)
  gtk_entry_set_placeholder_text(pw.apiKeyEntry, "sk-...")
  gtk_box_append(box, pw.apiKeyEntry)

  # Model name
  let modelLabel = gtk_label_new("Model:")
  gtk_widget_set_halign(modelLabel, 1)
  gtk_box_append(box, modelLabel)
  pw.modelEntry = gtk_entry_new()
  gtk_entry_set_placeholder_text(pw.modelEntry, "gpt-4o-mini")
  gtk_box_append(box, pw.modelEntry)

  result = box

proc buildGeneralTab(pw: PrefsWindow): pointer =
  let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8)
  setMargins(box, 16)

  pw.trayToggle = gtk_check_button_new_with_label("Show system tray icon")
  gtk_box_append(box, pw.trayToggle)

  pw.shortcutToggle = gtk_check_button_new_with_label("Global keyboard shortcut")
  gtk_box_append(box, pw.shortcutToggle)

  let scBox = gtk_box_new(0, 8)
  let scLabel = gtk_label_new("Shortcut:")
  gtk_box_append(scBox, scLabel)
  pw.shortcutEntry = gtk_entry_new()
  gtk_box_append(scBox, pw.shortcutEntry)
  gtk_box_append(box, scBox)

  # Save button
  let saveBtn = gtk_button_new_with_label("Save")
  gtk_widget_set_halign(saveBtn, 2)  # GTK_ALIGN_END

  proc onSaveClicked(button, data: pointer) {.cdecl.} =
    if gPrefs == nil: return

    # Read external API settings
    if gtk_check_button_get_active(gPrefs.extToggle) != 0:
      gConfig.summary.backend = "external"
    else:
      gConfig.summary.backend = "local"
    gConfig.summary.external.apiUrl = $gtk_editable_get_text(gPrefs.apiUrlEntry)
    gConfig.summary.external.apiKey = $gtk_editable_get_text(gPrefs.apiKeyEntry)
    gConfig.summary.external.model = $gtk_editable_get_text(gPrefs.modelEntry)

    # Read general settings
    gConfig.tray.enabled = gtk_check_button_get_active(gPrefs.trayToggle) != 0
    gConfig.shortcut.enabled = gtk_check_button_get_active(gPrefs.shortcutToggle) != 0
    gConfig.shortcut.keybinding = $gtk_editable_get_text(gPrefs.shortcutEntry)

    # Read selected model tier
    if gtk_check_button_get_active(gPrefs.radio14B) != 0:
      gConfig.summary.modelPath = modelPath(mt14B)
    elif gtk_check_button_get_active(gPrefs.radio32B) != 0:
      gConfig.summary.modelPath = modelPath(mt32B)
    else:
      gConfig.summary.modelPath = modelPath(mt7B)

    if gPrefs.onSave != nil:
      gPrefs.onSave(gConfig)

    gtk_window_close(gPrefs.window)

  discard g_signal_connect(saveBtn, "clicked", onSaveClicked, nil)
  gtk_box_append(box, saveBtn)

  result = box

var gPrefsWindow*: PrefsWindow = nil

proc initPrefsWindow*(cfg: AppConfig): PrefsWindow =
  result = PrefsWindow()
  gPrefs = result
  gPrefsWindow = result
  gConfig = cfg

  let win = gtk_window_new()
  result.window = win
  gtk_window_set_title(win, "Captions Preferences")
  gtk_window_set_default_size(win, 520, 480)

  # Build layout: stack switcher on top, stack below
  let mainBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)

  let stack = gtk_stack_new()
  let switcher = gtk_stack_switcher_new()
  gtk_stack_switcher_set_stack(switcher, stack)
  gtk_widget_set_halign(switcher, GTK_ALIGN_CENTER)
  gtk_widget_set_margin_top(switcher, 8)
  gtk_widget_set_margin_bottom(switcher, 8)

  gtk_box_append(mainBox, switcher)
  gtk_box_append(mainBox, stack)

  # Build tabs
  discard gtk_stack_add_titled(stack, buildModelTab(result), "model", "Model")
  discard gtk_stack_add_titled(stack, buildExternalTab(result), "external", "External API")
  discard gtk_stack_add_titled(stack, buildGeneralTab(result), "general", "General")

  gtk_window_set_child(win, mainBox)

proc showPreferences*(pw: PrefsWindow, cfg: AppConfig) =
  if pw.window == nil: return
  gConfig = cfg

  # Update hardware info
  let hw = detectHardware()
  let tier = recommendTier(hw)
  let hwText = &"GPU: {hw.gpu.name}  |  VRAM: {hw.gpu.vramMb} MB  |  RAM: {hw.totalRamMb} MB"
  gtk_label_set_text(pw.hwLabel, hwText.cstring)
  gtk_label_set_text(pw.recLabel, (&"Recommended tier: {tier}").cstring)

  # Pre-select recommended tier
  case tier
  of mt32B: gtk_check_button_set_active(pw.radio32B, 1)
  of mt14B: gtk_check_button_set_active(pw.radio14B, 1)
  of mt7B: gtk_check_button_set_active(pw.radio7B, 1)

  # Set model download status
  for t in ModelTier:
    let downloaded = isModelDownloaded(t)
    let status = if downloaded: "Downloaded" else: "Not downloaded"
    let label = case t
      of mt7B: pw.status7B
      of mt14B: pw.status14B
      of mt32B: pw.status32B
    gtk_label_set_text(label, status.cstring)

  # Set external API config
  let extEnabled = cfg.summary.backend == "external"
  gtk_check_button_set_active(pw.extToggle, if extEnabled: 1 else: 0)
  gtk_editable_set_text(pw.apiUrlEntry, cfg.summary.external.apiUrl.cstring)
  gtk_editable_set_text(pw.apiKeyEntry, cfg.summary.external.apiKey.cstring)
  gtk_editable_set_text(pw.modelEntry, cfg.summary.external.model.cstring)

  # Set general config
  gtk_check_button_set_active(pw.trayToggle, if cfg.tray.enabled: 1 else: 0)
  gtk_check_button_set_active(pw.shortcutToggle, if cfg.shortcut.enabled: 1 else: 0)
  gtk_editable_set_text(pw.shortcutEntry, cfg.shortcut.keybinding.cstring)

  gtk_window_present(pw.window)

proc destroy*(pw: PrefsWindow) =
  if pw.window != nil:
    gtk_window_destroy(pw.window)
    pw.window = nil
  if gPrefs == pw:
    gPrefs = nil
