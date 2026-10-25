#!/bin/bash
# Put these customizations onto a fresh Omarchy install.
# Every file it would overwrite is first copied to <file>.pre-dotfiles.
#
#   ./install.sh            configs, plugins, scripts, third-party plugins + patches
#   ./install.sh --packages also install the extra pacman/AUR packages
#   ./install.sh --system   also copy the /etc tweaks (asks for sudo)
set -e
R=$(cd "$(dirname "$0")" && pwd)

place() { # place <src-dir> <dest-dir>
  (cd "$1" && find . -type f) | while read -r f; do
    dst="$2/${f#./}"
    mkdir -p "$(dirname "$dst")"
    [ -e "$dst" ] && ! cmp -s "$1/$f" "$dst" && cp -a "$dst" "$dst.pre-dotfiles"
    cp -a "$1/$f" "$dst"
  done
}

echo "== configs"
place "$R/config" "$HOME/.config"
echo "== scripts"
place "$R/local/bin" "$HOME/.local/bin"

echo "== third-party plugins"
P=$HOME/.config/omarchy/plugins
[ -d "$P/zed.shanshui" ] || git clone https://github.com/zednaked/omarchy-shanshui "$P/zed.shanshui"
[ -d "$P/io.github.moizibnyousaf.omawhatsapp" ] || git clone https://github.com/MoizIbnYousaf/Omarchy-Whatsapp "$P/io.github.moizibnyousaf.omawhatsapp"
git -C "$P/io.github.moizibnyousaf.omawhatsapp" apply "$R/patches/omawhatsapp.patch" 2>/dev/null \
  && echo "omawhatsapp patch applied" || echo "omawhatsapp patch skipped (already applied or upstream changed)"

echo "== Panacea (optional, off by default: panacea-mode on)"
if [ ! -d "$HOME/.config/panacea" ]; then
  tmp=$(mktemp -d)
  git clone https://github.com/EnsixD/Panacea "$tmp/Panacea"
  git -C "$tmp/Panacea" checkout 8636001 2>/dev/null || true
  cp -a "$tmp/Panacea/panacea" "$HOME/.config/panacea"
  (cd "$HOME/.config/panacea" && patch -p1 < "$R/patches/panacea.patch") || echo "panacea patch did not apply cleanly"
  rm -rf "$tmp"
fi

if [[ " $* " == *" --packages "* ]]; then
  echo "== packages"
  omarchy pkg add $(cat "$R/packages/pacman.txt")
  omarchy pkg aur add $(cat "$R/packages/aur.txt")
fi

if [[ " $* " == *" --system "* ]]; then
  echo "== /etc tweaks"
  sudo cp -a /etc/bluetooth/main.conf /etc/bluetooth/main.conf.pre-dotfiles 2>/dev/null || true
  sudo cp "$R/system/etc/bluetooth/main.conf" /etc/bluetooth/main.conf
  sudo cp "$R/system/etc/modprobe.d/btusb-no-autosuspend.conf" /etc/modprobe.d/
fi

echo "== done. Now: omarchy theme set coppernight && omarchy restart shell"
