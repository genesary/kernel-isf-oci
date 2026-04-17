# kernel-isf

Community-maintained ISF (Intermediate Symbol Format) symbol images for Linux kernel memory forensics with [Volatility3](https://github.com/volatilityfoundation/volatility3).

## What is this?

Volatility3 needs ISF symbol tables to analyze memory dumps. These are generated from kernel debug packages using [dwarf2json](https://github.com/volatilityfoundation/dwarf2json). This project automates that process and publishes the results as container images, making it easy to use them in Kubernetes environments or any container workflow.

Every symbol set is published as OCI images. Tags match `uname -r` output directly. All images work as Kubernetes Image Volumes (K8s 1.31+), with `oras pull`, `crane export`, or `docker cp`.

| Tag | Base | Contents |
|-----|------|----------|
| `ghcr.io/genesary/kernel-isf-oci:<uname -r>` | scratch | ISF JSON file only |
| `ghcr.io/genesary/kernel-isf-oci:<uname -r>-busybox` | busybox | ISF + vol-qemu + qemu_elf.py + entrypoint |
| `ghcr.io/genesary/kernel-isf-toolbox:latest` | alpine | Volatility3 + dwarf2json + vol-qemu + qemu_elf.py + mquire |

## Supported Distributions

| Distro | Debug Package Source |
|--------|---------------------|
| Fedora | [Koji](https://kojipkgs.fedoraproject.org/packages/kernel/) |
| CentOS Stream | [CentOS Stream Koji](https://kojihub.stream.centos.org/) |
| Rocky Linux | [Rocky mirrors](https://download.rockylinux.org/pub/rocky/) |
| AlmaLinux | [AlmaLinux vault](https://repo.almalinux.org/vault/) |
| Debian | [security.debian.org](https://security.debian.org/) |
| Ubuntu | [ddebs.ubuntu.com](http://ddebs.ubuntu.com/) |
| openSUSE | [openSUSE debug mirrors](https://ftp.gwdg.de/pub/opensuse/debug/) |

## Quick Start

### Pull symbols

```bash
# Pull ISF JSON (with oras, crane, or docker)
oras pull ghcr.io/genesary/kernel-isf-oci:6.17.7-200.fc42.x86_64
crane export ghcr.io/genesary/kernel-isf-oci:6.17.7-200.fc42.x86_64 - | tar xf -

# Pull tools (vol-qemu + qemu_elf.py)
oras pull ghcr.io/genesary/kernel-isf-oci:tools

# Pull busybox image (for init containers)
docker pull ghcr.io/genesary/kernel-isf-oci:6.17.7-200.fc42.x86_64-busybox
```

### Use as Kubernetes Image Volume (K8s 1.31+)

```yaml
containers:
  - name: forensics
    image: your-volatility3-image
    volumeMounts:
      - name: symbols
        mountPath: /usr/local/lib/python3.12/site-packages/volatility3/symbols
volumes:
  - name: symbols
    image:
      reference: ghcr.io/genesary/kernel-isf-oci:6.17.7-200.fc42.x86_64
```

### Use as Kubernetes init container

```yaml
initContainers:
  - name: isf-symbols
    image: ghcr.io/genesary/kernel-isf-oci:6.17.7-200.fc42.x86_64-busybox
    volumeMounts:
      - name: symbols
        mountPath: /dest/symbols
containers:
  - name: forensics
    image: your-volatility3-image
    volumeMounts:
      - name: symbols
        mountPath: /usr/local/lib/python3.12/site-packages/volatility3/symbols
volumes:
  - name: symbols
    emptyDir: {}
```

### Local build and test

```bash
# Build from manifest
./scripts/build-local.sh fedora 6.17.7-200.fc42.x86_64

# Build from direct URL
./scripts/build-local.sh --url https://kojipkgs.fedoraproject.org/.../kernel-debuginfo.rpm 6.17.7-200.fc42.x86_64

# Build and push to registry
./scripts/build-local.sh fedora 6.17.7-200.fc42.x86_64 --push ghcr.io/genesary
```

## Requesting New Symbols

### Option 1: Open an Issue

Use the [Symbol Request](../../issues/new?template=symbol-request.yml) issue template. Fill in your distro, version, and `uname -r` output. The CI pipeline will build and publish the images automatically.

### Option 2: Submit a PR

Add an entry to the appropriate file in `symbols/`:

```yaml
# symbols/fedora.yaml
symbols:
  - kernel: "6.17.7-200.fc42.x86_64"
    version: "42"
    debug_url: "https://kojipkgs.fedoraproject.org/packages/kernel/6.17.7/200.fc42/x86_64/kernel-debuginfo-6.17.7-200.fc42.x86_64.rpm"
    status: pending
```

Merging the PR triggers the build automatically.

## Included Tools

### vol-qemu

A CLI wrapper for running any Volatility3 plugin on KubeVirt QEMU ELF memory dumps. Included in all busybox images.

```bash
vol-qemu -f /dump/vm.memory.dump linux.pslist.PsList
vol-qemu -f /dump/vm.memory.dump --info
vol-qemu --list
```

### qemu_elf.py

A Volatility3 stacker plugin that enables automatic QEMU ELF support. Install it into your vol3 framework:

```bash
cp qemu_elf.py /path/to/volatility3/framework/layers/qemu_elf.py
```

## How It Works

```
symbol request (issue/PR)
        │
        ▼
  symbols/<distro>.yaml   ──►  GitHub Actions
        │                           │
        │                    ┌──────┴──────┐
        │                    ▼             ▼
        │              download        build
        │              debug pkg     dwarf2json
        │                    │             │
        │                    ▼             ▼
        │               extract        generate
        │               vmlinux       ISF JSON
        │                    │             │
        │                    └──────┬──────┘
        │                           │
        │                    ┌─────┬──────┐
        │                    ▼     ▼      ▼
        │              scratch busybox  scratch
        │              (ISF)  (image)  (tools)
        │                │      │        │
        ▼                ▼      ▼        ▼
  status: built       ghcr.io ghcr.io  ghcr.io
```

## Repository Structure

```
kernel-isf/
├── symbols/                    Per-distro manifest files
│   ├── fedora.yaml
│   ├── centos.yaml             CentOS Stream 9 + 10
│   ├── rocky.yaml
│   ├── almalinux.yaml
│   ├── rhel.yaml
│   ├── debian.yaml
│   ├── ubuntu.yaml
│   ├── suse.yaml
├── scripts/
│   ├── build-local.sh          Local build and test
│   ├── extract-vmlinux.sh      Extract vmlinux from debug packages
│   ├── generate-isf.sh         Generate ISF JSON from vmlinux
│   ├── download-debuginfo.sh   Download debug packages by distro
│   ├── parse-kernel.sh         Infer distro from uname -r
│   ├── vol-qemu                KubeVirt QEMU ELF dump wrapper
│   └── qemu_elf.py             Vol3 stacker plugin for QEMU ELF
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   └── symbol-request.yml  Structured issue form
│   ├── pull_request_template.md
│   └── workflows/
│       ├── build-isf.yml       Reusable: build + push one symbol
│       ├── build-all.yml       Build all pending symbols on merge
│       └── process-request.yml Issue-to-build pipeline
├── Dockerfile.builder          Multi-stage ISF generation
├── Dockerfile.scratch          ISF-only OCI image (Image Volume / oras pull)
├── Dockerfile.busybox          Init container output image
├── Dockerfile.tools            vol-qemu + qemu_elf.py OCI image
├── entrypoint.sh               Busybox entrypoint (copies symbols)
├── docs/
│   └── usage.md                Detailed usage examples
├── CONTRIBUTING.md             How to contribute, DCO requirement
├── CODE_OF_CONDUCT.md          CNCF Code of Conduct
├── SECURITY.md                 Vulnerability reporting policy
├── DCO                         Developer Certificate of Origin 1.1
├── LICENSE                     Apache-2.0
└── README.md
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to submit symbol requests, PRs, and the DCO requirement.

## License

Apache License 2.0

