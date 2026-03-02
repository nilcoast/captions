## Linux system tray via libayatana-appindicator3 (StatusNotifierItem D-Bus protocol).
## Works with Waybar, swaybar, GNOME (via extensions), KDE Plasma.

import std/logging
import ./appindicator_bindings

type
  Tray* = ref object
    indicator: pointer   # AppIndicator*
    menu: pointer        # GtkMenu*
    statusItem: pointer  # GtkMenuItem* (status display)
    toggleItem: pointer  # GtkMenuItem* (toggle capture)
    onToggle*: proc()
    onQuit*: proc()
    onPrefs*: proc()

var gTray: Tray = nil

proc onToggleActivate(widget: pointer, data: pointer) {.cdecl.} =
  if gTray != nil and gTray.onToggle != nil:
    gTray.onToggle()

proc onPrefsActivate(widget: pointer, data: pointer) {.cdecl.} =
  if gTray != nil and gTray.onPrefs != nil:
    gTray.onPrefs()

proc onQuitActivate(widget: pointer, data: pointer) {.cdecl.} =
  if gTray != nil and gTray.onQuit != nil:
    gTray.onQuit()

proc initTray*(): Tray =
  result = Tray()
  gTray = result

  # Create AppIndicator
  result.indicator = app_indicator_new(
    "captions",
    "audio-input-microphone",  # XDG icon name
    APP_INDICATOR_CATEGORY_APPLICATION_STATUS
  )

  if result.indicator == nil:
    warn "Failed to create AppIndicator — tray icon will not be available"
    return

  app_indicator_set_status(result.indicator, APP_INDICATOR_STATUS_ACTIVE)

  # Build GTK3 menu
  let menu = gtk_menu_new()
  result.menu = menu

  # Toggle item
  let toggleItem = gtk_menu_item_new_with_label("Toggle Capture")
  result.toggleItem = toggleItem
  discard g_signal_connect_gtk3(toggleItem, "activate", onToggleActivate, nil)
  gtk_menu_shell_append(menu, toggleItem)

  # Separator
  gtk_menu_shell_append(menu, gtk_separator_menu_item_new())

  # Status item (disabled, informational)
  let statusItem = gtk_menu_item_new_with_label("Status: Idle")
  result.statusItem = statusItem
  gtk_widget_set_sensitive(statusItem, 0)
  gtk_menu_shell_append(menu, statusItem)

  # Separator
  gtk_menu_shell_append(menu, gtk_separator_menu_item_new())

  # Preferences item
  let prefsItem = gtk_menu_item_new_with_label("Preferences...")
  discard g_signal_connect_gtk3(prefsItem, "activate", onPrefsActivate, nil)
  gtk_menu_shell_append(menu, prefsItem)

  # Separator
  gtk_menu_shell_append(menu, gtk_separator_menu_item_new())

  # Quit item
  let quitItem = gtk_menu_item_new_with_label("Quit")
  discard g_signal_connect_gtk3(quitItem, "activate", onQuitActivate, nil)
  gtk_menu_shell_append(menu, quitItem)

  gtk_widget_show_all(menu)
  app_indicator_set_menu(result.indicator, menu)

  info "System tray initialized"

proc setStatus*(t: Tray, isActive: bool) =
  if t.indicator == nil: return

  if isActive:
    app_indicator_set_icon_full(t.indicator, "audio-input-microphone-high",
                                "Captions Active")
    if t.statusItem != nil:
      gtk_menu_item_set_label(t.statusItem, "Status: Active")
    if t.toggleItem != nil:
      gtk_menu_item_set_label(t.toggleItem, "Stop Capture")
  else:
    app_indicator_set_icon_full(t.indicator, "audio-input-microphone",
                                "Captions")
    if t.statusItem != nil:
      gtk_menu_item_set_label(t.statusItem, "Status: Idle")
    if t.toggleItem != nil:
      gtk_menu_item_set_label(t.toggleItem, "Toggle Capture")

proc destroy*(t: Tray) =
  # AppIndicator and GTK widgets are GObject-managed; they clean up on process exit.
  # We just nil our references.
  t.indicator = nil
  t.menu = nil
  t.statusItem = nil
  t.toggleItem = nil
  if gTray == t:
    gTray = nil
