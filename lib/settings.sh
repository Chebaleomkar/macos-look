#!/usr/bin/env bash
# shellcheck shell=bash
# Desktop, dock and extension settings.

apply_settings() {
    if (( DRY_RUN )); then
        log "would apply config/settings.dconf"
    else
        dconf load / <"$ROOT/config/settings.dconf"
    fi
    ok "Applied GTK, dock, panel and window settings"

    case "$CLOCK" in
        12h) run gsettings set org.gnome.desktop.interface clock-format '12h' ;;
        24h) run gsettings set org.gnome.desktop.interface clock-format '24h' ;;
    esac
}

set_wallpaper() {
    local uri=$1
    run gsettings set org.gnome.desktop.background picture-uri "$uri"
    run gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
}

apply_wallpaper() {
    case "$WALLPAPER" in
        none)
            ok "Leaving the current wallpaper unchanged"
            ;;
        gradient)
            local dir="$DATA_HOME/backgrounds"
            local file="$dir/macos-look-gradient.xml"
            if (( ! DRY_RUN )); then
                mkdir -p "$dir"
                cp "$ROOT/assets/wallpaper/macos-look-gradient.xml" "$file"
            fi
            set_wallpaper "file://$file"
            ok "Applied the built-in license-free gradient wallpaper"
            ;;
        *)
            [[ -f "$WALLPAPER" ]] || die "Wallpaper not found: $WALLPAPER"
            set_wallpaper "file://$WALLPAPER"
            ok "Applied wallpaper: $WALLPAPER"
            ;;
    esac
}
