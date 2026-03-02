## Bindings for libayatana-appindicator3 (StatusNotifierItem / D-Bus tray protocol).
## Used by Waybar, swaybar, GNOME (via extensions), KDE Plasma.

{.passl: gorge("pkg-config --libs ayatana-appindicator3-0.1 2>/dev/null || echo -layatana-appindicator3").}
{.passc: gorge("pkg-config --cflags ayatana-appindicator3-0.1 2>/dev/null || echo -I/usr/include/libayatana-appindicator3-0.1").}

# Also need GTK3 for menu construction (appindicator uses GTK3 menus internally)
{.passl: gorge("pkg-config --libs gtk+-3.0 2>/dev/null || echo -lgtk-3").}
{.passc: gorge("pkg-config --cflags gtk+-3.0 2>/dev/null || echo -I/usr/include/gtk-3.0").}

const
  APP_INDICATOR_CATEGORY_APPLICATION_STATUS* = 0.cint
  APP_INDICATOR_STATUS_PASSIVE* = 0.cint
  APP_INDICATOR_STATUS_ACTIVE* = 1.cint
  APP_INDICATOR_STATUS_ATTENTION* = 2.cint

# AppIndicator
proc app_indicator_new*(id, icon_name: cstring, category: cint): pointer
  {.importc, cdecl.}
proc app_indicator_set_status*(self: pointer, status: cint)
  {.importc, cdecl.}
proc app_indicator_set_menu*(self: pointer, menu: pointer)
  {.importc, cdecl.}
proc app_indicator_set_icon_full*(self: pointer, icon_name, desc: cstring)
  {.importc, cdecl.}

# GTK3 menu construction (minimal subset)
proc gtk_menu_new*(): pointer
  {.importc, cdecl.}
proc gtk_menu_item_new_with_label*(label: cstring): pointer
  {.importc, cdecl.}
proc gtk_separator_menu_item_new*(): pointer
  {.importc, cdecl.}
proc gtk_menu_shell_append*(menu_shell, child: pointer)
  {.importc, cdecl.}
proc gtk_widget_show_all*(widget: pointer)
  {.importc, cdecl.}
proc gtk_widget_set_sensitive*(widget: pointer, sensitive: cint)
  {.importc, cdecl.}
proc gtk_menu_item_set_label*(menu_item: pointer, label: cstring)
  {.importc, cdecl.}

# GObject signal connection (GTK3 version — same ABI as GTK4 but separate linkage)
proc g_signal_connect_data_gtk3(instance: pointer, detailed_signal: cstring,
                                 c_handler: pointer, data: pointer,
                                 destroy_data: pointer, connect_flags: cint): culong
  {.importc: "g_signal_connect_data", cdecl.}

template g_signal_connect_gtk3*(instance, signal, handler, data: untyped): untyped =
  g_signal_connect_data_gtk3(cast[pointer](instance), signal,
                              cast[pointer](handler), cast[pointer](data), nil, 0)
