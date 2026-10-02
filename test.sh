#!/usr/bin/env bash
# Run GUT unit tests for OpenGolf Tycoon.
# Resolves Godot (bundled zip, PATH, or download), imports the project on first
# run, then executes the unit suite. Safe to re-run; subsequent calls skip the
# extract/import work.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

GODOT_BIN="$("$ROOT/scripts/resolve-godot.sh")"
echo "Using Godot: $GODOT_BIN"

# First-run (and after a clean checkout): import resources so GUT can load scripts.
if [ ! -f "$ROOT/.godot/global_script_class_cache.cfg" ]; then
    echo "Importing project (first run)..."
    "$GODOT_BIN" --headless --path "$ROOT" --import --quit >/dev/null
fi

exec "$GODOT_BIN" --headless --path "$ROOT" \
    -s addons/gut/gut_cmdln.gd \
    -gconfig=res://gutconfig.json \
    -gexit \
    "$@"
