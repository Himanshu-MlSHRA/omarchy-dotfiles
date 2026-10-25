#!/bin/bash
# Copy this machine's Omarchy customizations into the repo.
# Re-run before every commit. Only copies; never touches the live system.
set -e
R=$(cd "$(dirname "$0")" && pwd)
C=$HOME/.config
EX=(--exclude='*.bak*' --exclude='*.orig*' --exclude='*-bak*' --exclude='*.genie*' --exclude='*-removed*'
    --exclude='*.nothing-removed*' --exclude='.git' --exclude='__pycache__')

cp_file() { mkdir -p "$R/$2"; cp -a "$1" "$R/$2/"; }

rm -rf "$R/config" "$R/local" "$R/system" "$R/patches" "$R/packages"

# Omarchy shell: your plugins (all anshu.*), theme, shell layout, hooks, branding
mkdir -p "$R/config/omarchy/plugins"
for p in "$C"/omarchy/plugins/anshu.*; do
  rsync -a "${EX[@]}" "$p" "$R/config/omarchy/plugins/"
done
rsync -a "${EX[@]}" --exclude='backgrounds' "$C/omarchy/themes/coppernight" "$R/config/omarchy/themes/"
cp_file "$C/omarchy/shell.json" config/omarchy
cp_file "$C/omarchy/shell.toml" config/omarchy
cp_file "$C/omarchy/extensions/omarchy-menu.jsonc" config/omarchy/extensions
cp_file "$C/omarchy/hooks/theme-set.d/theme-gtk-css.sh" config/omarchy/hooks/theme-set.d
rsync -a "$C/omarchy/branding/" "$R/config/omarchy/branding/"

# Hyprland (only the files that differ from Omarchy's defaults)
for f in autostart.lua bindings.lua looknfeel.lua monitors.lua; do cp_file "$C/hypr/$f" config/hypr; done

# Terminals, prompt, GTK
cp_file "$C/alacritty/alacritty.toml" config/alacritty
cp_file "$C/foot/foot.ini" config/foot
cp_file "$C/kitty/kitty.conf" config/kitty
cp_file "$C/ghostty/config" config/ghostty
cp_file "$C/starship.toml" config
for g in gtk-3.0 gtk-4.0; do [ -f "$C/$g/gtk.css" ] && cp_file "$C/$g/gtk.css" "config/$g"; done
cp_file "$C/spotify-flags.conf" config
cp_file "$C/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf" config/wireplumber/wireplumber.conf.d

# Panacea: your edits as a patch against the pristine copy you installed
mkdir -p "$R/patches"
(cd "$C" && diff -ruN -x '*.bak*' -x 'last_wifi_ssid' -x 'settings.json' panacea.orig-*/ panacea/ \
  | sed -E 's#panacea\.orig-[0-9]+/#a/#; s#^(\+\+\+ )panacea/#\1b/#' > "$R/patches/panacea.patch") || true
# Third-party plugins: your local patches only (the plugins come from their repos)
git -C "$C/omarchy/plugins/io.github.moizibnyousaf.omawhatsapp" diff > "$R/patches/omawhatsapp.patch"
git -C "$C/omarchy/plugins/zed.shanshui" diff > "$R/patches/shanshui.patch"
[ -s "$R/patches/shanshui.patch" ] || rm "$R/patches/shanshui.patch"

# Your scripts
mkdir -p "$R/local/bin"
cp -a "$HOME/.local/bin/panacea-mode" "$HOME/.local/bin/fp-chip" "$R/local/bin/"

# System-level tweaks (need sudo to install)
mkdir -p "$R/system/etc/bluetooth" "$R/system/etc/modprobe.d"
cp /etc/bluetooth/main.conf "$R/system/etc/bluetooth/"
cp /etc/modprobe.d/btusb-no-autosuspend.conf "$R/system/etc/modprobe.d/"

# Packages you added on top of Omarchy
mkdir -p "$R/packages"
cat /usr/share/omarchy/install/omarchy-*.packages | grep -v '^#' | awk '{print $1}' | sort -u > /tmp/omarchy-base.txt
# minus what the Omarchy installer itself puts down (boot, microcode, its own packages)
printf '%s\n' efibootmgr intel-ucode amd-ucode mkinitcpio omarchy omarchy-keyring omarchy-settings sudo usbutils \
  rtkit lib32-gcc-libs lib32-glibc openbsd-netcat >> /tmp/omarchy-base.txt
sort -u -o /tmp/omarchy-base.txt /tmp/omarchy-base.txt
pacman -Qqe | sort | comm -23 - /tmp/omarchy-base.txt | grep -vxF -f <(pacman -Qqm) > "$R/packages/pacman.txt" || true
pacman -Qqm > "$R/packages/aur.txt"
rm -f /tmp/omarchy-base.txt

echo "synced into $R"
