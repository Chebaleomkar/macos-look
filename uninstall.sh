#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

ASSUME_YES=0
DRY_RUN=0
KEEP_SETTINGS=0
RESTORE_SETTINGS=0
PURGE=0

# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

usage() {
    cat <<'EOF'
macOS-look for Ubuntu — uninstall script

Usage:
  ./uninstall.sh [options]

Options:
  -y, --yes              Do not ask for confirmation
  -n, --dry-run          Show what would happen, change nothing
      --keep-settings    Leave theme/dock/panel settings untouched
      --restore-settings Restore the full dconf dump taken at install time
      --purge            Also delete the cache and install state
  -h, --help             Show this help

Log out and back in afterwards to return to the stock GNOME session.
EOF
}

parse_args() {
    while (( $# )); do
        case "$1" in
            -y|--yes) ASSUME_YES=1 ;;
            -n|--dry-run) DRY_RUN=1 ;;
            --keep-settings) KEEP_SETTINGS=1 ;;
            --restore-settings) RESTORE_SETTINGS=1 ;;
            --purge) PURGE=1 ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown option: $1 (try --help)" ;;
        esac
        shift
    done
}

confirm() {
    cat <<'EOF'
This will remove the macOS-look theme, icons, cursors and extensions,
and reset the settings this installer applied.

Your settings backup stays in ~/.local/state/macos-look/backup.
EOF
    local reply
    read -r -p "Continue? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || die "Aborted."
}

remove_extensions() {
    local file="$STATE_DIR/installed-extensions.txt"
    local uuid

    if [[ -f "$file" ]]; then
        while IFS= read -r uuid; do
            [[ -z "$uuid" ]] && continue
            if [[ -d "$EXT_DIR/$uuid" ]]; then
                run rm -rf "$EXT_DIR/$uuid"
                ok "Removed extension: $uuid"
            fi
        done <"$file"
    else
        warn "No installed-extension record found; leaving extensions untouched."
    fi

    # The bundled animation extension is always ours.
    if [[ -d "$EXT_DIR/smooth-window-animations@omkar" ]]; then
        run rm -rf "$EXT_DIR/smooth-window-animations@omkar"
        ok "Removed bundled animation extension"
    fi
}

remove_theme() {
    if [[ -x "$CACHE_DIR/src/WhiteSur-gtk-theme/install.sh" ]]; then
        run env -C "$CACHE_DIR/src/WhiteSur-gtk-theme" bash ./install.sh -r --silent-mode || true
    fi
    if [[ -x "$CACHE_DIR/src/WhiteSur-icon-theme/install.sh" ]]; then
        run env -C "$CACHE_DIR/src/WhiteSur-icon-theme" bash ./install.sh -r --silent-mode || true
    fi

    local dir
    for dir in "$HOME"/.themes/WhiteSur*; do
        [[ -e "$dir" ]] || continue
        run rm -rf "$dir"
    done
    for dir in "$DATA_HOME"/icons/WhiteSur "$DATA_HOME"/icons/WhiteSur-light \
        "$DATA_HOME"/icons/WhiteSur-dark "$DATA_HOME"/icons/WhiteSur-cursors; do
        [[ -e "$dir" ]] || continue
        run rm -rf "$dir"
    done
    run rm -f "$DATA_HOME/backgrounds/macos-look-gradient.xml"
    ok "Removed WhiteSur theme files"
}

restore_gtk_config() {
    local tarball
    tarball=$(find "$BACKUP_DIR" -maxdepth 1 -name 'gtk-4.0-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null |
        sort -nr | head -n1 | cut -d' ' -f2-)
    if [[ -n "$tarball" && -f "$tarball" ]]; then
        run tar -xzf "$tarball" -C "$HOME/.config"
        ok "Restored the pre-install GTK4 configuration"
    fi
}

reset_settings() {
    if (( RESTORE_SETTINGS )); then
        if [[ -f "$STATE_DIR/latest-backup.dconf" ]]; then
            run dconf load / <"$STATE_DIR/latest-backup.dconf"
            ok "Restored the dconf dump taken at install time"
        else
            warn "No dconf backup found; skipping full restore."
        fi
        return
    fi

    run dconf reset -f /org/gnome/shell/extensions/dash-to-dock/
    run dconf reset -f /org/gnome/shell/extensions/just-perfection/
    run dconf reset -f /org/gnome/shell/extensions/rounded-window-corners-reborn/
    run dconf reset -f /org/gnome/shell/extensions/user-theme/
    run dconf reset -f /org/gnome/shell/extensions/blur-my-shell/

    run gsettings reset org.gnome.desktop.wm.preferences button-layout
    run gsettings reset org.gnome.desktop.interface color-scheme
    run gsettings reset org.gnome.desktop.interface accent-color
    run gsettings reset org.gnome.desktop.interface clock-format
    run gsettings reset org.gnome.desktop.interface enable-hot-corners

    local themes=(/usr/share/themes/Yaru-dark /usr/share/themes/Yaru /usr/share/themes/Adwaita)
    local theme
    for theme in "${themes[@]}"; do
        if [[ -d "$theme" ]]; then
            run gsettings set org.gnome.desktop.interface gtk-theme "$(basename "$theme")"
            break
        fi
    done

    if [[ -d /usr/share/icons/Yaru ]]; then
        run gsettings set org.gnome.desktop.interface icon-theme 'Yaru'
    else
        run gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'
    fi

    if [[ -d /usr/share/icons/Yaru ]]; then
        run gsettings set org.gnome.desktop.interface cursor-theme 'Yaru'
    else
        run gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'
    fi

    if fc-match 'Ubuntu' | grep -qi '^Ubuntu'; then
        run gsettings set org.gnome.desktop.interface font-name 'Ubuntu 11'
        run gsettings set org.gnome.desktop.interface document-font-name 'Ubuntu 11'
    else
        run gsettings set org.gnome.desktop.interface font-name 'Sans 11'
        run gsettings set org.gnome.desktop.interface document-font-name 'Sans 11'
    fi

    ok "Reset settings applied by this installer"
}

restore_extension_list() {
    if (( DRY_RUN )); then
        log "would remove macOS-look extensions from the enabled list"
        return
    fi

    local -a ours=(
        "user-theme@gnome-shell-extensions.gcampax.github.com"
        "dash-to-dock@micxgx.gmail.com"
        "blur-my-shell@aunetx"
        "just-perfection-desktop@just-perfection"
        "rounded-window-corners@fxgn"
        "compiz-alike-magic-lamp-effect@hermes83.github.com"
        "touchpad-gesture-customization@coooolapps.com"
        "smooth-window-animations@omkar"
    )

    local cur reenable="false"
    [[ -d "$SYS_EXT_DIR/ubuntu-dock@ubuntu.com" ]] && reenable="true"
    cur=$(dconf read /org/gnome/shell/enabled-extensions 2>/dev/null || true)

    local new
    new=$(python3 - "$cur" "$reenable" "${ours[@]}" <<'PY'
import ast
import sys

raw = sys.argv[1].strip()
reenable_ubuntu_dock = sys.argv[2] == 'true'
ours = set(sys.argv[3:])

cur = []
if raw and not raw.startswith('@'):
    try:
        cur = list(ast.literal_eval(raw))
    except (ValueError, SyntaxError):
        cur = []

out = [u for u in cur if u not in ours]
if reenable_ubuntu_dock and 'ubuntu-dock@ubuntu.com' not in out:
    out.insert(0, 'ubuntu-dock@ubuntu.com')

print('[' + ', '.join("'%s'" % u for u in out) + ']')
PY
)

    dconf write /org/gnome/shell/enabled-extensions "$new"
    ok "Updated the enabled-extension list"
}

purge_state() {
    run rm -rf "$CACHE_DIR" "$STATE_DIR"
    ok "Removed cache and install state"
}

main() {
    parse_args "$@"
    detect_env
    printf '\n  macOS-look uninstall — %s (GNOME %s)\n\n' "$PRETTY_NAME" "$GNOME_VERSION"

    if (( ! ASSUME_YES && ! DRY_RUN )); then
        confirm
    fi

    remove_extensions
    remove_theme
    if (( ! KEEP_SETTINGS )); then
        restore_gtk_config
        reset_settings
    fi
    restore_extension_list

    if (( PURGE )); then
        purge_state
    fi

    cat <<EOF

${C_GREEN}${C_BOLD}Uninstall complete.${C_RESET}

Log out and back in to return to the stock GNOME session.
Backup kept at: ${BACKUP_DIR}
EOF
}

trap 'die "Uninstall failed at line ${LINENO}."' ERR
main "$@"
