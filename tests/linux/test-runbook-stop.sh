#!/bin/bash
# The STOP paths of runbook steps F, G and Z (docs/r3-integration.md, issue #16), run as a normal user.
#   usage: test-runbook-stop.sh [LINUX_DIR]
# The code blocks are cut out of the runbook itself and run with stand-ins: sudo is a no-op wrapper, /boot/efi and /etc/omarchy-k114s
# are rewritten to a throwaway folder, `sync` fails on demand, k114s-boot-once ($K) and systemctl only log. So this proves the
# STOP texts, exit codes and what aura-try reads, not that any boot works.
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
DOC=$T/../../docs/r3-integration.md
W=$BASE/rb; mkdir -p "$W/bin" "$W/home"
for c in findmnt mount; do printf '#!/bin/sh\nexit 0\n' > "$W/bin/$c"; done
printf '#!/bin/sh\n[ -e "%s/fail-sync" ] && exit 1\nexit 0\n' "$W" > "$W/bin/sync"
printf '#!/bin/sh\necho "$@" >> "%s/calls"\n' "$W" > "$W/bin/systemctl"
printf '#!/bin/sh\necho "$@" >> "%s/calls"\nexit 0\n' "$W" > "$W/k"
chmod +x "$W"/bin/* "$W/k"
block() { # block ANCHOR: the first ( ... ) code block after the line starting with ANCHOR
  awk -v a="$1" 'index($0, a) == 1 { f = 1 } f && $0 == "    (" { c = 1; next } c && $0 == "    )" { exit } c { print }' "$DOC"
}
run() { # run NAME  (stdin: the block, already rewritten) -> $out, $rc
  out=$(cd "$W" && HOME=$W/home PATH=$W/bin:$PATH K=$W/k R=$W/R bash -c 'sudo() { "$@"; }; '"$(cat)" 2>&1); rc=$?
}
rewrite() { sed "s#/boot/efi#$W/esp#g; s#/etc/omarchy-k114s#$W/etc#g; s#systemctl reboot#systemctl reboot-test#"; }
fresh() { rm -rf "$W/esp" "$W/etc" "$W/R" "$W/calls" "$W/fail-sync" "$W/home/.config"; mkdir -p "$W/esp/m1n1" "$W/etc" "$W/R" "$W/home/.config"; chmod -R u+w "$W" 2>/dev/null; }
first() { sed -n 1p "$W/esp/aura-try" 2>/dev/null; }

# --- step F -----------------------------------------------------------------------------------------------------------------
fresh; echo stage2 > "$W/R/boot-ctxr-r3a.bin"; fh=$(sum "$W/R/boot-ctxr-r3a.bin")
blockF=$(block '**8. Step F' | rewrite | sed "s/5164bb1e1be1fba39aee64229863b2f835828edd8b4f90e8cfa91e71a6fd8cd9/$fh/")
ok "step F block found" "$(echo "$blockF" | grep -c 'aura-try')" 5
fresh; echo stage2 > "$W/R/boot-ctxr-r3a.bin"; run <<< "$blockF"
ok "F: everything works: aura-try armed, the reboot runs" "$rc $(first) $(cat "$W/calls" | grep -c reboot-test)" "0 armed 1"
fresh; echo stage2 > "$W/R/boot-ctxr-r3a.bin"; touch "$W/fail-sync"; run <<< "$blockF"
ok "F: sync -f alone fails after the file was written: exit 1, no reboot, aura-try reads spent" "$rc $(first) $(grep -c reboot-test "$W/calls")" "1 spent 0"
ok "F: that STOP text says it may have read armed, now spent, and that the kernel request is pending" "$(echo "$out" | grep -c 'may have read armed.*set to spent.*request armed above is still pending')" 1
ok "F: and it no longer says the file was not written" "$(echo "$out" | grep -c 'aura-try was not written;')" 0

# the spend write fails too (aura-try cannot be written and still reads armed): a separate STOP, no reboot
fresh; echo stage2 > "$W/R/boot-ctxr-r3a.bin"; printf 'armed\nx\n' > "$W/esp/aura-try"; chmod a-w "$W/esp/aura-try"; touch "$W/fail-sync"
run <<< "$(echo "$blockF" | sed "s#> $W/esp/aura-try#> $W/esp/aura-try-none/x#")"
ok "F: when aura-try cannot be set to spent: exit 1, its own STOP, no reboot" "$rc $(echo "$out" | grep -c 'does not read spent') $(grep -c reboot-test "$W/calls" 2>/dev/null)" "1 1 0"

# --- step G -----------------------------------------------------------------------------------------------------------------
GH=9825a10317866865b49d26bc1df2d0d04a818d385ca62c1a3ce81d96f3d6b8fc
blockG=$(block '**9. Step G' | rewrite)
ok "step G block found" "$(echo "$blockG" | grep -c 'aura-try')" 5
fresh; echo gpu > "$W/esp/m1n1/boot-ctxr-r3-gpu.bin"; touch "$W/etc/stage2-trial.parked-r3a"
bg=$(printf '%s' "$blockG" | sed "s/$GH/$(sum "$W/esp/m1n1/boot-ctxr-r3-gpu.bin")/")
run <<< "$bg"
ok "G: the matching file passes the hash check: aura-try armed, trial restored, reboot" "$rc $(first) $(test -f "$W/etc/stage2-trial"; echo $?) $(grep -c reboot-test "$W/calls")" "0 armed 0 1"
fresh; echo changed > "$W/esp/m1n1/boot-ctxr-r3-gpu.bin"; touch "$W/etc/stage2-trial.parked-r3a"; run <<< "$blockG"
ok "G: a different boot-ctxr-r3-gpu.bin stops before the arm: nothing armed, nothing written" "$rc $(test -e "$W/esp/aura-try"; echo $?) $(test -e "$W/calls"; echo $?)" "1 1 1"
ok "G: that STOP names the file" "$(echo "$out" | grep -c 'STOP: m1n1/boot-ctxr-r3-gpu.bin is not the file the GPU trial proved')" 1
fresh; : > "$W/esp/m1n1/boot-ctxr-r3-gpu.bin"; touch "$W/etc/stage2-trial.parked-r3a"; run <<< "$blockG"
ok "G: a file that is missing or empty stops too" "$rc $(test -e "$W/esp/aura-try"; echo $?)" "1 1"
fresh; echo gpu > "$W/esp/m1n1/boot-ctxr-r3-gpu.bin"; touch "$W/etc/stage2-trial.parked-r3a" "$W/fail-sync"; run <<< "$bg"
ok "G: sync -f alone fails: exit 1, aura-try spent, the trial stays parked, no reboot" "$rc $(first) $(test -f "$W/etc/stage2-trial"; echo $?) $(grep -c reboot-test "$W/calls")" "1 spent 1 0"
ok "G: that STOP text says it may have read armed" "$(echo "$out" | grep -c 'may have read armed.*set to spent')" 1

# --- step Z: the spent step (the block up to the update-m1n1 copy) ----------------------------------------------------------
blockZ=$(block '**Z. Undo' | rewrite | sed '/before-undo$/,$d')
ok "step Z block found" "$(echo "$blockZ" | grep -c 'aura-try')" 3
fresh; printf 'armed\nm1n1/boot-ctxr-r3-gpu.bin\n' > "$W/esp/aura-try"; run <<< "$blockZ"
ok "Z: armed becomes spent, the undo goes on" "$rc $(first)" "0 spent"
fresh; printf 'spent\nm1n1/boot-ctxr-r3-gpu.bin\n' > "$W/esp/aura-try"; run <<< "$blockZ"
ok "Z: already spent: left alone" "$rc $(first)" "0 spent"
fresh; printf 'armed\nm1n1/boot-ctxr-r3-gpu.bin\n' > "$W/esp/aura-try"; touch "$W/fail-sync"; run <<< "$blockZ"
ok "Z: the sync fails: STOP, exit 1" "$rc $(echo "$out" | grep -c 'STOP: aura-try still reads armed or was not synced')" "1 1"
fresh; printf 'armed\nm1n1/boot-ctxr-r3-gpu.bin\n' > "$W/esp/aura-try"; chmod 555 "$W/esp"; run <<< "$blockZ"; chmod 755 "$W/esp"
ok "Z: the write fails (sed -i cannot make its temp file): aura-try still armed, STOP, exit 1" "$rc $(first) $(echo "$out" | grep -c 'STOP: aura-try still reads armed or was not synced')" "1 armed 1"
finish "runbook STOP tests"
