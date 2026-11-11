#!/usr/bin/env bash
# shellcheck shell=bash
# GNOME extension installation and enablement.

extension_present() {
    local uuid=$1
    [[ -f "$EXT_DIR/$uuid/metadata.json" ]] && return 0
    [[ -f "$SYS_EXT_DIR/$uuid/metadata.json" ]] && return 0
    return 1
}

# True when an installed copy declares support for this GNOME major version.
# This catches extensions left over from a previous Ubuntu release.
extension_usable() {
    local uuid=$1
    local dir

    for dir in "$EXT_DIR/$uuid" "$SYS_EXT_DIR/$uuid"; do
        [[ -f "$dir/metadata.json" ]] || continue
        if python3 - "$dir/metadata.json" "$GNOME_VERSION" <<'PY'
import json
import sys

try:
    meta = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)

current = sys.argv[2]
versions = [str(v) for v in meta.get('shell-version', [])]
sys.exit(0 if current in versions or '*' in versions else 1)
PY
        then
            return 0
        fi
    done

    return 1
}

compile_schemas() {
    local dir=$1
    if compgen -G "$dir/schemas/*.xml" >/dev/null; then
        glib-compile-schemas "$dir/schemas" 2>/dev/null ||
            warn "Could not compile schemas for $(basename "$dir")"
    fi
}

fetch_ego_zip() {
    local uuid=$1
    local out=$2
    local api="https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${GNOME_VERSION}"
    local json dl

    json=$(curl -fsSL --retry 3 --connect-timeout 10 -m 40 "$api") || return 1
    dl=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("download_url",""))' \
        <<<"$json" 2>/dev/null) || return 1
    [[ -n "$dl" ]] || return 1

    curl -fsSL --retry 3 --connect-timeout 10 -m 180 \
        "https://extensions.gnome.org${dl}" -o "$out"
}

install_from_ego() {
    local uuid=$1
    local label=$2

    if extension_usable "$uuid"; then
        ok "$label is already installed"
        record_installed_extension "$uuid"
        return
    fi

    if (( DRY_RUN )); then
        log "would install $label from extensions.gnome.org"
        return
    fi

    local zip="$CACHE_DIR/$uuid.zip"
    if ! fetch_ego_zip "$uuid" "$zip"; then
        warn "$label has no release compatible with GNOME $GNOME_VERSION — skipped."
        return
    fi

    local tmp
    tmp=$(mktemp -d)
    if ! unzip -q "$zip" -d "$tmp"; then
        warn "Could not unpack $label — skipped."
        rm -rf "$tmp"
        return
    fi

    local src=$tmp
    if [[ ! -f "$src/metadata.json" ]]; then
        local inner
        inner=$(find "$tmp" -maxdepth 3 -name metadata.json -printf '%h\n' | head -n1)
        [[ -n "$inner" ]] && src=$inner
    fi

    if [[ ! -f "$src/metadata.json" ]]; then
        warn "Invalid archive for $label — skipped."
        rm -rf "$tmp"
        return
    fi

    rm -rf "$EXT_DIR/$uuid"
    mkdir -p "$EXT_DIR/$uuid"
    cp -a "$src/." "$EXT_DIR/$uuid/"
    rm -rf "$tmp"

    compile_schemas "$EXT_DIR/$uuid"
    record_installed_extension "$uuid"
    ok "Installed $label"
}

install_vendored() {
    local uuid=$1
    local label=$2
    local src="$ROOT/assets/extensions/$uuid"

    if [[ ! -d "$src" ]]; then
        warn "Bundled extension $uuid is missing — skipped."
        return
    fi

    if (( DRY_RUN )); then
        log "would install bundled extension: $label"
        return
    fi

    rm -rf "$EXT_DIR/$uuid"
    mkdir -p "$EXT_DIR/$uuid"
    cp -a "$src/." "$EXT_DIR/$uuid/"
    compile_schemas "$EXT_DIR/$uuid"
    record_installed_extension "$uuid"
    ok "Installed $label (bundled)"
}

install_extensions() {
    local uuid label source optional
    mkdir -p "$EXT_DIR"

    while IFS='|' read -r uuid label source optional; do
        [[ -z "${uuid:-}" || "$uuid" == \#* ]] && continue
        case "$source" in
            ego) install_from_ego "$uuid" "$label" ;;
            vendor) install_vendored "$uuid" "$label" ;;
            *) warn "Unknown source '$source' for $uuid" ;;
        esac
    done <"$ROOT/config/extensions.conf"
}

merge_extension_lists() {
    local -a uuids=("$@")
    local cur_en cur_dis new_en new_dis

    if (( DRY_RUN )); then
        log "would enable: ${uuids[*]}"
        log "would disable ubuntu-dock@ubuntu.com"
        return
    fi

    cur_en=$(dconf read /org/gnome/shell/enabled-extensions 2>/dev/null || true)
    cur_dis=$(dconf read /org/gnome/shell/disabled-extensions 2>/dev/null || true)

    new_en=$(python3 - "$cur_en" "${uuids[@]}" <<'PY'
import ast
import sys

raw = sys.argv[1].strip()
cur = []
if raw and not raw.startswith('@'):
    try:
        cur = list(ast.literal_eval(raw))
    except (ValueError, SyntaxError):
        cur = []

want = sys.argv[2:]
out = [u for u in cur if u != 'ubuntu-dock@ubuntu.com' and u not in want]
out.extend(u for u in want if u not in out)
print('@as [' + ', '.join("'%s'" % u for u in out) + ']')
PY
)

    new_dis=$(python3 - "$cur_dis" "${uuids[@]}" <<'PY'
import ast
import sys

raw = sys.argv[1].strip()
cur = []
if raw and not raw.startswith('@'):
    try:
        cur = list(ast.literal_eval(raw))
    except (ValueError, SyntaxError):
        cur = []

drop = set(sys.argv[2:]) | {'ubuntu-dock@ubuntu.com'}
out = [u for u in cur if u not in drop]
print('@as [' + ', '.join("'%s'" % u for u in out) + ']')
PY
)

    dconf write /org/gnome/shell/enabled-extensions "$new_en"
    dconf write /org/gnome/shell/disabled-extensions "$new_dis"
    gsettings set org.gnome.shell disable-user-extensions false
    ok "Extension list updated (Ubuntu Dock disabled, macOS extensions enabled)"
}

enable_extensions() {
    local -a uuids=()
    local uuid label source optional

    while IFS='|' read -r uuid label source optional; do
        [[ -z "${uuid:-}" || "$uuid" == \#* ]] && continue
        if extension_present "$uuid"; then
            uuids+=("$uuid")
        else
            warn "$label is not installed; leaving it out of the enabled list."
        fi
    done <"$ROOT/config/extensions.conf"

    merge_extension_lists "${uuids[@]}"
}
