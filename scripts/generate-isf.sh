#!/bin/sh
# Generate ISF symbol table from vmlinux using dwarf2json
# Usage: generate-isf <vmlinux-path> [output-path]
#
# Examples:
#   generate-isf /tmp/debuginfo/usr/lib/debug/lib/modules/6.18.10-200.fc43.x86_64/vmlinux
#   generate-isf /tmp/vmlinux /output/fedora-43-6.18.10-200.json

set -e

VMLINUX="$1"
OUTPUT="${2:-/tmp/isf.json}"

if [ -z "$VMLINUX" ]; then
    echo "Usage: generate-isf <vmlinux-path> [output-path]"
    echo ""
    echo "Generates an ISF JSON file from vmlinux using dwarf2json."
    exit 1
fi

if [ ! -f "$VMLINUX" ]; then
    echo "[-] File not found: $VMLINUX"
    exit 1
fi

echo "[*] Generating ISF from: $VMLINUX"
echo "[*] Output: $OUTPUT"
echo "[*] This may take a few minutes for large kernels..."

dwarf2json linux --elf "$VMLINUX" > "$OUTPUT"

SIZE=$(du -h "$OUTPUT" | cut -f1)
echo ""
echo "[+] ISF generated: $OUTPUT ($SIZE)"
