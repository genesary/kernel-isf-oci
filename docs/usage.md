# Usage Guide

## Pulling ISF Symbol Images

Every kernel symbol set is published as two container image variants:

| Variant | Tag | Use case |
|---------|-----|----------|
| **Scratch** | `ghcr.io/genesary/kernel-isf-oci:<uname -r>` | Minimal OCI image with just the ISF JSON. Use when you can extract layers directly. |
| **Busybox** | `ghcr.io/genesary/kernel-isf-oci:<uname -r>-busybox` | Includes `cp` and an entrypoint. Designed for Kubernetes init containers. |

### Examples

```bash
# Pull a scratch image
docker pull ghcr.io/genesary/kernel-isf-oci:6.17.7-200.fc42.x86_64

# Pull the busybox variant
docker pull ghcr.io/genesary/kernel-isf-oci:6.17.7-200.fc42.x86_64-busybox
```

## Kubernetes Init Container

Use the busybox image as an init container to inject ISF symbols into a shared volume. The forensics container then reads them from the standard Volatility3 symbols path.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: forensics
spec:
  initContainers:
    - name: isf-symbols
      image: ghcr.io/genesary/kernel-isf-oci:6.17.7-200.fc42.x86_64-busybox
      # Default copies to /dest/symbols — override with args
      volumeMounts:
        - name: symbols
          mountPath: /dest/symbols

  containers:
    - name: vol3
      image: your-volatility3-image:latest
      command: ["vol-qemu", "-f", "/dump/vm.memory.dump", "linux.pslist.PsList"]
      volumeMounts:
        - name: symbols
          mountPath: /usr/local/lib/python3.12/site-packages/volatility3/symbols
        - name: dump
          mountPath: /dump

  volumes:
    - name: symbols
      emptyDir: {}
    - name: dump
      persistentVolumeClaim:
        claimName: memory-dump-pvc
```

## Extracting ISF JSON from Scratch Image

If you just need the JSON file (no init container), extract it from the scratch image:

```bash
# Create a temporary container and copy the file out
docker create --name tmp ghcr.io/genesary/kernel-isf-oci:6.17.7-200.fc42.x86_64
docker cp tmp:/symbols/linux/ ./symbols/
docker rm tmp
```

Or use `crane` / `skopeo` to pull the layer directly without Docker:

```bash
# With crane
crane export ghcr.io/genesary/kernel-isf-oci:6.17.7-200.fc42.x86_64 - | tar -xf - symbols/

# With skopeo + umoci
skopeo copy docker://ghcr.io/genesary/kernel-isf-oci:6.17.7-200.fc42.x86_64 oci:isf-image:latest
umoci unpack --image isf-image:latest bundle
ls bundle/rootfs/symbols/linux/
```

## Using vol-qemu with KubeVirt Dumps

The busybox image includes `vol-qemu`, a wrapper that handles QEMU ELF core dumps from KubeVirt's memory-dump API. It also includes `qemu_elf.py`, a Volatility3 stacker plugin.

```bash
# Show dump info (CR3, KASLR offset, kernel version)
vol-qemu -f /dump/vm.memory.dump --info

# Run any vol3 plugin
vol-qemu -f /dump/vm.memory.dump linux.pslist.PsList
vol-qemu -f /dump/vm.memory.dump linux.lsmod.Lsmod
vol-qemu -f /dump/vm.memory.dump linux.malfind.Malfind

# List common forensic plugins
vol-qemu --list
```

## Installing qemu_elf.py as a Vol3 Plugin

For standard `vol` usage (without the `vol-qemu` wrapper), install the stacker plugin:

```bash
cp qemu_elf.py /path/to/volatility3/framework/layers/qemu_elf.py
```

This enables automatic QEMU ELF support — `vol -f dump.elf linux.pslist` will just work.
