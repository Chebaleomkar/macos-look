# macOS-look for Ubuntu

A one-command installer that turns a stock Ubuntu GNOME desktop into a clean,
macOS-style setup: floating bottom dock, WhiteSur theme and icons, Inter font,
rounded window corners, magic-lamp minimize and smooth maximize/restore.

Designed to work across Ubuntu releases by detecting your GNOME Shell version
and fetching extension builds that are compatible with it.

> Not affiliated with Apple. No Apple wallpapers are bundled.

---

## What it does

| Layer | Installed |
|---|---|
| GTK / GNOME Shell theme | [WhiteSur](https://github.com/vinceliuice/WhiteSur-gtk-theme) (dark by default) |
| Icons | [WhiteSur-icon-theme](https://github.com/vinceliuice/WhiteSur-icon-theme) |
| Cursors | [WhiteSur-cursors](https://github.com/vinceliuice/WhiteSur-cursors) |
| Font | Inter (`fonts-inter`) |
| Dock | Dash to Dock: bottom, auto-hide, hover reveal, click-to-minimize, 48px |
| Window controls | traffic lights on the left (`close,minimize,maximize`) |
| Corners | Rounded Window Corners Reborn (works on maximized windows too) |
| Minimize | Compiz-alike magic lamp |
| Maximize/restore | bundled *Smooth Window Animations* extension (400 ms ease-in-out) |
| Panel | Just Perfection: no Activities label, clock on the right |
| Effects | Blur my Shell |
| Gestures | Touchpad Gesture Customization (laptops) |
| Wallpaper | license-free gradient (or `--wallpaper PATH` / `none`) |

Ubuntu Dock is disabled to avoid the known double-dock conflict.

---

## Requirements

- Ubuntu **24.04 or newer** (GNOME Shell 45–50+)
- A normal desktop session (Wayland or X11)
- Internet access
- `sudo` for a small set of packages

Supported releases are detected automatically; the extension versions are
resolved per GNOME major version via extensions.gnome.org.

---

## Install

### From a clone

```bash
git clone https://github.com/Chebaleomkar/macos-look.git
cd macos-look
./install.sh
```

### One-liner

After editing `REPO_OWNER` in `bootstrap.sh` (or setting `MACOS_LOOK_REPO`):

```bash
curl -fsSL https://raw.githubusercontent.com/Chebaleomkar/macos-look/main/bootstrap.sh | bash
```

Preview without changing anything:

```bash
./install.sh --dry-run
```

**After installing, log out and back in once.** GNOME only loads new
extensions and the Shell theme at session start. On Wayland there is no way
around this; `./install.sh --logout` can do it for you.

---

## Options

```text
-y, --yes             no confirmation prompt
-n, --dry-run         show actions only
    --light           light theme variant
    --clock 12h|24h   clock format (default: 24h)
    --wallpaper PATH  custom wallpaper
    --wallpaper none  keep the current wallpaper
    --no-theme        skip GTK/icon/cursor/font installation
    --no-extensions   skip extensions
    --no-settings     skip settings
    --logout          offer to log out when finished
```

---

## Uninstall

```bash
./uninstall.sh
```

It removes the theme, icons, cursors, installed extensions and resets the
settings this installer wrote. Your settings are backed up first in
`~/.local/state/macos-look/backup/`.

- `--keep-settings` — remove files but leave settings alone
- `--restore-settings` — restore the full dconf dump from install time
- `--purge` — also delete the cache and state directory

Log out and back in afterwards.

---

## Customizing

- **Dock, panel, corners:** edit `config/settings.dconf` (plain dconf format).
- **Extension set:** edit `config/extensions.conf` (`uuid|label|source|optional`).
- **Theme variant:** `--light`, or change the `-c` flag in `lib/theme.sh`.
- **Smooth maximize:** edit `DURATION` / `MODE` in
  `assets/extensions/smooth-window-animations@omkar/extension.js`.

The installer is idempotent: re-running it skips what is already installed and
re-applies the settings.

---

## Known limitations

- **Dock magnification** (the macOS "fish-eye" effect) was removed from Dash to
  Dock upstream; it cannot be enabled on current versions.
- **Brave / Chromium** draw their own window buttons, so WhiteSur cannot style
  them. GTK apps get the traffic lights.
- **Login screen (GDM)** theming is intentionally skipped: it needs root and can
  break the login flow.
- **Global app menu** (a macOS-style menu bar) would require Fildem, which is
  unreliable on Wayland — not included.
- **Sandboxed apps** (Flatpak/Snap) may need a theme override to follow WhiteSur.
- **Apple wallpapers** are not shipped. Use `--wallpaper PATH` with your own.

---

## How it works

1. Detects Ubuntu + GNOME major version and session type.
2. Backs up dconf and `~/.config/gtk-4.0`.
3. Installs prerequisites with apt.
4. Clones and runs the upstream WhiteSur installers (cached in
   `~/.cache/macos-look`).
5. Queries `extensions.gnome.org/extension-info/?uuid=…&shell_version=…` so each
   GNOME release gets a compatible extension build. If none exists, it warns
   and continues instead of breaking the install.
6. Applies `config/settings.dconf` and merges the extension list — it never
   overwrites your other extensions, and it removes `ubuntu-dock` from it.
7. Applies the wallpaper.

## Publishing for your community

1. Create a GitHub repository and push this folder to it.
2. The one-liner and `clone` URLs in `README.md`/`bootstrap.sh` are already
   configured for this repository.
3. Test on a clean VM for each Ubuntu release you want to support before
   announcing.
4. Share the one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/Chebaleomkar/macos-look/main/bootstrap.sh | bash
```

---

## Troubleshooting

- **Maximize/restore looks instant or odd** — the bundled
  *Smooth Window Animations* extension normally stays silent. For debugging,
  set `DEBUG = true` at the top of the installed
  (`~/.local/share/gnome-shell/extensions/smooth-window-animations@omkar/extension.js`),
  log out/in once, and watch `journalctl --user -b | grep smooth-wm`.
  Disable it at any time with
  `gnome-extensions disable smooth-window-animations@omkar`.
- **Install log** — `~/.local/state/macos-look/install.log`.
- **Settings backup** — `~/.local/state/macos-look/backup/`.
- **Extension missing after an Ubuntu upgrade** — re-running `./install.sh`
  detects stale, incompatible extension installs and fetches a matching build.

---

## Repository layout

```text
install.sh                 entry point
uninstall.sh               revert
bootstrap.sh               one-line download + install
lib/common.sh              detection, logging, backup, sudo
lib/deps.sh                apt packages
lib/theme.sh               WhiteSur / icons / cursors / font
lib/extensions.sh          extension install + enable lists
lib/settings.sh            dconf + wallpaper
config/settings.dconf      dock, panel, corners, theme keys
config/extensions.conf     extension matrix
assets/extensions/         bundled extensions (our animation fix)
assets/wallpaper/          license-free gradient
```

---

## Credits and licenses

- Installer code: MIT (see `LICENSE`).
- [WhiteSur GTK Theme](https://github.com/vinceliuice/WhiteSur-gtk-theme),
  [WhiteSur Icon Theme](https://github.com/vinceliuice/WhiteSur-icon-theme) and
  [WhiteSur cursors](https://github.com/vinceliuice/WhiteSur-cursors) are
  GPL-3.0 by vinceliuice.
- [Inter](https://rsms.me/inter/) is licensed under the SIL Open Font License.
- GNOME extensions keep their own licenses; see each extension directory or
  its extensions.gnome.org page.
