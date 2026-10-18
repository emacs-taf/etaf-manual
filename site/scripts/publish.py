#!/usr/bin/env python3
"""Build/publish etaf.top, preserving installed-package download URLs.

Default: build the site and deploy it. --packages DIR combines the site with a
validated workspace package release. --packages-only DIR leaves site pages alone.
--pages-only DIR regenerates the archive pages from an already published archive.
ETAF_TOP_ROOT=lightos (default) uses the existing SSH hop; direct uses ETAF_TOP_HOST
(default root@aliyun-hk). ETAF_TOP_KEEP defaults to 5. No SSH or web-server
configuration is modified. Authentication is noninteractive.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import html
import json
import os
from pathlib import Path
import re
import shlex
import shutil
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
STYLE = """*, *::before, *::after { box-sizing: border-box; }
:root {
  color-scheme: light;
  --paper: #faf8f3;
  --paper-2: #f3f0e8;
  --rule: #e2ddd1;
  --rule-strong: #c9c3b5;
  --ink: #1c1a16;
  --ink-2: #45413a;
  --ink-3: #7a7468;
  --accent: #5b3ea8;
  --font-text: "Source Serif 4", "Iowan Old Style", "Palatino Linotype", Palatino,
    Georgia, "Songti SC", "Noto Serif SC", serif;
  --font-mono: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --paper: #191a1c;
  --paper-2: #202225;
  --rule: #2f3135;
  --rule-strong: #43464b;
  --ink: #e3e1db;
  --ink-2: #b8b6af;
  --ink-3: #89877f;
  --accent: #c3b0ff;
}
:root[data-theme="dark"] body {
  background-color: var(--paper);
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/%3E%3CfeColorMatrix type='saturate' values='0'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='.055'/%3E%3C/svg%3E");
  background-size: 160px 160px;
}
html { -webkit-text-size-adjust: 100%; }
body { margin: 0; background: var(--paper); color: var(--ink);
  font-family: var(--font-text); font-size: 1rem; line-height: 1.65; }
a { color: var(--accent); text-decoration-thickness: 1px; text-underline-offset: 2px; }
a:hover { text-decoration-thickness: 2px; }
code { font-family: var(--font-mono); font-size: .86em; background: var(--paper-2);
  border: 1px solid var(--rule); border-radius: 2px; padding: .05em .3em; }
pre { margin: .8rem 0 0; padding: 1rem 1.1rem; border: 1px solid var(--rule);
  border-left: 3px solid var(--accent); background: var(--paper-2);
  white-space: pre-wrap; overflow-wrap: anywhere;
  font-family: var(--font-mono); font-size: .82rem; line-height: 1.7; }
pre code { background: none; border: 0; padding: 0; font: inherit; }
.wrap { width: 100%; max-width: 76rem; margin: 0 auto; padding: 0 clamp(1.1rem, 4vw, 2.5rem); }
.visually-hidden { position: absolute; width: 1px; height: 1px; margin: -1px;
  padding: 0; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; border: 0; }
.site-header { border-bottom: 1px solid var(--rule); }
.bar { display: flex; align-items: center; justify-content: space-between;
  gap: 1rem; height: 3.6rem; }
.brand { display: inline-flex; align-items: center; gap: .55rem; color: var(--ink);
  text-decoration: none; font-size: .95rem; font-weight: 600;
  letter-spacing: .14em; text-transform: uppercase; }
.brand img { display: block; }
.theme { display: inline-flex; align-items: center; justify-content: center;
  width: 2rem; height: 2rem; padding: 0; border: 1px solid var(--rule);
  border-radius: 50%; background: transparent; color: var(--ink-2); cursor: pointer; }
.theme:hover { color: var(--accent); border-color: var(--accent); }
.theme svg { width: 1rem; height: 1rem; }
.theme .sun, .theme .moon { display: none; }
:root[data-theme="dark"] .theme .sun { display: block; }
:root[data-theme="light"] .theme .moon { display: block; }
.hero { padding: clamp(3rem, 7vw, 5rem) 0 1.6rem; }
.eyebrow { margin: 0 0 .9rem; font-family: var(--font-mono); font-size: .72rem;
  letter-spacing: .16em; text-transform: uppercase; color: var(--accent); }
h1 { margin: 0; font-size: clamp(2.3rem, 6vw, 3.6rem); line-height: 1.05;
  font-weight: 600; letter-spacing: -.02em; overflow-wrap: anywhere; }
h2 { margin: 0; font-size: 1.4rem; line-height: 1.25; font-weight: 600; letter-spacing: -.01em; }
.lead { margin: 1rem 0 0; max-width: 48rem; font-size: clamp(1.05rem, 2.2vw, 1.22rem);
  line-height: 1.6; color: var(--ink-2); }
.meta { display: flex; flex-wrap: wrap; align-items: baseline; gap: .55rem;
  margin: 1.4rem 0 0; font-family: var(--font-mono); font-size: .8rem; color: var(--ink-3); }
.meta strong { font-weight: 600; color: var(--ink); font-variant-numeric: tabular-nums; }
.meta .dot { color: var(--rule-strong); }
.install { padding: 1.6rem 0 0; border-top: 1px solid var(--rule); }
.install-head { display: flex; align-items: baseline; justify-content: space-between; gap: 1rem; }
.copy { padding: .25rem .6rem; border: 1px solid var(--rule-strong); border-radius: 2px;
  background: transparent; color: var(--ink-3); font-family: var(--font-mono);
  font-size: .68rem; letter-spacing: .08em; text-transform: uppercase; cursor: pointer; }
.copy:hover, .copy.done { color: var(--accent); border-color: var(--accent); }
.note { margin: .75rem 0 0; max-width: 54rem; color: var(--ink-3); font-size: .9rem; }
.group { margin-top: 3rem; }
.group-head { display: flex; align-items: baseline; gap: .7rem; }
.group-head h2 { font-size: 1.5rem; }
.tag { font-family: var(--font-mono); font-size: .7rem; color: var(--ink-3); }
table { width: 100%; border-collapse: collapse; margin-top: .4rem; }
thead th { padding: .55rem .7rem .5rem; border-bottom: 1px solid var(--rule-strong);
  color: var(--ink-3); font-family: var(--font-mono); font-size: .66rem; font-weight: 500;
  letter-spacing: .11em; text-transform: uppercase; text-align: left; }
tbody td { padding: .8rem .7rem; border-bottom: 1px solid var(--rule); vertical-align: top; text-align: left; }
tbody tr:hover td { background: var(--paper-2); }
th:first-child, td:first-child { padding-left: 0; }
th:last-child, td:last-child { padding-right: 0; }
.pkg a { color: var(--ink); font-size: 1.03rem; font-weight: 600; text-decoration: none; }
.pkg a:hover { color: var(--accent); }
.summary { display: block; margin-top: .1rem; color: var(--ink-3); font-size: .86rem;
  line-height: 1.5; overflow-wrap: anywhere; }
.version { padding: .1rem .4rem; border: 1px solid var(--rule); border-radius: 2px;
  background: var(--paper-2); color: var(--ink-2); font-family: var(--font-mono);
  font-size: .74rem; white-space: nowrap; }
.requires { max-width: 18rem; color: var(--ink-3); font-family: var(--font-mono);
  font-size: .72rem; line-height: 1.6; overflow-wrap: anywhere; }
th.num, td.num { text-align: right; }
td.num { color: var(--ink-3); font-family: var(--font-mono); font-size: .85rem;
  font-variant-numeric: tabular-nums; white-space: nowrap; }
td.num.is-known { color: var(--ink); }
th.src, td.src { width: 1%; text-align: right; white-space: nowrap; }
.tar { display: inline-flex; align-items: center; gap: .35rem; padding: .2rem .5rem;
  border: 1px solid var(--rule); border-radius: 2px; color: var(--ink-2);
  font-family: var(--font-mono); font-size: .72rem; text-decoration: none; }
.tar:hover { color: var(--accent); border-color: var(--accent); }
.tar svg { width: .85rem; height: .85rem; }
.crumbs { display: flex; align-items: center; gap: .45rem; padding: 1.8rem 0 0;
  color: var(--ink-3); font-family: var(--font-mono); font-size: .73rem; }
.crumbs a { color: var(--ink-3); text-decoration: none; }
.crumbs a:hover { color: var(--accent); }
.hero.detail { padding: 1.2rem 0; }
.details { margin-top: 2.5rem; padding-top: 1.6rem; border-top: 1px solid var(--rule); }
.title-row { display: flex; align-items: baseline; flex-wrap: wrap; gap: 1rem; }
.title-row .version { font-size: .85rem; padding: .15rem .5rem; }
.actions { display: flex; align-items: center; flex-wrap: wrap; gap: .6rem; margin-top: 1.3rem; }
.button { display: inline-flex; align-items: center; gap: .4rem; padding: .4rem .8rem;
  border: 1px solid var(--rule-strong); border-radius: 2px; color: var(--ink-2);
  font-family: var(--font-mono); font-size: .76rem; text-decoration: none; }
.button:hover { color: var(--accent); border-color: var(--accent); }
.button.primary { background: var(--ink); border-color: var(--ink); color: var(--paper); }
.button.primary:hover { background: var(--accent); border-color: var(--accent); color: var(--paper); }
.button svg { width: .9rem; height: .9rem; }
.stat { color: var(--ink-3); font-family: var(--font-mono); font-size: .76rem; }
.stat strong { color: var(--ink); font-size: .95rem; font-weight: 600;
  font-variant-numeric: tabular-nums; }
.facts { margin: .8rem 0 0; }
.facts > div { display: grid; grid-template-columns: 9.5rem minmax(0, 1fr); gap: 1rem;
  padding: .65rem 0; border-top: 1px solid var(--rule); }
.facts > div:first-child { border-top: 0; }
.facts dt { padding-top: .15rem; color: var(--ink-3); font-family: var(--font-mono);
  font-size: .66rem; letter-spacing: .1em; text-transform: uppercase; }
.facts dd { margin: 0; color: var(--ink-2); overflow-wrap: anywhere; }
.site-footer { margin-top: 3.5rem; padding: 1.4rem 0 3rem; border-top: 1px solid var(--rule);
  color: var(--ink-3); font-size: .86rem; }
.site-footer p { margin: 0; max-width: 56rem; }
.site-footer .asof { margin-top: .5rem; font-family: var(--font-mono); font-size: .7rem; }
@media (max-width: 720px) {
  thead { display: none; }
  tbody tr { display: grid; grid-template-columns: auto minmax(0, 1fr) auto;
    grid-template-areas: "pkg pkg pkg" "ver dl tar"; gap: .35rem .8rem;
    align-items: center; padding: .85rem 0; border-bottom: 1px solid var(--rule); }
  tbody td { padding: 0; border-bottom: 0; }
  tbody tr:hover td { background: none; }
  td.pkg { grid-area: pkg; }
  td.version-cell { grid-area: ver; }
  td.requires { display: none; }
  td.num { grid-area: dl; justify-self: start; text-align: left; font-size: .78rem; }
  td.num::before { content: attr(data-label); margin-right: .3rem; color: var(--ink-3);
    font-size: .62rem; letter-spacing: .1em; text-transform: uppercase; }
  td.src { grid-area: tar; justify-self: end; width: auto; }
  .facts > div { grid-template-columns: 1fr; gap: .1rem; }
}
"""

GROUPS = (
    ("Framework", {"etaf-install", "etaf-ui", "etaf", "ebox", "ecss", "ekp", "etaf-db"}),
    ("Applications", {"etaf-md-preview", "etaf-rss", "etaf-reader", "etaf-algo-lab",
                      "etaf-screensaver", "etaf-desktop", "etaf-miniflux", "etaf-ncm",
                      "etaf-weread", "etaf-bili", "etaf-youtube", "etaf-pi", "etaf-telega",
                      "etaf-ascii-video", "etaf-video-player", "etaf-video-studio",
                      "etaf-manual"}),
    ("Games", {"etaf-gamekit", "etaf-solitaire", "etaf-xiangqi", "etaf-tanks", "etaf-salvage"}),
)

MANUAL = "https://etaf.top/introduction/"
INSTALL = "https://etaf.top/introduction/#installation"
BOOTSTRAP = """(require 'package)
(add-to-list 'package-archives '("etaf" . "https://etaf.top/packages/"))
(package-initialize)
(package-refresh-contents)
(package-install 'etaf-install)
(call-interactively #'etaf-install)"""


TAR_ICON = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" '
            'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
            '<path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>')

HEADER = """<header class="site-header">
<div class="wrap bar">
<a class="brand" href="/"><img src="/favicon.svg" alt="" width="24" height="24"><span>ETAF</span></a>
<button class="theme" type="button" data-theme-toggle aria-label="Toggle colour theme" title="Toggle colour theme">
<svg class="sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>
<svg class="moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5a8.5 8.5 0 1 0 11 11Z"/></svg>
</button>
</div>
</header>"""

THEME_SCRIPT = """(() => {
  const root = document.documentElement;
  let stored = null;
  try { stored = localStorage.getItem('starlight-theme'); } catch (error) {}
  const systemDark = matchMedia('(prefers-color-scheme: dark)').matches;
  root.dataset.theme = stored === 'light' || stored === 'dark' ? stored
    : systemDark ? 'dark' : 'light';
  document.addEventListener('click', (event) => {
    if (!(event.target instanceof Element)) return;
    const button = event.target.closest('[data-theme-toggle]');
    if (!button) return;
    const next = root.dataset.theme === 'dark' ? 'light' : 'dark';
    root.dataset.theme = next;
    try { localStorage.setItem('starlight-theme', next); } catch (error) {}
  });
})();"""

PAGE_SCRIPT = """(() => {
  const number = new Intl.NumberFormat('en-US');
  const setCount = (node, value) => {
    node.textContent = number.format(value);
    node.classList.add('is-known');
  };
  document.querySelectorAll('[data-copy]').forEach((button) => {
    button.addEventListener('click', async () => {
      const target = document.querySelector(button.dataset.copy);
      if (!target) return;
      try { await navigator.clipboard.writeText(target.textContent); }
      catch (error) {
        const range = document.createRange();
        range.selectNodeContents(target);
        const selection = getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        document.execCommand('copy');
        selection.removeAllRanges();
      }
      button.textContent = 'Copied';
      button.classList.add('done');
      setTimeout(() => { button.textContent = 'Copy'; button.classList.remove('done'); }, 1600);
    });
  });
  const source = document.body.dataset.downloadsUrl;
  if (!source) return;
  fetch(source, {cache: 'no-store'}).then((response) => response.ok ? response.json() : null)
    .then((data) => {
      if (!data) return;
      const counts = data.packages || {};
      document.querySelectorAll('[data-downloads]').forEach((node) => {
        const value = counts[node.dataset.downloads];
        if (Number.isFinite(value)) setCount(node, value);
      });
      const total = Number.isFinite(data.total) ? data.total
        : Object.values(counts).reduce((sum, value) => sum + value, 0);
      document.querySelectorAll('[data-downloads-total]').forEach((node) => setCount(node, total));
      document.querySelectorAll('[data-downloads-asof]').forEach((node) => {
        if (!data.as_of) return;
        node.textContent = 'Download counts updated ' + data.as_of.replace('T', ' ').replace('Z', ' UTC');
        node.hidden = false;
      });
    }).catch(() => {});
})();"""


def page(title, body, downloads="downloads.json", *, canonical, description):
    title = html.escape(title)
    description = html.escape(description)
    canonical = html.escape(canonical)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>{title}</title>
<meta name="description" content="{description}">
<link rel="canonical" href="{canonical}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="ETAF">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:url" content="{canonical}">
<meta property="og:image" content="https://etaf.top/og/archive.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="ETAF package archive">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{title}">
<meta name="twitter:description" content="{description}">
<meta name="twitter:image" content="https://etaf.top/og/archive.png">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<style>{STYLE}</style>
<script>{THEME_SCRIPT}</script>
</head>
<body data-downloads-url="{downloads}">
{HEADER}
{body}
<script>{PAGE_SCRIPT}</script>
</body>
</html>
"""


def archive_pages(package_dir):
    """Write the archive index and one detail page per package.

    Package names link to a page, never straight to a download: visitors want to
    know what a package is, where its source lives and how to install it. Every
    page is generated from the published manifest, so it cannot drift from what
    the archive actually serves. Download counts are filled from downloads.json,
    which a timer on the web host rewrites from the access log; the markup keeps
    a placeholder so the page still reads without JavaScript.
    """
    manifest = json.loads((package_dir / "manifest.json").read_text())
    sources = manifest.get("sources", {})
    packages = sorted(manifest["packages"], key=lambda item: item["name"])
    sections = []
    for label, members in GROUPS:
        selected = [item for item in packages if item["name"] in members]
        if not selected:
            continue
        rows = []
        for item in selected:
            name = html.escape(item["name"])
            version = html.escape(item["version"])
            requirements = html.escape(requirements_text(item))
            summary = html.escape(item.get("summary", ""))
            rows.append(
                "<tr>"
                f'<td class="pkg"><a href="{name}/"><strong>{name}</strong></a>'
                f'<span class="summary">{summary}</span></td>'
                f'<td class="version-cell"><span class="version">{version}</span></td>'
                f'<td class="requires">{requirements}</td>'
                f"{download_cell(item['name'])}"
                f'<td class="src"><a class="tar" href="{html.escape(item["file"])}" '
                f'title="Download {name} {version}">{TAR_ICON}<span>tar</span></a></td>'
                "</tr>")
        sections.append(f"""<section class="group" id="{label.lower()}">
<div class="group-head"><h2>{label}</h2><span class="tag">{len(selected)} packages</span></div>
<table>
<thead><tr><th scope="col">Package</th><th scope="col">Version</th>
<th scope="col" class="requires">Requires</th><th scope="col" class="num">Downloads</th>
<th scope="col" class="src"><span class="visually-hidden">Tarball</span></th></tr></thead>
<tbody>
{chr(10).join(rows)}
</tbody>
</table>
</section>""")
    body = f"""<main class="wrap">
<section class="hero">
<p class="eyebrow">package.el archive</p>
<h1>ETAF package archive</h1>
<p class="lead">One archive for all of ETAF: the framework, its applications and its games.
Add it once, then <code>M-x etaf-install</code> pulls everything a target needs.</p>
<p class="meta"><span><strong>{len(packages)}</strong> packages</span>
<span class="dot" aria-hidden="true">·</span>
<span><strong data-downloads-total>—</strong> downloads</span>
<span class="dot" aria-hidden="true">·</span>
<span>Emacs 29.1 or newer</span></p>
</section>
<section class="install" aria-labelledby="install-title">
<div class="install-head"><h2 id="install-title">Install</h2>
<button class="copy" type="button" data-copy="#bootstrap">Copy</button></div>
<pre id="bootstrap"><code>{BOOTSTRAP}</code></pre>
<p class="note">Evaluate this once; it only bootstraps the installer. Then run
<code>M-x etaf-install</code> and pick a target. Applications and games pull the framework they
need automatically. Read the <a href="{INSTALL}">installation reference</a> or the
<a href="{MANUAL}">ETAF Reference Manual</a> for the supported workflows.</p>
</section>
{chr(10).join(sections)}
<footer class="site-footer">
<p>Manifest <a href="manifest.json">manifest.json</a> records the sealed workspace and provider
revisions; each package page shows its source commit. Older versions stay downloadable, and a
versioned file never changes bytes.</p>
<p class="asof" data-downloads-asof hidden></p>
</footer>
</main>"""
    (package_dir / "index.html").write_text(page(
        "ETAF package archive", body,
        canonical="https://etaf.top/packages/",
        description="ETAF package archive: framework, applications and games for Emacs 29.1 "
                    "and newer. One package.el entry installs everything."))
    for item in packages:
        package_page(item, sources, package_dir / item["name"])


def requirements_text(item):
    return ", ".join(f"{key} {value}" for key, value in item["requirements"]) or "Emacs"


def download_cell(name):
    """A count cell filled by downloads.json; the dash is the no-JavaScript state."""
    safe = html.escape(name)
    return (f'<td class="num" data-downloads="{safe}" data-label="downloads" '
            f'title="Downloads of every {safe} version">—</td>')


def package_page(item, sources, directory):
    """Write one package's detail page."""
    name = item["name"]
    safe_name = html.escape(name)
    version = html.escape(item["version"])
    repo = REPOSITORIES.get(name, f"emacs-taf/{name}")
    requirements = html.escape(requirements_text(item))
    revision = sources.get(name, "")
    source_line = (
        f'<a href="https://github.com/{repo}/commit/{revision}"><code>{html.escape(revision[:12])}</code></a>'
        if revision else "not recorded")
    tarball = html.escape(item["file"])
    body = f"""<main class="wrap">
<nav class="crumbs" aria-label="Breadcrumb"><a href="../">Packages</a>
<span aria-hidden="true">/</span><span>{safe_name}</span></nav>
<section class="hero detail">
<div class="title-row"><h1>{safe_name}</h1><span class="version">{version}</span></div>
<p class="lead">{html.escape(item.get("summary", ""))}</p>
<div class="actions">
<a class="button primary" href="../{tarball}">{TAR_ICON}<span>Download {version}</span></a>
<a class="button" href="https://github.com/{repo}">Repository</a>
<span class="stat"><strong data-downloads="{safe_name}">—</strong> downloads</span>
</div>
</section>
<section class="install" aria-labelledby="install-title">
<div class="install-head"><h2 id="install-title">Install</h2>
<button class="copy" type="button" data-copy="#bootstrap">Copy</button></div>
<pre id="bootstrap"><code>{BOOTSTRAP}</code></pre>
<p class="note">One entry installs everything ETAF provides. Evaluate this once (it only bootstraps
the installer), then use <code>M-x etaf-install</code> and pick <code>{safe_name}</code>.
<code>etaf-install</code> checks the required capabilities, installs the framework dependencies,
opens the application and reopens it offline later. Upgrade or remove with
<code>M-x list-packages</code>, then restart Emacs. Read the
<a href="{INSTALL}">installation reference</a> for the full workflow.</p>
</section>
<section class="details" aria-labelledby="details-title">
<div class="group-head"><h2 id="details-title">Package details</h2></div>
<dl class="facts">
<div><dt>Version</dt><dd><code>{version}</code></dd></div>
<div><dt>Requires</dt><dd>{requirements}</dd></div>
<div><dt>Repository</dt><dd><a href="https://github.com/{repo}">github.com/{repo}</a></dd></div>
<div><dt>Source commit</dt><dd>{source_line}</dd></div>
<div><dt>SHA-256</dt><dd><code>{html.escape(item["sha256"])}</code></dd></div>
<div><dt>Archive file</dt><dd><a href="../{tarball}"><code>{tarball}</code></a> — the exact bytes
<code>package.el</code> installs, byte-compiled locally on install</dd></div>
</dl>
</section>
<footer class="site-footer">
<p>This page is generated from <a href="../manifest.json">manifest.json</a> on every release.
The archive is built from the commit above; rebuild it from that commit to compare the checksum.</p>
<p class="asof" data-downloads-asof hidden></p>
</footer>
</main>"""
    target = directory / "index.html"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(page(
        f"{name} — ETAF package archive", body, "../downloads.json",
        canonical=f"https://etaf.top/packages/{name}/",
        description=item.get("summary", "")))


def pages_source(destination, source):
    """Copy an already public archive so archive_pages can rewrite its presentation.

    A pages-only publication cannot introduce package bytes: the manifest and
    every indexed tarball must verify first. Older tarballs stay in the previous
    release and the deployer carries them forward unchanged.
    """
    sys.path.insert(0, str(REPOSITORY / "scripts"))
    import package_archive
    manifest = package_archive.verify(source)
    destination.mkdir()
    for name in ("manifest.json", "archive-contents",
                 *(item["file"] for item in manifest["packages"])):
        shutil.copyfile(source / name, destination / name)


def publish(args):
    package_input = args.packages_only or args.packages
    pages_input = args.pages_only
    archive_input = package_input or pages_input
    mode = "packages" if pages_input or args.packages_only else "combined" if args.packages else "site"
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
        elif pages_input:
            pages_source(work / "packages", pages_input.resolve())
        if not args.no_build and not (args.packages_only or pages_input):
            subprocess.run(["npm", "run", "build"], cwd=SITE, check=True, timeout=600)
        if args.build_only:
            print(f"Built {SITE / 'dist'}")
            return
        if mode != "packages" and not (SITE / "dist/index.html").is_file():
            raise ValueError("Site build is missing; run without --no-build")
        if mode != "packages" and (SITE / "dist/packages").exists():
            raise ValueError("dist/packages is reserved; supply a validated --packages release instead")
        if archive_input:
            archive_pages(work / "packages")
        payload = work / "payload.tgz"
        with tarfile.open(payload, "w:gz") as archive:
            if mode != "packages":
                add_tree(archive, SITE / "dist")
            if archive_input:
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
    packages.add_argument("--pages-only", type=Path,
                          help="Regenerate archive pages from an already published archive; package bytes stay unchanged")
    args = parser.parse_args()
    if args.build_only and (args.packages or args.packages_only or args.pages_only):
        parser.error("--build-only cannot publish packages or archive pages")
    publish(args)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"error=publish\nhint={error}", file=sys.stderr)
        sys.exit(1)
