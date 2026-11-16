#!/bin/bash
# linux/99-k114s-no-appledrm.conf and linux/initramfs-no-appledrm-k114s in a replica root and a fake mkinitcpio module list.
# Nothing real is built and no real system file is touched: the real proof (a throw-away image listed with lsinitcpio) is the
# root's step in docs/r3-display-d5-d9.md, G6b.
#   usage: test-initramfs-no-appledrm.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
TOOL=$L/initramfs-no-appledrm-k114s; DROP=$L/99-k114s-no-appledrm.conf; NAME=${DROP##*/}
ok "installer parses" "$(bash -n "$TOOL" 2>&1)" ""
ok "drop-in parses" "$(bash -n "$DROP" 2>&1)" ""
ok "installer is executable in the repository" "$(test -x "$TOOL"; echo $?)" 0

# --- the installer, against a replica root ---------------------------------------------------------------------------------
X=$BASE/root; D=$X/etc/mkinitcpio.conf.d; mkdir -p "$D"; printf 'HOOKS+=(x)\n' > "$D/95-other.conf"
run() { out=$(K114S_ROOT=$X bash "$TOOL" "$@" 2>&1); rc=$?; }
run; ok "install: exit 0 and the drop-in is the repository's file, mode 644" "$rc $(cmp -s "$DROP" "$D/$NAME"; echo $?) $(stat -c %a "$D/$NAME")" "0 0 644"
run; ok "install: a second run is the same (idempotent)" "$rc $(cmp -s "$DROP" "$D/$NAME"; echo $?)" "0 0"
echo '# edited' > "$D/$NAME"; run; ok "install: a different file of that name is replaced and said so" "$rc $(echo "$out" | grep -c replacing) $(cmp -s "$DROP" "$D/$NAME"; echo $?)" "0 1 0"
ok "install: no other drop-in is touched" "$(cat "$D/95-other.conf")" 'HOOKS+=(x)'
run --undo; ok "undo: removes the file and nothing else" "$rc $(test -e "$D/$NAME"; echo $?) $(test -e "$D/95-other.conf"; echo $?)" "0 1 0"
run --undo; ok "undo: with nothing installed says so and exits 0" "$rc $(echo "$out" | grep -c 'nothing to undo')" "0 1"
echo '# somebody else' > "$D/$NAME"; run --undo; ok "undo: a file this script did not install is kept" "$rc $(cat "$D/$NAME")" "1 # somebody else"
run --bogus; ok "an unknown argument stops" "$rc" 1
out=$(env -u K114S_ROOT bash "$TOOL" 2>&1); ok "without root and without K114S_ROOT it stops (nothing under /etc is written by a test)" "$? $(echo "$out" | grep -c 'run with sudo')" "1 1"

# --- the drop-in, against a fake mkinitcpio: add_module returns at once for a module already counted as added (as the real one does) ---
# The module list is what autodetect and kms would offer on a display-tree boot, the two MODULES entries of 92-omarchy-mac-*.conf and the display-only pair.
MODS="drm_dma_helper appledrm dcp_fabric_core snd_pcm typec simpledrm_helper"   # apple_pmp is not here: only the MODULES entry below may add it
fake() { # fake WITH_DROPIN: prints the modules the fake build adds
  (
    declare -A _addedmodules; added=()
    add_module() { local t=${1//-/_}; (( _addedmodules["$t"] == 1 )) && return; _addedmodules["$t"]=1; added+=("$t"); }
    [ "$1" = yes ] && . "$DROP"
    _addedmodules[builtin_thing]=2     # preload_builtin_modules marks built-ins 2: untouched
    for m in $MODS; do add_module "$m"; done   # the hooks (kms: drivers/gpu/drm, and every dependency the real add_module follows)
    add_module apple-pmp                       # a MODULES entry, as 92-omarchy-mac-pmp.conf adds it
    printf '%s\n' "${added[*]}"
  )
}
ok "without the drop-in the fake build adds appledrm and dcp_fabric_core (the test sees the problem)" "$(fake no | grep -c -E 'appledrm.*dcp_fabric_core|dcp_fabric_core.*appledrm')" 1
ok "with the drop-in: appledrm and dcp_fabric_core are out, the rest is added in order, apple_pmp stays through its MODULES entry" "$(fake yes)" "drm_dma_helper snd_pcm typec simpledrm_helper apple_pmp"
ok "with the drop-in, the key add_module looks up (the name without .ko and with underscores) is set for both" "$(
  declare -A _addedmodules; . "$DROP"; t=appledrm.ko; t=${t%.ko*}; echo "${_addedmodules[$t]} ${_addedmodules[dcp_fabric_core]}")" "1 1"
ok "sourced with no associative _addedmodules (a hook reading the configuration), under set -u: no error, no array made" "$(bash -c 'set -u; . "$1"; declare -p _addedmodules 2>&1 | grep -c "not found"' _ "$DROP")" 1
ok "sourced a second time (mkinitcpio re-reads the configuration after the hooks): the same state" "$(bash -c 'declare -A _addedmodules; . "$1"; . "$1"; echo ${#_addedmodules[@]} ${_addedmodules[appledrm]}' _ "$DROP")" "2 1"
ok "the drop-in names simpledrm nowhere (it is built in and stays)" "$(grep -v '^#' "$DROP" | grep -c simpledrm)" 0
# the mechanism it relies on is still in this host's mkinitcpio (skipped where mkinitcpio is not installed)
if [ -r /usr/lib/initcpio/functions ]; then
  ok "this host's add_module still returns early for a module counted as added" "$(grep -c '(( _addedmodules\["\$target"\] == 1 )) && return' /usr/lib/initcpio/functions)" 1
  ok "this host's mkinitcpio declares _addedmodules associative before it reads the configuration" "$(grep -n -m1 -E '^declare -A .*_addedmodules' /usr/bin/mkinitcpio | cut -d: -f1 | awk '{ print ($1 > 0 && $1 < 100) }')" 1
  ok "this host's mkinitcpio never resets _addedmodules between the configuration and the hooks (the drop-in would stop working)" "$(grep -c -E '(^|[^[:alnum:]_])(unset _addedmodules|_addedmodules=\()' /usr/bin/mkinitcpio /usr/lib/initcpio/functions | awk -F: '{ n += $2 } END { print n + 0 }')" 0
fi
finish "initramfs no-appledrm tests"
