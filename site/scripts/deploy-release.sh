# Deploy one release on the web host.  This script is read from standard input
# by ssh and runs as root there; its arguments are the release stamp, the
# uploaded tarball and how many releases to keep.
set -eu

stamp="$1"
tarball="$2"
keep="${3:-5}"
base=/srv/etaf.top
release="$base/releases/$stamp"

mkdir -p "$release"
tar xzf "$tarball" -C "$release"
rm -f "$tarball"
chmod -R a+rX "$release"

# Switch `current` atomically: never expose a half-written release.
ln -sfn "$release" "$base/current.next"
mv -fT "$base/current.next" "$base/current"

# Keep the newest releases, newest first.
cd "$base/releases"
ls -1dt */ 2>/dev/null | tail -n "+$((keep + 1))" | while read -r old; do
  [ "$old" = "$stamp/" ] && continue
  rm -rf -- "$old"
done
printf 'release %s active\n' "$stamp"
