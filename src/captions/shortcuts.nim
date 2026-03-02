## Platform-switch module for global keyboard shortcuts.

when defined(macosx):
  import ./shortcuts_macos
  export shortcuts_macos
else:
  import ./shortcuts_linux
  export shortcuts_linux
