# Dancing Mouse — Build System
# ============================
#
# Targets:
#   make build     — Compile (release)
#   make app       — Build + assemble .app bundle
#   make dmg       — Build .app + create distributable DMG
#   make icon      — Generate app icon (AppIcon.icns)
#   make run       — Build .app and launch it
#   make debug     — Build debug .app and launch it
#   make install   — Copy .app to /Applications
#   make uninstall — Remove from /Applications
#   make clean     — Remove all build artifacts
#
# Variables:
#   CODESIGN_IDENTITY  — Code signing identity (default: ad-hoc "-")
#                        Set to your Developer ID for distribution:
#                        make app CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)"

.PHONY: build app dmg icon run debug install uninstall clean help

SHELL := /bin/bash
PROJECT_DIR := $(shell pwd)
APP_NAME := Dancing Mouse
BUNDLE := build/$(APP_NAME).app

export CODESIGN_IDENTITY ?= -

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Compile release binary
	swift build -c release

app: ## Build .app bundle (release)
	@chmod +x Scripts/build-app.sh
	Scripts/build-app.sh release

debug: ## Build debug .app and launch it
	@chmod +x Scripts/build-app.sh
	Scripts/build-app.sh debug
	open "$(BUNDLE)"

dmg: app ## Build .app + create DMG for distribution
	@chmod +x Scripts/create-dmg.sh
	Scripts/create-dmg.sh

icon: ## Generate AppIcon.icns
	@mkdir -p build
	swift Scripts/generate-icon.swift build

run: app ## Build .app and launch it
	open "$(BUNDLE)"

install: app ## Install .app to /Applications
	@echo "==> Installing to /Applications..."
	cp -R "$(BUNDLE)" "/Applications/$(APP_NAME).app"
	@echo "✅  Installed to /Applications/$(APP_NAME).app"

uninstall: ## Remove from /Applications
	@echo "==> Removing from /Applications..."
	rm -rf "/Applications/$(APP_NAME).app"
	@echo "✅  Removed."

clean: ## Remove all build artifacts
	swift package clean
	rm -rf build/
	rm -rf .build/

