#!/bin/bash
# Tests of linux/r3a-trial/k114s-lid-sleep and of what k114s-boot-once check makes of it, in fake roots. No real file,
# unit or target is touched; systemctl is a stand-in that keeps the unit state as symlinks in the fake root.
#   usage: test-lid-sleep.sh [PATH-TO-r3a-trial-folder]
set -u
H=$(cd "$(dirname "$0")" && pwd); D=${1:-$H/../../linux/r3a-trial}
W=$(mktemp -d "${TMPDIR:-/tmp}/k114s-lid-sleep-test.XXXXXX"); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
has() { if printf '%s' "$2" | grep -q -- "$3"; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1: lacks [$3]: $(printf '%s' "$2" | tail -2)"; fi; }
BLI=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
GATE=k114s-lid-sleep-gate.service

# a fake machine in $W/$1: the four sleep targets masked in /etc, as the Mac is today
mk() {
  r=$W/$1; mkdir -p "$r/etc/systemd/system" "$r/run/systemd" "$r/state" "$r/efivars" "$r/esp/EFI/Linux" "$r/etc-k"
  for t in suspend hibernate hybrid-sleep suspend-then-hibernate; do ln -s /dev/null "$r/etc/systemd/system/$t.target"; done
  cat > "$r/systemctl" <<'SH'
#!/bin/sh
R=$K114S_ROOT; echo "$@" >> "$R/calls"; E=$R/etc/systemd/system; N=$R/run/systemd/system
case $1 in
  is-enabled) for u in "$@"; do [ "$u" = is-enabled ] && continue
    if [ "$(readlink "$E/$u" 2>/dev/null)" = /dev/null ]; then echo masked
    elif [ "$(readlink "$N/$u" 2>/dev/null)" = /dev/null ]; then echo masked-runtime
    elif [ -e "$E/sysinit.target.wants/$u" ]; then echo enabled
    else case $u in *.target) echo static ;; *) echo disabled ;; esac; fi; done ;;
  enable) mkdir -p "$E/sysinit.target.wants"; ln -sf "$E/$2" "$E/sysinit.target.wants/$2" ;;
  disable) rm -f "$E/sysinit.target.wants/$2" ;;
  mask) ln -sf /dev/null "$E/$2" ;;
  unmask) [ "$(readlink "$E/$2")" = /dev/null ] && rm -f "$E/$2" ;;
  is-active) [ -e "$R/logind-up" ] ;;
  daemon-reload) [ -e "$R/reload-fails" ] && exit 1 ;;
  kill) echo "$@" >> "$R/hups" ;;
esac
exit 0
SH
  chmod +x "$r/systemctl"
  printf 'default_entry: 1\n/Omarchy\n  protocol: efi\n  path: boot():/EFI/Linux/a.efi\n' > "$r/esp/limine.conf"; echo x > "$r/esp/EFI/Linux/a.efi"
}
ls_() { r=$1; shift; K114S_ROOT=$W/$r K114S_STATE=$W/$r/state K114S_EFIVARS=$W/$r/efivars K114S_SYSTEMCTL=$W/$r/systemctl K114S_BOOTID=${BOOT:-boot2} sh "$D/k114s-lid-sleep" "$@" 2>&1; }   # the tool in fake root $r
inst() { ls_ "$1" install; }
reboot() { rm -rf "$W/$1/run"; mkdir -p "$W/$1/run/systemd"; }                 # /run is empty after a reboot
sysst() { K114S_ROOT=$W/$1 "$W/$1/systemctl" is-enabled suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target 2>&1 | tr '\n' ' '; }
st1() { K114S_ROOT=$W/$1 "$W/$1/systemctl" is-enabled "$2"; }
arm_rec() { printf '%s %s\n' "$2" "$3" > "$W/$1/state/boot-once-armed"; }       # arm record: boot, entry id
selected() { { printf '\007\000\000\000'; printf '%s' "$2" | iconv -t UTF-16LE; printf '\0\0'; } > "$W/$1/efivars/LoaderEntrySelected-$BLI"; }
trial_file() { mkdir -p "$W/$1/proc/device-tree/chosen"; printf 'm1n1/boot-ctxr-r3-gpu.bin\0' > "$W/$1/proc/device-tree/chosen/aurora,trial"; }

# --- install on the Mac's current state (four masks, the two 30 drop-ins not yet there) --------------------------------
mk a; out=$(inst a); rc=$?
ok "install: exit 0" "$rc" 0
ok "install: only suspend.target is unmasked; hibernate, hybrid-sleep and suspend-then-hibernate stay masked" "$(sysst a)" "static masked masked masked "
ok "install: the gate unit is enabled" "$(st1 a $GATE)" enabled
has "install: the fail-closed sleep lock is in /etc" "$(cat $W/a/etc/systemd/sleep.conf.d/30-k114s-r3a-trial.conf)" "^AllowSuspend=no"
has "install: the fail-closed lid lock is in /etc" "$(cat $W/a/etc/systemd/logind.conf.d/30-k114s-r3a-trial.conf)" "^HandleLidSwitch=lock"
ok "install: this (ordinary) boot is opened at once" "$(ls $W/a/run/systemd/sleep.conf.d $W/a/run/systemd/logind.conf.d | grep -c 40-k114s-lid-sleep.conf)" 2
l=$(cat $W/a/run/systemd/logind.conf.d/40-k114s-lid-sleep.conf)
ok "ordinary boot: lid on battery suspends" "$(printf '%s' "$l" | grep -c '^HandleLidSwitch=suspend$')" 1
ok "ordinary boot: lid on external power locks" "$(printf '%s' "$l" | grep -c '^HandleLidSwitchExternalPower=lock$')" 1
ok "ordinary boot: docked lid is ignored" "$(printf '%s' "$l" | grep -c '^HandleLidSwitchDocked=ignore$')" 1
s=$(cat $W/a/run/systemd/sleep.conf.d/40-k114s-lid-sleep.conf)
ok "ordinary boot: suspend allowed, to idle only" "$(printf '%s' "$s" | grep -c -E '^(AllowSuspend=yes|SuspendState=freeze)$')" 2
ok "ordinary boot: hibernate, hybrid and suspend-then-hibernate stay refused in sleep.conf" "$(printf '%s' "$s" | grep -c -E '^Allow(Hibernation|HybridSleep|SuspendThenHibernate)=no$')" 3
ok "ordinary boot: no value in the 40 files allows hibernation" "$(cat $W/a/run/systemd/*/40-k114s-lid-sleep.conf | grep -c -E '^Allow(Hibernation|HybridSleep|SuspendThenHibernate)=yes')" 0
ok "ordinary boot: nothing masks suspend at runtime" "$(ls $W/a/run/systemd/system 2>/dev/null | wc -l | tr -d ' ')" 0
ok "ordinary boot: gate and status agree" "$(ls_ a status | sed -n 1p)" "this boot: ordinary"

# --- a reboot into an ordinary boot, then each kind of trial boot --------------------------------------------------------
reboot a; out=$(ls_ a gate); ok "ordinary boot after a reboot: gate opens" "$(ls $W/a/run/systemd/sleep.conf.d)" 40-k114s-lid-sleep.conf
ok "ordinary boot: hibernate stays masked, suspend is open" "$(sysst a)" "static masked masked masked "

reboot a; trial_file a; out=$(ls_ a gate)
has "Stage 2 trial boot: the gate says so" "$out" "trial boot (Stage 2 trial)"
ok "Stage 2 trial boot: all four targets masked (suspend at runtime)" "$(sysst a)" "masked-runtime masked masked masked "
ok "Stage 2 trial boot: no 40 drop-in" "$(ls $W/a/run/systemd/sleep.conf.d $W/a/run/systemd/logind.conf.d 2>/dev/null | grep -c 40-k114s)" 0
ok "Stage 2 trial boot: check passes" "$(ls_ a check >/dev/null; echo $?)" 0
rm -rf "$W/a/proc"

reboot a; arm_rec a boot1 Omarchy.linux-k114s-r3b; selected a Omarchy.linux-k114s-r3b; out=$(ls_ a gate)
has "one-shot kernel trial boot (selected entry = armed entry): trial" "$out" "trial boot (one-shot kernel trial)"
ok "one-shot kernel trial boot: suspend masked at runtime, others masked" "$(sysst a)" "masked-runtime masked masked masked "
reboot a; selected a Omarchy.linux-k114s; BOOT=boot3 ls_ a gate >/dev/null
ok "the next ordinary boot (trial over, default entry selected): open again" "$(sysst a)" "static masked masked masked "
reboot a; BOOT=boot1 ls_ a gate >/dev/null
ok "the boot that ran arm is an ordinary boot: open" "$(ls $W/a/run/systemd/sleep.conf.d)" 40-k114s-lid-sleep.conf
reboot a; rm -f $W/a/efivars/* $W/a/state/lid-sleep-trial-seen; out=$(ls_ a gate)
has "armed record but the selected entry unreadable: trial (fail closed)" "$out" "trial boot (armed one-shot, boot entry unreadable)"
rm -f $W/a/state/boot-once-armed

# --- check ----------------------------------------------------------------------------------------------------------------
reboot a; ls_ a gate >/dev/null
out=$(ls_ a check); ok "check: ordinary boot with the gate in place passes" "$?" 0; has "check: says the gate holds it" "$out" "suspend.target is static, held by"
trial_file a                                  # a trial boot whose gate did not run: suspend open and the 40 files in place
out=$(ls_ a check); rc=$?; ok "check: a trial boot with suspend open refuses" "$rc" 1; has "check: names the trial" "$out" "BAD   this boot is a trial (Stage 2 trial) and suspend.target is 'static'"
reboot a; ls_ a gate >/dev/null; ok "check: trial boot, gate ran: passes" "$(ls_ a check >/dev/null; echo $?)" 0
rm -rf "$W/a/proc"; reboot a; ls_ a gate >/dev/null
K114S_ROOT=$W/a $W/a/systemctl disable $GATE; out=$(ls_ a check); rc=$?; ok "check: suspend open and the gate not enabled refuses" "$rc" 1; has "check: names the gate" "$out" "k114s-lid-sleep-gate.service is 'disabled'"
K114S_ROOT=$W/a $W/a/systemctl enable $GATE
mv $W/a/etc/systemd/system/hibernate.target $W/a/h; out=$(ls_ a check); rc=$?; ok "check: hibernate.target unmasked refuses" "$rc" 1; has "check: names hibernate" "$out" "hibernate.target is 'static', not masked"; mv $W/a/h $W/a/etc/systemd/system/hibernate.target
mv $W/a/etc/systemd/sleep.conf.d/30-k114s-r3a-trial.conf $W/a/s; out=$(ls_ a check); rc=$?; ok "check: suspend open without the AllowSuspend=no lock refuses" "$rc" 1; has "check: names the lock" "$out" "no fail-closed lock"; mv $W/a/s $W/a/etc/systemd/sleep.conf.d/30-k114s-r3a-trial.conf
mk b; ok "check: today's state (four masks, no gate) passes" "$(ls_ b check >/dev/null; echo $?)" 0

# --- undo -----------------------------------------------------------------------------------------------------------------
out=$(ls_ a undo); rc=$?
ok "undo: exit 0" "$rc" 0
ok "undo: the four targets are masked again" "$(sysst a)" "masked masked masked masked "
ok "undo: the gate is gone" "$(ls $W/a/etc/systemd/system/$GATE $W/a/etc/systemd/system/sysinit.target.wants/$GATE 2>&1 | grep -c 'No such file')" 2
ok "undo: no 40 drop-in is left" "$(ls $W/a/run/systemd/sleep.conf.d $W/a/run/systemd/logind.conf.d 2>/dev/null | grep -c 40-k114s)" 0
ok "undo: the tool and its copies are removed from the library folder" "$(ls $W/a/usr/local/lib/omarchy-k114s)" ""
ok "undo: the two 30 drop-ins stay" "$(ls $W/a/etc/systemd/sleep.conf.d $W/a/etc/systemd/logind.conf.d | grep -c 30-k114s-r3a-trial.conf)" 2
mk c; ls_ c install >/dev/null; ls_ c undo >/dev/null; ls_ c install >/dev/null
ok "install, undo, install again: open" "$(sysst c)" "static masked masked masked "
touch $W/c/logind-up; : > $W/c/hups; ls_ c close >/dev/null; ok "close by hand HUPs a running logind" "$(wc -l < $W/c/hups | tr -d ' ')" 1
ok "close by hand: suspend masked at runtime" "$(sysst c)" "masked-runtime masked masked masked "
ls_ c open >/dev/null; ok "open by hand lifts the runtime mask" "$(sysst c)" "static masked masked masked "
mk e; out=$(ls_ e open); rc=$?
ok "open without the installed 40 drop-ins refuses and leaves nothing" "$rc $(ls $W/e/run/systemd/sleep.conf.d 2>/dev/null | wc -l | tr -d ' ')" "1 0"

# --- k114s-boot-once check -----------------------------------------------------------------------------------------------
# the real boot-once reads the lid-sleep tool from K114S_LIDSLEEP and passes its test hooks on to it
bo() { # bo ROOT [ENV...]: boot-once check against fake root ROOT (which holds the ESP and the state)
  r=$1; shift; env K114S_ESP=$W/$r/esp K114S_ETC=$W/$r/etc-k K114S_EFIVARS=$W/$r/efivars K114S_STATE=$W/$r/state K114S_BOOTID=${BOOT:-boot2} \
    K114S_ROOT=$W/$r K114S_SYSTEMCTL=$W/$r/systemctl K114S_LIDSLEEP=$W/$r/usr/local/lib/omarchy-k114s/k114s-lid-sleep "$@" sh "$D/k114s-boot-once" check 2>&1; }
mk f; out=$(bo f); rc=$?; ok "boot-once check: four masked targets pass (today)" "$rc $(printf '%s' "$out" | grep -c '^BAD')" "0 0"
ls_ f install >/dev/null; out=$(bo f); rc=$?; ok "boot-once check: ordinary boot, suspend open, gate in place: passes" "$rc $(printf '%s' "$out" | grep -c '^BAD')" "0 0"
has "boot-once check: it says why" "$out" "suspend.target static"
reboot f; trial_file f; ls_ f gate >/dev/null; out=$(bo f); rc=$?; ok "boot-once check: trial boot, suspend masked at runtime: passes" "$rc" 0
has "boot-once check: names masked-runtime" "$out" "suspend.target masked-runtime"
rm -rf $W/f/proc; reboot f; ls_ f gate >/dev/null            # an ordinary boot, opened
trial_file f; out=$(bo f); rc=$?                              # the trial file now contradicts the open boot: the gate did not close it
 ok "boot-once check: a trial boot with suspend open refuses" "$rc" 1; has "boot-once check: says the gate does not hold it" "$out" "the lid-sleep gate does not hold it: BAD   this boot is a trial"
rm -rf $W/f/proc
K114S_ROOT=$W/f $W/f/systemctl disable $GATE; out=$(bo f); rc=$?; ok "boot-once check: suspend open, gate disabled: refuses" "$rc" 1; has "boot-once check: names the target" "$out" "BAD   suspend.target is 'static', not masked"
K114S_ROOT=$W/f $W/f/systemctl enable $GATE
rm $W/f/usr/local/lib/omarchy-k114s/k114s-lid-sleep; out=$(bo f); rc=$?; ok "boot-once check: suspend open and no lid-sleep tool: refuses" "$rc" 1; has "boot-once check: says there is no tool" "$out" "there is no .* to close it for a trial"
mk g; mv $W/g/etc/systemd/system/hibernate.target $W/g/h; out=$(bo g); rc=$?; ok "boot-once check: hibernate unmasked refuses" "$rc" 1; has "boot-once check: names hibernate" "$out" "BAD   hibernate.target is 'static', not masked"
mk i; ls_ i install >/dev/null; mv $W/i/etc/systemd/system/hybrid-sleep.target $W/i/h; out=$(bo i); rc=$?; ok "boot-once check: gate installed does not excuse an unmasked hybrid-sleep" "$rc" 1; has "boot-once check: names hybrid-sleep" "$out" "BAD   hybrid-sleep.target is 'static', not masked"
mk j; ls_ j install >/dev/null; arm_rec j boot1 Omarchy.linux-k114s-r3b; selected j Omarchy.linux-k114s-r3b   # one-shot trial boot, gate did not run
out=$(bo j); rc=$?; ok "boot-once check: a one-shot trial boot with suspend open refuses" "$rc" 1; has "boot-once check: names the one-shot trial" "$out" "this boot is a trial (one-shot kernel trial)"
ls_ j gate >/dev/null; ok "boot-once check: the same boot after the gate ran passes" "$(bo j >/dev/null; echo $?)" 0

# --- a /run mask proves nothing about the next boot (the trial the arm sets up) -------------------------------------------
mk n; inst n >/dev/null; reboot n; ls_ n gate >/dev/null; ls_ n close >/dev/null
ok "close by hand: suspend.target is masked-runtime" "$(st1 n suspend.target)" masked-runtime
ok "masked-runtime with the gate, tool, 40 and 30 files in place: check passes" "$(ls_ n check >/dev/null; echo $?)" 0
ok "masked-runtime with the gate in place: boot-once check passes" "$(bo n >/dev/null; echo $?)" 0
K114S_ROOT=$W/n $W/n/systemctl disable $GATE; out=$(ls_ n check); rc=$?
ok "masked-runtime, gate disabled: check refuses" "$rc" 1; has "masked-runtime, gate disabled: names the gate" "$out" "suspend.target is 'masked-runtime' and k114s-lid-sleep-gate.service is 'disabled'"
out=$(bo n); rc=$?; ok "masked-runtime, gate disabled: boot-once check refuses" "$rc" 1; has "masked-runtime, gate disabled: boot-once says the gate does not hold it" "$out" "BAD   suspend.target is 'masked-runtime', not masked in /etc, and the lid-sleep gate does not hold it"
K114S_ROOT=$W/n $W/n/systemctl enable $GATE
L=$W/n/usr/local/lib/omarchy-k114s
mv $L/k114s-lid-sleep $W/n/t; out=$(ls_ n check); rc=$?; ok "masked-runtime, tool missing: check refuses" "$rc" 1; has "masked-runtime, tool missing: names it" "$out" "the tool is not in"
out=$(bo n); ok "masked-runtime, tool missing: boot-once check refuses" "$?" 1; mv $W/n/t $L/k114s-lid-sleep
mv $L/lid-sleep/logind-40-k114s-lid-sleep.conf $W/n/t; out=$(ls_ n check); rc=$?; ok "masked-runtime, a 40 drop-in missing: check refuses" "$rc" 1; has "masked-runtime, a 40 drop-in missing: names it" "$out" "logind-40-k114s-lid-sleep.conf is missing"
out=$(bo n); ok "masked-runtime, a 40 drop-in missing: boot-once check refuses" "$?" 1; mv $W/n/t $L/lid-sleep/logind-40-k114s-lid-sleep.conf
mv $W/n/etc/systemd/logind.conf.d/30-k114s-r3a-trial.conf $W/n/t; out=$(ls_ n check); rc=$?; ok "masked-runtime, the lid lock gone: check refuses" "$rc" 1; has "masked-runtime, the lid lock gone: names the lock" "$out" "no fail-closed lock"
out=$(bo n); ok "masked-runtime, the lid lock gone: boot-once check refuses" "$?" 1; mv $W/n/t $W/n/etc/systemd/logind.conf.d/30-k114s-r3a-trial.conf
mv $W/n/etc/systemd/sleep.conf.d/30-k114s-r3a-trial.conf $W/n/t; ok "masked-runtime, the sleep lock gone: boot-once check refuses" "$(bo n >/dev/null; echo $?)" 1; mv $W/n/t $W/n/etc/systemd/sleep.conf.d/30-k114s-r3a-trial.conf
ok "masked-runtime, everything restored: both checks pass again" "$(ls_ n check >/dev/null; echo $?)$(bo n >/dev/null; echo $?)" 00
# hibernate, hybrid-sleep and suspend-then-hibernate must be masked in /etc: nothing ever masks them in /run
for tg in hibernate hybrid-sleep suspend-then-hibernate; do
  mk o-$tg; rm $W/o-$tg/etc/systemd/system/$tg.target; mkdir -p $W/o-$tg/run/systemd/system; ln -s /dev/null $W/o-$tg/run/systemd/system/$tg.target
  out=$(ls_ o-$tg check); rc=$?; ok "$tg masked only in /run: check refuses" "$rc" 1; has "$tg masked only in /run: names it" "$out" "BAD   $tg.target is 'masked-runtime', not masked in /etc"
  out=$(bo o-$tg); rc=$?; ok "$tg masked only in /run: boot-once check refuses" "$rc" 1; has "$tg masked only in /run: boot-once names it" "$out" "BAD   $tg.target is 'masked-runtime', not masked"
done

# --- a spent arming record: the trial entry becomes the default and must not name every later boot ----------------------
mk p; inst p >/dev/null
reboot p; arm_rec p boot1 Omarchy.linux-k114s; selected p Omarchy.linux-k114s; out=$(BOOT=boot2 ls_ p gate)
has "trial boot: the gate closes it" "$out" "trial boot (one-shot kernel trial)"
ok "trial boot: the gate spends the arming record" "$(cat $W/p/state/lid-sleep-trial-seen)" "boot1 Omarchy.linux-k114s boot2"
ok "trial boot: status still says trial after the record is spent" "$(BOOT=boot2 ls_ p status | sed -n 1p)" "this boot: trial (one-shot kernel trial)"
ok "trial boot: check still passes" "$(BOOT=boot2 ls_ p check >/dev/null; echo $?)" 0
rm -f "$W/p/state/boot-once-armed"
ok "clearing the arming record leaves this boot a trial" "$(BOOT=boot2 ls_ p status | sed -n 1p)" "this boot: trial (one-shot kernel trial)"
ok "open still refuses after clear" "$(BOOT=boot2 ls_ p open >/dev/null; echo $?)" 1
BOOT=boot2 ls_ p open --force >/dev/null
out=$(BOOT=boot2 ls_ p check); rc=$?
ok "both checks still refuse an opened trial after clear" "$rc$(BOOT=boot2 bo p >/dev/null; echo $?)" 11
has "check reports the open drop-in after clear" "$out" "a 40 drop-in is in"
BOOT=boot2 ls_ p gate >/dev/null
ok "running the gate again after clear closes the same trial" "$(sysst p)" "masked-runtime masked masked masked "
arm_rec p boot1 Omarchy.linux-k114s
reboot p; BOOT=boot3 ls_ p gate >/dev/null            # the trial entry is now the default entry: LoaderEntrySelected still names it
ok "later boot selecting the same entry (promoted to default): ordinary, open" "$(ls $W/p/run/systemd/sleep.conf.d) $(sysst p)" "40-k114s-lid-sleep.conf static masked masked masked "
ok "later boot selecting the same entry: status says ordinary" "$(BOOT=boot3 ls_ p status | sed -n 1p)" "this boot: ordinary"
arm_rec p boot4 Omarchy.linux-k114s; reboot p; out=$(BOOT=boot5 ls_ p gate)
has "a new arm of the same entry is a trial again" "$out" "trial boot (one-shot kernel trial)"
ok "the new trial spends the new record" "$(cat $W/p/state/lid-sleep-trial-seen)" "boot4 Omarchy.linux-k114s boot5"
mk q; inst q >/dev/null; reboot q; arm_rec q boot1 Omarchy.linux-k114s; rm -f $W/q/efivars/*; out=$(BOOT=boot2 ls_ q gate)
has "unreadable boot entry: trial" "$out" "boot entry unreadable"; ok "unreadable boot entry still spends the record" "$(cat "$W/q/state/lid-sleep-trial-seen")" "boot1 Omarchy.linux-k114s boot2"
reboot q; BOOT=boot3 ls_ q gate >/dev/null
ok "next boot with the entry still unreadable is ordinary" "$(sysst q)" "static masked masked masked "
mk mismatch; inst mismatch >/dev/null; reboot mismatch
arm_rec mismatch boot1 Omarchy.linux-k114s; selected mismatch Omarchy.linux-k114s-r3b
BOOT=boot2 ls_ mismatch gate >/dev/null
ok "a different selected entry opens on the first boot after arming" "$(sysst mismatch)" "static masked masked masked "
reboot mismatch; selected mismatch Omarchy.linux-k114s; BOOT=boot3 ls_ mismatch gate >/dev/null
ok "a different entry on the first boot spends the record for later boots" "$(sysst mismatch)" "static masked masked masked "
# a stale record that the gate never saw (it did not run on the trial boot): the first boot that selects the entry is closed once
mk t; inst t >/dev/null; reboot t; arm_rec t boot1 Omarchy.linux-k114s; selected t Omarchy.linux-k114s; BOOT=boot3 ls_ t gate >/dev/null
ok "a trial the gate missed: the next boot that selects the entry is closed once" "$(sysst t)" "masked-runtime masked masked masked "
reboot t; BOOT=boot4 ls_ t gate >/dev/null
ok "a trial the gate missed: the boot after that is ordinary" "$(sysst t)" "static masked masked masked "
# the boot-once check and its self-test arming of the default entry itself still work with the seen file around
ok "boot-once check on a spent record: passes" "$(BOOT=boot3 bo p >/dev/null; echo $?)" 0

# --- open by hand refuses on a trial boot; close fails loudly -------------------------------------------------------------
mk r; inst r >/dev/null; reboot r; trial_file r
out=$(ls_ r open); rc=$?; ok "open on a Stage 2 trial boot refuses and writes nothing" "$rc $(ls $W/r/run/systemd/sleep.conf.d 2>/dev/null | wc -l | tr -d ' ')" "1 0"
has "open on a trial boot: says why" "$out" "this boot is a trial (Stage 2 trial): not opening it"
out=$(ls_ r open --force); rc=$?; ok "open --force on a trial boot opens" "$rc $(ls $W/r/run/systemd/sleep.conf.d | wc -l | tr -d ' ')" "0 1"
rm -rf $W/r/proc; reboot r; arm_rec r boot1 Omarchy.linux-k114s; selected r Omarchy.linux-k114s
out=$(BOOT=boot2 ls_ r open); rc=$?; ok "open on a one-shot kernel trial boot refuses" "$rc $(ls $W/r/run/systemd/sleep.conf.d 2>/dev/null | wc -l | tr -d ' ')" "1 0"
reboot r; rm -f $W/r/state/boot-once-armed; ok "open on an ordinary boot opens" "$(ls_ r open >/dev/null; echo $?) $(ls $W/r/run/systemd/sleep.conf.d | wc -l | tr -d ' ')" "0 1"
mk s; inst s >/dev/null; touch $W/s/reload-fails; out=$(ls_ s close); rc=$?
ok "close: a daemon-reload that fails is an error" "$rc" 1; has "close: says the mask did not take" "$out" "did not mask at runtime"
ok "close: the 40 drop-ins are gone even then" "$(ls $W/s/run/systemd/sleep.conf.d $W/s/run/systemd/logind.conf.d 2>/dev/null | grep -c 40-k114s)" 0

echo "test-lid-sleep: $pass passed, $fail failed"; [ "$fail" = 0 ]
