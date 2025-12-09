#!/bin/bash

# --- CachyOS FreshInstall Starter ---
# Shell: Fish (CachyOS Default)
# Hardware: NVIDIA RTX 4080
# Author: MathDesigns
# -----------------------------------------------

# --- Colors ---
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}::: Initializing CachyOS Fresh Setup...${NC}"

if [ "$EUID" -eq 0 ]; then
  echo -e "${RED}Stop! Run this as your normal user (not root).${NC}"
  exit 1
fi

# ------------------------------------------------------
# 1. SMART UPDATES
# ------------------------------------------------------

echo -e "${BLUE}::: Ranking Mirrors (Speed Boost)...${NC}"
sudo cachyos-rate-mirrors

echo -e "${BLUE}::: Syncing Repositories...${NC}"
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm archlinux-keyring cachyos-keyring

# ------------------------------------------------------
# 2. INSTALLATION
# ------------------------------------------------------
echo -e "${BLUE}::: Installing Power User Tools...${NC}"

REPO_PKGS=(
    # --- Apps ---
    "vesktop" "thunderbird" "firefox" "brave-bin"
    "docker" "docker-compose" "scrcpy" "solaar"

    # --- UX Upgrades ---
    "starship"
    "zoxide"
    "flatseal"
    "fzf"
    
    # --- Power User Tools ---
    "snapper"
    "snap-pac"
    "nvtop"
    "tealdeer"
    "scx-scheds"
    
    # --- Dev Tools ---
    "wget" "unzip" "curl"
)
paru -S --needed --noconfirm "${REPO_PKGS[@]}"

echo -e "${BLUE}::: Installing AUR Packages...${NC}"
AUR_PKGS=(
    "tidal-hifi-bin"
    "appimagelauncher"
    "localsend-bin"
    "vscodium-bin"
    "uefitool"
)
paru -S --needed --noconfirm "${AUR_PKGS[@]}"

if command -v flatpak &> /dev/null; then
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub "com.bambulab.BambuStudio"
fi

# ------------------------------------------------------
# 3. ADVANCED CONFIGURATION
# ------------------------------------------------------

# --- A. Snapper (Forced Config for Btrfs Assistant) ---
echo -e "${BLUE}::: Configuring Snapper...${NC}"

# 1. Ensure Config Exists
if [ ! -f /etc/snapper/configs/root ]; then
    sudo snapper -c root create-config / 2>/dev/null || true
fi

# 2. Force Configuration (Timeline & Limits)
sudo snapper -c root set-config TIMELINE_CREATE="yes"
sudo snapper -c root set-config TIMELINE_LIMIT_HOURLY="5"
sudo snapper -c root set-config TIMELINE_LIMIT_DAILY="7"
sudo snapper -c root set-config TIMELINE_LIMIT_WEEKLY="0"
sudo snapper -c root set-config TIMELINE_LIMIT_MONTHLY="0"
sudo snapper -c root set-config TIMELINE_LIMIT_YEARLY="0"
sudo snapper -c root set-config NUMBER_LIMIT="50"

# 3. Enable Systemd Timers
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer

# 4. Set Permissions
sudo chmod a+rx /.snapshots

echo -e "${GREEN}    -> Snapper Configured (Timeline & Cleanup Active).${NC}"

# --- B. Fish Shell Config ---
echo -e "${BLUE}::: Configuring Fish Shell...${NC}"
FISH_CONF="$HOME/.config/fish/config.fish"
mkdir -p "$HOME/.config/fish"

grep -qF "starship init fish" "$FISH_CONF" || echo 'starship init fish | source' >> "$FISH_CONF"
grep -qF "zoxide init fish" "$FISH_CONF" || echo 'zoxide init fish | source' >> "$FISH_CONF"
# Removed topgrade alias

tldr --update > /dev/null

# --- C. Vesktop RTX 4080 Flags ---
echo -e "${BLUE}::: Optimizing Vesktop...${NC}"
mkdir -p "$HOME/.config"
cat <<EOF > "$HOME/.config/vesktop-flags.conf"
--disable-features=WebRtcAllowInputVolumeAdjustment
--enable-features=VaapiVideoDecode
--use-gl=desktop
--enable-gpu-rasterization
--enable-zero-copy
EOF

# --- D. TidaLuna (Direct Method) ---
echo -e "${BLUE}::: Patching TidaLuna...${NC}"
TIDAL_RES="/opt/tidal-hifi/resources"
TEMP_DIR=$(mktemp -d)

if [ -d "$TIDAL_RES" ]; then
    echo "    -> Downloading Luna..."
    curl -L -o "$TEMP_DIR/luna.zip" https://github.com/Inrixia/TidaLuna/releases/latest/download/luna.zip
    
    # Backup
    if [ -f "$TIDAL_RES/app.asar" ] && [ ! -f "$TIDAL_RES/original.asar" ]; then
        echo "    -> Creating backup..."
        sudo mv "$TIDAL_RES/app.asar" "$TIDAL_RES/original.asar"
    fi

    # Clean & Install
    if [ -d "$TIDAL_RES/app" ]; then
        sudo rm -rf "$TIDAL_RES/app"
    fi
    
    echo "    -> Extracting..."
    sudo mkdir -p "$TIDAL_RES/app"
    sudo unzip -q -o "$TEMP_DIR/luna.zip" -d "$TIDAL_RES/app"
    
    echo -e "${GREEN}    -> TidaLuna Patched.${NC}"
    rm -rf "$TEMP_DIR"
else
    echo -e "${YELLOW}    -> Tidal directory not found.${NC}"
fi

# ------------------------------------------------------
# 4. FINAL HEALTH CHECKS
# ------------------------------------------------------
echo -e "${BLUE}::: Final Checks...${NC}"

sudo systemctl enable --now docker.service
if ! groups "$USER" | grep -q "docker"; then
    sudo usermod -aG docker "$USER"
    echo -e "${YELLOW}    -> Added user to Docker group. REBOOT REQUIRED.${NC}"
fi

if ! systemctl is-active --quiet fstrim.timer; then
    sudo systemctl enable --now fstrim.timer
fi

echo -e "${GREEN}=========================================="
echo " SYSTEM READY | REBOOT REQUIRED | Have fun using CachyOS"
echo "=========================================="