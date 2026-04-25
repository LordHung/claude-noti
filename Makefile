# Claude Code notifier — install Makefile.
#
# Common usage:
#   make setup        # build + install everything (no tmux click navigation)
#   make setup-tmux   # same as `setup`, plus tmux click-back-to-pane wiring
#   make uninstall    # remove the .app, hook scripts, and our hook entries
#
# Prerequisites: Xcode command line tools, jq (`brew install jq`).
# Tmux support also assumes you launch Claude Code from inside a tmux pane.

PREFIX        ?= $(HOME)/.claude/hooks
APP_NAME      = Claude Notifier.app
SCHEME        = Terminal Notifier
PROJECT       = Terminal Notifier.xcodeproj
BUILD_DIR     = $(CURDIR)/build/Release
LSREGISTER    = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

HOOK_SCRIPTS  = notify.sh build-title.sh notification.sh stop.sh
TMUX_SCRIPTS  = click-action.sh

.DEFAULT_GOAL := help
.PHONY: help setup setup-tmux build install-app install-hooks install-tmux-hooks settings settings-tmux uninstall clean check-deps

help:
	@echo "Claude Code notifier — Makefile targets"
	@echo ""
	@echo "  make setup        Build + install (no tmux click navigation)"
	@echo "  make setup-tmux   Build + install + tmux click-back-to-pane wiring"
	@echo "  make uninstall    Remove the .app, hook scripts, and hook entries"
	@echo "  make build        Build Claude Notifier.app only"
	@echo "  make clean        Remove build artifacts"
	@echo ""
	@echo "Install prefix: $(PREFIX)"

# ----------------------------------------------------------------------
# Top-level convenience targets
# ----------------------------------------------------------------------

setup: check-deps build install-app install-hooks settings
	@echo ""
	@echo "[done] Claude Code notifications are wired up."
	@echo "       Try /rename my-task in Claude Code, then exit a turn."
	@echo "       If notifications are silent, grant 'Claude Code'"
	@echo "       notification permission in System Settings."

setup-tmux: check-deps build install-app install-hooks install-tmux-hooks settings-tmux
	@echo ""
	@echo "[done] Claude Code notifications + tmux click navigation are wired up."
	@echo "       Notifications fired from inside tmux will jump back to the"
	@echo "       originating pane on click."

# ----------------------------------------------------------------------
# Building
# ----------------------------------------------------------------------

build:
	@echo "[build] Claude Notifier.app -> $(BUILD_DIR)"
	@mkdir -p "$(BUILD_DIR)"
	xcodebuild \
	  -project "$(PROJECT)" \
	  -scheme "$(SCHEME)" \
	  -configuration Release \
	  MACOSX_DEPLOYMENT_TARGET=10.13 \
	  CONFIGURATION_BUILD_DIR="$(BUILD_DIR)" \
	  build | grep -E '(error:|warning:|BUILD)' || true
	@test -d "$(BUILD_DIR)/$(APP_NAME)" || (echo "[error] build did not produce $(APP_NAME)"; exit 1)

# ----------------------------------------------------------------------
# Installing
# ----------------------------------------------------------------------

install-app:
	@echo "[install] $(APP_NAME) -> $(PREFIX)"
	@mkdir -p "$(PREFIX)"
	@rm -rf "$(PREFIX)/$(APP_NAME)"
	cp -R "$(BUILD_DIR)/$(APP_NAME)" "$(PREFIX)/$(APP_NAME)"
	@echo "[lsregister] registering bundle with LaunchServices"
	@"$(LSREGISTER)" -f "$(PREFIX)/$(APP_NAME)" || true

install-hooks:
	@echo "[install] hook scripts -> $(PREFIX)"
	@mkdir -p "$(PREFIX)"
	@for f in $(HOOK_SCRIPTS); do \
	  install -m 755 hooks/$$f "$(PREFIX)/$$f"; \
	  echo "  $$f"; \
	done
	@if [ -f hooks/claude-icon.png ]; then \
	  install -m 644 hooks/claude-icon.png "$(PREFIX)/claude-icon.png"; \
	  echo "  claude-icon.png"; \
	fi

install-tmux-hooks:
	@echo "[install] tmux hook scripts -> $(PREFIX)"
	@for f in $(TMUX_SCRIPTS); do \
	  install -m 755 hooks/$$f "$(PREFIX)/$$f"; \
	  echo "  $$f"; \
	done

settings:
	@bash scripts/install-hooks-settings.sh

settings-tmux:
	@bash scripts/install-hooks-settings.sh --with-tmux

# ----------------------------------------------------------------------
# Uninstall
# ----------------------------------------------------------------------

uninstall:
	@echo "[uninstall] removing $(PREFIX)/$(APP_NAME)"
	@rm -rf "$(PREFIX)/$(APP_NAME)"
	@for f in $(HOOK_SCRIPTS) $(TMUX_SCRIPTS) claude-icon.png; do \
	  if [ -e "$(PREFIX)/$$f" ]; then \
	    echo "  rm $$f"; \
	    rm -f "$(PREFIX)/$$f"; \
	  fi; \
	done
	@echo "[note] not editing settings.json automatically — remove the"
	@echo "       Notification + Stop hook entries by hand if you want them gone."

# ----------------------------------------------------------------------
# Misc
# ----------------------------------------------------------------------

clean:
	@echo "[clean] removing build/"
	@rm -rf build

check-deps:
	@command -v xcodebuild >/dev/null 2>&1 || \
	  (echo "[error] xcodebuild not found — install Xcode command line tools (xcode-select --install)"; exit 1)
	@command -v jq >/dev/null 2>&1 || \
	  (echo "[error] jq not found — brew install jq"; exit 1)
	@echo "[ok] xcodebuild + jq present"
