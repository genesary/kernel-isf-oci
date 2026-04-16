#!/bin/sh
# Download kernel debug package for a given distro/version/kernel/arch.
# Usage: download-debuginfo <distro> <version> <kernel> <arch> [debug_url] [output-dir]
#
# If debug_url is provided, it is used directly. Otherwise the script
# attempts to resolve the package URL from well-known repositories.
#
# Supported distros: fedora, rhel, centos, debian, ubuntu, suse, arch

set -e

DISTRO="$1"
VERSION="$2"
KERNEL="$3"
ARCH="$4"
DEBUG_URL="$5"
OUTDIR="${6:-/tmp/debugpkg}"

if [ -z "$DISTRO" ] || [ -z "$VERSION" ] || [ -z "$KERNEL" ] || [ -z "$ARCH" ]; then
    echo "Usage: download-debuginfo <distro> <version> <kernel> <arch> [debug_url] [output-dir]"
    echo ""
    echo "Examples:"
    echo "  download-debuginfo fedora 43 6.18.10-200.fc43.x86_64 x86_64"
    echo "  download-debuginfo ubuntu 24.04 6.8.0-41-generic amd64"
    echo "  download-debuginfo debian 12 6.1.0-23-amd64 amd64"
    echo "  download-debuginfo centos 9-stream 5.14.0-362.el9.x86_64 x86_64"
    echo "  download-debuginfo suse 15.5 5.14.21-150500.55.31-default x86_64"
    echo "  download-debuginfo arch rolling 6.9.1.arch1-1 x86_64"
    exit 1
fi

mkdir -p "$OUTDIR"

# If a direct URL is provided, just download it
if [ -n "$DEBUG_URL" ]; then
    echo "[*] Downloading from provided URL: $DEBUG_URL"
    FILENAME=$(basename "$DEBUG_URL")
    curl -fSL -o "$OUTDIR/$FILENAME" "$DEBUG_URL"
    echo "[+] Downloaded: $OUTDIR/$FILENAME"
    exit 0
fi

echo "[*] Resolving debug package for $DISTRO $VERSION kernel $KERNEL ($ARCH)"

case "$DISTRO" in
    fedora)
        # Parse kernel version: 6.18.10-200.fc43.x86_64 → base=6.18.10 release=200.fc43
        KBASE=$(echo "$KERNEL" | sed "s/\\.${ARCH}\$//; s/-/./; s/\\./ /" | awk '{print $1}')
        KRELEASE=$(echo "$KERNEL" | sed "s/\\.${ARCH}\$//; s/^[^-]*-//")
        URL="https://kojipkgs.fedoraproject.org/packages/kernel/${KBASE}/${KRELEASE}/${ARCH}/kernel-debuginfo-${KERNEL}.rpm"
        FILENAME="kernel-debuginfo-${KERNEL}.rpm"
        ;;
    rhel|centos)
        # CentOS debuginfo mirror
        URL="http://debuginfo.centos.org/${VERSION}/${ARCH}/kernel-debuginfo-${KERNEL}.rpm"
        FILENAME="kernel-debuginfo-${KERNEL}.rpm"
        ;;
    debian)
        # Debian debug archive (ddebs)
        # Package naming: linux-image-<kver>-dbg_<debver>_<arch>.deb
        # Without full debian version, try the ddebs pool
        KSHORT=$(echo "$KERNEL" | sed 's/-amd64$//' | sed 's/-arm64$//')
        URL="http://ddebs.debian.org/pool/main/l/linux/linux-image-${KERNEL}-dbg_${KSHORT}-1_${ARCH}.deb"
        FILENAME="linux-image-${KERNEL}-dbg_${ARCH}.deb"
        ;;
    ubuntu)
        # Ubuntu debug symbol archive (ddebs)
        KSHORT=$(echo "$KERNEL" | sed 's/-generic$//' | sed 's/-lowlatency$//')
        URL="http://ddebs.ubuntu.com/pool/main/l/linux/linux-image-unsigned-${KERNEL}-dbgsym_${KSHORT}.${KSHORT}_${ARCH}.ddeb"
        FILENAME="linux-image-unsigned-${KERNEL}-dbgsym_${ARCH}.ddeb"
        ;;
    suse|opensuse)
        # openSUSE debug repo (under /debug/update/leap/<ver>/sle/)
        URL="https://download.opensuse.org/debug/update/leap/${VERSION}/sle/${ARCH}/kernel-default-debuginfo-${KERNEL}.${ARCH}.rpm"
        FILENAME="kernel-default-debuginfo-${KERNEL}.${ARCH}.rpm"
        ;;
    arch)
        # Arch uses debuginfod, not downloadable debug packages
        echo "[-] Arch Linux does not ship debug packages."
        echo "    Debug symbols are served via https://debuginfod.archlinux.org"
        echo "    Arch kernel ISF generation is not yet supported."
        exit 1
        ;;
    *)
        echo "[-] Unsupported distro: $DISTRO"
        echo "    Provide a direct debug_url instead."
        exit 1
        ;;
esac

echo "[*] Trying: $URL"
if curl -fSL -o "$OUTDIR/$FILENAME" "$URL"; then
    echo "[+] Downloaded: $OUTDIR/$FILENAME"
else
    echo "[-] Download failed. The auto-resolved URL may be wrong."
    echo "    URL tried: $URL"
    echo ""
    echo "    Please provide the debug_url directly in your symbol request."
    echo "    Common sources:"
    echo "      Fedora:  https://kojipkgs.fedoraproject.org/packages/kernel/"
    echo "      RHEL:    https://debuginfo.centos.org/"
    echo "      Debian:  http://ddebs.debian.org/pool/main/l/linux/"
    echo "      Ubuntu:  http://ddebs.ubuntu.com/pool/main/l/linux/"
    echo "      SUSE:    https://download.opensuse.org/debug/"
    echo "      Arch:    https://archive.archlinux.org/packages/l/linux-debug/"
    exit 1
fi
