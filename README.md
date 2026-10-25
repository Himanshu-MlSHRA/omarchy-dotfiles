# omarchy-dotfiles

A **Dynamic Island** for [Omarchy](https://omarchy.org). The top bar becomes one small island, and everything
(Wi-Fi, sound, Bluetooth, battery, music, notifications, volume, menus, even app windows) comes out of it.

https://github.com/user-attachments/assets/13f49d9a-b1be-438c-b85d-ffbb143b266a

## Install

Pick one, paste it in a terminal, done. Needs **Omarchy 4**.

| | What you get | Command |
|---|---|---|
| **1. Island** | The island bar. Notifications, volume and brightness show inside it. | `curl -fsSL https://raw.githubusercontent.com/Himanshu-MlSHRA/omarchy-dotfiles/main/install.sh \| bash -s -- island` |
| **2. Island + motion** | Option 1, plus apps **fly out of the island** when they open, menus **grow out of it**, and workspaces slide. | `curl -fsSL https://raw.githubusercontent.com/Himanshu-MlSHRA/omarchy-dotfiles/main/install.sh \| bash -s -- motion` |
| **3. Everything** | Exactly my setup: option 2, plus the Coppernight theme, the dot-matrix lock screen with always-on display, the Shan Shui painted wallpaper, restyled widgets and terminal fonts. | `curl -fsSL https://raw.githubusercontent.com/Himanshu-MlSHRA/omarchy-dotfiles/main/install.sh \| bash -s -- full` |

**Undo** (puts back exactly what you had before):
```sh
curl -fsSL https://raw.githubusercontent.com/Himanshu-MlSHRA/omarchy-dotfiles/main/install.sh | bash -s -- remove
```

Your files are backed up first, to `~/.local/state/omarchy-dotfiles/`. Nothing in Omarchy itself is changed, so `omarchy update` keeps working.

## Shortcuts

| Keys | What it does | In |
|---|---|---|
| `SUPER + B` (or click the island) | Open / close the island | 1 2 3 |
| `Tab` / `Shift + Tab` / `←` `→` | Next / previous page in the island | 1 2 3 |
| Click a tile | Open Wi-Fi, sound, Bluetooth, battery or Claude inside the island | 1 2 3 |
| `Esc` | Go back one step, then close | 1 2 3 |
| Click / right-click a notification | Open it / dismiss it | 1 2 3 |
| `SUPER + ALT + SPACE` | App launcher (grows out of the island in 2 and 3) | Omarchy |
| `SUPER + SPACE` | Omarchy menu | Omarchy |
| `SUPER + ESC` | System menu: lock, suspend, restart, shut down | Omarchy |
| `SUPER + 1` … `9` | Switch workspace (slides in 2 and 3) | Omarchy |
| `SUPER + SHIFT + L` | Lock the screen | 3 |
| `SUPER + ALT + W` | Painted wallpaper ↔ still wallpaper | 3 |
| `SUPER + ALT + SHIFT + W` | Wallpaper settings, inside the island | 3 |

**Lock screen (3):** leave it for 30 seconds and it turns into an always-on display. The screen dims and the
clock drifts a little so an OLED panel doesn't burn in. Touch anything to wake it.

**Turn off just the flying windows:** put `{ "windowFlight": false }` in `~/.config/omarchy/island.json`.

## Why

Stock Omarchy puts things all over the screen: a bar on top, notifications in a corner, menus in the middle, the
volume popup somewhere else. I wanted one calm place, like a phone, where everything comes out of the top of
the screen and goes back into it.

Everything is built with Omarchy's own plugin system (Quickshell). No fork, no Waybar.

## What's inside

| Folder | What it is |
|---|---|
| `config/omarchy/plugins/anshu.bar` | The Dynamic Island |
| `config/omarchy/plugins/anshu.notifications` | Notifications, drawn by the island |
| `config/omarchy/plugins/anshu.menu` | Menus and launcher that grow out of the island |
| `config/omarchy/plugins/anshu.lock` | Lock screen and always-on display |
| `config/omarchy/plugins/anshu.*` (others) | Restyled clock, workspaces, Wi-Fi, sound, Bluetooth, power, weather |
| `config/omarchy/themes/coppernight` | My tweaks to the Coppernight theme |
| `config/hypr`, terminals, `starship.toml` | Window look, animations, Maple Mono font |
| `install.sh` | The installer above |

## Credits

- [Omarchy](https://github.com/basecamp/omarchy) by DHH and contributors
- [Coppernight theme](https://github.com/hembramnishant50-glitch/omarchy-coppernight-theme) by Nishant
- [Shan Shui wallpaper](https://github.com/zednaked/omarchy-shanshui) by ZeD, based on LingDong-'s [{Shan, Shui}*](https://github.com/LingDong-/shan-shui-inf)
- Look and motion inspired by [Panacea](https://github.com/EnsixD/Panacea) and [Atoll](https://github.com/Ebullioscopic/Atoll)

Made on Omarchy 4.0 with Hyprland 0.56. MIT licensed.
