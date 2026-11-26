#!/bin/bash
# Fake-root tests of linux/omarchy-patches-install, linux/omarchy-patches-apply and their hook.
#   usage: test-omarchy-patches.sh LINUX_DIR [OMARCHY_SRC]
# OMARCHY_SRC, if given, is an omacom/omarchy checkout at the revision the machine runs; the real
# patches in patches/omarchy/ are then checked to apply to it without fuzz, and to come out again.
set -u
L=$(cd "$1" && pwd); P=$(cd "$L/../patches/omarchy" && pwd); INSTALL=$L/omarchy-patches-install
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got '$2' want '$3'"; fi; }
BASE=$(mktemp -d "${TMPDIR:-/tmp}/k114s-omarchy-patches-test.XXXXXX"); trap 'rm -rf "$BASE"' EXIT

# "Omarchy" scripts as the package ships them, and the package database's record of them.
orig() { mkdir -p "$1/usr/bin"
  printf '#!/bin/bash\n# one\nkey=user\necho "$key"\n# end\n' > "$1/usr/bin/omarchy-a"
  printf '#!/bin/bash\n# two\ncache=user\necho "$cache"\n# end\n' > "$1/usr/bin/omarchy-b"
  printf 'one\n' > "$1/usr/bin/omarchy-c"
  printf 'a\nb\nc\nd\n' > "$1/usr/bin/omarchy-x"
  chmod 755 "$1"/usr/bin/omarchy-*; }
fixed() { sed -i 's/^key=user$/key=user-org/' "$1/usr/bin/omarchy-a"; sed -i 's/^cache=user$/cache=user-org/' "$1/usr/bin/omarchy-b"; }
shipped() { # record the files now under $1/usr (but /usr/local) as what the package installed
  local d=$1/var/lib/pacman/local/omarchy-dev-1-1 f; mkdir -p "$d"
  (cd "$1" && find usr -path usr/local -prune -o -type f -print | LC_ALL=C sort) | while read -r f; do
    echo "./$f time=1.0 size=$(stat -c %s "$1/$f") sha256digest=$(sha256sum "$1/$f" | cut -c1-64)"; done | gzip > "$d/mtree"; }
# A patch in Omarchy's tree layout (a/bin/...) between two versions of one file.
mkpatch() { local out=$1 file=$2; mkdir -p "$BASE/mp"; printf "$3" > "$BASE/mp/old"; printf "$4" > "$BASE/mp/new"
  diff -u "$BASE/mp/old" "$BASE/mp/new" | sed "1s#^--- .*#--- a/bin/$file#; 2s#^+++ .*#+++ b/bin/$file#" > "$out"; }
SRC=$BASE/src; mkdir -p "$SRC" "$BASE/a" "$BASE/b"; orig "$BASE/a"; orig "$BASE/b"; fixed "$BASE/b"
{ echo "A test fix. Free text before the diff is ignored by patch."; echo
  for f in omarchy-a omarchy-b; do diff -u "$BASE/a/usr/bin/$f" "$BASE/b/usr/bin/$f" | sed "1s#^--- .*#--- a/bin/$f#; 2s#^+++ .*#+++ b/bin/$f#"; done; } > "$SRC/0001-test.patch"
sumof() { cat "$1/usr/bin/omarchy-a" "$1/usr/bin/omarchy-b" | sha256sum | cut -c1-64; }
ORIG=$(sumof "$BASE/a"); FIXED=$(sumof "$BASE/b")
mk() { local r; r=$(mktemp -d "$BASE/root.XXXXXX"); orig "$r"; shipped "$r"; echo "$r"; }
inst() { K114S_ROOT=$1 K114S_OMARCHY_PATCHES_SRC=${2:-$SRC} bash "$INSTALL" "${@:3}" 2>&1; }
apply() { K114S_ROOT=$1 bash "$1/usr/local/lib/omarchy-k114s/omarchy-patches-apply" 2>&1; }
leftovers() { find "$1/usr" \( -name '*.orig' -o -name '*.rej' \) | wc -l | tr -d ' '; }
x() { tr '\n' ' ' < "$1/usr/bin/omarchy-x"; }
installed() { (cd "$1/usr/local/lib/omarchy-k114s/omarchy-patches" && ls *.patch 2>/dev/null) | tr '\n' ' '; }
markers() { (cd "$1/usr/local/lib/omarchy-k114s/omarchy-patches" && ls *.applied 2>/dev/null) | tr '\n' ' '; }

r=$(mk); out=$(inst "$r"); rc=$?
ok "install: succeeds" "$rc" 0
ok "install: fix applied" "$(sumof "$r")" "$FIXED"
ok "install: reports applied" "$(grep -c '0001-test: applied' <<<"$out")" 1
ok "install: modes kept" "$(stat -c %a "$r/usr/bin/omarchy-a" "$r/usr/bin/omarchy-b" | tr '\n' ' ')" "755 755 "
ok "install: hook in place" "$(test -f "$r/etc/pacman.d/hooks/03-k114s-omarchy-patches.hook" && echo yes)" yes
ok "install: applier and its library" "$(test -x "$r/usr/local/lib/omarchy-k114s/omarchy-patches-apply" && test -f "$r/usr/local/lib/omarchy-k114s/omarchy-patches-lib.sh" && echo yes)" yes
ok "install: no .orig or .rej" "$(leftovers "$r")" 0
ok "install: applied-here record written" "$(markers "$r")" "0001-test.applied "
out=$(apply "$r"); ok "again: in place" "$(grep -c '0001-test: in place' <<<"$out")" 1
ok "again: files unchanged" "$(sumof "$r")" "$FIXED"
out=$(inst "$r"); ok "reinstall: in place, unchanged" "$(grep -c 'in place' <<<"$out"):$(sumof "$r")" "1:$FIXED"

# An Omarchy update puts the shipped files back; the hook's run re-applies the fix.
orig "$r"; out=$(apply "$r"); rc=$?
ok "after update: re-applied" "$rc:$(sumof "$r")" "0:$FIXED"

# Omarchy changes the lines the fix touches: nothing written, reported, transaction not failed.
orig "$r"; sed -i 's/^key=user$/key=account/' "$r/usr/bin/omarchy-a"; changed=$(sumof "$r")
out=$(apply "$r"); rc=$?
ok "changed upstream: exit 0" "$rc" 0
ok "changed upstream: reported" "$(grep -c 'does not fit this Omarchy build' <<<"$out")" 1
ok "changed upstream: nothing written (the other file too)" "$(sumof "$r")" "$changed"
ok "changed upstream: no .orig or .rej" "$(leftovers "$r")" 0

# Context changed within fuzz range: still refused, no fuzzy application.
orig "$r"; sed -i 's/^# end$/# finish/' "$r/usr/bin/omarchy-b"; fuzzy=$(sumof "$r")
out=$(apply "$r"); ok "fuzz needed: refused, nothing written" "$(grep -c 'does not fit' <<<"$out"):$(sumof "$r")" "1:$fuzzy"

# Three-way merge: the same patch with a base folder (the files it was written for).
M=$BASE/merge; mkdir -p "$M/0001-test.base/bin"; cp "$SRC/0001-test.patch" "$M/"
cp "$BASE/a/usr/bin/omarchy-a" "$BASE/a/usr/bin/omarchy-b" "$M/0001-test.base/bin/"
NOTES=$BASE/notes; NOTIFY=$BASE/notify; printf '#!/bin/bash\nprintf "%%s|%%s\\n" "$1" "$2" >> %s\n' "$NOTES" > "$NOTIFY"; chmod 755 "$NOTIFY"
applyn() { : > "$NOTES"; K114S_NOTIFY_CMD=$NOTIFY K114S_ROOT=$1 bash "$1/usr/local/lib/omarchy-k114s/omarchy-patches-apply" 2>&1; }
# The notification command is never run as root, so its checks only hold for a normal user.
nok() { if [ "$(id -u)" = 0 ]; then echo "SKIP $1 (root: the notification command is not run)"; else ok "$@"; fi; }
r=$(mk); out=$(inst "$r" "$M"); ok "merge: install with a base succeeds, applied exactly" "$?:$(sumof "$r")" "0:$FIXED"
ok "merge: base folder installed" "$(test -f "$r/usr/local/lib/omarchy-k114s/omarchy-patches/0001-test.base/bin/omarchy-a" && echo yes)" yes
out=$(applyn "$r"); nok "merge: exact fit raises no notification" "$(wc -c < "$NOTES" | tr -d ' ')" 0
# Omarchy changes a context line next to the fix (the fuzz case above): merged, not refused.
orig "$r"; sed -i 's/^# end$/# finish/' "$r/usr/bin/omarchy-b"; shipped "$r"
out=$(applyn "$r"); ok "merge: nearby change merged" "$(grep -c '0001-test: applied by a three-way merge' <<<"$out"):$(tr '\n' ' ' < "$r/usr/bin/omarchy-b")" "1:#!/bin/bash # two cache=user-org echo \"\$cache\" # finish "
nok "merge: no notification" "$(wc -c < "$NOTES" | tr -d ' ')" 0
ok "merge: no .orig or .rej" "$(leftovers "$r")" 0
out=$(applyn "$r"); ok "merge: next run says in place" "$(grep -c '0001-test: in place (merged' <<<"$out")" 1
ok "merge: modes kept" "$(stat -c %a "$r/usr/bin/omarchy-b")" 755
out=$(inst "$r" "$M" --undo); ok "merge: undo takes the merged change out, keeps Omarchy's" "$(grep -c '0001-test: taken out' <<<"$out"):$(tr '\n' ' ' < "$r/usr/bin/omarchy-b")" "1:#!/bin/bash # two cache=user echo \"\$cache\" # finish "

# Refresh the same patch bytes with a changed base, then with no base.
nearby_root() { local r; r=$(mk); sed -i 's/^# end$/# finish/' "$r/usr/bin/omarchy-b"; shipped "$r"; echo "$r"; }
newbase=$BASE/newbase; cp -r "$M" "$newbase"
printf '# an extra line in the base\n' >> "$newbase/0001-test.base/bin/omarchy-a"
r=$(nearby_root); before=$(sumof "$r"); out=$(inst "$r" "$M")
ok "base-only refresh fixture: installed by three-way merge" "$(grep -c 'applied by a three-way merge' <<<"$out")" 1
out=$(inst "$r" "$M")
ok "unchanged base: merged patch stays in place" "$(grep -c 'in place (merged' <<<"$out"):$(grep -c 'taken out' <<<"$out")" "1:0"
out=$(inst "$r" "$newbase"); rc=$?
ok "changed base: reverses the old merge and applies the new one" "$rc:$(grep -c 'taken out' <<<"$out"):$(grep -c 'applied by a three-way merge' <<<"$out")" "0:1:1"
out=$(inst "$r" "$newbase" --undo)
ok "changed base: undo restores packaged bytes" "$?:$(sumof "$r")" "0:$before"
r=$(nearby_root); inst "$r" "$M" >/dev/null
out=$(inst "$r" "$SRC"); rc=$?
ok "removed base: reverses the old merge before replacing the base" "$rc:$(grep -c 'taken out' <<<"$out"):$(sumof "$r")" "0:1:$before"
out=$(inst "$r" "$SRC" --undo)
ok "removed base: undo leaves packaged bytes" "$?:$(sumof "$r")" "0:$before"

# Base generation accepts a uniquely fitting direction and leaves an existing base alone
# if a zero-context insertion fits both ways.
encoder=$L/../tools/omarchy-patch-base
encoded=$BASE/encoded; mkdir -p "$encoded"; cp "$SRC/0001-test.patch" "$encoded/"
for version in a b; do
  out=$("$encoder" "$encoded/0001-test.patch" "$BASE/$version/usr" 2>&1); rc=$?
  diff -r "$M/0001-test.base" "$encoded/0001-test.base" >/dev/null
  ok "base encoding from fixture $version: stores packaged bytes" "$rc:$?" "0:0"
done
printf 'one\ninserted\n' > "$BASE/b/usr/bin/omarchy-c"
diff -U0 --label a/bin/omarchy-c --label b/bin/omarchy-c \
  "$BASE/a/usr/bin/omarchy-c" "$BASE/b/usr/bin/omarchy-c" > "$encoded/0002-insert.patch"
out=$("$encoder" "$encoded/0002-insert.patch" "$BASE/a/usr" 2>&1)
ok "zero-context insertion: a unique fit encodes the shipped file" "$?:$(cat "$encoded/0002-insert.base/bin/omarchy-c")" "0:one"
out=$("$encoder" "$encoded/0002-insert.patch" "$BASE/b/usr" 2>&1); rc=$?
ok "ambiguous insertion: refused before replacing the base" "$rc:$(grep -c 'both applies and reverses' <<<"$out"):$(cat "$encoded/0002-insert.base/bin/omarchy-c")" "1:1:one"

# Omarchy changes the very line the fix changes: a conflict. Nothing written, and a notification.
r=$(mk); inst "$r" "$M" >/dev/null; orig "$r"; sed -i 's/^key=user$/key=account/' "$r/usr/bin/omarchy-a"; shipped "$r"; changed=$(sumof "$r")
out=$(applyn "$r"); ok "merge conflict: reported, nothing written (the other file too)" "$(grep -c 'three-way merge from its base conflicts' <<<"$out"):$(sumof "$r")" "1:$changed"
nok "merge conflict: one notification naming the patch" "$(wc -l < "$NOTES" | tr -d ' '):$(grep -c '0001-test: Omarchy changed the same lines' "$NOTES")" "1:1"
# Without a base folder, a patch that no longer fits is also notified.
r=$(mk); inst "$r" >/dev/null; orig "$r"; sed -i 's/^key=user$/key=account/' "$r/usr/bin/omarchy-a"
out=$(applyn "$r"); nok "no base, does not fit: notified" "$(grep -c '0001-test: Omarchy changed those lines' "$NOTES")" 1
# A write that fails part-way (the second file read-only; root ignores the mode) puts back the first.
if [ "$(id -u)" != 0 ]; then
  r=$(mk); inst "$r" "$M" >/dev/null; orig "$r"; sed -i 's/^# end$/# finish/' "$r/usr/bin/omarchy-a" "$r/usr/bin/omarchy-b"; shipped "$r"
  before=$(sumof "$r"); chmod 444 "$r/usr/bin/omarchy-b"; out=$(applyn "$r"); rc=$?; chmod 755 "$r/usr/bin/omarchy-b"
  ok "merge write fails: exit 0, reported, both files as they were" "$rc:$(grep -c 'could not write the three-way merge' <<<"$out"):$(sumof "$r")" "0:1:$before"
  nok "merge write fails: notified" "$(grep -c '0001-test: failed while applying' "$NOTES")" 1
fi
# Inject a failed write and a failed restore, including when the suite runs as root.
shim=$BASE/shim; mkdir -p "$shim"
printf '#!/bin/bash\ncase "$1" in */out/bin/omarchy-b|*/keep/bin/omarchy-a) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v cat)" > "$shim/cat"
printf '#!/bin/bash\nif [[ ${FAIL_RESCUE_COPY:-} == 1 && ${*: -1} == *.rescue.*/ ]]; then exit 1; fi\nexec %s "$@"\n' "$(command -v cp)" > "$shim/cp"
chmod 755 "$shim/cat" "$shim/cp"
rescue_path() { sed -n 's#.*Copies of the originals are in \(.*\)/\. Reinstall.*#\1#p' <<<"$1"; }
backup=$BASE/backup; mkdir -p "$backup/bin"
r=$(mk); inst "$r" "$M" >/dev/null; orig "$r"; sed -i 's/^# end$/# finish/' "$r/usr/bin/omarchy-b"; shipped "$r"
cp "$r"/usr/bin/omarchy-{a,b} "$backup/bin/"
d=$r/usr/local/lib/omarchy-k114s/omarchy-patches/0001-test.rescue
mkdir -p "$d/bin"; printf 'stale\n' > "$d/bin/omarchy-a"
out=$(PATH=$shim:$PATH apply "$r"); rc=$?; w=$(rescue_path "$out")
ok "stuck apply: hook succeeds and reports a new rescue directory" "$rc:$( [[ $w == "$d".* && -d $w ]] && echo yes )" "0:yes"
diff -r "$backup" "$w" >/dev/null 2>&1
ok "stuck apply: exact originals at the reported path, older rescue preserved" "$?:$(cat "$d/bin/omarchy-a")" "0:stale"

r=$(nearby_root); inst "$r" "$M" >/dev/null
cp "$r"/usr/bin/omarchy-{a,b} "$backup/bin/"
out=$(PATH=$shim:$PATH FAIL_RESCUE_COPY=1 TMPDIR=$BASE inst "$r" "$M" --undo); rc=$?; w=$(rescue_path "$out")
ok "stuck undo: reports retained workspace when rescue copy fails" "$rc:$( [[ $w == "$BASE"/k114s-omarchy-merge.*/keep && -d $w ]] && echo yes )" "1:yes"
diff -r "$backup" "$w" >/dev/null 2>&1
ok "stuck undo: retained originals match and the applied record survives" "$?:$(markers "$r")" "0:0001-test.applied "
# Omarchy ships the fix in one file and changes only context in the other: nothing is written,
# and --undo leaves Omarchy's own fix alone.
r=$(mk); inst "$r" "$M" >/dev/null; orig "$r"; sed -i 's/^key=user$/key=user-org/' "$r/usr/bin/omarchy-a"; sed -i 's/^# end$/# finish/' "$r/usr/bin/omarchy-b"; shipped "$r"
before=$(sumof "$r"); out=$(applyn "$r")
ok "partly shipped: reported, nothing written" "$(grep -c '0001-test: Omarchy ships part of this change' <<<"$out"):$(sumof "$r")" "1:$before"
nok "partly shipped: notified" "$(grep -c '0001-test: Omarchy ships part of it now' "$NOTES")" 1
out=$(inst "$r" "$M" --undo); ok "partly shipped, undo: Omarchy's fix kept, nothing changed" "$(sumof "$r")" "$before"
y() { tr '\n' ' ' < "$1/usr/bin/omarchy-y"; }
# Two hunks in one file: Omarchy ships the first and changes context near the second. Taking the
# merged change out again would remove Omarchy's hunk too, so nothing is written.
two=$BASE/two; mkdir -p "$two/0001-two.base/bin"
mkpatch "$two/0001-two.patch" omarchy-y '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n' '1\nTWO\n3\n4\n5\n6\n7\n8\n9\n10\nELEVEN\n12\n'
printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n' > "$two/0001-two.base/bin/omarchy-y"
r=$(mk); printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n' > "$r/usr/bin/omarchy-y"; shipped "$r"; inst "$r" "$two" >/dev/null
# (git merge-file treats changes on adjacent lines as a conflict, so Omarchy's lie three lines away.)
printf '1\nTWO\n3\n4\n5\n6\n7\neight\n9\n10\n11\n12\n' > "$r/usr/bin/omarchy-y"; shipped "$r"
out=$(applyn "$r"); ok "partly shipped in one file: reported, nothing written" "$(grep -c '0001-two: Omarchy ships part of this change' <<<"$out"):$(y "$r")" "1:1 TWO 3 4 5 6 7 eight 9 10 11 12 "
out=$(inst "$r" "$two" --undo); ok "partly shipped in one file, undo: Omarchy's hunk kept" "$(y "$r")" "1 TWO 3 4 5 6 7 eight 9 10 11 12 "
# Two hunks, Omarchy changes context near both and ships neither: merged, and undo gives Omarchy's file.
r=$(mk); printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n' > "$r/usr/bin/omarchy-y"; shipped "$r"; inst "$r" "$two" >/dev/null
printf '1\n2\n3\n4\nfive\n6\n7\neight\n9\n10\n11\n12\n' > "$r/usr/bin/omarchy-y"; shipped "$r"
out=$(applyn "$r"); ok "two hunks, context changed: merged" "$(y "$r")" "1 TWO 3 4 five 6 7 eight 9 10 ELEVEN 12 "
out=$(inst "$r" "$two" --undo); ok "two hunks, context changed, undo: Omarchy's file" "$(y "$r")" "1 2 3 4 five 6 7 eight 9 10 11 12 "
# A base folder that does not match its patch is refused by the installer.
bad=$BASE/badbase; cp -r "$M" "$bad"; sed -i 's/^key=user$/key=other/' "$bad/0001-test.base/bin/omarchy-a"
r=$(mk); out=$(inst "$r" "$bad"); ok "bad base: install refused, nothing applied" "$?:$(grep -c 'base folder that does not match' <<<"$out"):$(sumof "$r")" "1:1:$ORIG"

# Omarchy merges the fix: its package installs the fixed files. Nothing is written, the hook says
# to retire the patch, and neither --undo nor a refresh without it takes Omarchy's fix out.
merged() { local r; r=$(mk); inst "$r" >/dev/null; orig "$r"; fixed "$r"; shipped "$r"; echo "$r"; }
r=$(merged); touch -d '2001-01-01' "$r/usr/bin/omarchy-a"
out=$(apply "$r"); ok "upstream merged: says retire" "$(grep -c 'Omarchy ships this change itself now' <<<"$out")" 1
ok "upstream merged: not rewritten" "$(stat -c %Y "$r/usr/bin/omarchy-a")" "$(date -d '2001-01-01' +%s)"
out=$(inst "$r" "$SRC" --undo); rc=$?
ok "upstream merged, undo: succeeds" "$rc" 0
ok "upstream merged, undo: Omarchy's fix kept" "$(sumof "$r")" "$FIXED"
ok "upstream merged, undo: says why" "$(grep -c 'its own carry this change' <<<"$out")" 1
other=$BASE/other; mkdir -p "$other"; mkpatch "$other/0002-other.patch" omarchy-c 'one\n' 'two\n'
r=$(merged); out=$(inst "$r" "$other"); rc=$?
ok "upstream merged, retired: Omarchy's fix kept" "$rc:$(sumof "$r")" "0:$FIXED"
ok "upstream merged, retired: forgotten" "$(installed "$r")" "0002-other.patch "

# Two patches share a file and Omarchy merges only one of them: the other is still re-applied,
# the merged one is reported for retirement, and neither --undo nor retiring it strips Omarchy's fix.
share=$BASE/share; mkdir -p "$share"
mkpatch "$share/0001-ours.patch" omarchy-y '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n' '1\nTWO\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n'
mkpatch "$share/0002-merged.patch" omarchy-y '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n' '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\nELEVEN\n12\n'
y() { tr '\n' ' ' < "$1/usr/bin/omarchy-y"; }
sharedroot() { local r; r=$(mk); printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n' > "$r/usr/bin/omarchy-y"; shipped "$r"; inst "$r" "$share" >/dev/null
  printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\nELEVEN\n12\n' > "$r/usr/bin/omarchy-y"; shipped "$r"; echo "$r"; }
r=$(sharedroot); out=$(apply "$r")
ok "shared file, one merged: ours re-applied" "$(tr '\n' ' ' < "$r/usr/bin/omarchy-y")" "1 TWO 3 4 5 6 7 8 9 10 ELEVEN 12 "
ok "shared file, one merged: merged one reported" "$(grep -c '0002-merged: Omarchy ships this change itself now' <<<"$out")" 1
out=$(inst "$r" "$share" --undo); ok "shared file, undo: only ours taken out" "$(tr '\n' ' ' < "$r/usr/bin/omarchy-y")" "1 2 3 4 5 6 7 8 9 10 ELEVEN 12 "
r=$(sharedroot); apply "$r" >/dev/null; keep=$BASE/keep; mkdir -p "$keep"; cp "$share/0001-ours.patch" "$keep/"
out=$(inst "$r" "$keep"); ok "shared file, merged one retired: Omarchy's fix kept" "$(tr '\n' ' ' < "$r/usr/bin/omarchy-y")" "1 TWO 3 4 5 6 7 8 9 10 ELEVEN 12 "
ok "shared file, merged one retired: its record gone" "$(markers "$r")" "0001-ours.applied "

# Omarchy already ships one of two patches on a shared file: later refreshes never adopt it,
# and --undo leaves Omarchy's change in.
r=$(mk); printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\nELEVEN\n12\n' > "$r/usr/bin/omarchy-y"; shipped "$r"
out=$(inst "$r" "$share"); ok "already shipped: reported, not recorded" "$(grep -c '0002-merged: Omarchy ships' <<<"$out"):$(markers "$r")" "1:0001-ours.applied "
out=$(inst "$r" "$share"); ok "already shipped, second refresh: still not adopted" "$(grep -c 'recorded as applied' <<<"$out"):$(markers "$r")" "0:0001-ours.applied "
out=$(inst "$r" "$share" --undo); ok "already shipped, undo: Omarchy's change kept" "$(tr '\n' ' ' < "$r/usr/bin/omarchy-y")" "1 2 3 4 5 6 7 8 9 10 ELEVEN 12 "

# Only files the Omarchy package installed may be changed: no created or deleted files.
newf=$BASE/newf; mkdir -p "$newf"; printf 'hello\n' > "$BASE/mp/created"
diff -u /dev/null "$BASE/mp/created" | sed "1s#^--- .*#--- /dev/null#; 2s#^+++ .*#+++ b/bin/omarchy-new#" > "$newf/0001-new.patch"
r=$(mk); out=$(inst "$r" "$newf"); rc=$?
ok "creates a file: refused, nothing installed" "$rc:$(test -e "$r/usr/bin/omarchy-new" && echo there || echo gone):$(test -e "$r/etc/pacman.d/hooks/03-k114s-omarchy-patches.hook" && echo hook || echo nohook)" "1:gone:nohook"
foreign=$BASE/foreign; mkdir -p "$foreign"; mkpatch "$foreign/0001-foreign.patch" omarchy-unowned 'a\n' 'b\n'
r=$(mk); printf 'a\n' > "$r/usr/bin/omarchy-unowned"; out=$(inst "$r" "$foreign"); rc=$?
ok "file no package installed: refused" "$rc:$(grep -c 'none of omarchy, omarchy-dev and omarchy-mac installed' <<<"$out")" "1:1"
# A file another omarchy-* package owns (the hook does not watch it): refused too.
r=$(mk); d=$r/var/lib/pacman/local/omarchy-settings-dev-1-1; mkdir -p "$d"
echo "./usr/bin/omarchy-unowned time=1.0 size=2 sha256digest=$(printf 'a\n' | sha256sum | cut -c1-64)" | gzip > "$d/mtree"
printf 'a\n' > "$r/usr/bin/omarchy-unowned"; out=$(inst "$r" "$foreign"); rc=$?
ok "file of another omarchy package: refused" "$rc:$(cat "$r/usr/bin/omarchy-unowned")" "1:a"
# A file omarchy-mac owns (the platform data and audio rules): accepted, and applied.
r=$(mk); d=$r/var/lib/pacman/local/omarchy-mac-1-1; mkdir -p "$d"
echo "./usr/bin/omarchy-unowned time=1.0 size=2 sha256digest=$(printf 'a\n' | sha256sum | cut -c1-64)" | gzip > "$d/mtree"
printf 'a\n' > "$r/usr/bin/omarchy-unowned"; out=$(inst "$r" "$foreign"); rc=$?
ok "file of omarchy-mac: accepted and applied" "$rc:$(cat "$r/usr/bin/omarchy-unowned")" "0:b"
# A sibling package whose name starts with omarchy-mac (omarchy-mac-boot) is not omarchy-mac: refused.
r=$(mk); d=$r/var/lib/pacman/local/omarchy-mac-boot-20261104-1; mkdir -p "$d"
echo "./usr/bin/omarchy-unowned time=1.0 size=2 sha256digest=$(printf 'a\n' | sha256sum | cut -c1-64)" | gzip > "$d/mtree"
printf 'a\n' > "$r/usr/bin/omarchy-unowned"; out=$(inst "$r" "$foreign"); rc=$?
ok "file of omarchy-mac-boot: refused (not matched by the omarchy-mac glob)" "$rc:$(cat "$r/usr/bin/omarchy-unowned")" "1:a"

# Applied by the first version of this tool (no records): the next run adopts it, once.
legacy() { local r; r=$(mk); inst "$r" >/dev/null; rm -f "$r"/usr/local/lib/omarchy-k114s/omarchy-patches/{*.applied,.records}; echo "$r"; }
r=$(legacy); out=$(inst "$r"); ok "first version: adopted on refresh" "$(grep -c 'recorded as applied here' <<<"$out"):$(markers "$r")" "1:0001-test.applied "
out=$(inst "$r" "$SRC" --undo); ok "adopted: undo takes it out" "$(sumof "$r")" "$ORIG"
r=$(legacy); out=$(inst "$r" "$SRC" --undo); ok "first version, straight to undo: taken out" "$(grep -c 'taken out' <<<"$out"):$(sumof "$r")" "1:$ORIG"
# A refused install on a first-version install leaves it unmigrated, so it is adopted later.
r=$(legacy); out=$(inst "$r" "$newf"); ok "refused refresh: first version left unmigrated" "$(markers "$r"):$(test -e "$r/usr/local/lib/omarchy-k114s/omarchy-patches/.records" && echo marked || echo unmarked)" ":unmarked"

# Retiring: a refresh without the patch takes it out first. The last one is retired with --undo.
r=$(mk); inst "$r" >/dev/null; empty=$BASE/empty; mkdir -p "$empty"
out=$(inst "$r" "$empty"); rc=$?
ok "no patches in source: refused" "$rc" 1
ok "no patches in source: points at --undo" "$(grep -c -- '--undo' <<<"$out")" 1
ok "no patches in source: fix still in" "$(sumof "$r")" "$FIXED"
out=$(inst "$r" "$other"); rc=$?
ok "retire: succeeds" "$rc" 0
ok "retire: old fix taken out" "$(sumof "$r")" "$ORIG"
ok "retire: old patch forgotten" "$(installed "$r")" "0002-other.patch "
ok "retire: new fix applied" "$(cat "$r/usr/bin/omarchy-c")" two
out=$(inst "$r"); ok "switch back: first fix in, second out" "$(sumof "$r"):$(cat "$r/usr/bin/omarchy-c")" "$FIXED:one"

# Stacked patches on neighbouring lines of one file: 0001 b->B, 0002 c->C with B as context.
stack=$BASE/stack; mkdir -p "$stack"
mkpatch "$stack/0001-p.patch" omarchy-x 'a\nb\nc\nd\n' 'a\nB\nc\nd\n'
mkpatch "$stack/0002-q.patch" omarchy-x 'a\nB\nc\nd\n' 'a\nB\nC\nd\n'
r=$(mk); inst "$r" "$stack" >/dev/null; ok "stacked: both applied" "$(x "$r")" "a B C d "
out=$(inst "$r" "$other"); ok "stacked, both retired: file as shipped" "$(x "$r")" "a b c d "
ok "stacked, both retired: only the new one installed" "$(installed "$r")" "0002-other.patch "
changed=$BASE/changed; mkdir -p "$changed"
mkpatch "$changed/0001-p.patch" omarchy-x 'a\nb\nc\nd\n' 'a\nBB\nc\nd\n'
mkpatch "$changed/0002-q.patch" omarchy-x 'a\nBB\nc\nd\n' 'a\nBB\nC\nd\n'
r=$(mk); inst "$r" "$stack" >/dev/null; out=$(inst "$r" "$changed")
ok "stacked, lower changed: old out, new in, upper back" "$(x "$r")" "a BB C d "
# A new patch that sorts below an installed one it overlaps.
upper=$BASE/upper; mkdir -p "$upper"; mkpatch "$upper/0002-q.patch" omarchy-x 'a\nb\nc\nd\n' 'a\nb\nC\nd\n'
r=$(mk); inst "$r" "$upper" >/dev/null; ok "new lower patch: upper alone first" "$(x "$r")" "a b C d "
out=$(inst "$r" "$stack"); ok "new lower patch: both in, in order" "$(x "$r")" "a B C d "
out=$(inst "$r" "$stack" --undo); ok "stacked, undo: file as shipped" "$(x "$r")" "a b c d "

# Undo puts the shipped files back and removes everything installed.
r=$(mk); inst "$r" >/dev/null; out=$(inst "$r" "$SRC" --undo); rc=$?
ok "undo: succeeds" "$rc" 0
ok "undo: files as shipped" "$(sumof "$r")" "$ORIG"
ok "undo: hook, applier, library and patches gone" "$(find "$r/etc" "$r/usr/local" -type f | wc -l | tr -d ' ')" 0
out=$(inst "$r" "$SRC" --undo); rc=$?; ok "undo twice: refused" "$rc" 1
r=$(mk); inst "$r" >/dev/null; orig "$r"; out=$(inst "$r" "$SRC" --undo); rc=$?
ok "undo after an update: succeeds, files as shipped" "$rc:$(sumof "$r")" "0:$ORIG"
r=$(mk); out=$(K114S_ROOT=$r bash "$INSTALL" bogus 2>&1); rc=$?; ok "unknown argument: refused" "$rc" 1

# The Limine guard follows the install, retirement and undo of the patches that use it.
r=$(mk); boot_src=$BASE/boot-src; mkdir "$boot_src"
boot_patch=$(printf '%s\n' "$P"/0006-*.patch)
cp "$SRC/0001-test.patch" "$boot_patch" "$boot_src/"
cp -r "${boot_patch%.patch}.base" "$boot_src/"
cp "${boot_patch%.patch}.base/bin/omarchy-plymouth-set" "$r/usr/bin/"
shipped "$r"
guard=$r/etc/boot/hooks/pre.d/00-k114s-boot-rebuild-guard
out=$(inst "$r" "$boot_src"); rc=$?
ok "0006: installs the executable Limine guard and applies the patch" \
  "$rc:$(test -x "$guard" && cmp -s "$guard" "$L/${guard##*/}" && echo yes):$(grep -c '0006-.*: applied' <<<"$out")" "0:yes:1"
out=$(inst "$r"); rc=$?
ok "0006: retiring the patch removes the guard" "$rc:$(test ! -e "$guard" && echo yes)" "0:yes"
out=$(inst "$r" "$boot_src") && out=$(inst "$r" "$boot_src" --undo); rc=$?
ok "0006: undo removes the guard" "$rc:$(test ! -e "$guard" && echo yes)" "0:yes"

r=$(mk); initcpio_src=$BASE/initcpio-src; mkdir "$initcpio_src"
initcpio_patch=$(printf '%s\n' "$P"/0007-*.patch)
cp "$SRC/0001-test.patch" "$initcpio_patch" "$initcpio_src/"
cp -r "${initcpio_patch%.patch}.base" "$initcpio_src/"
cp "${initcpio_patch%.patch}.base/bin/omarchy-boot-sync-initcpio" "$r/usr/bin/"
shipped "$r"
guard=$r/etc/boot/hooks/pre.d/00-k114s-boot-rebuild-guard
out=$(inst "$r" "$initcpio_src"); rc=$?
ok "0007 without 0006: installs the executable Limine guard and applies the patch" \
  "$rc:$(test -x "$guard" && cmp -s "$guard" "$L/${guard##*/}" && echo yes):$(grep -c '0007-.*: applied' <<<"$out")" "0:yes:1"
out=$(inst "$r"); rc=$?
ok "0007: retiring the patch removes the guard and restores the shipped script" \
  "$rc:$(test ! -e "$guard" && cmp -s "$r/usr/bin/omarchy-boot-sync-initcpio" "${initcpio_patch%.patch}.base/bin/omarchy-boot-sync-initcpio" && echo yes)" "0:yes"

# Without GNU patch: the hook writes nothing and says so; the installer refuses.
nopatch=$BASE/nopatch; mkdir -p "$nopatch"
for t in bash basename dirname cat cmp cut gzip zcat awk sed sort head id install mkdir rm sha256sum env tr; do ln -s "$(command -v $t)" "$nopatch/$t"; done
r=$(mk); inst "$r" >/dev/null; orig "$r"
out=$(PATH=$nopatch K114S_ROOT=$r "$nopatch/bash" "$r/usr/local/lib/omarchy-k114s/omarchy-patches-apply" 2>&1); rc=$?
ok "no patch tool: hook exits 0, writes nothing" "$rc:$(sumof "$r")" "0:$ORIG"
ok "no patch tool: says so" "$(grep -c 'GNU patch is not installed' <<<"$out")" 1
out=$(PATH=$nopatch K114S_ROOT=$r K114S_OMARCHY_PATCHES_SRC=$SRC "$nopatch/bash" "$INSTALL" --undo 2>&1); rc=$?
ok "no patch tool: installer refuses" "$rc:$(grep -c 'GNU patch is not installed' <<<"$out")" "1:1"

# The hook runs the installed applier after the Omarchy package changes, never before.
H=$L/03-k114s-omarchy-patches.hook
ok "hook: Exec is the installed applier" "$(sed -n 's/^Exec = //p' "$H")" /usr/local/lib/omarchy-k114s/omarchy-patches-apply
ok "hook: after the transaction" "$(sed -n 's/^When = //p' "$H")" PostTransaction
ok "hook: all three package names" "$(sed -n 's/^Target = //p' "$H" | tr '\n' ' ')" "omarchy omarchy-dev omarchy-mac "
ok "hook: cannot abort a transaction" "$(grep -c AbortOnFail "$H")" 0

# The real patches against the Omarchy revision this machine runs.
if [ -n "${2:-}" ]; then
  # Omarchy's bin/ installs as /usr/bin and its shell/ as /usr/share/omarchy/shell.
  O=$BASE/omarchy; mkdir -p "$O/usr/share/omarchy"; cp -a "$2/bin" "$O/usr/bin"
  [ -d "$2/shell" ] && cp -a "$2/shell" "$O/usr/share/omarchy/shell"
  shipped "$O"
  # Patches to omarchy-mac's files (0003, 0004) have no counterpart in an omacom/omarchy tree.
  R=$BASE/real; mkdir -p "$R"; real_count=0
  for p in "$P"/*.patch; do
    n=$(basename "$p"); mac_missing=""; unexpected=""
    while read -r f; do
      [ -f "$O/usr/$f" ] && continue
      case "$n:$f" in
        0003-omarchy-mac-k114s-display-cutout.patch:share/omarchy-platform/display-cutouts.json|\
        0004-omarchy-mac-k-board-audio-names.patch:share/omarchy-platform/audio.json|\
        0004-omarchy-mac-k-board-audio-names.patch:bin/omarchy-audio-asahi-mic-map|\
        0004-omarchy-mac-k-board-audio-names.patch:share/pipewire/pipewire.conf.d/asahi-device-names.conf|\
        0004-omarchy-mac-k-board-audio-names.patch:share/wireplumber/wireplumber.conf.d/asahi-audio-no-suspend.conf)
          mac_missing=$f ;;
        *) unexpected=$f; break ;;
      esac
    done < <(sed -n 's#^+++ b/\([^[:space:]]*\).*#\1#p' "$p" | LC_ALL=C sort -u)
    if [ -n "$unexpected" ]; then ok "real $n: target $unexpected exists" missing present; continue; fi
    if [ -n "$mac_missing" ]; then echo "SKIP real $n: $mac_missing belongs to omarchy-mac"; continue; fi
    cp "$p" "$R/"; [ -d "${p%.patch}.base" ] && cp -r "${p%.patch}.base" "$R/"
    real_count=$((real_count + 1))
    patch -p1 -d "$O/usr" -F0 -s -f --dry-run < "$p" >/dev/null 2>&1; ok "real $n: applies without fuzz" "$?" 0
  done
  out=$(K114S_ROOT=$O K114S_OMARCHY_PATCHES_SRC=$R bash "$INSTALL" 2>&1); ok "real patches: install succeeds" "$?" 0
  ok "real patches: all applied" "$(grep -c ': applied' <<<"$out")" "$real_count"
  for f in "$O"/usr/bin/omarchy-agent-*; do head -1 "$f" | grep -q python && { python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$f" || ok "real: $(basename "$f") parses" 1 0; }; done
  for f in "$O"/usr/share/omarchy/shell/plugins/*/*.qml; do
    [ -x /usr/lib/qt6/bin/qmllint ] || break
    # This qmllint reports a syntax error as a "Warning: ... [syntax]" line and exits non-zero.
    lint=$(/usr/lib/qt6/bin/qmllint "$f" 2>&1); lrc=$?
    if [ "$lrc" != 0 ] || grep -q '\[syntax\]' <<<"$lint"; then ok "real: $(basename "$f") passes qmllint" "$lrc" 0; fi
  done
  out=$(K114S_ROOT=$O K114S_OMARCHY_PATCHES_SRC=$R bash "$INSTALL" --undo 2>&1)
  same=same; diff -r "$2/bin" "$O/usr/bin" >/dev/null || same=differs
  [ -d "$2/shell" ] && { diff -r "$2/shell" "$O/usr/share/omarchy/shell" >/dev/null || same=differs; }
  ok "real patches: undo gives the shipped files" "$same" same
  ok "real patches: no .orig or .rej" "$(leftovers "$O")" 0
fi

echo "omarchy patches tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
