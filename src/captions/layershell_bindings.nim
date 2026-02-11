## Hand-written gtk4-layer-shell bindings.
## Uses `pointer` for GtkWindow* to match our gtk4_bindings approach.

{.passl: gorge("pkg-config --libs gtk4-layer-shell-0").}
{.passc: gorge("pkg-config --cflags gtk4-layer-shell-0").}

type
  GtkLayerShellLayer* {.size: sizeof(cint).} = enum
    GTK_LAYER_SHELL_LAYER_BACKGROUND = 0
    GTK_LAYER_SHELL_LAYER_BOTTOM = 1
    GTK_LAYER_SHELL_LAYER_TOP = 2
    GTK_LAYER_SHELL_LAYER_OVERLAY = 3

  GtkLayerShellEdge* {.size: sizeof(cint).} = enum
    GTK_LAYER_SHELL_EDGE_TOP = 0
    GTK_LAYER_SHELL_EDGE_BOTTOM = 1
    GTK_LAYER_SHELL_EDGE_LEFT = 2
    GTK_LAYER_SHELL_EDGE_RIGHT = 3

proc gtk_layer_init_for_window*(window: pointer) {.importc, cdecl, dynlib: "libgtk4-layer-shell.so".}
proc gtk_layer_set_layer*(window: pointer, layer: GtkLayerShellLayer) {.importc, cdecl, dynlib: "libgtk4-layer-shell.so".}
proc gtk_layer_set_anchor*(window: pointer, edge: GtkLayerShellEdge, anchor: cint) {.importc, cdecl, dynlib: "libgtk4-layer-shell.so".}
proc gtk_layer_set_margin*(window: pointer, edge: GtkLayerShellEdge, margin: cint) {.importc, cdecl, dynlib: "libgtk4-layer-shell.so".}
proc gtk_layer_set_exclusive_zone*(window: pointer, zone: cint) {.importc, cdecl, dynlib: "libgtk4-layer-shell.so".}
proc gtk_layer_set_namespace*(window: pointer, ns: cstring) {.importc, cdecl, dynlib: "libgtk4-layer-shell.so".}
proc gtk_layer_set_keyboard_mode*(window: pointer, mode: cint) {.importc, cdecl, dynlib: "libgtk4-layer-shell.so".}

const
  GTK_LAYER_SHELL_KEYBOARD_MODE_NONE* = 0.cint
  GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE* = 1.cint
  GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND* = 2.cint
