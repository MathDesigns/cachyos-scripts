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

# A subshell keeps traps and temporary state local to this installation step.
install_tidaluna() (
    local temp_dir="" transaction_dir="" committed=0 rollback_failed=0 publish_started=0

    cleanup_tidaluna() {
        local status=$?
        trap - EXIT HUP INT TERM
        if [ -n "$transaction_dir" ]; then
            if [ "$committed" -eq 0 ]; then
                if [ "$publish_started" -eq 1 ] && sudo test ! -e "$transaction_dir/new-app"; then
                    sudo rm -rf -- "$TIDAL_RES/app" || rollback_failed=1
                fi
                # Look for saved files rather than flags: a signal may arrive
                # immediately after a successful move.
                if sudo test -e "$transaction_dir/previous-app"; then
                    sudo mv -T -- "$transaction_dir/previous-app" "$TIDAL_RES/app" || rollback_failed=1
                fi
                if sudo test -e "$transaction_dir/previous.asar"; then
                    sudo mv -T -- "$transaction_dir/previous.asar" "$TIDAL_RES/app.asar" || rollback_failed=1
                fi
            fi
            if [ "$rollback_failed" -eq 1 ]; then
                echo "    -> Rollback failed; recovery files retained at $transaction_dir" >&2
                status=1
            else
                sudo rm -rf -- "$transaction_dir" || {
                    echo "    -> Could not clean staging directory: $transaction_dir" >&2
                }
            fi
        fi
        if [ -n "$temp_dir" ]; then
            rm -rf -- "$temp_dir" || echo "    -> Could not clean download directory: $temp_dir" >&2
        fi
        exit "$status"
    }
    trap cleanup_tidaluna EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if [ ! -d "$TIDAL_RES" ]; then
        echo -e "${YELLOW}    -> Tidal directory not found.${NC}"
        return 0
    fi
    temp_dir=$(mktemp -d) || return 1
    echo "    -> Downloading Luna..."
    curl --fail --location --show-error -o "$temp_dir/luna.zip" \
        https://github.com/Inrixia/TidaLuna/releases/latest/download/luna.zip || return 1
    unzip -tq "$temp_dir/luna.zip" || return 1

    echo "    -> Extracting..."
    mkdir -- "$temp_dir/app" || return 1
    unzip -q "$temp_dir/luna.zip" -d "$temp_dir/app" || return 1
    # Reject empty archives and archives with an unexpected top-level layout.
    if [ ! -s "$temp_dir/app/package.json" ]; then
        echo "    -> Luna archive is missing package.json." >&2
        return 1
    fi

    # Stage on the target filesystem before touching any installed files.
    transaction_dir=$(sudo mktemp -d "$TIDAL_RES/.tidaluna.XXXXXX") || return 1
    sudo cp -a -- "$temp_dir/app" "$transaction_dir/new-app" || return 1
    sudo chown -R root:root -- "$transaction_dir/new-app" || return 1

    # Copy the pristine backup first; never overwrite an existing original.
    if [ -f "$TIDAL_RES/app.asar" ] && [ ! -e "$TIDAL_RES/original.asar" ]; then
        echo "    -> Creating backup..."
        sudo cp -a -- "$TIDAL_RES/app.asar" "$transaction_dir/original.asar" || return 1
        sudo mv -T -- "$transaction_dir/original.asar" "$TIDAL_RES/original.asar" || return 1
    fi
    if [ -e "$TIDAL_RES/app" ]; then
        sudo mv -T -- "$TIDAL_RES/app" "$transaction_dir/previous-app" || return 1
    fi
    if [ -e "$TIDAL_RES/app.asar" ]; then
        sudo mv -T -- "$TIDAL_RES/app.asar" "$transaction_dir/previous.asar" || return 1
    fi
    publish_started=1
    sudo mv -T -- "$transaction_dir/new-app" "$TIDAL_RES/app" || return 1
    committed=1
    echo -e "${GREEN}    -> TidaLuna Patched.${NC}"
)

if ! install_tidaluna; then
    echo -e "${RED}    -> TidaLuna installation failed. Check the errors above.${NC}" >&2
    exit 1
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