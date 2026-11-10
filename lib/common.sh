#!/usr/bin/env bash
# shellcheck shell=bash
# Shared helpers for the macOS-look installer.

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'

log()  { printf '%s %s\n' "${C_BLUE}==>${C_RESET}" "$*"; }
ok()   { printf '%s %s\n' "${C_GREEN} ✓${C_RESET}" "$*"; }
warn() { printf '%s %s\n' "${C_YELLOW} !${C_RESET}" "$*" >&2; }
die()  { printf '%s %s\n' "${C_RED} ✗${C_RESET}" "$*" >&2; exit 1; }
step() { printf '\n%s\n' "${C_BOLD}$*${C_RESET}"; }

DRY_RUN=${DRY_RUN:-0}
ASSUME_YES=${ASSUME_YES:-0}
SUDO_CMD=()

# run: print + execute, or just print in dry-run mode.
run() {
    if (( DRY_RUN )); then
        printf '%s\n' "${C_DIM}  [dry-run] $*${C_RESET}" >&2
        return 0
    fi
    "$@"
}

detect_env() {
    [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release"
    # shellcheck disable=SC1091
    . /etc/os-release

    if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *ubuntu* ]]; then
        die "This installer targets Ubuntu (detected: ${PRETTY_NAME:-unknown})."
    fi

    command -v gnome-shell >/dev/null 2>&1 || die "GNOME Shell is not installed."
    command -v dconf >/dev/null 2>&1 || die "dconf is missing (is this a GNOME session?)."

    GNOME_VERSION=$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -n1)
    [[ "${GNOME_VERSION:-}" =~ ^[0-9]+$ ]] || die "Could not detect the GNOME Shell version."
    (( GNOME_VERSION >= 45 )) || die "GNOME Shell 45 or newer is required (detected ${GNOME_VERSION})."

    if ! dconf dump / >/dev/null 2>&1; then
        die "Cannot reach dconf. Run this inside your desktop session, not over SSH."
    fi

    SESSION_TYPE=${XDG_SESSION_TYPE:-unknown}
    DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
    STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/macos-look
    CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/macos-look
    EXT_DIR="$DATA_HOME/gnome-shell/extensions"
    SYS_EXT_DIR="/usr/share/gnome-shell/extensions"
    BACKUP_DIR="$STATE_DIR/backup"
    LOG_FILE="$STATE_DIR/install.log"

    mkdir -p "$STATE_DIR" "$CACHE_DIR" "$BACKUP_DIR"
}

ensure_sudo() {
    if (( EUID == 0 )); then
        SUDO_CMD=()
        return
    fi
    if ! sudo -n true 2>/dev/null; then
        log "Administrator access is needed to install a few system packages."
        sudo -v || die "sudo authentication failed."
    fi
    SUDO_CMD=(sudo)

    if [[ -z "${SUDO_KEEPALIVE_PID:-}" ]]; then
        (
            while kill -0 "$$" 2>/dev/null; do
                sleep 50
                sudo -n true 2>/dev/null || true
            done
        ) >/dev/null 2>&1 &
        SUDO_KEEPALIVE_PID=$!
    fi
}

start_log() {
    # Keep a copy of the run for troubleshooting, but never hide output.
    if [[ -t 1 ]]; then
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
}

backup_state() {
    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    local dump="$BACKUP_DIR/dconf-$stamp.dump"

    if (( DRY_RUN )); then
        log "would back up current settings to $dump"
        return
    fi

    dconf dump / >"$dump"
    ln -sfn "$dump" "$STATE_DIR/latest-backup.dconf"
    if [[ -d "$HOME/.config/gtk-4.0" ]]; then
        tar -czf "$BACKUP_DIR/gtk-4.0-$stamp.tar.gz" -C "$HOME/.config" gtk-4.0
    fi
    ok "Current settings backed up to $dump"

    if [[ ! -f "$STATE_DIR/installed-extensions.txt" ]]; then
        : >"$STATE_DIR/installed-extensions.txt"
    fi
}

record_installed_extension() {
    local uuid=$1
    local file="$STATE_DIR/installed-extensions.txt"
    (( DRY_RUN )) && return
    touch "$file"
    grep -qxF "$uuid" "$file" || printf '%s\n' "$uuid" >>"$file"
}
