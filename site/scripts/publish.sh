#!/usr/bin/env bash
# Build the manual site and publish it to https://etaf.top.
#
#   scripts/publish.sh [--build-only] [--no-build]
#
# The site is built in this checkout (Emacs exports the book, Astro builds
# dist/) and uploaded to the web host as a new release; the `current` symlink
# then switches atomically and the published URLs are checked.
#
# ETAF_TOP_ROOT selects the transport: `lightos` (default) forwards the
# deployment through the home entry host, `direct` connects to the web host
# itself.  ETAF_TOP_HOST overrides the root login (default root@aliyun-hk) and
# ETAF_TOP_KEEP how many releases to keep (default 5).
set -euo pipefail

site_dir="$(cd "$(dirname "$0")/.." && pwd)"
top_root="${ETAF_TOP_ROOT:-lightos}"
top_host="${ETAF_TOP_HOST:-root@aliyun-hk}"
keep="${ETAF_TOP_KEEP:-5}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
build=1
publish=1

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  printf '\nOptions:\n  --build-only  build dist/ without publishing\n  --no-build    publish the existing dist/\n'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --build-only) publish=0 ;;
    --no-build) build=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*"; }

# Run a command string on the web host as root.  With the default transport the
# command first lands on the home entry host and is forwarded from there.
run_root() {
  if [ "$top_root" = direct ]; then
    ssh "$top_host" "$1"
  else
    ssh lightos "ssh $top_host $1"
  fi
}

if [ "$build" = 1 ]; then
  log "Building the site ..."
  ( cd "$site_dir" && npm run build )
  log "Built $site_dir/dist"
fi

if [ "$publish" = 0 ]; then
  exit 0
fi

if [ ! -f "$site_dir/dist/index.html" ]; then
  echo "desktop site build not found in $site_dir/dist; run without --no-build" >&2
  exit 2
fi

tarball="$(mktemp -t etaf-top).tgz"
trap 'rm -f "$tarball"' EXIT
# --no-xattrs keeps macOS metadata out of the archive sent to Linux.
tar czf "$tarball" --no-xattrs -C "$site_dir/dist" .
# The web host serves stable names (pages, screenshots, font stylesheets), so
# responses must revalidate; without this a browser can keep showing a cached
# page after a release.  Content-hashed build output is cached instead.  The
# configuration is installed only when it differs.
log "Syncing the web host configuration ..."
run_root "sh -s" <<'REMOTE'
set -eu
cat > /tmp/etaf-top.caddy <<'CONFIG'
etaf.top {
	encode zstd gzip
	root * /srv/etaf.top/current

	# Build output under /_astro/ carries a content hash in its name; the two
	# matchers stay mutually exclusive so neither rule can shadow the other.
	@hashed path /_astro/*
	header @hashed Cache-Control "public, max-age=31536000, immutable"

	# Pages, screenshots and font stylesheets keep stable names: a browser must
	# ask again, so a cached copy never hides a new release.
	@stable not path /_astro/*
	header @stable Cache-Control "no-cache"

	file_server
}
CONFIG
if cmp -s /tmp/etaf-top.caddy /etc/caddy/etaf.top.caddy; then
  echo "web host configuration unchanged"
  exit 0
fi
cp /etc/caddy/etaf.top.caddy "/etc/caddy/etaf.top.caddy.bak-$(date +%Y%m%d-%H%M%S)"
cp /tmp/etaf-top.caddy /etc/caddy/etaf.top.caddy
caddy validate --config /etc/caddy/Caddyfile >/dev/null
systemctl reload caddy
echo "web host configuration installed and Caddy reloaded"
REMOTE

log "Uploading $(( $(wc -c < "$tarball") / 1024 )) KiB to $top_host ..."
run_root "'cat > /tmp/etaf-top-$stamp.tgz'" < "$tarball"

log "Deploying release $stamp ..."
run_root "sh -s -- $stamp /tmp/etaf-top-$stamp.tgz $keep" \
  < "$site_dir/scripts/deploy-release.sh"

log "Verifying ..."
failed=0
for path in / /zh-cn/ /introduction/ /zh-cn/introduction/ /symbol-index/ /zh-cn/symbol-index/; do
  code="$(curl -fsS -o /dev/null -w '%{http_code}' "https://etaf.top$path" || true)"
  if [ "$code" = 200 ]; then
    log "  $path -> 200"
  else
    log "  $path -> ${code:-no response}"
    failed=1
  fi
done
if [ "$failed" != 0 ]; then
  echo "FAIL: publishing did not answer on all checked URLs" >&2
  exit 1
fi
log "Published https://etaf.top (release $stamp)"
