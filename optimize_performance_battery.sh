#!/usr/bin/env bash
# ==============================================================================
# ThinkPad 13 Gen 2 (Debian) - Balanced Performance & Battery Optimization Script
# Hardware: Intel Core i5-7200U (Kaby Lake), Intel HD Graphics 620, NVMe SSD (Intel 600P)
# ==============================================================================

set -euo pipefail

# Ensure script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "[-] Error: This script must be run with sudo or as root."
    echo "    Usage: sudo bash $0"
    exit 1
fi

echo "=========================================================="
echo " Starting System Optimization for Performance & Battery..."
echo "=========================================================="

# 1. Update package lists and install required drivers / daemons
echo "[1/7] Installing required drivers and management daemons..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    intel-media-va-driver \
    vainfo \
    thermald \
    powertop

# Enable and start thermald (Intel Dynamic Platform and Thermal Framework)
systemctl enable --now thermald.service

# 2. Configure Intel Graphics (i915)
# - Enable Framebuffer Compression (FBC) for power saving
# - Disable Panel Self Refresh (PSR=0) to prevent Kaby Lake boot errors & display flicker
# - Enable GuC/HuC firmware loading (enable_guc=2) for hardware video decode offload
echo "[2/7] Configuring Intel HD Graphics 620 features..."
cat << 'EOF' > /etc/modprobe.d/i915-power.conf
# Framebuffer Compression enabled, PSR disabled (prevents Kaby Lake DRM errors & flicker)
# GuC/HuC enabled (offloads media & power management to GPU microcontroller)
options i915 enable_fbc=1 enable_psr=0 enable_guc=2
EOF

# 3. Optimize Audio Power Management & Fix Driver Probing
# Sunrise Point-LP PCH has 3 competing drivers (snd_hda_intel, snd_soc_avs, snd_sof).
# Forcing dsp_driver=1 prevents snd_soc_avs DSP probe failure errors at boot.
echo "[3/7] Configuring Audio power saving and DSP driver..."
cat << 'EOF' > /etc/modprobe.d/audio-power.conf
# Power down audio codec after 1s idle
options snd_hda_intel power_save=1 power_save_controller=Y
# Force legacy HDA driver to eliminate AVS / SOF probe failures at boot
options snd-intel-dspcfg dsp_driver=1
EOF

# 4. Optimize Virtual Memory & Kernel Wakeups (Sysctl)
echo "[4/7] Tuning sysctl parameters for NVMe responsiveness & battery..."
cat << 'EOF' > /etc/sysctl.d/99-performance-battery.conf
# Balanced memory swapping: avoid unnecessary NVMe wear and disk wakeups
vm.swappiness = 15

# Keep file system cache (directory/inode trees) in RAM for snappy desktop feel
vm.vfs_cache_pressure = 50

# Flusher thread interval: 15s instead of 5s to let drives stay in low-power state
vm.dirty_writeback_centisecs = 1500
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# Disable NMI watchdog: eliminates periodic CPU wakeups on all cores, enabling C8-C10 states
kernel.nmi_watchdog = 0
EOF

# Apply sysctl settings immediately
sysctl -p /etc/sysctl.d/99-performance-battery.conf

# 5. Optimize Wi-Fi Power Management
echo "[5/7] Enabling Wi-Fi power saving in NetworkManager..."
mkdir -p /etc/NetworkManager/conf.d
cat << 'EOF' > /etc/NetworkManager/conf.d/default-wifi-powersave.conf
[connection]
# 3 = enable Wi-Fi power saving (Intel 8265)
wifi.powersave = 3
EOF

# 6. Configure Udev Rules for Runtime Power Management
# - Exclude Intel SSD 600P (8086:f1a5) to prevent NVMe controller timeouts
# - Exclude LPSS I2C controller (8086:9d60) to prevent TrackPoint/touchpad latency
# - Exclude USB input devices (HID class 03) to prevent keyboard/mouse input lag
echo "[6/7] Setting PCIe and USB Runtime PM udev rules..."
cat << 'EOF' > /etc/udev/rules.d/10-runtime-pm.rules
# Enable Runtime Power Management for PCI devices except Intel 600P SSD and LPSS I2C
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}!="0x8086", ATTR{power/control}="auto"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}!="0xf1a5", ATTR{device}!="0x9d60", ATTR{power/control}="auto"

# Enable USB autosuspend ONLY for non-input devices (preserves mouse & keyboard responsiveness)
ACTION=="add", SUBSYSTEM=="usb", ATTR{bInterfaceClass}!="03", TEST=="power/control", ATTR{power/control}="auto"
EOF

# Reload udev rules and trigger
udevadm control --reload
udevadm trigger --subsystem-match=pci --subsystem-match=usb 2>/dev/null || true

# 7. Configure GRUB Kernel Parameters for PCIe ASPM, GuC & Clean Boot
echo "[7/7] Configuring GRUB kernel parameters (PCIe ASPM, GuC, clean boot)..."
mkdir -p /etc/default/grub.d
cat << 'EOF' > /etc/default/grub.d/99-thinkpad-optimizations.cfg
# Enable PCIe ASPM powersave policy at kernel initialization
# Force snd-intel-dspcfg legacy HDA to avoid AVS boot errors
# Enable i915 GuC/HuC firmware loading
# Suppress harmless ACPI/TPM firmware warnings (loglevel=3)
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT pcie_aspm=force pcie_aspm.policy=powersave snd_intel_dspcfg.dsp_driver=1 i915.enable_guc=2 loglevel=3"
EOF

# Update GRUB configuration
if command -v update-grub &>/dev/null; then
    update-grub
fi

# Ensure user 'antonio' is in systemd-journal and adm groups for log diagnostics
if id "antonio" &>/dev/null; then
    usermod -aG adm,systemd-journal antonio || true
fi

echo ""
echo "=========================================================="
echo " Optimization completed successfully!"
echo " Summary of changes:"
echo "  - Intel VA-API hardware video acceleration driver installed"
echo "  - thermald daemon enabled (thermal/throttling balance)"
echo "  - i915: FBC enabled, PSR disabled (fixes boot errors & flicker), GuC/HuC enabled"
echo "  - Audio: snd-intel-dspcfg.dsp_driver=1 (fixes snd_soc_avs boot error)"
echo "  - PCIe ASPM: configured via GRUB (pcie_aspm=force pcie_aspm.policy=powersave)"
echo "  - Udev: safe Runtime PM excluding Intel 600P SSD and LPSS I2C"
echo "  - Sysctl: vm.swappiness=15 and nmi_watchdog=0 (deep C-states)"
echo "  - Wi-Fi 8265 power saving enabled"
echo "  - Log diagnosis: user antonio added to adm & systemd-journal"
echo "=========================================================="
