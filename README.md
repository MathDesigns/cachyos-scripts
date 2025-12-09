# 🚀 CachyOS Post-Install & Maintenance Toolkit

A collection of automated scripts to provision, configure, and maintain a high-performance **CachyOS (Arch Linux)** workstation. 

Tailored for **Software Development** and **Gaming** on NVIDIA hardware (RTX 4080).

## 📂 Scripts Included

### 1. `cachy-freshintall.sh` (The "One-Click" Setup)
The main provisioning script. Run this immediately after a fresh install.
* **Performance:** Ranks mirrors for speed, enables `scx` schedulers, and sets up `nvtop`.
* **Safety:** Configures **Snapper** + **Snap-pac** for automatic Btrfs snapshots on update.
* **Visuals:** Configures **Fish** shell with **Starship** prompt, **Zoxide**, and **Fzf**.
* **Patches:** * Injects **TidaLuna** theme into Tidal Hi-Fi.
    * Configures **Vesktop** with custom flags for RTX 40xx series (WebRTC volume fix + NVDEC).
* **Dev Tools:** Installs Docker (rootless setup), VSCodium, etc.

### 2. `maintenance.sh` (The Updater)
A robust maintenance utility to keep the system healthy.
* **Step 1:** Re-ranks CachyOS mirrors (ensures max download speed).
* **Step 2:** Updates System & AUR packages via `paru`.
* **Step 3:** Updates Flatpaks.

---

## 🛠️ Prerequisites

* **OS:** CachyOS
* **Shell:** Fish (Recommended/Default).
* **GPU:** NVIDIA (Script contains specific flags for RTX 40 series).
* **Filesystem:** Btrfs (Required for Snapper config).

## 🚀 Usage

### 1. Installation
Clone the repository:
```bash
git clone [https://github.com/mathMathDesigns/cachyos-scripts.git](https://github.com/MathDesigns/cachyos-scripts.git)
cd cachyos-scripts
chmod +x *.sh