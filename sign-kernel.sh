#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo."
  exit 1
fi

echo "Installing sbsigntool if missing..."
apt-get update && apt-get install -y sbsigntool

KERNEL="/boot/vmlinuz-7.2.6-cachyos-thinkpad13"
KEY="/home/antonio/kernel-build/MOK.priv"
CERT="/home/antonio/kernel-build/MOK.pem"

if [ ! -f "$KERNEL" ]; then
    echo "Kernel $KERNEL not found!"
    exit 1
fi

echo "Signing kernel image for Secure Boot..."
sbsign --key "$KEY" --cert "$CERT" "$KERNEL" --output "$KERNEL"

echo "Kernel successfully signed!"
