# K114s (omarchy-m5p-oled): shared by omarchy-patches-apply and omarchy-patches-install.
# The caller sets ROOT (empty on the machine itself) and defines say().

have_patch() { command -v patch >/dev/null 2>&1; }

# Patches are against Omarchy's tree (a/bin/omarchy-...); its bin/ is installed as /usr/bin.
# Whole patch or nothing, no fuzz, no .orig or .rej files.
run_patch() {
  local p=$1
  shift
  patch -p1 -d "$ROOT/usr" -F0 -s -f --no-backup-if-mismatch -r - "$@" < "$p" >/dev/null 2>&1
}
is_in() { run_patch "$1" -R --dry-run; }
fits() { run_patch "$1" -N --dry-run; }

# The files a patch changes, relative to /usr.
patch_files() { sed -n 's#^+++ b/\([^[:space:]]*\).*#\1#p' "$1" | LC_ALL=C sort -u; }

# The sha256 the Omarchy package (omarchy, or omarchy-dev on Edge: the two the hook watches)
# recorded for usr/FILE when it installed it, or nothing.
shipped_sha() {
  local m
  for m in "$ROOT"/var/lib/pacman/local/omarchy-[0-9]*/mtree "$ROOT"/var/lib/pacman/local/omarchy-dev-[0-9]*/mtree; do
    [[ -f $m ]] || continue
    zcat -f "$m" 2>/dev/null | awk -v p="./usr/$1" '$1 == p {
      for (i = 2; i <= NF; i++) if ($i ~ /^sha256digest=/) { sub(/^sha256digest=/, "", $i); print $i; exit } }'
  done | head -n 1
}

# What says a patch's change was made here: written beside the patch when the applier applies
# it, it lists each file the patch touches with the package's sha256 of that file at that moment
# ("-" for a file no package records, such as one the patch creates). While every one of those
# is still the package's current record, the package has not replaced the files since, so the
# change in them is this machine's, however many patches share a file. Once the package has
# installed a different version of any of them, a change found in them is the package's own.
marker() { printf '%s.applied\n' "${1%.patch}"; }
baselines() {
  local f s
  while read -r f; do
    s=$(shipped_sha "$f")
    printf '%s %s\n' "$f" "${s:--}"
  done < <(patch_files "$1")
}
record_applied() { baselines "$1" > "$(marker "$1")"; }
applied_here() { [[ -f $(marker "$1") ]] && [[ $(baselines "$1") == "$(cat "$(marker "$1")")" ]]; }

# Files a patch touches that are byte for byte what the Omarchy package installed: none, all,
# some, or unknown (the package database has no record of at least one). Only used to adopt a
# patch applied before markers existed.
origin() {
  local f want n=0 same=0 unknown=0
  while read -r f; do
    n=$((n + 1))
    want=$(shipped_sha "$f")
    if [[ -z $want || ! -f $ROOT/usr/$f ]]; then unknown=$((unknown + 1)); continue; fi
    [[ $(sha256sum "$ROOT/usr/$f" | cut -c1-64) == "$want" ]] && same=$((same + 1))
  done < <(patch_files "$1")
  if (( unknown || n == 0 )); then echo unknown
  elif (( same == n )); then echo shipped
  elif (( same == 0 )); then echo ours
  else echo mixed; fi
}

# Take an installed patch out of the files, but only where its change was made here. When the
# Omarchy package's own files carry the same change (it merged the fix), they are left as they are.
# Returns 1 only when a reversal that should work fails.
take_out() {
  local p=$1 name
  name=$(basename "$p" .patch)
  if ! is_in "$p"; then
    say "$name: not in the files; nothing to take out"
    rm -f "$(marker "$p")"
  elif applied_here "$p"; then
    if ! run_patch "$p" -R; then
      say "$name: could not take it out; reinstall the Omarchy package to restore its files"
      return 1
    fi
    say "$name: taken out"
    rm -f "$(marker "$p")"
  elif [[ -f $(marker "$p") ]]; then
    # Kept: it goes on saying that the package's files carry this change.
    say "$name: the Omarchy package has replaced these files since and its own carry this change; left as they are"
  else
    say "$name: no record that this change was made here; left as it is. Reinstall the Omarchy package to restore its files."
  fi
  return 0
}

# A patch applied by the first version of this tool, which kept no marker: adopt it when every
# file it touches differs from the package's own, which with one patch per file (all that version
# ever installed) means the change was made here. Run once, by migrate.
adopt() {
  local p=$1
  [[ -f $(marker "$p") ]] && return 0
  is_in "$p" || return 0
  [[ $(origin "$p") == ours ]] || return 0
  record_applied "$p"
  say "$(basename "$p" .patch): recorded as applied here"
}

# Once per install: adopt what the first version of this tool applied, then mark the install as
# keeping records, so that a later run never adopts a change the package itself ships.
migrate() {
  local dest=$1 p
  [[ -d $dest && ! -e $dest/.records ]] || return 0
  for p in "$dest"/*.patch; do [[ -f $p ]] && adopt "$p"; done
  : > "$dest/.records"
}

# A patch may only change files the Omarchy package (omarchy or omarchy-dev) installed: none it creates or deletes (a
# file it created could later collide with one the package ships), nothing the package database
# has no record of.
check_targets() {
  local p=$1 f n=0
  if grep -qE '^(---|[+][+][+]) /dev/null' "$p"; then echo "creates or deletes a file"; return 1; fi
  while read -r f; do
    n=$((n + 1))
    [[ -n $(shipped_sha "$f") ]] || { echo "changes $f, which neither omarchy nor omarchy-dev installed"; return 1; }
  done < <(patch_files "$p")
  (( n )) || { echo "changes no file"; return 1; }
}
