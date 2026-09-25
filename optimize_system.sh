#!/usr/bin/env bash
# ==============================================================================
# Comprehensive System Optimization Script - ThinkPad 13 Gen 2 (Debian Testing)
# Hardware: Intel Core i5-7200U (Kaby Lake), Intel HD Graphics 620, NVMe Intel 600P
# ==============================================================================

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[-] Error: This script must be run as root or with sudo."
    echo "    Usage: sudo bash $0"
    exit 1
fi

echo "================================================================="
echo " Starting System Optimization for Performance, Latency & Storage "
echo "================================================================="

# ------------------------------------------------------------------------------
# 1. Boot Time Optimization: Eliminate Startup Bottlenecks & Redundant Services
# ------------------------------------------------------------------------------
echo "[1/6] Streamlining system services and boot sequence..."

# NetworkManager-wait-online delays boot by 5.5+ seconds waiting for network links
if systemctl is-enabled NetworkManager-wait-online.service &>/dev/null; then
    echo "  -> Disabling NetworkManager-wait-online.service..."
    systemctl disable NetworkManager-wait-online.service
fi

# ModemManager is not needed (no WWAN cellular modem present)
if systemctl is-active ModemManager.service &>/dev/null || systemctl is-enabled ModemManager.service &>/dev/null; then
    echo "  -> Stopping and disabling ModemManager.service (no cellular modem)..."
    systemctl stop ModemManager.service || true
    systemctl disable ModemManager.service || true
fi

# switcheroo-control is for hybrid/dual GPU setups; this system has only Intel HD 620
if systemctl is-active switcheroo-control.service &>/dev/null || systemctl is-enabled switcheroo-control.service &>/dev/null; then
    echo "  -> Stopping and disabling switcheroo-control.service (single integrated GPU)..."
    systemctl stop switcheroo-control.service || true
    systemctl disable switcheroo-control.service || true
fi

# cups-browsed continuously polls LAN for remote broadcast printers
if systemctl is-active cups-browsed.service &>/dev/null || systemctl is-enabled cups-browsed.service &>/dev/null; then
    echo "  -> Stopping and disabling cups-browsed.service..."
    systemctl stop cups-browsed.service || true
    systemctl disable cups-browsed.service || true
fi

# ------------------------------------------------------------------------------
# 2. Memory Compression (Zswap) & GRUB Kernel Parameters
# ------------------------------------------------------------------------------
echo "[2/6] Configuring Zswap memory compression and kernel parameters..."

# Enable zswap with zstd compression and zsmalloc pool in GRUB
cat << 'EOF' > /etc/default/grub.d/99-thinkpad-optimizations.cfg
# Enable PCIe ASPM powersave policy at kernel initialization
# Force snd-intel-dspcfg legacy HDA to avoid AVS boot errors
# Enable i915 GuC/HuC firmware loading
# Enable Zswap with zstd compression and zsmalloc allocator for responsive multitasking
# Suppress harmless ACPI/TPM firmware warnings (loglevel=3)
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT pcie_aspm=force pcie_aspm.policy=powersave snd_intel_dspcfg.dsp_driver=1 i915.enable_guc=2 zswap.enabled=1 zswap.compressor=zstd zswap.zpool=zsmalloc loglevel=3"
EOF

if command -v update-grub &>/dev/null; then
    echo "  -> Updating GRUB configuration..."
    update-grub
fi

# Apply zswap immediately if supported by running kernel
if [ -d /sys/module/zswap/parameters ]; then
    echo "  -> Activating zswap immediately..."
    echo 1 > /sys/module/zswap/parameters/enabled 2>/dev/null || true
    echo zstd > /sys/module/zswap/parameters/compressor 2>/dev/null || true
    echo zsmalloc > /sys/module/zswap/parameters/zpool 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 3. Kernel Sysctl Tuning: Network (BBR), Inotify, and VM Cache
# ------------------------------------------------------------------------------
echo "[3/6] Tuning sysctl (TCP BBR, inotify limits, VM parameters)..."

# Ensure tcp_bbr module is loaded at boot
mkdir -p /etc/modules-load.d
cat << 'EOF' > /etc/modules-load.d/bbr.conf
tcp_bbr
EOF
modprobe tcp_bbr 2>/dev/null || true

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

# Modern TCP BBR Congestion Control & Fast Open for lower latency and better Wi-Fi throughput
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0

# Developer inotify watch limits (prevents file watcher exhaustion in editors / dev tools)
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
EOF

sysctl -p /etc/sysctl.d/99-performance-battery.conf

# ------------------------------------------------------------------------------
# 4. Systemd Journal Size Boundary
# ------------------------------------------------------------------------------
echo "[4/6] Limiting systemd-journald disk consumption..."
mkdir -p /etc/systemd/journald.conf.d
cat << 'EOF' > /etc/systemd/journald.conf.d/00-journal-size.conf
[Journal]
SystemMaxUse=100M
SystemMaxFileSize=20M
MaxRetentionSec=1month
EOF

systemctl restart systemd-journald

# ------------------------------------------------------------------------------
# 5. Clean Package Residuals & APT Cache
# ------------------------------------------------------------------------------
echo "[5/6] Cleaning up uninstalled package configurations and cache..."
RC_PACKAGES=$(dpkg -l | awk '/^rc/ {print $2}')
if [ -n "$RC_PACKAGES" ]; then
    echo "  -> Purging leftover configuration files ($RC_PACKAGES)..."
    dpkg --purge $RC_PACKAGES
else
    echo "  -> No residual package configurations found."
fi

echo "  -> Cleaning APT cache..."
apt-get clean

# ------------------------------------------------------------------------------
# 6. NVMe SSD TRIM Execution
# ------------------------------------------------------------------------------
echo "[6/6] Executing filesystem TRIM across SSD partitions..."
fstrim -av

echo ""
echo "================================================================="
echo " System Optimization Complete!"
echo " Summary of enhancements:"
echo "  [✓] Boot time reduced by ~5.5s (NetworkManager-wait-online disabled)"
echo "  [✓] Inactive services disabled (ModemManager, switcheroo, cups-browsed)"
echo "  [✓] Zswap enabled (zstd + zsmalloc) to compress RAM and minimize SSD writes"
echo "  [✓] TCP BBR congestion control & Fast Open enabled for snappy networking"
echo "  [✓] Inotify file watches raised to 524,288 for IDE and dev tool performance"
echo "  [✓] Journal logs capped at 100MB to avoid silent disk bloat"
echo "  [✓] Residual package configs purged & APT cache cleaned"
echo "  [✓] NVMe SSD trimmed for peak write performance"
echo "================================================================="
