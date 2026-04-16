#!/bin/sh
# Extract vmlinux from a distro debug package
# Usage: extract-vmlinux <package-file> [output-dir]
#
# Supports:
#   .rpm          — Fedora, RHEL, CentOS, SUSE (kernel-debuginfo)
#   .deb / .ddeb  — Debian, Ubuntu (linux-image-*-dbg)
#   .pkg.tar.zst  — Arch Linux (linux-debug)

set -e

PKG="$1"
OUTDIR="${2:-/tmp/debuginfo}"

if [ -z "$PKG" ]; then
    echo "Usage: extract-vmlinux <package-file> [output-dir]"
    echo ""
    echo "Examples:"
    echo "  extract-vmlinux kernel-debuginfo-6.18.10-200.fc43.x86_64.rpm"
    echo "  extract-vmlinux linux-image-6.1.0-23-amd64-dbg_6.1.99-1_amd64.deb"
    echo "  extract-vmlinux linux-image-unsigned-6.8.0-41-generic-dbgsym_6.8.0-41.41_amd64.ddeb"
    echo "  extract-vmlinux linux-debug-6.9.1.arch1-1-x86_64.pkg.tar.zst"
    exit 1
fi

mkdir -p "$OUTDIR"

case "$PKG" in
    *.rpm)
        echo "[*] Extracting RPM: $PKG"
        cd "$OUTDIR"
        rpm2cpio "$PKG" | cpio -idmv 2>&1 | grep vmlinux || true
        ;;
    *.deb|*.ddeb)
        echo "[*] Extracting DEB: $PKG"
        cd "$OUTDIR"
        # .deb/.ddeb is an ar archive: debian-binary, control.tar.*, data.tar.*
        ar x "$PKG"
        # Extract the data archive
        if [ -f data.tar.xz ]; then
            tar xf data.tar.xz 2>&1 | grep vmlinux || true
        elif [ -f data.tar.zst ]; then
            zstd -d data.tar.zst -o data.tar
            tar xf data.tar 2>&1 | grep vmlinux || true
        elif [ -f data.tar.gz ]; then
            tar xzf data.tar.gz 2>&1 | grep vmlinux || true
        elif [ -f data.tar.bz2 ]; then
            tar xjf data.tar.bz2 2>&1 | grep vmlinux || true
        fi
        rm -f debian-binary control.tar.* data.tar*
        ;;
    *.pkg.tar.zst)
        echo "[*] Extracting Arch package: $PKG"
        cd "$OUTDIR"
        zstd -d "$PKG" --stdout | tar xv 2>&1 | grep vmlinux || true
        ;;
    *)
        echo "Unknown package format: $PKG"
        exit 1
        ;;
esac

# Search for vmlinux (exact) or vmlinux-* (Debian/Ubuntu naming)
VMLINUX=$(find "$OUTDIR" -name vmlinux -type f 2>/dev/null | head -1)
if [ -z "$VMLINUX" ]; then
    VMLINUX=$(find "$OUTDIR" -name 'vmlinux-*' -type f 2>/dev/null | head -1)
fi
if [ -n "$VMLINUX" ]; then
    echo ""
    echo "[+] Found: $VMLINUX"
    echo "[+] Size: $(du -h "$VMLINUX" | cut -f1)"
    echo ""
    echo "Next: generate-isf $VMLINUX"
else
    echo ""
    echo "[-] vmlinux not found in package"
    echo "    Extracted contents in: $OUTDIR"
fi
