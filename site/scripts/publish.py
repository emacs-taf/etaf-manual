#!/usr/bin/env python3
"""Build/publish etaf.top, preserving installed-package download URLs.

Default: build the site and deploy it. --packages DIR combines the site with a
validated workspace package release. --packages-only DIR leaves site pages alone.
ETAF_TOP_ROOT=lightos (default) uses the existing SSH hop; direct uses ETAF_TOP_HOST
(default root@aliyun-hk). ETAF_TOP_KEEP defaults to 5. No SSH or web-server
configuration is modified. Authentication is noninteractive.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tarfile
import tempfile
import uuid

SITE = Path(__file__).resolve().parents[1]
REPOSITORY = SITE.parent


def remote(command, **kwargs):
    host = os.environ.get("ETAF_TOP_HOST", "root@aliyun-hk")
    route = os.environ.get("ETAF_TOP_ROOT", "lightos")
    if route not in ("lightos", "direct") or not re.fullmatch(r"[A-Za-z0-9_@.:-]+", host) or host.startswith("-"):
        raise ValueError("Invalid ETAF_TOP_ROOT or ETAF_TOP_HOST")
    ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", host, command]
    if route == "lightos":
        ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "lightos", shlex.join(ssh)]
    return subprocess.run(ssh, check=True, timeout=600, **kwargs)


def add_tree(archive, directory, prefix=""):
    """Send regular generated files only; never follow resource symlinks."""
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Publication input cannot be a symlink: {path}")
        if path.is_file():
            archive.add(path, arcname=prefix + path.relative_to(directory).as_posix(), recursive=False)
        elif not path.is_dir():
            raise ValueError(f"Publication input is not a regular file: {path}")


def archive_index(package_dir):
    """Write a readable index for the archive directory.

    package.el only needs `archive-contents`, but a bare directory URL answers
    404 without a page, so visitors conclude the archive is not public. The
    listing is generated from the published manifest, not maintained by hand.
    """
    import html
    import json

    manifest = json.loads((package_dir / "manifest.json").read_text())
    rows = []
    for item in sorted(manifest["packages"], key=lambda entry: entry["name"]):
        requirements = ", ".join(f"{name} {version}" for name, version in item["requirements"]) or "Emacs"
        rows.append(
            "<tr>"
            f'<td><a href="{html.escape(item["file"])}">{html.escape(item["name"])}</a></td>'
            f'<td>{html.escape(item["version"])}</td>'
            f'<td>{html.escape(requirements)}</td>'
            f'<td>{html.escape(item.get("summary", ""))}</td>'
            f'<td><code>{html.escape(item["sha256"][:12])}</code></td>'
            "</tr>")
    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ETAF package archive</title>
<style>
body {{ font: 16px/1.6 ui-sans-serif, system-ui, sans-serif; margin: 2rem auto; max-width: 62rem; padding: 0 1.2rem; color: #1d2330; }}
h1 {{ font-size: 1.6rem; margin-bottom: .3rem; }}
p.lead {{ margin-top: 0; color: #55607a; }}
pre {{ background: #f4f6fb; border: 1px solid #dde3ee; border-radius: 8px; padding: .9rem 1rem; overflow-x: auto; }}
table {{ border-collapse: collapse; width: 100%; margin-top: 1.5rem; }}
th, td {{ text-align: left; padding: .45rem .6rem; border-bottom: 1px solid #e4e9f2; vertical-align: top; }}
th {{ font-size: .85rem; text-transform: uppercase; letter-spacing: .04em; color: #55607a; }}
code {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .85em; }}
footer {{ margin-top: 2rem; color: #55607a; font-size: .9rem; }}
</style>
</head>
<body>
<h1>ETAF package archive</h1>
<p class="lead">This directory is the <code>package.el</code> archive for ETAF. Workstation install:</p>
<pre><code>(require 'package)
(add-to-list 'package-archives '("etaf" . "https://etaf.top/packages/"))
(package-initialize)
(package-refresh-contents)
(package-install 'etaf-install)
(call-interactively #'etaf-install)</code></pre>
<table>
<thead><tr><th>Package</th><th>Version</th><th>Requires</th><th>Summary</th><th>SHA-256</th></tr></thead>
<tbody>
{chr(10).join(rows)}
</tbody>
</table>
<footer>Manifest <a href="manifest.json">manifest.json</a> records the sealed workspace and provider revisions.
Older versions stay downloadable; a versioned file never changes bytes.
See the <a href="/introduction/#installation">installation reference</a> /
<a href="/zh-cn/introduction/#安装">安装说明</a>.</footer>
</body>
</html>
"""
    (package_dir / "index.html").write_text(page)


def publish(args):
    package_input = args.packages_only or args.packages
    mode = "packages" if args.packages_only else "combined" if args.packages else "site"
    keep = int(os.environ.get("ETAF_TOP_KEEP", "5"))
    if keep < 2:
        raise ValueError("ETAF_TOP_KEEP must retain at least two releases")
    with tempfile.TemporaryDirectory(prefix="etaf-top-") as temporary:
        work = Path(temporary)
        if package_input:
            # This command rejects partial/stale evidence and developer archives,
            # then copies an explicit public allowlist. Logs stay on this host.
            subprocess.run([sys.executable, str(REPOSITORY.parent / "scripts/package-release.py"),
                            "stage", "--directory", str(package_input.resolve()),
                            "--output", str(work / "packages")], check=True, timeout=120)
        if not args.no_build and not args.packages_only:
            subprocess.run(["npm", "run", "build"], cwd=SITE, check=True, timeout=600)
        if args.build_only:
            print(f"Built {SITE / 'dist'}")
            return
        if mode != "packages" and not (SITE / "dist/index.html").is_file():
            raise ValueError("Site build is missing; run without --no-build")
        if mode != "packages" and (SITE / "dist/packages").exists():
            raise ValueError("dist/packages is reserved; supply a validated --packages release instead")
        if package_input:
            archive_index(work / "packages")
        payload = work / "payload.tgz"
        with tarfile.open(payload, "w:gz") as archive:
            if mode != "packages":
                add_tree(archive, SITE / "dist")
            if package_input:
                add_tree(archive, work / "packages", "packages/")
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
        staging = remote("mktemp -d /tmp/etaf-top.XXXXXXXX", capture_output=True, text=True).stdout.strip()
        if not re.fullmatch(r"/tmp/etaf-top\.[A-Za-z0-9]+", staging):
            raise ValueError("Remote did not return a safe upload directory")
        try:
            files = {"payload.tgz": payload,
                     "deploy-release.py": SITE / "scripts/deploy-release.py",
                     "package_archive.py": REPOSITORY / "scripts/package_archive.py"}
            for name, source in files.items():
                with source.open("rb") as stream:
                    remote("cat > " + shlex.quote(staging + "/" + name), stdin=stream)
            command = ["python3", staging + "/deploy-release.py", "--archive", staging + "/payload.tgz",
                       "--release", stamp, "--mode", mode, "--keep", str(keep)]
            try:
                remote(shlex.join(command))
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                print("Deployment did not confirm success; reading current without changing it", file=sys.stderr)
                remote("readlink /srv/etaf.top/current")
                raise
            current = remote("readlink /srv/etaf.top/current", capture_output=True, text=True).stdout.strip()
            if current != "/srv/etaf.top/releases/" + stamp:
                raise ValueError(f"A different release is current after deployment: {current}")
            print(f"Published https://etaf.top ({mode}, release {stamp}); current read back")
        finally:
            try:
                remote("rm -rf -- " + shlex.quote(staging))
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                print(f"Upload cleanup failed; private staging remains at {staging}: {error}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    build = parser.add_mutually_exclusive_group()
    build.add_argument("--build-only", action="store_true")
    build.add_argument("--no-build", action="store_true")
    packages = parser.add_mutually_exclusive_group()
    packages.add_argument("--packages", type=Path, help="Publish site and validated package archive together")
    packages.add_argument("--packages-only", type=Path, help="Publish packages without rebuilding/changing site pages")
    args = parser.parse_args()
    if args.build_only and (args.packages or args.packages_only):
        parser.error("--build-only cannot publish packages")
    publish(args)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"error=publish\nhint={error}", file=sys.stderr)
        sys.exit(1)
