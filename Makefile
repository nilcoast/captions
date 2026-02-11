PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
MODEL_DIR ?= $(HOME)/.local/share/captions
MODEL_URL ?= https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
SYSTEMD_DIR ?= $(HOME)/.config/systemd/user

.PHONY: build release install install-model install-config install-service uninstall clean

build:
	nim c --threads:on --mm:orc -o:captions src/captions.nim

release:
	nim c --threads:on --mm:orc -d:release -o:captions src/captions.nim

install: release
	install -Dm755 captions $(DESTDIR)$(BINDIR)/captions
	@echo "Installed captions to $(BINDIR)/captions"
	@echo ""
	@echo "Optional next steps:"
	@echo "  make install-model    Download whisper model (~142 MiB)"
	@echo "  make install-config   Install example config"
	@echo "  make install-service  Install systemd user service"

install-model:
	@mkdir -p $(MODEL_DIR)
	@if [ -f "$(MODEL_DIR)/ggml-base.en.bin" ]; then \
		echo "Model already exists at $(MODEL_DIR)/ggml-base.en.bin"; \
	else \
		echo "Downloading ggml-base.en.bin (~142 MiB)..."; \
		curl -L -o "$(MODEL_DIR)/ggml-base.en.bin" --progress-bar "$(MODEL_URL)"; \
		echo "Model saved to $(MODEL_DIR)/ggml-base.en.bin"; \
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
	@mkdir -p $(SYSTEMD_DIR)
	sed 's|%h/.local/bin/captions|$(BINDIR)/captions|g' config/captions.service > $(SYSTEMD_DIR)/captions.service
	chmod 644 $(SYSTEMD_DIR)/captions.service
	systemctl --user daemon-reload
	@echo "Service installed. Enable with:"
	@echo "  systemctl --user enable --now captions"

install-all: install install-model install-config install-service
	@echo ""
	@echo "All done. Enable the service:"
	@echo "  systemctl --user enable --now captions"
	@echo ""
	@echo "Add to your sway config:"
	@echo "  bindsym \$$mod+c exec captions toggle"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/captions
	rm -f $(SYSTEMD_DIR)/captions.service
	-systemctl --user disable --now captions 2>/dev/null
	-systemctl --user daemon-reload 2>/dev/null
	@echo "Uninstalled. Model and config left in place."
	@echo "Remove manually if desired:"
	@echo "  rm -rf $(MODEL_DIR)"
	@echo "  rm -rf $(HOME)/.config/captions"

clean:
	rm -f captions
