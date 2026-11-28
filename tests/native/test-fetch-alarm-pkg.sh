#!/bin/bash
# Exercise the downloader against local archives, with curl standing in for the mirror.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -r -- "$fixture" </dev/null' EXIT
export B="$fixture/build cache" MIRROR=https://fixture.invalid/aarch64
export MIRROR_DIR="$fixture/mirror" CURL_LOG="$fixture/curl.log"
export INTERRUPT=
download=$repo/build/native/fetch-alarm-pkg
filename=fixture-1.0-1-aarch64.pkg.tar.gz
db=$B/pkgcache/db/extra.db
package=$B/pkgcache/pkg/$filename
mirror_package=$MIRROR_DIR/extra/$filename

mkdir -p "$fixture/bin" "$fixture/database/fixture-1.0-1" "$fixture/payload/usr/bin" \
  "$MIRROR_DIR/extra" "$MIRROR_DIR/core"
echo 'verified payload' > "$fixture/payload/usr/bin/fixture"
bsdtar -czf "$mirror_package" -C "$fixture/payload" usr
sum=$(sha256sum < "$mirror_package")
printf '%%FILENAME%%\n%s\n\n%%SHA256SUM%%\n%s\n' "$filename" "${sum%% *}" \
  > "$fixture/database/fixture-1.0-1/desc"
bsdtar -czf "$MIRROR_DIR/extra/extra.db" -C "$fixture/database" fixture-1.0-1
bsdtar -czf "$MIRROR_DIR/core/core.db" --files-from /dev/null
echo 'wrong payload' > "$fixture/payload/usr/bin/fixture"
bsdtar -czf "$fixture/wrong-package" -C "$fixture/payload" usr

cat > "$fixture/bin/curl" <<'CURL'
#!/bin/bash
set -euo pipefail
while (( $# > 1 )); do
  case $1 in
    -o) output=$2; shift 2 ;;
    --retry) shift 2 ;;
    -fsSL) shift ;;
    *) exit 99 ;;
  esac
done
[[ $1 == "$MIRROR/"* ]]
path=${1#"$MIRROR/"}
printf '%s\n' "$path" >> "$CURL_LOG"
case $path in
  *.db) cache_dir=$B/pkgcache/db ;;
  *) cache_dir=$B/pkgcache/pkg ;;
esac
if [[ ${output%/*} != "$cache_dir" || $output == "$cache_dir/${path##*/}" ]]; then
  printf 'curl must write to a staging file beside the cache entry: %s\n' "$output" >&2
  exit 99
fi
if [[ $path == "$INTERRUPT" ]]; then
  head -c 32 "$MIRROR_DIR/$path" > "$output"
  exit 18
fi
cp -- "$MIRROR_DIR/$path" "$output"
CURL
chmod +x "$fixture/bin/curl"
export PATH="$fixture/bin:$PATH"

check() {
  local label=$1 expected_status=$2 expected_requests=$3 status=0
  local prefix=$fixture/$label
  : > "$CURL_LOG"
  "$download" "$prefix" fixture > "$fixture/output" 2>&1 || status=$?
  if [[ $status != "$expected_status" || $(cat "$CURL_LOG") != "$expected_requests" ]]; then
    cat "$fixture/output" >&2
    printf '%s: expected exit %s, got %s. Mirror requests:\n' "$label" "$expected_status" "$status" >&2
    cat "$CURL_LOG" >&2
    exit 1
  fi
  if [[ $status == 0 ]]; then
    [[ $(cat "$prefix/usr/bin/fixture") == 'verified payload' ]]
  else
    [[ ! -e $prefix/usr/bin/fixture ]]
  fi
}

INTERRUPT=extra/extra.db
check interrupted-db 18 "$INTERRUPT"
[[ -z $(ls -A "$B/pkgcache/db") ]] || { echo 'interrupted database left cache files' >&2; exit 1; }

INTERRUPT=extra/$filename
check interrupted-package 18 "$(printf '%s\n' extra/extra.db core/core.db "$INTERRUPT")"
[[ -z $(ls -A "$B/pkgcache/pkg") ]] || { echo 'interrupted package left cache files' >&2; exit 1; }

INTERRUPT=
check retry 0 "extra/$filename"

# Simulate the permanent files left behind by the old downloader.
head -c 32 "$MIRROR_DIR/extra/extra.db" > "$db"
head -c 32 "$mirror_package" > "$package"
check recover-old-cache 0 "$(printf '%s\n' extra/extra.db "extra/$filename")"
cmp "$db" "$MIRROR_DIR/extra/extra.db"
cmp "$package" "$mirror_package"
check healthy-cache 0 ''

# A successful transfer with the wrong contents must fail before extraction or cache publication.
rm -- "$package" </dev/null
cp -- "$fixture/wrong-package" "$mirror_package"
check checksum-mismatch 1 "extra/$filename"
[[ -z $(ls -A "$B/pkgcache/pkg") ]] || { echo 'bad checksum left cache files' >&2; exit 1; }

echo 'Arch Linux ARM download cache checks passed.'
