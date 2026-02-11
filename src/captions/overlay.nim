## GTK4 + layer-shell transparent overlay for displaying captions.

import std/[deques, strformat]
import ./gtk4_bindings
import ./layershell_bindings
import ./config

type
  Overlay* = ref object
    app: pointer      # GtkApplication*
    window: pointer   # GtkWindow*
    label: pointer    # GtkLabel*
    box: pointer      # GtkBox*
    lines: Deque[string]
    cfg: OverlayConfig
    visible*: bool
    fadeSourceId: cuint

var gOverlay*: Overlay = nil

proc updateLabel(o: Overlay) =
  var text = ""
  for i, line in o.lines:
    if i > 0: text.add("\n")
    text.add(line)
  gtk_label_set_text(o.label, text.cstring)

proc addLine*(o: Overlay, text: string) =
  if text.len == 0: return
  o.lines.addLast(text)
  while o.lines.len > o.cfg.maxLines:
    discard o.lines.popFirst()
  updateLabel(o)
  # Reset fade timer
  if o.fadeSourceId != 0:
    discard g_source_remove(o.fadeSourceId)
    o.fadeSourceId = 0
  if o.cfg.fadeTimeout > 0:
    proc fadeCallback(data: pointer): cint {.cdecl.} =
      if gOverlay != nil:
        gOverlay.lines.clear()
        updateLabel(gOverlay)
        gOverlay.fadeSourceId = 0
      return 0  # one-shot (G_SOURCE_REMOVE)
    o.fadeSourceId = g_timeout_add(cuint(o.cfg.fadeTimeout * 1000), fadeCallback, nil)

proc showOverlay*(o: Overlay) =
  if o.window != nil:
    gtk_widget_show(o.window)
    o.visible = true

proc hideOverlay*(o: Overlay) =
  if o.window != nil:
    o.lines.clear()
    updateLabel(o)
    gtk_widget_hide(o.window)
    o.visible = false

# --- Idle callback for thread-safe text updates ---

type
  TextUpdateObj = object
    text: array[4096, char]
    len: int

proc c_malloc(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}
proc c_free(p: pointer) {.importc: "free", header: "<stdlib.h>".}

proc idleAddText*(text: string) =
  ## Thread-safe: schedule text addition on the GTK main loop.
  ## Uses C malloc/free to avoid Nim allocator issues during GTK shutdown.
  let update = cast[ptr TextUpdateObj](c_malloc(csize_t(sizeof(TextUpdateObj))))
  zeroMem(update, sizeof(TextUpdateObj))
  let copyLen = min(text.len, 4095)
  if copyLen > 0:
    copyMem(addr update.text[0], unsafeAddr text[0], copyLen)
  update.text[copyLen] = '\0'
  update.len = copyLen

  proc callback(data: pointer): cint {.cdecl.} =
    let upd = cast[ptr TextUpdateObj](data)
    if gOverlay != nil and gOverlay.label != nil:
      var s = newString(upd.len)
      if upd.len > 0:
        copyMem(addr s[0], addr upd.text[0], upd.len)
      gOverlay.addLine(s)
    c_free(data)
    return 0  # one-shot

  discard g_idle_add(callback, cast[pointer](update))

# --- CSS styling ---

proc loadCss(o: Overlay) =
  let css = &"""
    window {{
      background-color: transparent;
    }}
    .caption-box {{
      background-color: {o.cfg.bgColor};
      border-radius: {o.cfg.borderRadius}px;
      padding: {o.cfg.padding}px {o.cfg.padding * 2}px;
      margin-bottom: {o.cfg.marginBottom}px;
    }}
    .caption-label {{
      color: {o.cfg.textColor};
      font: {o.cfg.font};
    }}
  """
  let provider = gtk_css_provider_new()
  gtk_css_provider_load_from_string(provider, css.cstring)
  let display = gdk_display_get_default()
  gtk_style_context_add_provider_for_display(display, provider, STYLE_PROVIDER_PRIORITY_APPLICATION)

# --- Application activation ---

proc onActivate(app: pointer, data: pointer) {.cdecl.} =
  let o = gOverlay
  if o == nil: return
  o.app = app

  let win = gtk_application_window_new(app)
  o.window = win
  gtk_window_set_title(win, "captions")
  gtk_window_set_default_size(win, 0, 0)
  gtk_window_set_decorated(win, 0)

  # Initialize layer shell
  gtk_layer_init_for_window(win)
  gtk_layer_set_layer(win, GTK_LAYER_SHELL_LAYER_OVERLAY)
  gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_BOTTOM, 1)
  gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_LEFT, 1)
  gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_RIGHT, 1)
  gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_BOTTOM, o.cfg.marginBottom.cint)
  gtk_layer_set_exclusive_zone(win, 0)
  gtk_layer_set_namespace(win, "captions")
  gtk_layer_set_keyboard_mode(win, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE)

  # Load CSS
  loadCss(o)

  # Build widget tree
  let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)
  gtk_widget_add_css_class(box, "caption-box")
  gtk_widget_set_halign(box, GTK_ALIGN_CENTER)
  gtk_widget_set_valign(box, GTK_ALIGN_END)

  let label = gtk_label_new("")
  gtk_widget_add_css_class(label, "caption-label")
  gtk_label_set_wrap(label, 1)
  gtk_label_set_justify(label, GTK_JUSTIFY_CENTER)
  gtk_widget_set_hexpand(label, 1)

  gtk_box_append(box, label)
  gtk_window_set_child(win, box)

  o.box = box
  o.label = label

  # Start hidden — only show when capture is toggled on
  gtk_widget_hide(win)
  o.visible = false

proc initOverlay*(cfg: OverlayConfig): Overlay =
  result = Overlay(
    cfg: cfg,
    lines: initDeque[string](),
    visible: false,
    fadeSourceId: 0,
  )
  gOverlay = result

proc runApp*(o: Overlay) =
  let app = gtk_application_new("com.nilcoast.captions", G_APPLICATION_DEFAULT_FLAGS)
  o.app = app
  discard g_signal_connect(app, "activate", onActivate, nil)
  discard g_application_run(app, 0, nil)

proc quitApp*(o: Overlay) =
  if o != nil and o.app != nil:
    g_application_quit(o.app)
