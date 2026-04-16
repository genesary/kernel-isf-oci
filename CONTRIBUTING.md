# Contributing to kernel-isf

Thank you for your interest in contributing! This project is community-driven and welcomes contributions of all kinds.

## Ways to Contribute

### Request New Kernel Symbols

The easiest way to contribute is to request ISF symbols for a kernel you need:

1. Open a [Symbol Request](../../issues/new?template=symbol-request.yml) issue
2. Or submit a PR adding an entry to the appropriate `symbols/<distro>.yaml` file

### Submit a PR

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Ensure your commits are signed off (see DCO below)
5. Submit a pull request

### Adding a New Kernel Entry

Add an entry to the appropriate distro manifest file in `symbols/`:

```yaml
# symbols/<distro>.yaml
symbols:
  - kernel: "6.17.7-200.fc42.x86_64"    # uname -r output
    version: "42"                         # distro version
    debug_url: "https://..."              # URL to debug package
    status: pending
```

### Testing Locally

Before submitting, you can test your entry locally:

```bash
# Build from manifest
./scripts/build-local.sh <distro> <kernel>

# Or from a direct URL
./scripts/build-local.sh --url <debug_url> <kernel>
```

## Developer Certificate of Origin (DCO)

This project uses the [Developer Certificate of Origin](https://developercertificate.org/) (DCO). All commits must be signed off to certify that you have the right to submit the contribution.

Sign off your commits with:

```bash
git commit -s -m "your commit message"
```

This adds a `Signed-off-by: Your Name <your@email.com>` trailer to your commit message.

## Commit Messages

Use clear, descriptive commit messages:

- `Add ISF symbols for Ubuntu 24.04 6.8.0-110-generic`
- `Fix Debian vmlinux extraction path`
- `Update openSUSE mirror URL`

## Code of Conduct

This project follows the [CNCF Code of Conduct](https://github.com/cncf/foundation/blob/main/code-of-conduct.md).

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
