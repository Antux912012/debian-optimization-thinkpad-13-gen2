#!/bin/bash
#
# CachyOS-Optimized Kernel Build Script
# Target: Lenovo ThinkPad 13 2nd Gen (i5-7200U Kaby Lake-U)
# Base: Debian Forky/Sid
#
# Usage:
#   ./build-kernel.sh              # Build with defaults (7.2.6)
#   ./build-kernel.sh 7.2.7        # Build a specific version
#   ./build-kernel.sh 7.3.1        # Build a different minor version
#
# CachyOS optimizations included:
#   - BORE scheduler (Burst-Oriented Response Enhancer)
#   - 1000 Hz timer frequency
#   - Full preemption (PREEMPT + DYNAMIC)
#   - Native march (-march=native for Kaby Lake)
#   - O3 compiler optimization
#   - BBR TCP congestion control (default)
#   - BFQ I/O scheduler
#   - ZSTD for ZSWAP and ZRAM
#   - MGLRU memory management
#   - ThinkPad-specific ACPI support
#   - Trimmed NR_CPUS (8)
#   - NUMA disabled (single-socket CPU)
#

set -euo pipefail

###############################################################################
# Configuration — edit these for your setup
###############################################################################
KERNEL_VERSION="${1:-7.2.6}"
KERNEL_MAJOR="${KERNEL_VERSION%%.*}"                          # e.g., 7
KERNEL_MINOR="${KERNEL_VERSION%.*}"                           # e.g., 7.2
BUILD_DIR="/home/antonio/kernel-build"
SRC_DIR="${BUILD_DIR}/linux-${KERNEL_VERSION}"
PATCHES_DIR="${BUILD_DIR}/patches"
CONFIGS_DIR="${BUILD_DIR}/configs"
OUTPUT_DIR="${BUILD_DIR}/output"
JOBS=$(( $(nproc) + 1 ))                                     # Use all cores + 1
LOCALVERSION="-cachyos-thinkpad13"
CACHYOS_PATCHES_REPO="https://raw.githubusercontent.com/CachyOS/kernel-patches/master"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*"; exit 1; }
step()  { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

###############################################################################
# Step 1: Download kernel source
###############################################################################
download_source() {
    step "Step 1: Downloading Linux ${KERNEL_VERSION} source"

    if [ -d "${SRC_DIR}" ]; then
        log "Source directory already exists: ${SRC_DIR}"
        log "Skipping download. Delete it to re-download."
        return 0
    fi

    local TARBALL="linux-${KERNEL_VERSION}.tar.xz"
    local URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/${TARBALL}"

    cd "${BUILD_DIR}"

    if [ ! -f "${TARBALL}" ]; then
        log "Downloading ${URL}..."
        wget --progress=dot:giga "${URL}" || error "Failed to download kernel source"
    else
        log "Tarball already exists, skipping download."
    fi

    log "Extracting ${TARBALL}..."
    tar xf "${TARBALL}"
    log "Source extracted to ${SRC_DIR}"
}

###############################################################################
# Step 2: Download CachyOS patches
###############################################################################
download_patches() {
    step "Step 2: Downloading CachyOS patches for ${KERNEL_MINOR}"

    cd "${PATCHES_DIR}"

    # BORE scheduler patch (CachyOS-tuned variant)
    local BORE_PATCH="0001-bore-cachy.patch"
    if [ ! -f "${BORE_PATCH}" ]; then
        log "Downloading BORE scheduler patch..."
        wget -q "${CACHYOS_PATCHES_REPO}/${KERNEL_MINOR}/sched/${BORE_PATCH}" \
            -O "${BORE_PATCH}" || warn "BORE patch download failed — will use EEVDF defaults"
    else
        log "BORE patch already downloaded."
    fi

    # ACPI-call patch (ThinkPad battery threshold control)
    local ACPI_PATCH="0001-acpi-call.patch"
    if [ ! -f "${ACPI_PATCH}" ]; then
        log "Downloading ACPI-call patch..."
        wget -q "${CACHYOS_PATCHES_REPO}/${KERNEL_MINOR}/misc/${ACPI_PATCH}" \
            -O "${ACPI_PATCH}" || warn "ACPI-call patch download failed — non-critical"
    else
        log "ACPI-call patch already downloaded."
    fi

    log "Patches downloaded to ${PATCHES_DIR}"
    ls -la "${PATCHES_DIR}"/*.patch 2>/dev/null || true
}

###############################################################################
# Step 3: Apply patches
###############################################################################
apply_patches() {
    step "Step 3: Applying CachyOS patches"

    cd "${SRC_DIR}"

    for patch in "${PATCHES_DIR}"/*.patch; do
        [ -f "$patch" ] || continue
        local pname=$(basename "$patch")

        # Check if already applied or fails
        if patch -p1 -N --dry-run --silent < "$patch" &>/dev/null; then
            log "Applying patch: ${pname}..."
            patch -p1 -N --silent < "$patch" || warn "Patch failed: ${pname} — continuing anyway"
        else
            log "Patch already applied or fails to apply: ${pname} — skipping"
        fi
    done
}

###############################################################################
# Step 4: Generate optimized kernel config
###############################################################################
generate_config() {
    step "Step 4: Generating CachyOS-optimized kernel config"

    cd "${SRC_DIR}"

    # Start from current running kernel's config
    if [ -f "/boot/config-$(uname -r)" ]; then
        log "Using running kernel config as base: /boot/config-$(uname -r)"
        cp "/boot/config-$(uname -r)" .config
    else
        error "Cannot find running kernel config at /boot/config-$(uname -r)"
    fi

    # Update config for new kernel version (accept defaults for new options)
    log "Running 'make olddefconfig' to update config..."
    make olddefconfig

    # Apply CachyOS-style optimizations via scripts/config
    log "Applying CachyOS performance optimizations..."

    #---------------------------------------------------------------------------
    # Timer and Scheduling
    #---------------------------------------------------------------------------
    # 1000 Hz timer for lowest latency
    scripts/config --disable CONFIG_HZ_100
    scripts/config --disable CONFIG_HZ_250
    scripts/config --disable CONFIG_HZ_300
    scripts/config --enable  CONFIG_HZ_1000
    scripts/config --set-val CONFIG_HZ 1000

    # Full preemption for best desktop responsiveness
    scripts/config --enable  CONFIG_PREEMPT
    scripts/config --disable CONFIG_PREEMPT_VOLUNTARY
    scripts/config --disable CONFIG_PREEMPT_NONE
    scripts/config --disable CONFIG_PREEMPT_LAZY
    scripts/config --enable  CONFIG_PREEMPT_DYNAMIC
    scripts/config --enable  CONFIG_PREEMPT_BUILD
    scripts/config --enable  CONFIG_PREEMPTION
    scripts/config --enable  CONFIG_PREEMPT_COUNT
    scripts/config --enable  CONFIG_PREEMPT_RCU

    # Scheduler features
    scripts/config --enable  CONFIG_SCHED_AUTOGROUP
    scripts/config --enable  CONFIG_SCHED_OMIT_FRAME_POINTER

    # No tickless idle (full dynamic ticks can hurt on laptops)
    scripts/config --enable  CONFIG_NO_HZ_IDLE
    scripts/config --disable CONFIG_NO_HZ_FULL

    #---------------------------------------------------------------------------
    # Compiler Optimizations
    #---------------------------------------------------------------------------
    # O3 optimization (CachyOS-style aggressive optimization)
    scripts/config --disable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE
    scripts/config --disable CONFIG_CC_OPTIMIZE_FOR_SIZE
    scripts/config --enable  CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3 \
        2>/dev/null || true  # May need BORE patch to expose this option

    #---------------------------------------------------------------------------
    # CPU Architecture — Kaby Lake native
    #---------------------------------------------------------------------------
    # Reduce NR_CPUS from 8192 to 8 (your laptop has 2C/4T)
    scripts/config --set-val CONFIG_NR_CPUS 8

    # Disable NUMA (single-socket, wasted overhead)
    scripts/config --disable CONFIG_NUMA
    scripts/config --disable CONFIG_NUMA_BALANCING
    scripts/config --disable CONFIG_NUMA_EMU

    # Disable SMT scheduling extensions we don't need
    scripts/config --enable  CONFIG_SCHED_SMT
    scripts/config --enable  CONFIG_SCHED_MC

    #---------------------------------------------------------------------------
    # Networking — BBR congestion control
    #---------------------------------------------------------------------------
    scripts/config --enable  CONFIG_TCP_CONG_BBR
    scripts/config --set-str CONFIG_DEFAULT_TCP_CONG "bbr"
    scripts/config --enable  CONFIG_TCP_CONG_ADVANCED

    # Enable CAKE qdisc for traffic shaping
    scripts/config --module   CONFIG_NET_SCH_CAKE
    scripts/config --enable   CONFIG_NET_SCH_FQ_CODEL

    #---------------------------------------------------------------------------
    # I/O Scheduler — BFQ for responsive desktop I/O
    #---------------------------------------------------------------------------
    scripts/config --enable  CONFIG_MQ_IOSCHED_BFQ
    scripts/config --enable  CONFIG_BFQ_GROUP_IOSCHED
    scripts/config --set-str CONFIG_DEFAULT_IOSCHED "bfq" 2>/dev/null || true

    #---------------------------------------------------------------------------
    # Memory Management — CachyOS-style
    #---------------------------------------------------------------------------
    # MGLRU (already enabled in Debian, ensure it stays)
    scripts/config --enable  CONFIG_LRU_GEN
    scripts/config --enable  CONFIG_LRU_GEN_ENABLED

    # Transparent Hugepages: madvise (avoid THP overhead for small apps)
    scripts/config --disable CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS
    scripts/config --enable  CONFIG_TRANSPARENT_HUGEPAGE_MADVISE

    # ZSWAP with ZSTD compression, enabled by default
    scripts/config --enable  CONFIG_ZSWAP
    scripts/config --enable  CONFIG_ZSWAP_DEFAULT_ON
    scripts/config --disable CONFIG_ZSWAP_COMPRESSOR_DEFAULT_LZO
    scripts/config --enable  CONFIG_ZSWAP_COMPRESSOR_DEFAULT_ZSTD
    scripts/config --set-str CONFIG_ZSWAP_COMPRESSOR_DEFAULT "zstd"

    # ZRAM with ZSTD
    scripts/config --module  CONFIG_ZRAM
    scripts/config --disable CONFIG_ZRAM_DEF_COMP_LZ4
    scripts/config --enable  CONFIG_ZRAM_DEF_COMP_ZSTD
    scripts/config --set-str CONFIG_ZRAM_DEF_COMP "zstd"
    scripts/config --enable  CONFIG_ZRAM_BACKEND_ZSTD
    scripts/config --enable  CONFIG_ZRAM_BACKEND_LZ4
    scripts/config --enable  CONFIG_ZRAM_WRITEBACK

    # Ensure ZSTD crypto is built-in
    scripts/config --enable  CONFIG_CRYPTO_ZSTD
    scripts/config --enable  CONFIG_CRYPTO_LZ4

    #---------------------------------------------------------------------------
    # ThinkPad-specific
    #---------------------------------------------------------------------------
    scripts/config --module  CONFIG_THINKPAD_ACPI
    scripts/config --enable  CONFIG_THINKPAD_ACPI_ALSA_SUPPORT
    scripts/config --enable  CONFIG_THINKPAD_ACPI_VIDEO
    scripts/config --enable  CONFIG_THINKPAD_ACPI_HOTKEY_POLL

    # Intel power management
    scripts/config --enable  CONFIG_X86_INTEL_PSTATE
    scripts/config --enable  CONFIG_INTEL_IDLE
    scripts/config --enable  CONFIG_CPU_FREQ_GOV_SCHEDUTIL
    scripts/config --enable  CONFIG_CPU_FREQ_GOV_POWERSAVE
    scripts/config --enable  CONFIG_CPU_FREQ_GOV_PERFORMANCE
    scripts/config --enable  CONFIG_CPU_FREQ_GOV_ONDEMAND
    scripts/config --module  CONFIG_CPU_FREQ_GOV_CONSERVATIVE

    # Intel GPU
    scripts/config --module  CONFIG_DRM_I915

    # Intel audio
    scripts/config --module  CONFIG_SND_HDA_INTEL
    scripts/config --module  CONFIG_SND_SOC_INTEL_SKL
    
    # Disable SND_PCSP to prevent "Driver 'pcspkr' is already registered" boot error
    scripts/config --disable CONFIG_SND_PCSP

    # Intel WiFi
    scripts/config --module  CONFIG_IWLWIFI
    scripts/config --module  CONFIG_IWLMVM

    # Intel NVMe
    scripts/config --module  CONFIG_NVME_CORE
    scripts/config --module  CONFIG_BLK_DEV_NVME

    # Intel Ethernet
    scripts/config --module  CONFIG_E1000E

    #---------------------------------------------------------------------------
    # Misc CachyOS optimizations
    #---------------------------------------------------------------------------
    # Kernel compression with ZSTD (fastest decompression)
    scripts/config --disable CONFIG_KERNEL_GZIP
    scripts/config --disable CONFIG_KERNEL_BZIP2
    scripts/config --disable CONFIG_KERNEL_LZMA
    scripts/config --disable CONFIG_KERNEL_XZ
    scripts/config --disable CONFIG_KERNEL_LZO
    scripts/config --disable CONFIG_KERNEL_LZ4
    scripts/config --enable  CONFIG_KERNEL_ZSTD

    # Module compression with ZSTD
    scripts/config --enable  CONFIG_MODULE_COMPRESS_ZSTD
    scripts/config --disable CONFIG_MODULE_COMPRESS_NONE
    scripts/config --disable CONFIG_MODULE_COMPRESS_GZIP
    scripts/config --disable CONFIG_MODULE_COMPRESS_XZ

    # Disable debug info to reduce package size massively
    scripts/config --disable CONFIG_DEBUG_INFO
    scripts/config --disable CONFIG_DEBUG_INFO_DWARF5
    scripts/config --disable CONFIG_DEBUG_INFO_DWARF4
    scripts/config --disable CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
    scripts/config --enable  CONFIG_DEBUG_INFO_NONE

    # Disable other debug features
    scripts/config --disable CONFIG_SLUB_DEBUG
    scripts/config --disable CONFIG_DEBUG_MISC
    scripts/config --disable CONFIG_FTRACE
    scripts/config --disable CONFIG_FUNCTION_TRACER
    scripts/config --disable CONFIG_STACK_TRACER
    scripts/config --disable CONFIG_SCHED_DEBUG
    scripts/config --disable CONFIG_DEBUG_PREEMPT
    scripts/config --disable CONFIG_KPROBES

    # Localversion
    scripts/config --set-str CONFIG_LOCALVERSION "${LOCALVERSION}"

    # Enable kernel signing for Secure Boot
    scripts/config --enable CONFIG_MODULE_SIG
    scripts/config --enable CONFIG_MODULE_SIG_ALL
    scripts/config --enable CONFIG_MODULE_SIG_FORCE
    scripts/config --set-str CONFIG_MODULE_SIG_KEY "/home/antonio/kernel-build/MOK_with_key.pem"
    scripts/config --enable CONFIG_SYSTEM_TRUSTED_KEYRING
    scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS "/home/antonio/kernel-build/MOK.pem"
    scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
    scripts/config --disable CONFIG_SYSTEM_REVOCATION_LIST

    # Final olddefconfig to resolve any dependencies
    log "Resolving config dependencies..."
    make olddefconfig

    # Save a copy of the final config
    cp .config "${CONFIGS_DIR}/config-${KERNEL_VERSION}${LOCALVERSION}"
    log "Config saved to ${CONFIGS_DIR}/config-${KERNEL_VERSION}${LOCALVERSION}"
}

###############################################################################
# Step 5: Build kernel and .deb packages
###############################################################################
build_kernel() {
    step "Step 5: Building kernel (this will take a while...)"

    cd "${SRC_DIR}"

    log "Starting compilation with ${JOBS} jobs..."
    log "Estimated time: 1.5-3 hours on i5-7200U"
    echo ""

    # Build .deb packages directly
    # This creates:
    #   linux-image-<version>.deb       — kernel image + modules
    #   linux-headers-<version>.deb     — headers for DKMS
    #   linux-libc-dev-<version>.deb    — libc headers
    nice -n 10 make -j${JOBS} \
        KCFLAGS="-O3 -march=native" \
        KDEB_PKGVERSION="1.0-cachyos" \
        bindeb-pkg 2>&1 | tee "${BUILD_DIR}/build.log"

    log "Build complete!"
}

###############################################################################
# Step 6: Collect output
###############################################################################
collect_output() {
    step "Step 6: Collecting output packages"

    cd "${BUILD_DIR}"

    # Move .deb files to output directory
    mv -f linux-image-*.deb "${OUTPUT_DIR}/" 2>/dev/null || true
    mv -f linux-headers-*.deb "${OUTPUT_DIR}/" 2>/dev/null || true
    mv -f linux-libc-dev*.deb "${OUTPUT_DIR}/" 2>/dev/null || true

    log "Output packages:"
    ls -lh "${OUTPUT_DIR}"/*.deb 2>/dev/null || warn "No .deb packages found"

    # Copy final config
    cp "${SRC_DIR}/.config" "${CONFIGS_DIR}/config-${KERNEL_VERSION}${LOCALVERSION}-final"

    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "  BUILD COMPLETE!"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""
    log "Install the kernel with:"
    log "  sudo dpkg -i ${OUTPUT_DIR}/linux-image-*.deb"
    log "  sudo dpkg -i ${OUTPUT_DIR}/linux-headers-*.deb"
    log ""
    log "Reboot and select the new kernel from GRUB."
    log ""
    log "To rebuild for a new version:"
    log "  ./build-kernel.sh 7.2.7"
    log ""
}

###############################################################################
# Main
###############################################################################
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  CachyOS-Optimized Kernel Build                        ║"
    echo "║  Target: ThinkPad 13 2nd Gen (i5-7200U)                ║"
    echo "║  Kernel: Linux ${KERNEL_VERSION}                              ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    download_source
    download_patches
    apply_patches
    generate_config
    build_kernel
    collect_output
}

main "$@"
