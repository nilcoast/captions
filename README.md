# captions

Real-time audio transcription overlay for Sway. Captures audio via PipeWire, transcribes with whisper.cpp, displays as a transparent Wayland overlay.

## Dependencies

- Nim >= 2.0
- libpipewire-0.3-dev
- libgtk-4-dev
- libgtk4-layer-shell-dev
- whisper.cpp (built and installed from source)

## Build & Install

```
make install-all
```

This compiles, installs to `~/.local/bin/`, downloads the whisper model, copies config, and installs a systemd user service.

Individual steps: `make install`, `make install-model`, `make install-config`, `make install-service`.

## Usage

```
captions              # start daemon
captions toggle       # start/stop capture
captions status       # query daemon state
captions quit         # shut down daemon
```

### Sway config

```
exec systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec systemctl --user start captions
bindsym $mod+c exec captions toggle
```

## Configuration

`~/.config/captions/captions.toml` — see `config/captions.toml.example` for all options.

Key setting: `[audio] source = "sink"` for system audio, `"mic"` for microphone input.
