#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

ASSUME_YES=0
DRY_RUN=0
DO_THEME=1
DO_EXTENSIONS=1
DO_SETTINGS=1
DO_WALLPAPER=1
CLOCK=24h
WALLPAPER=gradient
THEME_VARIANT=dark
LOGOUT=0

# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/deps.sh
source "$ROOT/lib/deps.sh"
# shellcheck source=lib/theme.sh
source "$ROOT/lib/theme.sh"
# shellcheck source=lib/extensions.sh
source "$ROOT/lib/extensions.sh"
# shellcheck source=lib/settings.sh
source "$ROOT/lib/settings.sh"

usage() {
    cat <<'EOF'
macOS-look for Ubuntu — install script

Usage:
  ./install.sh [options]

Options:
  -y, --yes             Do not ask for confirmation
  -n, --dry-run         Show what would happen, change nothing
      --light           Install the light theme variant (default: dark)
      --clock 12h|24h   Clock format (default: 24h)
      --wallpaper PATH  Use a custom wallpaper
      --wallpaper none  Keep the current wallpaper
      --no-theme        Skip GTK/icon/cursor/font installation
      --no-extensions   Skip GNOME extension installation
      --no-settings     Skip applying desktop settings
      --no-wallpaper    Keep the current wallpaper
      --logout          Offer to log out when finished
  -h, --help            Show this help

After installing, log out and back in once: GNOME only discovers new
extensions and the Shell theme at session start.

Revert everything with: ./uninstall.sh
EOF
}

parse_args() {
    while (( $# )); do
        case "$1" in
            -y|--yes) ASSUME_YES=1 ;;
            -n|--dry-run) DRY_RUN=1 ;;
            --light) THEME_VARIANT=light ;;
            --clock)
                shift
                CLOCK=${1:-}
                [[ "$CLOCK" == "12h" || "$CLOCK" == "24h" ]] || die "--clock expects 12h or 24h"
                ;;
            --clock=*) CLOCK=${1#*=} ;;
            --wallpaper)
                shift
                WALLPAPER=${1:-}
                ;;
            --wallpaper=*) WALLPAPER=${1#*=} ;;
            --no-theme) DO_THEME=0 ;;
            --no-extensions) DO_EXTENSIONS=0 ;;
            --no-settings) DO_SETTINGS=0 ;;
            --no-wallpaper|--wallpaper=none) WALLPAPER=none ;;
            --logout) LOGOUT=1 ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown option: $1 (try --help)" ;;
        esac
        shift
    done

    [[ "$CLOCK" == "12h" || "$CLOCK" == "24h" ]] || die "--clock expects 12h or 24h"
    [[ -n "${WALLPAPER:-}" ]] || die "--wallpaper needs a path or 'none'"
}

banner() {
    cat <<EOF

  macOS-look for Ubuntu
  ─────────────────────
  System    : ${PRETTY_NAME}
  GNOME     : ${GNOME_VERSION}
  Session   : ${SESSION_TYPE}
  Theme     : ${THEME_VARIANT}
  Wallpaper : ${WALLPAPER}
  Mode      : $([[ $DRY_RUN == 1 ]] && echo "dry-run" || echo "install")

EOF
}

confirm() {
    cat <<EOF
This will:
  • install a few system packages (sudo)
  • install the WhiteSur GTK/Shell theme, icons, cursors and Inter
  • install ${GNOME_VERSION}-compatible GNOME extensions (or bundled builds)
  • replace dock, panel, window and theme settings

A backup of your current dconf settings is saved first.
EOF
    local reply
    read -r -p "Continue? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || die "Aborted."
}

summary() {
    cat <<EOF

${C_GREEN}${C_BOLD}Done.${C_RESET}

One step left: log out and back in (or reboot) so GNOME loads the new
extensions and Shell theme. Until then the old theme stays visible.

  • Revert:    ./uninstall.sh
  • Log file:  ${LOG_FILE}
EOF

    if (( LOGOUT )) && (( ! DRY_RUN )); then
        printf '\nLogging out in 5 seconds — press Ctrl+C to cancel.\n'
        sleep 5
        gnome-session-quit --logout || true
    fi
}

main() {
    parse_args "$@"
    detect_env
    banner

    if (( ! ASSUME_YES && ! DRY_RUN )); then
        confirm
    fi

    start_log

    step "1/4 · System packages"
    install_deps

    if (( DO_THEME )); then
        step "2/4 · Theme, icons, cursors, font"
        install_gtk_theme
        install_icons
        install_cursors
        install_font
    else
        step "2/4 · Theme — skipped"
    fi

    if (( DO_EXTENSIONS )); then
        step "3/4 · GNOME extensions"
        install_extensions
    else
        step "3/4 · Extensions — skipped"
    fi

    if (( DO_SETTINGS )); then
        step "4/4 · Desktop settings"
        apply_settings
    else
        step "4/4 · Settings — skipped"
    fi

    if (( DO_EXTENSIONS )); then
        enable_extensions
    fi

    if (( DO_WALLPAPER )); then
        apply_wallpaper
    fi

    summary
}

trap 'die "Installation failed at line ${LINENO}. See ${LOG_FILE:-the output above}."' ERR
main "$@"
