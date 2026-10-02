# OpenGolf Tycoon Makefile
#
# Godot is resolved by scripts/resolve-godot.sh (bundled zip, $GODOT, PATH, or
# download). Override with: make test GODOT=/path/to/godot

GODOT ?= $(shell ./scripts/resolve-godot.sh)

.PHONY: test run editor help

help:
	@echo "OpenGolf Tycoon - Available commands:"
	@echo "  make test    - Run unit tests (extracts Godot and imports on first run)"
	@echo "  make run     - Run the game"
	@echo "  make editor  - Open in Godot editor"
	@echo ""
	@echo "Override Godot path: make test GODOT=/path/to/godot"

test:
	@./test.sh

run:
	@if [ -z "$(GODOT)" ]; then \
		echo "Error: Godot not found. Set GODOT variable."; \
		exit 1; \
	fi
	@$(GODOT) --path .

editor:
	@if [ -z "$(GODOT)" ]; then \
		echo "Error: Godot not found. Set GODOT variable."; \
		exit 1; \
	fi
	@$(GODOT) --editor --path .
