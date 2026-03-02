## Linux global keyboard shortcut via XDG GlobalShortcuts portal (D-Bus).
## Supported on Sway 1.9+, GNOME 44+, KDE Plasma 5.27+.

import std/logging
import ./config
import ./gtk4_bindings

# C-compatible types so Nim generates correct C pointer types for GLib
type
  GVariantPtr {.importc: "GVariant", header: "<glib.h>".} = object
  GVariant = ptr GVariantPtr
  GErrorObj {.importc: "GError", header: "<glib.h>".} = object
    domain: uint32
    code: cint
    message: cstring
  GError = ptr GErrorObj
  GVariantTypePtr {.importc: "GVariantType", header: "<glib.h>".} = object

proc g_variant_new_string(str: cstring): GVariant
  {.importc, header: "<glib.h>".}

proc g_dbus_proxy_new_for_bus_sync(bus_type: cint, flags: cint,
                                    info: pointer, name: cstring,
                                    object_path: cstring,
                                    interface_name: cstring,
                                    cancellable: pointer,
                                    error: ptr GError): pointer
  {.importc, header: "<gio/gio.h>".}

proc g_dbus_proxy_call_sync(proxy: pointer, method_name: cstring,
                             parameters: GVariant, flags: cint,
                             timeout_msec: cint, cancellable: pointer,
                             error: ptr GError): GVariant
  {.importc, header: "<gio/gio.h>".}

proc g_dbus_proxy_get_connection(proxy: pointer): pointer
  {.importc, header: "<gio/gio.h>".}

proc g_dbus_connection_signal_subscribe(connection: pointer,
                                         sender: cstring,
                                         interface_name: cstring,
                                         member: cstring,
                                         object_path: cstring,
                                         arg0: cstring,
                                         flags: cint,
                                         callback: pointer,
                                         user_data: pointer,
                                         user_data_free_func: pointer): cuint
  {.importc, header: "<gio/gio.h>".}

proc g_variant_new_tuple(children: ptr GVariant, n_children: csize_t): GVariant
  {.importc, header: "<glib.h>".}

proc g_variant_new_array(child_type: ptr GVariantTypePtr, children: ptr GVariant,
                          n_children: csize_t): GVariant
  {.importc, header: "<glib.h>".}

proc g_variant_new_dict_entry(key, value: GVariant): GVariant
  {.importc, header: "<glib.h>".}

proc g_variant_new_variant(value: GVariant): GVariant
  {.importc, header: "<glib.h>".}

proc g_variant_type_new(type_string: cstring): ptr GVariantTypePtr
  {.importc, header: "<glib.h>".}

proc g_error_free(error: GError)
  {.importc, header: "<glib.h>".}

proc g_object_unref(obj: pointer)
  {.importc, header: "<glib.h>".}

const
  G_BUS_TYPE_SESSION = 2.cint
  G_DBUS_PROXY_FLAGS_NONE = 0.cint
  G_DBUS_CALL_FLAGS_NONE = 0.cint
  G_DBUS_SIGNAL_FLAGS_NONE = 0.cint

type
  Shortcut* = ref object
    proxy: pointer
    onActivated*: proc()

var gShortcut: Shortcut = nil

proc onShortcutActivated(connection: pointer, senderName: cstring,
                          objectPath: cstring, interfaceName: cstring,
                          signalName: cstring, parameters: GVariant,
                          userData: pointer) {.cdecl.} =
  if gShortcut != nil and gShortcut.onActivated != nil:
    gShortcut.onActivated()

proc initShortcut*(cfg: ShortcutConfig): Shortcut =
  result = Shortcut()
  gShortcut = result

  var err: GError = nil

  # Connect to the GlobalShortcuts portal
  let proxy = g_dbus_proxy_new_for_bus_sync(
    G_BUS_TYPE_SESSION,
    G_DBUS_PROXY_FLAGS_NONE,
    nil,
    "org.freedesktop.portal.Desktop",
    "/org/freedesktop/portal/desktop",
    "org.freedesktop.portal.GlobalShortcuts",
    nil,
    addr err
  )

  if proxy == nil or err != nil:
    if err != nil:
      warn "GlobalShortcuts portal not available: " & $err.message
      g_error_free(err)
    else:
      warn "GlobalShortcuts portal not available"
    warn "Configure your compositor manually (e.g., bindsym $mod+c exec captions toggle)"
    return

  result.proxy = proxy

  # CreateSession — establish a portal session
  var sessionOpts: array[1, GVariant]
  sessionOpts[0] = g_variant_new_dict_entry(
    g_variant_new_string("session_handle_token"),
    g_variant_new_variant(g_variant_new_string("captions"))
  )

  let sessionDict = g_variant_new_array(
    g_variant_type_new("{sv}"),
    addr sessionOpts[0], 1
  )

  var sessionParams: array[1, GVariant]
  sessionParams[0] = sessionDict
  let sessionTuple = g_variant_new_tuple(addr sessionParams[0], 1)

  discard g_dbus_proxy_call_sync(
    proxy, "CreateSession", sessionTuple,
    G_DBUS_CALL_FLAGS_NONE, 5000, nil, addr err
  )

  if err != nil:
    warn "Failed to create GlobalShortcuts session: " & $err.message
    g_error_free(err)
    warn "Configure your compositor manually (e.g., bindsym $mod+c exec captions toggle)"
    return

  # BindShortcuts — register our shortcut
  let bindingVariant = g_variant_new_string(cfg.keybinding.cstring)

  var shortcutProps: array[1, GVariant]
  shortcutProps[0] = g_variant_new_dict_entry(
    g_variant_new_string("preferred-trigger"),
    g_variant_new_variant(bindingVariant)
  )

  let propsDict = g_variant_new_array(
    g_variant_type_new("{sv}"),
    addr shortcutProps[0], 1
  )

  var shortcutTupleArr: array[2, GVariant]
  shortcutTupleArr[0] = g_variant_new_string("captions-toggle")
  shortcutTupleArr[1] = propsDict

  let shortcutEntry = g_variant_new_tuple(addr shortcutTupleArr[0], 2)

  var shortcutsArray: array[1, GVariant]
  shortcutsArray[0] = shortcutEntry
  let shortcuts = g_variant_new_array(
    g_variant_type_new("(sa{sv})"),
    addr shortcutsArray[0], 1
  )

  let emptyOpts = g_variant_new_array(
    g_variant_type_new("{sv}"), nil, 0
  )

  var bindParams: array[4, GVariant]
  bindParams[0] = g_variant_new_string("")
  bindParams[1] = shortcuts
  bindParams[2] = g_variant_new_string("")
  bindParams[3] = emptyOpts

  let bindTuple = g_variant_new_tuple(addr bindParams[0], 4)

  discard g_dbus_proxy_call_sync(
    proxy, "BindShortcuts", bindTuple,
    G_DBUS_CALL_FLAGS_NONE, 5000, nil, addr err
  )

  if err != nil:
    warn "Failed to bind shortcut: " & $err.message
    g_error_free(err)
    warn "Configure your compositor manually (e.g., bindsym $mod+c exec captions toggle)"
    return

  # Subscribe to the Activated signal
  let connection = g_dbus_proxy_get_connection(proxy)
  if connection != nil:
    discard g_dbus_connection_signal_subscribe(
      connection,
      "org.freedesktop.portal.Desktop",
      "org.freedesktop.portal.GlobalShortcuts",
      "Activated",
      "/org/freedesktop/portal/desktop",
      nil,
      G_DBUS_SIGNAL_FLAGS_NONE,
      cast[pointer](onShortcutActivated),
      nil, nil
    )

  info "Global shortcut registered via XDG portal: " & cfg.keybinding

proc destroy*(s: Shortcut) =
  if s.proxy != nil:
    g_object_unref(s.proxy)
    s.proxy = nil
  if gShortcut == s:
    gShortcut = nil
