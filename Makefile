# Platform detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Platform-specific paths
ifeq ($(UNAME_S),Darwin)
  # macOS: Use standard /usr/local prefix and Application Support directory
  PREFIX ?= /usr/local
  MODEL_DIR ?= $(HOME)/Library/Application Support/captions
else
  # Linux/other: Use ~/.local for user-local installation
  PREFIX ?= $(HOME)/.local
  MODEL_DIR ?= $(HOME)/.local/share/captions
  SYSTEMD_DIR ?= $(HOME)/.config/systemd/user
endif

BINDIR ?= $(PREFIX)/bin
WHISPER_MODEL_URL ?= https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
SUMMARY_MODEL_URL ?= https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf

.PHONY: build release install install-model install-summary-model install-config install-service uninstall clean

build:
	nim c --threads:on --mm:orc -o:captions src/captions.nim

release:
	nim c --threads:on --mm:orc -d:release -o:captions src/captions.nim

install: release
	install -Dm755 captions $(DESTDIR)$(BINDIR)/captions
	@echo "Installed captions to $(BINDIR)/captions"
	@echo ""
	@echo "Optional next steps:"
	@echo "  make install-model           Download whisper model (~142 MiB)"
	@echo "  make install-summary-model   Download summary model (~4.4 GiB)"
	@echo "  make install-config          Install example config"
ifeq ($(UNAME_S),Darwin)
	@echo ""
	@echo "Note: systemd service not available on macOS."
	@echo "Consider using launchd for background daemon."
else
	@echo "  make install-service         Install systemd user service"
endif

install-model:
	@mkdir -p $(MODEL_DIR)
	@if [ -f "$(MODEL_DIR)/ggml-base.en.bin" ]; then \
		echo "Model already exists at $(MODEL_DIR)/ggml-base.en.bin"; \
	else \
		echo "Downloading ggml-base.en.bin (~142 MiB)..."; \
		curl -L -o "$(MODEL_DIR)/ggml-base.en.bin" --progress-bar "$(WHISPER_MODEL_URL)"; \
		echo "Model saved to $(MODEL_DIR)/ggml-base.en.bin"; \
	fi

install-summary-model:
	@mkdir -p "$(MODEL_DIR)"
	@if [ -f "$(MODEL_DIR)/qwen2.5-7b-instruct-q4_k_m.gguf" ]; then \
		echo "Summary model already exists at $(MODEL_DIR)/qwen2.5-7b-instruct-q4_k_m.gguf"; \
	else \
		echo "Downloading qwen2.5-7b-instruct-q4_k_m.gguf (~4.4 GiB)..."; \
		echo "This model provides better factual accuracy and less hallucination than Phi-3.1"; \
		curl -L -o "$(MODEL_DIR)/qwen2.5-7b-instruct-q4_k_m.gguf" --progress-bar "$(SUMMARY_MODEL_URL)"; \
		echo "Summary model saved to $(MODEL_DIR)/qwen2.5-7b-instruct-q4_k_m.gguf"; \
	fi

install-config:
	@mkdir -p $(HOME)/.config/captions
	@if [ -f "$(HOME)/.config/captions/captions.toml" ]; then \
		echo "Config already exists, not overwriting"; \
	else \
		cp config/captions.toml.example $(HOME)/.config/captions/captions.toml; \
		echo "Config installed to ~/.config/captions/captions.toml"; \
	fi

install-service:
ifeq ($(UNAME_S),Darwin)
	@echo "Skipping systemd service installation on macOS"
	@echo "Consider using launchd for background daemon instead."
	@echo "Example plist at: config/com.captions.daemon.plist (if available)"
else
	@mkdir -p $(SYSTEMD_DIR)
	sed 's|%h/.local/bin/captions|$(BINDIR)/captions|g' config/captions.service > $(SYSTEMD_DIR)/captions.service
	chmod 644 $(SYSTEMD_DIR)/captions.service
	systemctl --user daemon-reload
	@echo "Service installed. Enable with:"
	@echo "  systemctl --user enable --now captions"
endif

install-all: install install-model install-summary-model install-config install-service
	@echo ""
ifeq ($(UNAME_S),Darwin)
	@echo "All done! Binary and models installed."
	@echo "Start the daemon manually with:"
	@echo "  captions daemon"
	@echo ""
	@echo "Use 'captions toggle' to show/hide captions."
else
	@echo "All done. Enable the service:"
	@echo "  systemctl --user enable --now captions"
	@echo ""
	@echo "Add to your sway config:"
	@echo "  bindsym \$$mod+c exec captions toggle"
endif

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/captions
	rm -f $(SYSTEMD_DIR)/captions.service
	-systemctl --user disable --now captions 2>/dev/null
	-systemctl --user daemon-reload 2>/dev/null
	@echo "Uninstalled. Models and config left in place."
	@echo "Remove manually if desired:"
	@echo "  rm -rf $(MODEL_DIR)"
	@echo "  rm -rf $(HOME)/.config/captions"

clean:
	rm -f captions
