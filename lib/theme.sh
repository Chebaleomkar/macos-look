#!/usr/bin/env bash
# shellcheck shell=bash
# Theme, icon, cursor and font installation (WhiteSur + Inter).

REPO_DIR=""

prepare_repo() {
    local name=$1
    local url=$2
    REPO_DIR="$CACHE_DIR/src/$name"

    if [[ -d "$REPO_DIR/.git" ]]; then
        ok "Using cached $name"
        return
    fi

    if (( DRY_RUN )); then
        log "would clone $url"
        REPO_DIR="$CACHE_DIR/src/$name"
        return
    fi

    mkdir -p "$CACHE_DIR/src"
    run git clone --depth=1 "$url" "$REPO_DIR"
    ok "Downloaded $name"
}

run_repo_installer() {
    local repo=$1
    shift
    if (( DRY_RUN )); then
        log "would run: $repo/install.sh $*"
        return
    fi
    [[ -x "$repo/install.sh" ]] || chmod +x "$repo/install.sh"
    ( cd "$repo" && ./install.sh "$@" )
}

install_gtk_theme() {
    prepare_repo WhiteSur-gtk-theme https://github.com/vinceliuice/WhiteSur-gtk-theme.git
    local repo=$REPO_DIR
    run_repo_installer "$repo" -c "$THEME_VARIANT" -l
    ok "WhiteSur GTK + GNOME Shell theme installed ($THEME_VARIANT)"
}

install_icons() {
    prepare_repo WhiteSur-icon-theme https://github.com/vinceliuice/WhiteSur-icon-theme.git
    local repo=$REPO_DIR
    run_repo_installer "$repo"
    if (( ! DRY_RUN )); then
        local dir
        for dir in "$DATA_HOME"/icons/WhiteSur*; do
            [[ -d "$dir" ]] || continue
            gtk-update-icon-cache -f -t "$dir" >/dev/null 2>&1 || true
        done
    fi
    ok "WhiteSur icon theme installed"
}

install_cursors() {
    prepare_repo WhiteSur-cursors https://github.com/vinceliuice/WhiteSur-cursors.git
    local repo=$REPO_DIR
    run_repo_installer "$repo"
    ok "WhiteSur cursor theme installed"
}

install_font() {
    # fonts-inter is installed by install_deps; refresh the font cache.
    if (( DRY_RUN )); then
        log "would refresh the font cache"
        return
    fi
    fc-cache -f >/dev/null 2>&1 || true
    if fc-match "Inter" | grep -qi '^Inter'; then
        ok "Inter font is available"
    else
        warn "Inter was not detected by fontconfig; the UI font may fall back to Sans."
    fi
}
