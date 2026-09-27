# CachyOS-Optimized Kernel for ThinkPad 13 2nd Gen

Custom Linux kernel build with CachyOS performance patches, optimized specifically
for the Lenovo ThinkPad 13 2nd Gen (i5-7200U Kaby Lake).

## What's Included

### CachyOS Patches Applied
- **BORE Scheduler** (`0001-bore-cachy.patch`) — Burst-Oriented Response Enhancer
  on top of EEVDF for best desktop interactivity
- **ACPI-Call** (`0001-acpi-call.patch`) — ThinkPad battery threshold control

### Kernel Config Optimizations
| Feature | Setting | Purpose |
|:---|:---|:---|
| Timer Frequency | 1000 Hz | Lowest latency, smoothest desktop |
| Preemption | Full PREEMPT + DYNAMIC | Best responsiveness |
| CPU Architecture | Native (march=native) | Kaby Lake-specific code generation |
| Compiler | -O3 | Aggressive optimization |
| TCP Congestion | BBR (default) | Better network throughput |
| I/O Scheduler | BFQ | Fair I/O for desktop use |
| ZSWAP | ZSTD, default ON | Better memory compression |
| ZRAM | ZSTD default | Better swap compression |
| Kernel Compression | ZSTD | Fast boot decompression |
| Debug Info | Disabled | Much smaller packages |
| NR_CPUS | 8 | Reduced memory footprint |
| NUMA | Disabled | Not needed on single-socket |
| THP | madvise | Avoids overhead on small apps |
| MGLRU | Enabled | Multi-Gen LRU for better memory mgmt |

## Installation

```bash
# Install the kernel image and headers
sudo dpkg -i output/linux-image-*.deb
sudo dpkg -i output/linux-headers-*.deb

# Update GRUB
sudo update-grub

# Reboot
sudo reboot
```

After rebooting, select the new kernel in the GRUB menu. Verify with:
```bash
uname -r
# Should show: 7.2.6-cachyos-thinkpad13
```

## Rebuilding for a New Kernel Version

When a new kernel version is released:

```bash
cd ~/kernel-build

# 1. Clean old source (optional, saves disk space)
rm -rf linux-7.2.6

# 2. Update patches (they're version-specific)
cd patches
rm -f *.patch
wget https://raw.githubusercontent.com/CachyOS/kernel-patches/master/7.2/sched/0001-bore-cachy.patch
wget https://raw.githubusercontent.com/CachyOS/kernel-patches/master/7.2/misc/0001-acpi-call.patch
cd ..

# 3. Build the new version
./build-kernel.sh 7.2.7    # or whatever version
```

### For a New Major Version (e.g., 7.3.x)

```bash
cd ~/kernel-build/patches

# Download patches for the new major version
rm -f *.patch
wget https://raw.githubusercontent.com/CachyOS/kernel-patches/master/7.3/sched/0001-bore-cachy.patch
wget https://raw.githubusercontent.com/CachyOS/kernel-patches/master/7.3/misc/0001-acpi-call.patch

# Edit build-kernel.sh if needed, or just pass the version:
./build-kernel.sh 7.3.1
```

## Rolling Back

If the new kernel causes issues:
```bash
# Boot into the old kernel from GRUB's Advanced Options menu
# Then remove the custom kernel
sudo dpkg -r linux-image-7.2.6-cachyos-thinkpad13
sudo update-grub
```

## Directory Structure

```
~/kernel-build/
├── build-kernel.sh          # Main build script (reusable)
├── linux-7.2.6/             # Kernel source tree (can be deleted after build)
├── linux-7.2.6.tar.xz       # Downloaded source tarball
├── patches/                  # CachyOS patches
│   ├── 0001-bore-cachy.patch
│   └── 0001-acpi-call.patch
├── configs/                  # Saved kernel configs
│   ├── config-7.2.6-cachyos-thinkpad13       # Pre-build config
│   └── config-7.2.6-cachyos-thinkpad13-final # Post-build config
├── output/                   # Built .deb packages
│   ├── linux-image-7.2.6-cachyos-thinkpad13_*.deb
│   ├── linux-headers-7.2.6-cachyos-thinkpad13_*.deb
│   └── linux-libc-dev_*.deb
├── build.log                 # Full build log
└── README.md                 # This file
```

## Distributing

To install this kernel on another identical ThinkPad 13 2nd Gen:
```bash
# Copy the .deb files to the target machine, then:
sudo dpkg -i linux-image-*.deb linux-headers-*.deb
sudo update-grub
sudo reboot
```

> **Note:** These packages are compiled with `-march=native` for the i5-7200U
> (Kaby Lake). They will work on any Kaby Lake CPU but may not work on older CPUs.

## Build Requirements

```bash
sudo apt-get install -y build-essential bc kmod cpio flex libncurses5-dev \
    libelf-dev libssl-dev dwarves bison lz4 rsync zstd debhelper fakeroot \
    wget git python3
```
