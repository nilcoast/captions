## Platform-switch module for preferences window.

when defined(macosx):
  import ./preferences_macos
  export preferences_macos
else:
  import ./preferences_linux
  export preferences_linux
