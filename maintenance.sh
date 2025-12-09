#!/bin/bash

# --- CachyOS Maintenance Script ---
# 1. Ranks Mirrors (Speed)
# 2. Updates System (Repo)
# 3. Updates AUR
# 4. Updates Flatpaks
# ----------------------------------

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BLUE}::: Starting System Maintenance...${NC}"

# 1. Optimize Mirrors
echo -e "${BLUE}::: Ranking CachyOS Mirrors...${NC}"
if command -v cachyos-rate-mirrors &> /dev/null; then
    sudo cachyos-rate-mirrors
else
    echo "cachyos-rate-mirrors not found, skipping..."
fi

# 2. Update System & AUR
echo -e "${BLUE}::: Updating System & AUR...${NC}"
paru -Syu

# 3. Update Flatpaks
if command -v flatpak &> /dev/null; then
    echo -e "${BLUE}::: Updating Flatpaks...${NC}"
    flatpak update
fi

echo -e "${GREEN}::: Maintenance Complete! System is up to date. Reboot if asked${NC}"