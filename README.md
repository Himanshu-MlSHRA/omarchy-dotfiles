# omarchy-dotfiles

My [Omarchy](https://omarchy.org) 4 setup (Hyprland + the Quickshell-based Omarchy shell): a copper-on-black theme,
a Dynamic Island top bar, and every bar widget, menu and the lock screen rebuilt to match.

Only what differs from a stock Omarchy install is here.

![Walkthrough highlights](docs/walkthrough.gif)

▶ **Full 75-second walkthrough with sound:** [docs/walkthrough.mp4](docs/walkthrough.mp4) (GitHub downloads it, then play it locally): lock screen and always-on display, the island and its pages,
Wi-Fi / sound / Bluetooth / battery / Claude detail views, notifications, OSD, launcher, menus, windows flying in and out,
workspace switching, and the Shan Shui wallpaper.

## Why

Stock Omarchy is fast and good-looking, but its pieces live in different places: a status bar along the top,
notifications in a corner, menus and the launcher floating in the middle of the screen, an OSD somewhere else.
On a 14" laptop that means your eyes and the mouse keep jumping around.

I wanted **one calm surface**, like a phone: everything comes out of the top of the screen and goes back into it.
- The bar is a **Dynamic Island**. Wi-Fi, sound, Bluetooth, battery, media and Claude usage are pages and detail views inside it,
  not separate popups.
- Notifications, volume/brightness and the charging animation appear **in** the island.
- The launcher and every Omarchy menu **morph out of** the island. App windows **fly out of it** when they open and fall back in when they close.
- The lock screen got the same treatment: a dot-matrix clock, and an **always-on display** that dims the OLED panel
  and drifts the clock so it doesn't burn in.

All of it is Omarchy's own plugin system (Quickshell/QML): no forked Omarchy, no Waybar, and `omarchy update` keeps working.

## What's customized

### Desktop shell (`config/omarchy/plugins/anshu.*`)
| Plugin | What it is |
|---|---|
| `anshu.bar` | The top bar rebuilt as a **Dynamic Island**: a compact pill (date · time) that grows into pages (media with cover art + seek, Wi-Fi/BT/sound/battery tiles, Claude usage meters, system stats, quick toggles). Shows notifications and volume/brightness OSD inside the island. Windows fly out of / into it. Design notes in `ISLAND.md`. |
| `anshu.menu` | Omarchy's menu/launcher, opening as the island morphing into a card. |
| `anshu.lock` | Lock screen: hand-drawn dot-matrix clock, slide-up sheet, fingerprint badge, always-on dim mode. |
| `anshu.notifications` | Notification service; the island draws the popups. |
| `anshu.audio`, `anshu.bluetooth`, `anshu.network`, `anshu.power`, `anshu.monitor`, `anshu.weather`, `anshu.clock`, `anshu.workspaces`, `anshu.agents` | Bar widgets cloned from Omarchy's own, restyled with press-bounce and animated panels. |

`config/omarchy/shell.json` swaps these in for `omarchy.notifications`, `omarchy.osd`, `omarchy.menu` and `omarchy.lock`.

### Theme: Coppernight (`config/omarchy/themes/coppernight`)
- Palette `#000000 / #1F150C / #412D15 / #E1DCC9`, copper accent `#C9955C`, Yaru-wartybrown-dark icons.
- Themed: terminals, btop, Neovim, Helix, VS Code, Chromium, fastfetch, starship, fish/zsh, cava, Vencord (Discord),
  YouTube (Stylus), GTK/Nautilus (`gtk.css`, copied into gtk-3/4 by the `theme-gtk-css.sh` theme-set hook),
  Plymouth logo (`unlock.png`).
- `hyprland.lua` in the theme: fast, smooth macOS-style animation curves.

### Hyprland (`config/hypr`)
- `looknfeel.lua`: dimmed inactive windows, 0.90/0.82 window opacity, blur rules for menus/launcher, layer animations.
- `bindings.lua`:
  - `SUPER+B` open the island (or the Panacea panel when Panacea mode is on); `Esc` / `Tab` / arrows navigate it
  - `SUPER+SHIFT+L` lock
  - `SUPER+SHIFT+W` WhatsApp
  - `SUPER+ALT+W` Shan Shui painted wallpaper on/off, `SUPER+ALT+SHIFT+W` its settings
- `monitors.lua`: scale 2 (2880x1800 OLED laptop panel - change for your screen).
- `autostart.lua`: starts Panacea if Panacea mode was left on.

### Look elsewhere
- Font **Maple Mono NF** in alacritty / foot / kitty / ghostty, size 8–9.
- `starship.toml`: two-line copper prompt.
- `branding/`: custom ASCII art for About and the screensaver.

### Third-party plugins (not vendored - installed from their repos, my patches in `patches/`)
- [zed.shanshui](https://github.com/zednaked/omarchy-shanshui) - endless Chinese ink landscape painted as the wallpaper.
- [OmaWhatsApp](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp) - `patches/omawhatsapp.patch`: real chat names and
  message text in notifications. `omarchy plugin update` overwrites it; re-apply the patch after updating.
- [Panacea](https://github.com/EnsixD/Panacea) @ `8636001` - an alternative pill shell, **off by default**.
  `patches/panacea.patch` adds a light/dark palette (`Pal.qml`) and WhatsApp / Shan Shui / Claude buttons.
  Switch with `panacea-mode on|off|status` (in `local/bin`). Its own `install.sh` was never run - it replaces
  Hyprland, foot, fish, GRUB and SDDM configs.

### Scripts (`local/bin`)
- `panacea-mode` - switch between the island and the Panacea pill.
- `fp-chip` - list/clear prints stored on the match-on-chip fingerprint reader (Windows Hello dual-boot wipes them).

### System (`system/`, needs sudo)
- `/etc/bluetooth/main.conf` - fast connect, auto-reconnect, `JustWorksRepairing = always` (fixes earbuds refusing to reconnect).
- `/etc/modprobe.d/btusb-no-autosuspend.conf` - stops the Bluetooth adapter sleeping.
- `config/wireplumber/.../bluetooth-a2dp-autoconnect.conf` - prefer A2DP on connect.
- `config/spotify-flags.conf` - native Wayland (the X11 path crashed the GPU process).

### Packages added on top of Omarchy (`packages/`)
- **pacman**: see `packages/pacman.txt`
- **AUR**: see `packages/aur.txt`

## Not included (on purpose)
- Wallpapers - mostly copyrighted art.
- `~/.config/git/config` - personal name/email.
- WhatsApp session data, browser profiles, app state.
- Dozens of `*.bak*` / `*-backup-*` files from experimenting.

## Use
```sh
./sync.sh                 # refresh the repo from this machine (run before committing)
./install.sh              # on a fresh Omarchy: configs, plugins, scripts (backs up what it replaces)
./install.sh --packages --system
omarchy theme set coppernight && omarchy restart shell
```
