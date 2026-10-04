#!/usr/bin/env bash
# Fail if any project GDScript still carries a warning.
#
# Godot prints GDScript warnings only while a debugger is attached, which is
# why a headless test run never sees them and they only surface in the editor's
# debugger long after the code was written. This script gives that sweep a home
# in CI: it registers tools/warning_scan.gd as an autoload for one run (putting
# project.godot back afterwards), starts the game with -d, and fails if Godot
# printed anything out of GDScript::reload — a warning or a parse error.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

GODOT_BIN="$("$ROOT/scripts/resolve-godot.sh")"
echo "Using Godot: $GODOT_BIN"

# Scripts need the imported project (the class cache) to resolve each other.
if [ ! -f "$ROOT/.godot/global_script_class_cache.cfg" ]; then
    echo "Importing project (first run)..."
    "$GODOT_BIN" --headless --path "$ROOT" --import --quit >/dev/null
fi

PROJECT_FILE="$ROOT/project.godot"
PROJECT_BACKUP="$(mktemp)"
cp "$PROJECT_FILE" "$PROJECT_BACKUP"
restore_project_file() {
    cp "$PROJECT_BACKUP" "$PROJECT_FILE"
    rm -f "$PROJECT_BACKUP"
}
trap restore_project_file EXIT

# The sweep node has to be in the tree before the main scene loads, so it is
# autoloaded for this run only. `awk` keeps the edit portable to macOS, where
# `sed -i` needs an argument and would leave a stray backup file.
awk '
    /^EventFeedManager="/ { print; print "WarningScan=\"*res://tools/warning_scan.gd\""; next }
    { print }
' "$PROJECT_BACKUP" > "$PROJECT_FILE"

OUTPUT="$("$GODOT_BIN" --headless -d --path "$ROOT" -- --warning-sweep 2>&1 || true)"

# A sweep that never ran would pass silently, so check it reported in.
if ! printf '%s\n' "$OUTPUT" | grep -q "WARNING_SWEEP_DONE"; then
    echo "The warning sweep did not run — is the autoload edit still valid for" >&2
    echo "this project.godot? Full output follows." >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
fi

if printf '%s\n' "$OUTPUT" | grep -q "at: GDScript::reload"; then
    echo
    echo "GDScript warnings found:"
    printf '%s\n' "$OUTPUT" | grep -B 1 "at: GDScript::reload" | grep -v "^--$"
    echo
    echo "Fix the code above, or annotate the line with @warning_ignore(\"code\")"
    echo "when the construct is intentional."
    exit 1
fi

printf '%s\n' "$OUTPUT" | grep "WARNING_SWEEP_DONE"
echo "No GDScript warnings."
