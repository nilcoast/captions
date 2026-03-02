## Platform-switch module for system tray.

when defined(macosx):
  import ./tray_macos
  export tray_macos
else:
  import ./tray_linux
  export tray_linux
