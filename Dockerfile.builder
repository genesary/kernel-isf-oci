# Multi-stage ISF builder
#
# Builds dwarf2json from source, extracts vmlinux from a distro debug package,
# and generates the ISF JSON file.
#
# Build args:
#   DEBUG_PKG_URL  - URL to the kernel debug package
#   SYMBOL_ID      - Identifier for the output ISF file (e.g. fedora-43-6.18.10-200)
#
# Output: /output/<SYMBOL_ID>.json

# ── Stage 1: Build dwarf2json ───────────────────────────────────────────
FROM golang:1.26-alpine AS dwarf2json-build

RUN apk add --no-cache git && \
    git clone --depth 1 https://github.com/volatilityfoundation/dwarf2json.git /src && \
    cd /src && go build -o /dwarf2json .

# ── Stage 2: Download and extract vmlinux ────────────────────────────────
FROM fedora:latest AS extract

RUN dnf install -y cpio binutils xz zstd gzip bzip2 && dnf clean all

ARG DEBUG_PKG_URL
ARG SYMBOL_ID

COPY scripts/extract-vmlinux.sh /usr/local/bin/extract-vmlinux
COPY scripts/download-debuginfo.sh /usr/local/bin/download-debuginfo
RUN chmod +x /usr/local/bin/extract-vmlinux /usr/local/bin/download-debuginfo

# Download the debug package (preserve original filename for extension detection)
RUN mkdir -p /tmp/debugpkg && \
    FILENAME=$(basename "${DEBUG_PKG_URL}" | sed 's/?.*//' ) && \
    curl -fSL --retry 5 --retry-delay 5 --retry-all-errors -C - -o "/tmp/debugpkg/${FILENAME}" "${DEBUG_PKG_URL}"

# Extract vmlinux (supports both vmlinux and vmlinux-* naming)
RUN PKG=$(ls /tmp/debugpkg/* | head -1) && \
    extract-vmlinux "$PKG" /tmp/extract && \
    VMLINUX=$(find /tmp/extract -name vmlinux -type f 2>/dev/null | head -1) && \
    if [ -z "$VMLINUX" ]; then VMLINUX=$(find /tmp/extract -name 'vmlinux-*' -type f 2>/dev/null | head -1); fi && \
    if [ -z "$VMLINUX" ]; then echo "vmlinux not found"; exit 1; fi && \
    cp "$VMLINUX" /vmlinux && \
    rm -rf /tmp/debugpkg /tmp/extract

# ── Stage 3: Generate ISF JSON ──────────────────────────────────────────
FROM extract AS generate

ARG SYMBOL_ID

COPY --from=dwarf2json-build /dwarf2json /usr/local/bin/dwarf2json

RUN mkdir -p /output && \
    dwarf2json linux --elf /vmlinux > "/output/${SYMBOL_ID}.json" && \
    ls -lh "/output/${SYMBOL_ID}.json"
