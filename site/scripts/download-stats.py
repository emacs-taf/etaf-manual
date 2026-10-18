#!/usr/bin/env python3
"""Refresh the archive download counts from Caddy's JSON access log.

The archive pages read `downloads.json` in the browser; this timer rewrites it
from the log so the counts stay current between package releases. Deployment
verification appends `?deployment=<stamp>` to every archived file: those
requests check bytes, they are not somebody installing a package, so they are
excluded. Rotated logs stay readable, so counts survive log rotation for as
long as the files are kept.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import json
import os
from pathlib import Path
import re
import sys

ARCHIVE = re.compile(r"/packages/([a-z][a-z0-9-]*)-[0-9]+(?:\.[0-9]+)*\.tar\Z")
HOST = "etaf.top"


def lines(path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8", errors="replace") as stream:
        yield from stream


def count(log_dir):
    """Return per-package downloads and the timestamp of the oldest counted request."""
    counts = {}
    first = None
    for path in sorted(log_dir.glob(f"{HOST}.access*.log*")):
        if not path.is_file() or path.is_symlink():
            continue
        for line in lines(path):
            try:
                record = json.loads(line)
            except ValueError:
                continue
            request = record.get("request") or {}
            uri = request.get("uri") or ""
            if (record.get("status") != 200 or request.get("method") != "GET"
                    or request.get("host") != HOST or "deployment=" in uri):
                continue
            match = ARCHIVE.fullmatch(uri)
            if not match:
                continue
            counts[match[1]] = counts.get(match[1], 0) + 1
            stamp = record.get("ts")
            if isinstance(stamp, (int, float)):
                first = stamp if first is None else min(first, stamp)
    return counts, first


def moment(value):
    return datetime.fromtimestamp(value, timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log-dir", type=Path, default=Path("/var/log/caddy"))
    parser.add_argument("--output", type=Path,
                        default=Path("/srv/etaf.top/stats/packages/downloads.json"))
    args = parser.parse_args()
    counts, first = count(args.log_dir)
    payload = {
        "schema": 1,
        "as_of": moment(datetime.now(timezone.utc).timestamp()),
        "since": moment(first) if first is not None else None,
        "total": sum(counts.values()),
        "packages": dict(sorted(counts.items())),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_name(args.output.name + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, args.output)
    print(f"downloads={payload['total']} packages={len(counts)} "
          f"since={payload['since']} output={args.output}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"error=stats\nhint={error}", file=sys.stderr)
        sys.exit(1)
