#!/bin/sh
# Build ISF symbol artifacts locally for testing.
#
# Usage:
#   build-local.sh <distro> <kernel>
#   build-local.sh fedora 6.17.7-200.fc42.x86_64
#   build-local.sh --url <debug_url> <kernel>
#
# This replicates what the GitHub Actions workflow does, but locally.
# Requires: docker (or podman with docker alias)
# Optional: --push <registry> to push images after build

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "Usage:"
    echo "  build-local.sh <distro> <kernel>"
    echo "  build-local.sh --url <debug_url> <kernel>"
    echo ""
    echo "Examples:"
    echo "  build-local.sh fedora 6.17.7-200.fc42.x86_64"
    echo "  build-local.sh --url https://kojipkgs.fedoraproject.org/.../kernel-debuginfo-6.17.7-200.fc42.x86_64.rpm 6.17.7-200.fc42.x86_64"
    echo ""
    echo "Outputs:"
    echo "  ./output/<kernel>.json                  ISF JSON file"
    echo "  ./output/vol-qemu                       KubeVirt QEMU dump wrapper"
    echo "  ./output/qemu_elf.py                    Vol3 stacker plugin"
    echo "  kernel-isf:<kernel>-busybox             Container image (init container)"
    echo ""
    echo "To push as ORAS artifacts (requires oras CLI):"
    echo "  build-local.sh <distro> <kernel> --push <registry>"
    exit 1
}

# Parse args
DEBUG_URL=""
PUSH_REGISTRY=""
if [ "$1" = "--url" ]; then
    DEBUG_URL="$2"
    KERNEL="$3"
    [ -z "$KERNEL" ] && usage
    [ "$4" = "--push" ] && PUSH_REGISTRY="$5"
elif [ -n "$1" ] && [ -n "$2" ]; then
    DISTRO="$1"
    KERNEL="$2"
    [ "$3" = "--push" ] && PUSH_REGISTRY="$4"
    # Look up debug_url from manifest
    DISTRO_FILE="$REPO_DIR/symbols/${DISTRO}.yaml"
    if [ ! -f "$DISTRO_FILE" ]; then
        echo "[-] No manifest for distro: $DISTRO"
        echo "    Available: $(ls "$REPO_DIR/symbols/" | sed 's/.yaml//g' | tr '\n' ' ')"
        exit 1
    fi
    DEBUG_URL=$(python3 -c "
import yaml
with open('$DISTRO_FILE') as f:
    data = yaml.safe_load(f)
for s in data.get('symbols', []):
    if s.get('kernel') == '$KERNEL':
        print(s.get('debug_url', ''))
        break
" 2>/dev/null)
    if [ -z "$DEBUG_URL" ]; then
        echo "[-] Kernel $KERNEL not found in $DISTRO_FILE"
        echo "    Use --url to provide the debug package URL directly."
        exit 1
    fi
else
    usage
fi

echo "============================================"
echo "  kernel-isf local build"
echo "============================================"
echo "  Kernel:    $KERNEL"
echo "  Debug URL: $DEBUG_URL"
echo "============================================"
echo ""

cd "$REPO_DIR"

# Step 1: Build ISF via builder Dockerfile
echo "[1/4] Building ISF (this downloads the debug package and runs dwarf2json)..."
docker build \
    -f Dockerfile.builder \
    --build-arg "DEBUG_PKG_URL=$DEBUG_URL" \
    --build-arg "SYMBOL_ID=$KERNEL" \
    --target generate \
    -t "isf-builder:$KERNEL" \
    .

# Step 2: Extract artifacts
echo ""
echo "[2/4] Extracting ISF JSON..."
docker create --name "isf-extract-$$" "isf-builder:$KERNEL"
mkdir -p output
docker cp "isf-extract-$$:/output/$KERNEL.json" "output/$KERNEL.json"
docker rm "isf-extract-$$"

# Copy tools alongside
cp scripts/vol-qemu output/vol-qemu
cp scripts/qemu_elf.py output/qemu_elf.py

echo "  ISF:        output/$KERNEL.json ($(du -h "output/$KERNEL.json" | cut -f1))"
echo "  vol-qemu:   output/vol-qemu"
echo "  qemu_elf:   output/qemu_elf.py"

# Step 3: Build scratch image (ISF only — works as Image Volume + oras pull)
echo ""
echo "[3/5] Building scratch image (ISF only)..."

mkdir -p /tmp/isf-local-build
cp "output/$KERNEL.json" /tmp/isf-local-build/isf.json

cat > /tmp/isf-local-build/Dockerfile.scratch <<DOCKERFILE
FROM scratch
COPY isf.json /symbols/linux/isf.json
DOCKERFILE

docker build \
    -f /tmp/isf-local-build/Dockerfile.scratch \
    -t "kernel-isf:$KERNEL" \
    /tmp/isf-local-build

# Step 4: Build busybox container image
echo ""
echo "[4/5] Building busybox container image..."

cp scripts/vol-qemu /tmp/isf-local-build/vol-qemu
cp scripts/qemu_elf.py /tmp/isf-local-build/qemu_elf.py
cp entrypoint.sh /tmp/isf-local-build/entrypoint.sh

cat > /tmp/isf-local-build/Dockerfile.busybox <<DOCKERFILE
FROM busybox:stable
COPY isf.json /symbols/linux/isf.json
COPY vol-qemu /usr/local/bin/vol-qemu
COPY qemu_elf.py /usr/local/bin/qemu_elf.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/vol-qemu
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/dest/symbols"]
DOCKERFILE

docker build \
    -f /tmp/isf-local-build/Dockerfile.busybox \
    -t "kernel-isf:$KERNEL-busybox" \
    /tmp/isf-local-build

# Step 5: Build tools image (scratch — works as Image Volume + oras pull)
echo ""
echo "[5/5] Building tools image..."

cat > /tmp/isf-local-build/Dockerfile.tools <<DOCKERFILE
FROM scratch
COPY vol-qemu /vol-qemu
COPY qemu_elf.py /qemu_elf.py
DOCKERFILE

docker build \
    -f /tmp/isf-local-build/Dockerfile.tools \
    -t "kernel-isf:tools" \
    /tmp/isf-local-build

rm -rf /tmp/isf-local-build

echo ""
echo "============================================"
echo "  Build complete!"
echo "============================================"
echo ""
echo "  Files:   ./output/$KERNEL.json"
echo "           ./output/vol-qemu"
echo "           ./output/qemu_elf.py"
echo ""
echo "  Images:  kernel-isf:$KERNEL          (scratch — ISF only)"
echo "           kernel-isf:$KERNEL-busybox  (busybox — ISF + tools + entrypoint)"
echo "           kernel-isf:tools            (scratch — vol-qemu + qemu_elf.py)"
echo ""
echo "Test:"
echo "  docker run --rm kernel-isf:$KERNEL-busybox /tmp/test"
echo ""
echo "Use as K8s Image Volume (1.31+):"
echo "  volumes:"
echo "    - name: symbols"
echo "      image:"
echo "        reference: kernel-isf:$KERNEL"
