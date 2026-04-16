#!/bin/sh
# Copy ISF symbols and tools to the destination directory.
# Default destination: /dest/symbols (override via CMD or first argument)

DEST="${1:-/dest/symbols}"

echo "[*] Copying ISF symbols to $DEST"
mkdir -p "$DEST/linux"
cp /symbols/linux/*.json "$DEST/linux/"

# Copy vol-qemu and qemu_elf.py if present
if [ -f /usr/local/bin/vol-qemu ]; then
    cp /usr/local/bin/vol-qemu "$DEST/vol-qemu" 2>/dev/null || true
fi
if [ -f /usr/local/bin/qemu_elf.py ]; then
    cp /usr/local/bin/qemu_elf.py "$DEST/qemu_elf.py" 2>/dev/null || true
fi

echo "[+] Done. Contents of $DEST:"
ls -lhR "$DEST"
