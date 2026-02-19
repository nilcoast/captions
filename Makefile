PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
MODEL_DIR ?= $(HOME)/.local/share/captions
WHISPER_MODEL_URL ?= https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
SUMMARY_MODEL_URL ?= https://huggingface.co/bartowski/Phi-3.1-mini-128k-instruct-GGUF/resolve/main/Phi-3.1-mini-128k-instruct-Q4_K_M.gguf
SYSTEMD_DIR ?= $(HOME)/.config/systemd/user

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
	@echo "  make install-summary-model   Download summary model (~950 MiB)"
	@echo "  make install-config          Install example config"
	@echo "  make install-service         Install systemd user service"

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
	@mkdir -p $(MODEL_DIR)
	@if [ -f "$(MODEL_DIR)/phi-3.1-mini-128k-instruct-q4_k_m.gguf" ]; then \
		echo "Summary model already exists at $(MODEL_DIR)/phi-3.1-mini-128k-instruct-q4_k_m.gguf"; \
	else \
		echo "Downloading phi-3.1-mini-128k-instruct-q4_k_m.gguf (~2.3 GiB)..."; \
		curl -L -o "$(MODEL_DIR)/phi-3.1-mini-128k-instruct-q4_k_m.gguf" --progress-bar "$(SUMMARY_MODEL_URL)"; \
		echo "Summary model saved to $(MODEL_DIR)/phi-3.1-mini-128k-instruct-q4_k_m.gguf"; \
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

install-all: install install-model install-summary-model install-config install-service
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
	@echo "Uninstalled. Models and config left in place."
	@echo "Remove manually if desired:"
	@echo "  rm -rf $(MODEL_DIR)"
	@echo "  rm -rf $(HOME)/.config/captions"

clean:
	rm -f captions
