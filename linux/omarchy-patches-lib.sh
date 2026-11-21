# K114s (omarchy-m5p-oled): shared by omarchy-patches-apply and omarchy-patches-install.
# The caller sets ROOT (empty on the machine itself) and defines say().

have_patch() { command -v patch >/dev/null 2>&1; }

# Patch paths are relative to /usr: a/bin/omarchy-... for Omarchy's bin/, and
# a/share/omarchy/shell/... for its shell/, which installs as /usr/share/omarchy/shell.
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

# The sha256 the Omarchy package (omarchy, or omarchy-dev on Edge) or omarchy-mac (the Apple Silicon
# platform data: the three the hook watches) recorded for usr/FILE when it installed it, or nothing.
shipped_sha() {
  local m
  for m in "$ROOT"/var/lib/pacman/local/omarchy-[0-9]*/mtree "$ROOT"/var/lib/pacman/local/omarchy-dev-[0-9]*/mtree \
           "$ROOT"/var/lib/pacman/local/omarchy-mac-[0-9]*/mtree; do
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
  local p=$1 name how=exact result=clean
  name=$(basename "$p" .patch)
  is_in "$p" || { in_by_merge "$p" && how=merge; } || how=""
  if [[ -z $how ]]; then
    say "$name: not in the files; nothing to take out"
    rm -f "$(marker "$p")"
  elif applied_here "$p"; then
    # A change put in by a three-way merge comes out the same way.
    if [[ $how == exact ]]; then
      run_patch "$p" -R || result=failed
    else
      result=$(three_way "$p" rev write)
    fi
    if [[ $result == stuck\ * ]]; then
      say "$name: could not take it out or put the files back. Copies of the originals are in ${result#stuck }/. Reinstall the Omarchy package to restore its files."
      return 1
    elif [[ $result != clean ]]; then
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

# A patch's NAME.base/, when it has one, must hold every file the patch changes, and the patch
# must apply to them exactly: it is what the three-way merge takes the change from.
check_base() {
  local w rc
  [[ -d $(base_dir "$1") ]] || return 0
  have_merge || { echo "has a base folder, but git (for git merge-file) is not installed"; return 1; }
  w=$(mktemp -d "${TMPDIR:-/tmp}/k114s-omarchy-merge.XXXXXX") || return 1
  merge_sides "$1" "$w"; rc=$?; rm -rf "$w"
  (( rc == 0 )) || { echo "has a base folder that does not match it (a file missing, or the patch does not apply to it exactly)"; return 1; }
}

# A patch may only change files the Omarchy package (omarchy, omarchy-dev or omarchy-mac) installed: none it creates or deletes (a
# file it created could later collide with one the package ships), nothing the package database
# has no record of.
check_targets() {
  local p=$1 f n=0
  if grep -qE '^(---|[+][+][+]) /dev/null' "$p"; then echo "creates or deletes a file"; return 1; fi
  while read -r f; do
    n=$((n + 1))
    [[ -n $(shipped_sha "$f") ]] || { echo "changes $f, which none of omarchy, omarchy-dev and omarchy-mac installed"; return 1; }
  done < <(patch_files "$p")
  (( n )) || { echo "changes no file"; return 1; }
}

# Three-way merge. A patch may come with NAME.base/, a copy (paths relative to /usr) of each file
# it changes as it was in the Omarchy build the patch was written for. When Omarchy has since
# changed lines near the patch's, so that it no longer applies exactly, git merge-file carries
# the patch's change (base -> base with the patch) into the current files instead. Any overlap
# with Omarchy's own change is a conflict: then nothing is written.
base_dir() { printf '%s.base\n' "${1%.patch}"; }
same_base() {
  local old new f
  old=$(base_dir "$1"); new=$(base_dir "$2")
  [[ ! -d $old && ! -d $new ]] && return 0
  [[ -d $old && -d $new ]] || return 1
  # Only the patch targets participate in the merge.
  while read -r f; do
    cmp -s -- "$old/$f" "$new/$f" || return 1
  done < <(patch_files "$1")
}
have_merge() { command -v git >/dev/null 2>&1; }

# Fills $2/base and $2/new (base with the patch applied exactly). 1: no base or no git; 2: the
# base does not match the patch (a file is missing, or the patch does not apply to it exactly).
merge_sides() {
  local p=$1 w=$2 b f
  b=$(base_dir "$p")
  [[ -d $b ]] && have_merge || return 1
  mkdir -p "$w/base" "$w/new"
  while read -r f; do
    [[ -f $b/$f ]] || return 2
    mkdir -p "$(dirname "$w/base/$f")" "$(dirname "$w/new/$f")"
    cp "$b/$f" "$w/base/$f"; cp "$b/$f" "$w/new/$f"
  done < <(patch_files "$p")
  patch -p1 -d "$w/new" -F0 -s -f --no-backup-if-mismatch -r - -N < "$p" >/dev/null 2>&1 || return 2
}

# three_way PATCH fwd|rev check|write: merges the patch's change (fwd: base -> new) or its
# reversal (rev: new -> base) into the files under $ROOT/usr. Prints one of
#   nobase    no NAME.base/ (or no git): no three-way merge possible
#   badbase   NAME.base/ does not match the patch
#   conflict  the change overlaps Omarchy's own change to those lines; nothing written
#   partial   the merge would change the files, but taking the change out again would not give
#             them back exactly: part of it is already there (Omarchy shipped some hunks, in this
#             file or another). Nothing written: a later take-out would remove Omarchy's part too
#   noop      the merge leaves every file as it is (the change is already there, or already out)
#   clean     the merge is clean and changes the files; written with "write"
#   failed    a write failed; every file written so far was put back as it was
#   stuck DIR a write failed and putting a file back failed too; DIR holds the originals:
#             a fresh NAME.rescue.XXXXXX/ beside the patch, or the kept workspace if the copy fails
three_way() {
  local p=$1 dir=$2 mode=$3 w f from to rc rescue state=noop todo=0
  local -a written=()
  w=$(mktemp -d "${TMPDIR:-/tmp}/k114s-omarchy-merge.XXXXXX") || { echo nobase; return; }
  merge_sides "$p" "$w"; rc=$?
  if (( rc == 1 )); then echo nobase; rm -rf "$w"; return; fi
  if (( rc == 2 )); then echo badbase; rm -rf "$w"; return; fi
  if [[ $dir == fwd ]]; then from=base to=new; else from=new to=base; fi
  while read -r f; do
    [[ -f $ROOT/usr/$f ]] || { state=conflict; break; }
    mkdir -p "$(dirname "$w/out/$f")"
    if ! git merge-file -p -q "$ROOT/usr/$f" "$w/$from/$f" "$w/$to/$f" > "$w/out/$f" 2>/dev/null; then
      state=conflict; break
    fi
    cmp -s "$w/out/$f" "$ROOT/usr/$f" || todo=1
  done < <(patch_files "$p")
  if [[ $state != conflict ]] && (( todo )); then
    state=clean
    # The merge must be undoable: taking the change out of the result again gives back every
    # file exactly as it is now. If not, part of the change is already in them.
    while read -r f; do
      git merge-file -p -q "$w/out/$f" "$w/$to/$f" "$w/$from/$f" 2>/dev/null | cmp -s - "$ROOT/usr/$f" ||
        { state=partial; break; }
    done < <(patch_files "$p")
  fi
  if [[ $state == clean && $mode == write ]]; then
    # Same inode, owner and mode: only the contents change, as with patch. Every file is copied
    # first, and if any write fails, each file written so far (and the failed one) is put back.
    while read -r f; do
      cmp -s "$w/out/$f" "$ROOT/usr/$f" && continue
      mkdir -p "$(dirname "$w/keep/$f")"
      cp "$ROOT/usr/$f" "$w/keep/$f" || { state=failed; break; }
      written+=("$f")
      cat "$w/out/$f" > "$ROOT/usr/$f" || { state=failed; break; }
    done < <(patch_files "$p")
    if [[ $state == failed ]]; then
      for f in "${written[@]}"; do
        cmp -s "$w/keep/$f" "$ROOT/usr/$f" || cat "$w/keep/$f" > "$ROOT/usr/$f" 2>/dev/null || state=stuck
      done
      if [[ $state == stuck ]]; then
        if rescue=$(mktemp -d -- "${p%.patch}.rescue.XXXXXX" 2>/dev/null) &&
           cp -R -- "$w/keep/." "$rescue/" 2>/dev/null; then
          state="stuck $rescue"
        else
          # Keep the originals in the work folder if the rescue copy is incomplete.
          if [[ -n $rescue ]]; then rm -rf -- "$rescue" 2>/dev/null || true; fi
          state="stuck $w/keep"; w=""
        fi
      fi
    fi
  fi
  [[ -n $w ]] && rm -rf "$w"
  echo "$state"
}
# The patch's change is in the files, found by merging rather than by reversing it exactly.
in_by_merge() { [[ $(three_way "$1" fwd check) == noop ]]; }
