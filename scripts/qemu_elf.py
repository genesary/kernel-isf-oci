"""Volatility3 stacker for QEMU ELF core dumps (KubeVirt memory-dump API).

Vol3's built-in QemuStacker only handles QEVM savevm format.  KubeVirt uses
virDomainCoreDumpWithFormat which produces standard ELF ET_CORE files with
QEMU CPU-state notes.  The Elf64Stacker correctly parses the ELF but nothing
extracts CR3 from the QEMU notes to build the Intel page-table layer.

This stacker runs at stack_order=11 (after Elf64Stacker at 10), receives
the Elf64Layer, extracts CR3 from the first QEMU CPU-state note, and
creates an Intel32e layer.  Once installed, `vol -f <dump> linux.pslist`
just works.

Install: copy to volatility3/framework/layers/qemu_elf.py
"""

import logging
import struct
from typing import Optional

from volatility3.framework import constants, interfaces
from volatility3.framework.layers import intel

vollog = logging.getLogger(__name__)


def _find_note_segment(layer):
    """Return (offset, size) of PT_NOTE from ELF headers in the base layer."""
    # Read ELF header from the *base* (FileLayer), not the Elf64Layer
    # The Elf64Layer remaps LOAD segments — notes may not be at the same offset
    # We need the raw file to parse notes
    hdr = layer.read(0, 64)
    if hdr[:4] != b"\x7fELF":
        return None
    e_phoff = struct.unpack_from("<Q", hdr, 32)[0]
    e_phentsize = struct.unpack_from("<H", hdr, 54)[0]
    e_phnum = struct.unpack_from("<H", hdr, 56)[0]

    for i in range(e_phnum):
        ph = layer.read(e_phoff + i * e_phentsize, e_phentsize)
        p_type = struct.unpack_from("<I", ph, 0)[0]
        if p_type == 4:  # PT_NOTE
            p_offset = struct.unpack_from("<Q", ph, 8)[0]
            p_filesz = struct.unpack_from("<Q", ph, 32)[0]
            return (p_offset, p_filesz)
    return None


def _extract_cr3_from_notes(layer, note_off, note_sz):
    """Extract CR3 from the first QEMU CPU-state note.

    QEMUCPUState x86_64 layout:
        version(4) + size(4) + 18 regs(144) + 10 segments(240) + cr[0..4](40)
    CR3 is the 4th CR (index 3): offset = 8 + 144 + 240 + 3*8 = 416
    """
    pos = note_off
    end = note_off + note_sz
    while pos < end:
        if end - pos < 12:
            break
        note_hdr = layer.read(pos, 12)
        namesz, descsz, ntype = struct.unpack("<III", note_hdr)
        pos += 12
        # Read and align name
        if namesz > 0:
            name_raw = layer.read(pos, namesz)
            name = name_raw.rstrip(b"\x00").decode("ascii", errors="replace")
        else:
            name = ""
        pos = (pos + namesz + 3) & ~3
        # Read and align desc
        desc_pos = pos
        pos = (pos + descsz + 3) & ~3

        if name == "QEMU" and descsz >= 440:
            desc = layer.read(desc_pos, descsz)
            cr3_offset = 8 + 144 + 240 + 3 * 8
            cr3 = struct.unpack_from("<Q", desc, cr3_offset)[0]
            if cr3 != 0:
                return cr3
    return None


def _scan_kaslr(layer):
    """Scan physical memory (Elf64Layer) for VMCOREINFO KERNELOFFSET.

    Returns the KASLR shift as an integer, or 0 if not found.
    VMCOREINFO is a text block in physical memory containing lines like:
        OSRELEASE=6.18.10-200.fc43.x86_64
        KERNELOFFSET=34400000
    We skip format strings like KERNELOFFSET=%lx by checking the first char.
    """
    needle = b"KERNELOFFSET="
    hex_digits = set(b"0123456789abcdef")
    chunk_size = 16 * 1024 * 1024

    try:
        max_addr = layer.maximum_address
    except Exception:
        max_addr = 8 * 1024 * 1024 * 1024  # 8 GiB fallback

    offset = 0
    while offset < max_addr:
        try:
            size = min(chunk_size, max_addr - offset + 1)
            chunk = layer.read(offset, size, pad=True)
        except Exception:
            offset += chunk_size
            continue

        search_from = 0
        while True:
            idx = chunk.find(needle, search_from)
            if idx < 0:
                break
            val_start = idx + len(needle)
            if val_start < len(chunk) and chunk[val_start] in hex_digits:
                # Found a real KERNELOFFSET value
                val_end = val_start
                while val_end < len(chunk) and chunk[val_end] in hex_digits:
                    val_end += 1
                try:
                    return int(chunk[val_start:val_end], 16)
                except ValueError:
                    pass
            search_from = idx + 1
        offset += chunk_size - 64  # small overlap for boundary matches

    return 0


def _scan_linux_banner(layer):
    """Scan physical memory for the Linux version banner string.

    Returns the banner as a latin-1 string, or None.
    """
    needle = b"Linux version "
    chunk_size = 16 * 1024 * 1024
    try:
        max_addr = layer.maximum_address
    except Exception:
        max_addr = 8 * 1024 * 1024 * 1024

    offset = 0
    while offset < max_addr:
        try:
            size = min(chunk_size, max_addr - offset + 1)
            chunk = layer.read(offset, size, pad=True)
        except Exception:
            offset += chunk_size
            continue
        idx = chunk.find(needle)
        if idx >= 0:
            # Read a generous chunk and find the null terminator
            end = chunk.find(b"\x00", idx)
            if end < 0:
                end = min(idx + 512, len(chunk))
            banner_bytes = chunk[idx:end + 1]  # include null
            # Sanity: must contain a version-like string
            if b"(" in banner_bytes and b")" in banner_bytes:
                return banner_bytes.decode("latin-1")
        offset += chunk_size - 512  # overlap for boundary

    return None


def _is_qemu_elf(base_layer):
    """Check if the base (file) layer is a QEMU ELF core dump."""
    try:
        magic = base_layer.read(0, 4)
        if magic != b"\x7fELF":
            return False
        # Check ET_CORE (e_type at offset 16)
        e_type = struct.unpack_from("<H", base_layer.read(16, 2), 0)[0]
        if e_type != 4:  # ET_CORE
            return False
        # Check for QEMU note
        result = _find_note_segment(base_layer)
        if result is None:
            return False
        note_off, note_sz = result
        # Scan for a QEMU-named note
        pos = note_off
        end = note_off + note_sz
        while pos < end:
            if end - pos < 12:
                break
            note_hdr = base_layer.read(pos, 12)
            namesz, descsz, ntype = struct.unpack("<III", note_hdr)
            pos += 12
            if namesz > 0:
                name = base_layer.read(pos, namesz).rstrip(b"\x00")
                if name == b"QEMU":
                    return True
            pos = (pos + namesz + 3) & ~3
            pos = (pos + descsz + 3) & ~3
        return False
    except Exception:
        return False


class QemuElfStacker(interfaces.automagic.StackerLayerInterface):
    """Stacks Intel32e on top of Elf64Layer for QEMU ELF core dumps.

    Runs after Elf64Stacker (stack_order 10) creates the Elf64Layer.
    Extracts CR3 from QEMU CPU-state notes and builds the Intel
    page-translation layer that plugins need.
    """

    stack_order = 11

    @classmethod
    def stack(
        cls,
        context: interfaces.context.ContextInterface,
        layer_name: str,
        progress_callback: constants.ProgressCallback = None,
    ) -> Optional[interfaces.layers.DataLayerInterface]:
        # We run on the Elf64Layer — check that the layer below it is a QEMU ELF
        layer = context.layers.get(layer_name)
        if layer is None:
            return None

        # Must be an Elf64Layer
        if not layer_name.startswith("Elf64") and "Elf64" not in type(layer).__name__:
            return None

        # Get the base (file) layer to read raw ELF notes
        try:
            base_layer_name = layer.config.get("base_layer")
            if not base_layer_name:
                # Try common config paths
                for key in layer.config:
                    if "base_layer" in key:
                        base_layer_name = layer.config[key]
                        break
            if not base_layer_name:
                return None
            base_layer = context.layers[base_layer_name]
        except (KeyError, AttributeError):
            return None

        if not _is_qemu_elf(base_layer):
            return None

        # Extract CR3 from QEMU CPU-state notes
        result = _find_note_segment(base_layer)
        if result is None:
            return None
        note_off, note_sz = result
        cr3 = _extract_cr3_from_notes(base_layer, note_off, note_sz)
        if cr3 is None or cr3 == 0:
            vollog.warning("QEMU ELF: could not extract CR3 from CPU-state notes")
            return None

        vollog.info(f"QEMU ELF: CR3 = {cr3:#x}")

        # Scan physical memory for KASLR offset via VMCOREINFO
        kaslr = _scan_kaslr(layer)
        vollog.info(f"QEMU ELF: KASLR offset = {kaslr:#x}")

        # Build LinuxIntel32e layer on top of the Elf64Layer
        # LinuxIntel32e handles Linux-specific PTE masking (PROT_NONE inversion etc.)
        join = interfaces.configuration.path_join
        new_name = context.layers.free_layer_name("IntelLayer")
        config_path = join("QemuElfHelper", new_name)
        context.config[join(config_path, "memory_layer")] = layer_name
        context.config[join(config_path, "page_map_offset")] = cr3

        try:
            new_layer = intel.LinuxIntel32e(
                context,
                config_path=config_path,
                name=new_name,
                metadata={"os": "Linux"},
            )
        except Exception as e:
            vollog.warning(f"QEMU ELF: failed to create LinuxIntel32e layer: {e}")
            return None

        # kernel_virtual_offset is the ASLR shift — vol3's KernelModule automagic
        # reads this to set the module offset for symbol address translation
        new_layer.config["kernel_virtual_offset"] = kaslr

        # Pre-scan physical memory for the Linux kernel banner and set it on
        # the Intel layer config.  This makes vol3's SymbolFinder skip scanning
        # the Elf64Layer (whose restricted address_mask would clip 64-bit kernel
        # symbol addresses) and instead use the Intel layer's full 48-bit mask.
        banner = _scan_linux_banner(layer)
        if banner:
            new_layer.config["kernel_banner"] = banner
            vollog.info(f"QEMU ELF: pre-set kernel_banner on Intel layer")

        vollog.info(
            f"QEMU ELF: stacked LinuxIntel32e ({new_name}) on {layer_name} "
            f"with CR3={cr3:#x}, KASLR={kaslr:#x}"
        )
        return new_layer
