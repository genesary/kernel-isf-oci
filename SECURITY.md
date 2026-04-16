# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT open a public issue**
2. Use [GitHub Security Advisories](../../security/advisories/new) to report the vulnerability privately
3. We will acknowledge your report within 48 hours
4. We will provide a timeline for a fix within 7 days

## Security Considerations

- ISF JSON files are generated from publicly available kernel debug packages
- The build pipeline runs in isolated GitHub Actions containers
- Container images are published to ghcr.io with provenance attestations
- No secrets or credentials are embedded in published images
- The `vol-qemu` and `qemu_elf.py` tools process untrusted memory dumps — use them in isolated environments
