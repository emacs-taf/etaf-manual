#!/usr/bin/env python3
"""Check external repository links that point into the ETAF Reference Manual."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys
import unicodedata
from urllib.parse import unquote

SKIP_DIRECTORIES = {'.git', '.jj', 'node_modules', '__pycache__'}
REFERENCE = re.compile(
    r'https?://[^/\s)]+/emacs-taf/etaf-manual/'
    r'(?:src|tree)/branch/main/book/(?P<language>en|zh-CN)/'
    r'(?P<chapter>[a-z0-9-]+)\.md(?:#(?P<anchor>[^)\s]+))?'
)
HEADING = re.compile(r'^[ ]{0,3}(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$')
FENCE = re.compile(r'^[ ]{0,3}(`{3,}|~{3,})[ \t]*(.*)$')
LINK = re.compile(r'\[([^]]*)\]\([^)]*\)')


def markdown_files(directory):
    """Yield Markdown files below DIRECTORY, excluding generated directories."""
    for current, directories, files in os.walk(directory):
        directories[:] = sorted(name for name in directories
                                if name not in SKIP_DIRECTORIES)
        for name in sorted(files):
            if name.endswith('.md'):
                yield Path(current) / name


def scanned_files(root, manuscript):
    """Return the Markdown files that may contain manual references."""
    files = set(root.glob('*.md'))
    docs = root / 'docs'
    if docs.is_dir():
        files.update(markdown_files(docs))

    repositories = {
        child for child in root.iterdir()
        if child.is_dir() and ((child / '.git').exists() or (child / '.jj').exists())
    }
    repositories.add(manuscript)
    for repository in repositories:
        if repository.is_dir():
            files.update(markdown_files(repository))
    return sorted(files)


def generated_chapters(manuscript):
    """Return IDs for generated appendices and indices without source files."""
    try:
        description = json.loads((manuscript / 'book/book.json').read_text())
    except (OSError, ValueError):
        return set()
    entries = list(description.get('appendices') or []) + list(description.get('indices') or [])
    return {entry['id'] for entry in entries
            if isinstance(entry, dict) and entry.get('id') and entry.get('generate')}


def slug(text):
    """Return TEXT's GitHub-style heading slug as etaf-manual does."""
    plain = LINK.sub(r'\1', text).lower()
    characters = []
    for character in plain:
        category = unicodedata.category(character)
        if character == ' ':
            characters.append('-')
        elif (character in {'-', '_'} or category[:1] in {'L', 'N', 'M'}):
            characters.append(character)
    return ''.join(characters)


def chapter_anchors(chapter):
    """Return the unique heading anchors defined by CHAPTER."""
    seen = {}
    anchors = set()
    fence = None
    for line in chapter.read_text().splitlines():
        if fence:
            if re.match(r'^[ ]{0,3}' + re.escape(fence) + r'[`~]*[ \t]*$', line):
                fence = None
            continue
        opening = FENCE.match(line)
        if opening:
            fence = opening.group(1)
            continue
        heading = HEADING.match(line)
        if not heading:
            continue
        base = slug(heading.group(2))
        if base in seen:
            seen[base] += 1
            anchors.add(f'{base}-{seen[base]}')
        else:
            seen[base] = 0
            anchors.add(base)
    return anchors


def source_name(source, root):
    """Return SOURCE relative to ROOT when possible."""
    try:
        return str(source.relative_to(root))
    except ValueError:
        return str(source)


def check(root, manuscript):
    """Return all external-reference problems below ROOT."""
    generated = generated_chapters(manuscript)
    anchors = {}
    problems = []
    for source in scanned_files(root, manuscript):
        try:
            lines = source.read_text().splitlines()
        except OSError:
            continue
        for number, line in enumerate(lines, start=1):
            for reference in REFERENCE.finditer(line):
                language = reference.group('language')
                chapter_id = reference.group('chapter')
                target_name = f'book/{language}/{chapter_id}.md'
                if chapter_id in generated:
                    continue
                target = manuscript / target_name
                if not target.is_file():
                    problems.append((source_name(source, root), number,
                                     f'target chapter does not exist: {target_name}'))
                    continue
                encoded_anchor = reference.group('anchor')
                if encoded_anchor is None:
                    continue
                target_anchors = anchors.get(target)
                if target_anchors is None:
                    target_anchors = chapter_anchors(target)
                    anchors[target] = target_anchors
                anchor = unquote(encoded_anchor)
                if anchor not in target_anchors:
                    problems.append((source_name(source, root), number,
                                     f'target heading does not exist: {target_name}#{anchor}'))
    return problems


def parse_arguments(arguments):
    """Parse command-line ARGUMENTS."""
    manuscript = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=manuscript.parent,
                        help='workspace root to scan (default: the manuscript parent)')
    parser.add_argument('--manuscript', type=Path, default=manuscript,
                        help='ETAF manual checkout (default: this script repository)')
    return parser.parse_args(arguments)


def main(arguments=None):
    """Run the external-reference check and return its exit status."""
    options = parse_arguments(arguments)
    root = options.root.resolve()
    manuscript = options.manuscript.resolve()
    problems = check(root, manuscript)
    for source, line, message in problems:
        print(f'{source}:{line}: {message}', file=sys.stderr)
    return int(bool(problems))


if __name__ == '__main__':
    raise SystemExit(main())
