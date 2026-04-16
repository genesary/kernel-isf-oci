#!/bin/sh
# Parse a uname -r string and infer distro, version, and arch when possible.
#
# Usage: parse-kernel.sh <uname-r>
#
# Output: KEY=VALUE lines suitable for eval or GitHub Actions $GITHUB_OUTPUT
#
# Detectable patterns:
#   6.17.7-200.fc42.x86_64        → fedora 42 x86_64
#   5.14.0-362.el9.x86_64         → rhel/centos 9 x86_64
#   5.14.0-362.el9_3.x86_64       → rhel/centos 9 x86_64
#   5.14.21-150500.55.31-default  → suse 15.5 x86_64
#   6.9.1.arch1-1-x86_64          → arch rolling x86_64
#
# NOT detectable (user must provide distro + version):
#   6.1.0-23-amd64                → debian (no version info)
#   6.8.0-41-generic              → ubuntu (no version info)

set -e

KERNEL="$1"

if [ -z "$KERNEL" ]; then
    echo "Usage: parse-kernel.sh <uname-r>"
    exit 1
fi

DISTRO=""
VERSION=""
ARCH=""

# Extract arch from common suffixes
case "$KERNEL" in
    *.x86_64)   ARCH="x86_64";  KBODY="${KERNEL%.x86_64}" ;;
    *.aarch64)  ARCH="aarch64"; KBODY="${KERNEL%.aarch64}" ;;
    *.s390x)    ARCH="s390x";   KBODY="${KERNEL%.s390x}" ;;
    *.ppc64le)  ARCH="ppc64le"; KBODY="${KERNEL%.ppc64le}" ;;
    *-amd64)    ARCH="amd64";   KBODY="${KERNEL%-amd64}" ;;
    *-arm64)    ARCH="arm64";   KBODY="${KERNEL%-arm64}" ;;
    *)          ARCH="";        KBODY="$KERNEL" ;;
esac

# Fedora: 6.17.7-200.fc42
if echo "$KBODY" | grep -qE '\.fc[0-9]+$'; then
    DISTRO="fedora"
    VERSION=$(echo "$KBODY" | grep -oE 'fc[0-9]+$' | sed 's/^fc//')

# RHEL/CentOS: 5.14.0-362.el9 or 5.14.0-362.el9_3
elif echo "$KBODY" | grep -qE '\.el[0-9]+'; then
    DISTRO="rhel"
    VERSION=$(echo "$KBODY" | grep -oE 'el[0-9]+' | sed 's/^el//')

# SUSE: 5.14.21-150500.55.31-default (150500 = version 15.5)
elif echo "$KBODY" | grep -qE '\-[0-9]{6,}\.' && echo "$KBODY" | grep -qE '\-default$'; then
    DISTRO="suse"
    # Extract the 6-digit version code (e.g. 150500 = 15.05 = 15.5)
    VCODE=$(echo "$KBODY" | grep -oE '[0-9]{6}' | head -1)
    if [ -n "$VCODE" ]; then
        MAJOR=$(echo "$VCODE" | cut -c1-2)
        MINOR=$(echo "$VCODE" | cut -c3-4 | sed 's/^0//')
        VERSION="${MAJOR}.${MINOR}"
    fi

# Arch: 6.9.1.arch1-1
elif echo "$KBODY" | grep -qE '\.arch[0-9]'; then
    DISTRO="arch"
    VERSION="rolling"

# Debian-style: 6.1.0-23-amd64 (no distro info embedded)
# Ubuntu-style: 6.8.0-41-generic (no distro info embedded)
# Can't distinguish — leave for user to specify
fi

echo "distro=$DISTRO"
echo "version=$VERSION"
echo "arch=$ARCH"

if [ -n "$DISTRO" ]; then
    echo "inferred=true"
else
    echo "inferred=false"
fi
