#!/usr/bin/env bash
# Print the path to a Godot 4.6+ executable, extracting or downloading one if needed.
# Intended to be sourced by test.sh / Makefile so `make test` works on a clean checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_VERSION="${GODOT_VERSION:-4.6}"
GODOT_STATUS="${GODOT_STATUS:-stable}"
BUNDLED_NAME="Godot_v${GODOT_VERSION}-${GODOT_STATUS}_linux.x86_64"
BUNDLED_BIN="${ROOT}/${BUNDLED_NAME}"
BUNDLED_ZIP="${ROOT}/${BUNDLED_NAME}.zip"
DOWNLOAD_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_STATUS}/${BUNDLED_NAME}.zip"

is_godot() {
    local candidate="$1"
    if [ -x "$candidate" ] && [ -f "$candidate" ]; then
        return 0
    fi
    return 1
}

pick_godot() {
    if [ -n "${GODOT:-}" ] && is_godot "$GODOT"; then
        echo "$GODOT"
        return 0
    fi

    local candidate
    for candidate in \
        "$BUNDLED_BIN" \
        "${ROOT}/godot" \
        "/Applications/Godot.app/Contents/MacOS/Godot" \
        "${HOME}/Downloads/Godot.app/Contents/MacOS/Godot"
    do
        if is_godot "$candidate"; then
            echo "$candidate"
            return 0
        fi
    done

    if command -v godot >/dev/null 2>&1; then
        command -v godot
        return 0
    fi

    return 1
}

extract_bundled_zip() {
    local zip_path="$1"
    if [ ! -f "$zip_path" ]; then
        return 1
    fi
    echo "Extracting Godot from $(basename "$zip_path")..." >&2
    unzip -o -q "$zip_path" -d "$ROOT"
    if is_godot "$BUNDLED_BIN"; then
        chmod +x "$BUNDLED_BIN"
        echo "$BUNDLED_BIN"
        return 0
    fi
    # Zip may contain a differently named binary; take the first executable.
    local extracted
    extracted="$(find "$ROOT" -maxdepth 1 -type f -name 'Godot_v*' -perm -u+x | head -n 1 || true)"
    if [ -n "$extracted" ] && is_godot "$extracted"; then
        echo "$extracted"
        return 0
    fi
    return 1
}

download_godot() {
    local tmp_zip
    tmp_zip="$(mktemp "${ROOT}/godot-download.XXXXXX.zip")"
    echo "Downloading Godot ${GODOT_VERSION}-${GODOT_STATUS}..." >&2
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$DOWNLOAD_URL" -o "$tmp_zip"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$DOWNLOAD_URL" -O "$tmp_zip"
    else
        rm -f "$tmp_zip"
        echo "Error: need curl or wget to download Godot." >&2
        return 1
    fi
    local result=""
    if result="$(extract_bundled_zip "$tmp_zip")"; then
        rm -f "$tmp_zip"
        echo "$result"
        return 0
    fi
    rm -f "$tmp_zip"
    return 1
}

GODOT_BIN=""
if GODOT_BIN="$(pick_godot)"; then
    echo "$GODOT_BIN"
    exit 0
fi

if GODOT_BIN="$(extract_bundled_zip "$BUNDLED_ZIP")"; then
    echo "$GODOT_BIN"
    exit 0
fi

if GODOT_BIN="$(download_godot)"; then
    echo "$GODOT_BIN"
    exit 0
fi

echo "Error: Godot ${GODOT_VERSION} not found. Set GODOT to your Godot executable, or place ${BUNDLED_NAME}.zip in the project root." >&2
exit 1
