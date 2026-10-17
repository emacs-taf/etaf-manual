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


REPOSITORIES = {"etaf-install": "emacs-taf/emacs-taf"}
STYLE = """body { font: 16px/1.6 ui-sans-serif, system-ui, sans-serif; margin: 2rem auto;
  max-width: 62rem; padding: 0 1.2rem; color: #1d2330; }
h1 { font-size: 1.6rem; margin-bottom: .3rem; }
h2 { font-size: 1.1rem; margin: 1.8rem 0 .4rem; }
p.lead { margin-top: 0; color: #55607a; }
pre { background: #f4f6fb; border: 1px solid #dde3ee; border-radius: 8px; padding: .9rem 1rem; overflow-x: auto; }
table { border-collapse: collapse; width: 100%; margin-top: .6rem; }
th, td { text-align: left; padding: .45rem .6rem; border-bottom: 1px solid #e4e9f2; vertical-align: top; }
th { font-size: .85rem; text-transform: uppercase; letter-spacing: .04em; color: #55607a; }
code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .85em; }
footer { margin-top: 2rem; color: #55607a; font-size: .9rem; }
nav { margin-bottom: 1rem; } nav a { margin-right: 1rem; }"""

GROUPS = (
    ("framework", {"etaf-install", "etaf-ui", "etaf", "ebox", "ecss", "ekp", "etaf-db"},
     "Framework", "框架"),
    ("applications", {"etaf-md-preview", "etaf-rss", "etaf-reader", "etaf-algo-lab", "etaf-screensaver",
                      "etaf-desktop", "etaf-miniflux", "etaf-ncm", "etaf-weread", "etaf-bili",
                      "etaf-youtube", "etaf-pi", "etaf-telega", "etaf-ascii-video",
                      "etaf-video-player", "etaf-video-studio", "etaf-manual"},
     "Applications", "应用"),
    ("games", {"etaf-gamekit", "etaf-solitaire", "etaf-xiangqi", "etaf-tanks", "etaf-salvage"},
     "Games", "游戏"),
)

TEXT = {
    "en": {
        "archive": "ETAF package archive",
        "lead": ("This directory is the <code>package.el</code> archive for ETAF. "
                 "One entry installs everything ETAF provides:"),
        "steps": ("Evaluate this once (it only bootstraps the installer), then use "
                  "<code>M-x etaf-install</code> and pick a target. Applications and games "
                  "pull the framework they need automatically."),
        "columns": ("Package", "Version", "Requires", "Summary", "Source"),
        "footer": ("Manifest <a href=\"manifest.json\">manifest.json</a> records the sealed workspace "
                   "and provider revisions; each package page shows its source commit. Older versions "
                   "stay downloadable and a versioned file never changes bytes."),
        "install": "Install / 安装",
        "install_lead": ("One entry installs everything ETAF provides. Evaluate this once "
                         "(it only bootstraps the installer), then use <code>M-x etaf-install</code> "
                         "and pick <code>{name}</code>:"),
        "install_note": ("<code>etaf-install</code> checks the required capabilities, installs the "
                         "framework dependencies, opens the application and reopens it offline later. "
                         "Upgrade or remove with <code>M-x list-packages</code> (package.el is what runs "
                         "underneath), then restart Emacs."),
        "fields": {"version": "Version", "requires": "Requires", "repo": "Repository",
                   "commit": "Source commit", "sha": "SHA-256", "tar": "Source archive"},
        "tar_note": ("the exact bytes <code>package.el</code> installs; byte-compiled locally on install"),
        "page_footer": ("This page is generated from <a href=\"{manifest}\">manifest.json</a> on every "
                        "release. The archive is built from the commit above; rebuild it from that commit "
                        "to compare the checksum."),
        "other": ("简体中文", "/zh-cn/packages/"),
    },
    "zh": {
        "archive": "ETAF 包归档",
        "lead": "本目录是 ETAF 的 <code>package.el</code> 归档。一个入口即可安装 ETAF 提供的全部内容：",
        "steps": ("下面五行只需执行一次（只安装引导器），之后用 <code>M-x etaf-install</code> 选择目标。"
                  "应用和游戏会自动带上所需的框架依赖。"),
        "columns": ("包", "版本", "依赖", "简介", "源码包"),
        "footer": ("<a href=\"manifest.json\">manifest.json</a> 记录封口工作区与各提供方提交，每个包的页面给出"
                   "它对应的源码提交。旧版本始终可下载，同名版本的文件永不改变字节。"),
        "install": "安装",
        "install_lead": ("一个入口安装 ETAF 提供的全部内容。下面五行只需执行一次（只安装引导器），"
                         "之后用 <code>M-x etaf-install</code> 选择 <code>{name}</code>："),
        "install_note": ("<code>etaf-install</code> 会检查所需能力、安装框架依赖、打开应用，之后可离线重开。"
                         "升级或删除用 <code>M-x list-packages</code>（底层就是 package.el），改完重启 Emacs。"),
        "fields": {"version": "版本", "requires": "依赖", "repo": "源码仓库",
                   "commit": "源码提交", "sha": "SHA-256", "tar": "源码包"},
        "tar_note": "即 <code>package.el</code> 安装的同一份字节，安装时在本地编译",
        "page_footer": ("本页每次发布由 <a href=\"{manifest}\">manifest.json</a> 生成。归档由上面的提交构建，"
                        "可从该提交重建并比对校验和。"),
        "other": ("English", "/packages/"),
    },
}


def page(lang, title, body):
    return f"""<!doctype html>
<html lang="{'zh-CN' if lang == 'zh' else 'en'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>{STYLE}</style>
</head>
<body>
{body}
</body>
</html>
"""


def archive_pages(package_dir):
    """Write a bilingual archive: English at the root, Chinese under `zh-cn/`.

    Package names link to a page, never straight to a download: visitors want to
    know what a package is, where its source lives and how to install it. Both
    languages are generated from the published manifest, so they cannot drift.
    """
    import html
    import json

    manifest = json.loads((package_dir / "manifest.json").read_text())
    sources = manifest.get("sources", {})
    packages = sorted(manifest["packages"], key=lambda item: item["name"])
    for lang in ("en", "zh"):
        text = TEXT[lang]
        base = package_dir if lang == "en" else package_dir / "zh-cn"
        rows = []
        for group, members, label_en, label_zh in GROUPS:
            selected = [item for item in packages if item["name"] in members]
            if not selected:
                continue
            label = label_en if lang == "en" else label_zh
            rows.append(f'<h2>{label}</h2>\n<table>\n<thead><tr>' +
                        "".join(f'<th>{html.escape(column)}</th>' for column in text["columns"]) +
                        "</tr></thead>\n<tbody>")
            for item in selected:
                requirements = ", ".join(f"{key} {value}" for key, value in item["requirements"]) or "Emacs"
                tar_prefix = "" if lang == "en" else "../"
                rows.append(
                    "<tr>"
                    f'<td><a href="{html.escape(item["name"])}/"><strong>{html.escape(item["name"])}</strong></a></td>'
                    f'<td>{html.escape(item["version"])}</td>'
                    f'<td>{html.escape(requirements)}</td>'
                    f'<td>{html.escape(item.get("summary", ""))}</td>'
                    f'<td><a href="{tar_prefix}{html.escape(item["file"])}">tar</a></td>'
                    "</tr>")
            rows.append("</tbody>\n</table>")
        body = f"""<nav><a href="{text['other'][1]}">{text['other'][0]}</a>
<a href="https://etaf.top/{'introduction/' if lang == 'en' else 'zh-cn/introduction/'}">Reference manual / 参考手册</a></nav>
<h1>{text['archive']}</h1>
<p class="lead">{text['lead']}</p>
<pre><code>(require 'package)
(add-to-list 'package-archives '("etaf" . "https://etaf.top/packages/"))
(package-initialize)
(package-refresh-contents)
(package-install 'etaf-install)
(call-interactively #'etaf-install)</code></pre>
<p>{text['steps']}</p>
{chr(10).join(rows)}
<footer>{text['footer']}</footer>
"""
        target = base / "index.html"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(page(lang, text["archive"], body))
        for item in packages:
            package_page(item, sources, lang, base / item["name"])


def package_page(item, sources, lang, directory):
    """Write one package's detail page in LANG under DIRECTORY."""
    import html

    text = TEXT[lang]
    fields = text["fields"]
    name = item["name"]
    repo = REPOSITORIES.get(name, f"emacs-taf/{name}")
    requirements = ", ".join(f"{key} {value}" for key, value in item["requirements"]) or "Emacs"
    revision = sources.get(name, "")
    source_line = (
        f'<a href="https://github.com/{repo}/commit/{revision}"><code>{html.escape(revision[:12])}</code></a>'
        if revision else "not recorded")
    up = "../" if lang == "en" else "../../"
    switch = (f"/zh-cn/packages/{name}/" if lang == "en" else f"/packages/{name}/")
    body = f"""<nav><a href="../">← {text['archive']}</a><a href="{switch}">{text['other'][0]}</a></nav>
<h1>{html.escape(name)}</h1>
<p class="lead">{html.escape(item.get("summary", ""))}</p>
<h2>{text['install']}</h2>
<p>{text['install_lead'].format(name=html.escape(name))}</p>
<pre><code>(require 'package)
(add-to-list 'package-archives '("etaf" . "https://etaf.top/packages/"))
(package-initialize)
(package-refresh-contents)
(package-install 'etaf-install)
(call-interactively #'etaf-install)</code></pre>
<p>{text['install_note']}</p>
<table>
<tr><th>{fields['version']}</th><td><code>{html.escape(item["version"])}</code></td></tr>
<tr><th>{fields['requires']}</th><td>{html.escape(requirements)}</td></tr>
<tr><th>{fields['repo']}</th><td><a href="https://github.com/{repo}">github.com/{repo}</a></td></tr>
<tr><th>{fields['commit']}</th><td>{source_line}</td></tr>
<tr><th>{fields['sha']}</th><td><code>{html.escape(item["sha256"])}</code></td></tr>
<tr><th>{fields['tar']}</th><td><a href="{up}{html.escape(item["file"])}">{html.escape(item["file"])}</a>
  — {text['tar_note']}</td></tr>
</table>
<footer>{text['page_footer'].format(manifest=up + "manifest.json")}</footer>
"""
    target = directory / "index.html"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(page(lang, f"{name} — ETAF", body))


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
            archive_pages(work / "packages")
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
