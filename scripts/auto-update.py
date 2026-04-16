#!/usr/bin/env python3
"""Auto-detect new kernel releases and add them to symbol manifests.

Currently supports:
  - Fedora (Koji API)
  - CentOS Stream 9/10 (kojihub API)
  - Rocky Linux 9 (mirror directory listing)

Run manually:  python3 scripts/auto-update.py
Run in CI:     triggered by .github/workflows/auto-update.yml
"""

import json
import re
import sys
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError

import yaml

SYMBOLS_DIR = Path(__file__).parent.parent / "symbols"


def load_manifest(distro):
    path = SYMBOLS_DIR / f"{distro}.yaml"
    if not path.exists():
        return None, path
    with open(path) as f:
        return yaml.safe_load(f), path


def save_manifest(data, path):
    with open(path, "w") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)


def existing_kernels(data):
    return {s["kernel"] for s in data.get("symbols", []) or []}


def fetch_json(url):
    try:
        req = Request(url, headers={"Accept": "application/json"})
        with urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except (URLError, json.JSONDecodeError) as e:
        print(f"  Warning: failed to fetch {url}: {e}", file=sys.stderr)
        return None


def fetch_html(url):
    try:
        with urlopen(url, timeout=30) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except URLError as e:
        print(f"  Warning: failed to fetch {url}: {e}", file=sys.stderr)
        return None


# ── Fedora via Koji ──────────────────────────────────────────────────────

def check_fedora():
    """Query Koji for recent Fedora kernel builds."""
    data, path = load_manifest("fedora")
    if data is None:
        return
    existing = existing_kernels(data)
    added = 0

    # Check Fedora 41, 42, 43
    for release in ["41", "42", "43"]:
        tag = f"f{release}-updates"
        url = (
            f"https://koji.fedoraproject.org/kojihub/call/"
            f"listTagged?tag={tag}&package=kernel&latest=true&type=build"
        )
        # Koji XML-RPC is complex; use the web API instead
        url = f"https://koji.fedoraproject.org/koji/search?match=glob&type=build&terms=kernel-*.fc{release}"
        # Simpler: just check known URL patterns for recent versions
        # The Koji JSON API is at /api/v1 but not all instances support it
        # Fall back to checking the packages directory
        base = "https://kojipkgs.fedoraproject.org/packages/kernel"
        listing_url = f"{base}/?C=M&O=D"
        html = fetch_html(listing_url)
        if not html:
            continue

        # Parse version directories
        versions = re.findall(r'href="(\d+\.\d+\.\d+)/"', html)
        for ver in versions[:15]:  # check 15 most recent
            # Check for fc<release> builds
            rel_url = f"{base}/{ver}/"
            rel_html = fetch_html(rel_url)
            if not rel_html:
                continue
            releases = re.findall(rf'href="(\d+\.fc{release})/"', rel_html)
            for rel in releases:
                kernel = f"{ver}-{rel}.x86_64"
                if kernel in existing:
                    continue
                debug_url = (
                    f"{base}/{ver}/{rel}/x86_64/"
                    f"kernel-debuginfo-{kernel}.rpm"
                )
                entry = {
                    "kernel": kernel,
                    "version": release,
                    "debug_url": debug_url,
                    "status": "pending",
                }
                if data.get("symbols") is None:
                    data["symbols"] = []
                data["symbols"].append(entry)
                existing.add(kernel)
                added += 1
                print(f"  + Fedora {release}: {kernel}")

    if added:
        save_manifest(data, path)
        print(f"  Fedora: added {added} new kernel(s)")
    else:
        print(f"  Fedora: up to date")


# ── CentOS Stream via kojihub ────────────────────────────────────────────

def check_centos():
    """Check CentOS Stream kojihub for new kernel builds."""
    data, path = load_manifest("centos")
    if data is None:
        return
    existing = existing_kernels(data)
    added = 0

    for stream, pattern in [("9", "el9"), ("10", "el10")]:
        # List recent kernel builds from kojihub
        url = (
            f"https://kojihub.stream.centos.org/kojifiles/packages/kernel/"
        )
        html = fetch_html(url)
        if not html:
            continue

        # Parse version directories (e.g., 5.14.0/)
        versions = re.findall(r'href="(\d+\.\d+\.\d+)/"', html)
        # Only the 2 most recent base versions (e.g. 5.14.0 and 6.12.0)
        versions = sorted(versions, key=lambda v: [int(x) for x in v.split(".")], reverse=True)
        for ver in versions[:2]:
            rel_url = f"{url}{ver}/"
            rel_html = fetch_html(rel_url)
            if not rel_html:
                continue
            releases = re.findall(rf'href="(\d+\.{pattern})/"', rel_html)
            # Only recent releases (high release numbers)
            releases = sorted(releases, key=lambda r: int(r.split(".")[0]), reverse=True)
            for rel in releases[:10]:
                kernel = f"{ver}-{rel}.x86_64"
                if kernel in existing:
                    continue
                debug_url = (
                    f"{url}{ver}/{rel}/x86_64/"
                    f"kernel-debuginfo-{ver}-{rel}.x86_64.rpm"
                )
                entry = {
                    "kernel": kernel,
                    "version": f"{stream}-stream",
                    "debug_url": debug_url,
                    "status": "pending",
                }
                if data.get("symbols") is None:
                    data["symbols"] = []
                data["symbols"].append(entry)
                existing.add(kernel)
                added += 1
                print(f"  + CentOS Stream {stream}: {kernel}")

    if added:
        save_manifest(data, path)
        print(f"  CentOS: added {added} new kernel(s)")
    else:
        print(f"  CentOS: up to date")


# ── Rocky Linux via mirror ───────────────────────────────────────────────

def check_rocky():
    """Check Rocky Linux mirror for new kernel-debuginfo packages."""
    data, path = load_manifest("rocky")
    if data is None:
        return
    existing = existing_kernels(data)
    added = 0

    base = "https://download.rockylinux.org/pub/rocky/9/BaseOS/x86_64/debug/tree/Packages/k/"
    html = fetch_html(base)
    if not html:
        print("  Rocky: mirror unreachable")
        return

    # Parse kernel-debuginfo RPM filenames
    rpms = re.findall(
        r'(kernel-debuginfo-(\d+\.\d+\.\d+-\d+\.\w+\.\w+)\.rpm)',
        html,
    )
    for filename, kernel in rpms:
        if "common" in filename:
            continue
        if kernel in existing:
            continue
        entry = {
            "kernel": kernel,
            "version": "9",
            "debug_url": f"{base}{filename}",
            "status": "pending",
        }
        if data.get("symbols") is None:
            data["symbols"] = []
        data["symbols"].append(entry)
        existing.add(kernel)
        added += 1
        print(f"  + Rocky 9: {kernel}")

    if added:
        save_manifest(data, path)
        print(f"  Rocky: added {added} new kernel(s)")
    else:
        print(f"  Rocky: up to date")


# ── Main ─────────────────────────────────────────────────────────────────

def main():
    print("Checking for new kernel releases...")
    print()
    check_fedora()
    print()
    check_centos()
    print()
    check_rocky()
    print()
    print("Done.")


if __name__ == "__main__":
    main()
