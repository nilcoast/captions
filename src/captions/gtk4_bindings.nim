## Hand-written GTK4 / GLib / GDK4 C bindings.
## Only the subset needed for the overlay window.
##
## We use `pointer` for all GTK/GLib object types to avoid C type hierarchy
## mismatch errors (GtkApplication vs GApplication, GtkWindow vs GtkWidget, etc).

{.passl: gorge("pkg-config --libs gtk4").}
{.passc: gorge("pkg-config --cflags gtk4").}

type
  GSourceFunc* = proc(userData: pointer): cint {.cdecl.}

# --- Enums / Constants ---

const
  GTK_ORIENTATION_VERTICAL* = 1.cint
  GTK_ALIGN_END* = 2.cint
  GTK_ALIGN_CENTER* = 3.cint
  GTK_JUSTIFY_CENTER* = 2.cint
  G_APPLICATION_DEFAULT_FLAGS* = 0.cint
  STYLE_PROVIDER_PRIORITY_APPLICATION* = 600.cuint

# --- GLib functions ---

proc g_idle_add*(function: GSourceFunc, data: pointer): cuint {.importc, header: "<glib.h>".}
proc g_timeout_add*(interval: cuint, function: GSourceFunc, data: pointer): cuint {.importc, header: "<glib.h>".}
proc g_source_remove*(tag: cuint): cint {.importc, header: "<glib.h>".}

proc g_signal_connect_data*(
  instance: pointer,
  detailed_signal: cstring,
  c_handler: pointer,
  data: pointer,
  destroy_data: pointer,
  connect_flags: cint
): culong {.importc, header: "<gobject/gsignal.h>".}

template g_signal_connect*(instance, signal, handler, data: untyped): untyped =
  g_signal_connect_data(cast[pointer](instance), signal, cast[pointer](handler), cast[pointer](data), nil, 0)

# --- GTK Application ---
# All return/accept `pointer` to avoid GObject inheritance type issues.

proc gtk_application_new*(application_id: cstring, flags: cint): pointer {.importc, header: "<gtk/gtk.h>".}
proc g_application_run*(app: pointer, argc: cint, argv: pointer): cint {.importc, header: "<gio/gio.h>".}
proc g_application_quit*(app: pointer) {.importc, header: "<gio/gio.h>".}

proc gtk_application_window_new*(app: pointer): pointer {.importc, header: "<gtk/gtk.h>".}

# --- GtkWindow ---

proc gtk_window_set_title*(window: pointer, title: cstring) {.importc, header: "<gtk/gtk.h>".}
proc gtk_window_set_default_size*(window: pointer, width, height: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_window_set_decorated*(window: pointer, setting: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_window_set_child*(window: pointer, child: pointer) {.importc, header: "<gtk/gtk.h>".}

# --- GtkWidget ---

proc gtk_widget_show*(widget: pointer) {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_hide*(widget: pointer) {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_set_halign*(widget: pointer, align: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_set_valign*(widget: pointer, align: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_set_hexpand*(widget: pointer, expand: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_widget_add_css_class*(widget: pointer, css_class: cstring) {.importc, header: "<gtk/gtk.h>".}

# --- GtkBox ---

proc gtk_box_new*(orientation: cint, spacing: cint): pointer {.importc, header: "<gtk/gtk.h>".}
proc gtk_box_append*(box: pointer, child: pointer) {.importc, header: "<gtk/gtk.h>".}

# --- GtkLabel ---

proc gtk_label_new*(str: cstring): pointer {.importc, header: "<gtk/gtk.h>".}
proc gtk_label_set_markup*(label: pointer, str: cstring) {.importc, header: "<gtk/gtk.h>".}
proc gtk_label_set_wrap*(label: pointer, wrap: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_label_set_justify*(label: pointer, jtype: cint) {.importc, header: "<gtk/gtk.h>".}
proc gtk_label_set_text*(label: pointer, str: cstring) {.importc, header: "<gtk/gtk.h>".}

# --- CSS ---

proc gtk_css_provider_new*(): pointer {.importc, header: "<gtk/gtk.h>".}
proc gtk_css_provider_load_from_string*(provider: pointer, css: cstring) {.importc, header: "<gtk/gtk.h>".}
proc gdk_display_get_default*(): pointer {.importc, header: "<gdk/gdk.h>".}
proc gtk_style_context_add_provider_for_display*(
  display: pointer,
  provider: pointer,
  priority: cuint
) {.importc, header: "<gtk/gtk.h>".}
