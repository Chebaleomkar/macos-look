#!/usr/bin/env bash
# shellcheck shell=bash
# System dependency installation.

install_deps() {
    local pkgs=(
        git
        curl
        unzip
        sassc
        libglib2.0-bin
        libxml2-utils
        fonts-inter
    )
    local missing=()
    local pkg

    for pkg in "${pkgs[@]}"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done

    if (( ${#missing[@]} == 0 )); then
        ok "Required system packages are already installed"
        return
    fi

    if (( DRY_RUN )); then
        log "would install: ${missing[*]}"
        return
    fi

    ensure_sudo
    run "${SUDO_CMD[@]}" apt-get update -qq
    run env DEBIAN_FRONTEND=noninteractive "${SUDO_CMD[@]}" \
        apt-get install -y -qq "${missing[@]}"
    ok "Installed: ${missing[*]}"
}
