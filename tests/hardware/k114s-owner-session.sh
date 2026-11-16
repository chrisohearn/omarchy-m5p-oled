#!/bin/bash
# GUIDED OWNER SESSION for the K114s (about 30-45 min). Walks the owner through the manual hardware steps
# section by section, runs the read-only checks in tests/hardware/ that exist on this checkout, and prints a
# per-issue result summary to paste into the issues. See docs/owner-session.md.
#
#   bash tests/hardware/k114s-owner-session.sh [--section A|B|C|D|E] [--dry-run] [--self-test]
#     (no flags)    interactive: for each step Enter = do it, s = skip, q = quit; then p/f/o/s for the result
#     --section X   only that section (A no hardware, B keys and watching, C plugging, D reboot list, E not yet)
#     --dry-run     prints every step and every command, runs nothing, asks nothing
#     --self-test   runs the redactor checks and a dry run in a scratch state directory
#
# It NEVER suspends, plays audio, pairs, reboots or touches NVRAM or macOS. Pairing, audio playback on a headset,
# installs and Git are done by you, by hand, when a step says so. Reboot items (section D) are only listed: they
# are folded into the display trial boots. Steps that end the desktop session are listed after the summary is
# written. The log is private (directory 0700, file 0600) and redacted: MAC and
# IP addresses, e-mails, serials, labelled network names, UUIDs, hashes, home paths, host and user names.
set -u
cd "$(dirname "$0")/../.." || exit 2
umask 077

dry=0 only="" selftest=0
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) dry=1 ;;
    --self-test) selftest=1 ;;
    --section) shift; only=${1:-}; case $only in A|B|C|D|E) ;; *) echo "--section needs A, B, C, D or E" >&2; exit 2 ;; esac ;;
    -h|--help) sed -n 2,14p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

# --- redaction: everything written to the log or the summary goes through this -----------------------------------
redact() {
  local h u; h=$(hostname 2>/dev/null); u=$(id -un 2>/dev/null)
  local -a lit=()
  # host and user names match only as whole words outside paths, so /usr/lib/omarchy-mac/ survives
  # the rule runs twice so back-to-back names (the owner and group columns of ls -l) both match
  for v in "$h" "$u"; do [ "${#v}" -ge 3 ] && { v=$(printf %s "$v" | sed 's/[][\.*^$/|]/\\&/g')
    lit+=(-e "s/(^|[^[:alnum:]_.\/-])$v([^[:alnum:]_\/-]|$)/\1REDACTED\2/gI" -e "s/(^|[^[:alnum:]_.\/-])$v([^[:alnum:]_\/-]|$)/\1REDACTED\2/gI"
      -e "s#(/var/(lib|spool|mail|cache)|/srv)/$v([^[:alnum:]_.-]|$)#\1/USER\3#gI"); }; done
  sed -E \
    -e 's/([0-9A-Fa-f]{2}[:_-]){5}[0-9A-Fa-f]{2}/XX:XX:XX:XX:XX:XX/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/EMAIL/g' \
    -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/x.x.x.x/g' \
    -e 's/\b([0-9a-f]{1,4}:){7}[0-9a-f]{1,4}\b/IPV6/gI' \
    -e 's/(^|[^[:alnum:]_:])([0-9a-f]{1,4}(:[0-9a-f]{1,4})*)?::([0-9a-f]{1,4}(:[0-9a-f]{1,4})*)?/\1IPV6/gI' \
    -e 's/\b[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b/UUID/g' \
    -e 's/\b[0-9a-fA-F]{32,}\b/HASH/g' \
    -e 's#(/home|/Users)/[^/ ]+#\1/USER#g' \
    -e 's/(serial|ssid)[^:=]*[:=] *.*/\1 REDACTED/I' \
    -e 's/[A-Za-z0-9_.-]*([Cc]alib|[Tt]uning)[A-Za-z0-9_.-]*\.(bin|dat|plist)/CALFILE/g' \
    "${lit[@]}"
}

# --- state: private log directory ---------------------------------------------------------------------------------
state=${K114S_OWNER_STATE:-$HOME/.local/state/k114s-owner-session}
[ "$dry" = 1 ] && [ -z "${K114S_OWNER_STATE:-}" ] && state=$(mktemp -d "${TMPDIR:-/tmp}/k114s-owner-dry.XXXXXX")

selftest_run() {
  local out rc=0 bad=0 s mac ip mail hp
  hostname() { echo testhost; }; id() { echo testuser; }   # stubs: the redactor calls both
  t=$(mktemp -d) || exit 2   # global: the EXIT trap runs after this function returns
  trap 'rm -rf "$t"' EXIT
  ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; bad=1; }
  # 1. redactor, with sensitive-looking values built from pieces so this file stays publishable
  mac=$(printf '%s:%s:%s:%s:%s:%s' aa 0b 1c 2d 3e 4f); ip=$(printf '%s.%s.%s.%s' 192 168 1 77)
  mail=$(printf '%s@%s.%s' someone example com); hp=$(printf '/%s/%s/x' home alice)
  s=$(printf 'dev %s ip %s mail %s path %s\nSerial Number: C02ABC\nSSID: MyNet\nid 3f2504e0-4f89-11d3-9a0c-0305e82c3301\nID_SERIAL_SHORT=SN77Z\nSerial Number (system): SYS55\ninet6 fe80::a8bb:ccff:fedd:eeff\n' "$mac" "$ip" "$mail" "$hp" | redact)
  for leak in "$mac" "$ip" "$mail" alice C02ABC MyNet 3f2504e0 SN77Z SYS55 a8bb; do
    case $s in *"$leak"*) no "redactor leaked: ${leak:0:4}..." ;; esac
  done
  s=$(printf '/usr/lib/omarchy-mac/x at 10:15:30\n' | redact)
  [ "$s" = '/usr/lib/omarchy-mac/x at 10:15:30' ] || no "redactor changed a path or a time"
  s=$(printf '/usr/lib/testhost/x\n' | redact); [ "$s" = /usr/lib/testhost/x ] || no "redactor changed a host-named path"
  s=$(printf 'testhost testhost end\n1 testuser testuser 12 x\nTESTHOST up\n/var/lib/testuser/x\n' | redact)
  case $s in *testhost*|*testuser*|*TESTHOST*) no "redactor left a repeated or upper-case name: $s" ;; esac
  [ "$bad" = 0 ] && ok "redactor removes address, IPv6, mail, path, serial, network name, UUID"
  # 2. no forbidden command in any step line (suspend, reboot, NVRAM, audio playback, pairing, macOS)
  if grep -nE "^((KEY|NEED)=[a-z]+ )*(step|load|later) .*(systemctl (suspend|reboot|hibernate)|rtcwake|pm-test|nvram|aurora-bless|pw-play|aplay|paplay|speaker-test|bluetoothctl .*pair|shutdown|poweroff)" "$0" >"$t/forbidden"; then
    no "forbidden command in a step line"; cat "$t/forbidden"
  else ok "no suspend, reboot, NVRAM, playback or pairing command in any step"; fi
  # 2b. every capture that prompts for keys must be gated on the key policy, and the one after it must not name the moon key
  if grep -nE 'input-capture\.sh keys' "$0" | grep -vE '^[0-9]+:(NEED=moon step|  # |.*grep -)' | grep -vE '^[0-9]+:#|\$0'; then no "a keys capture is not gated on NEED=moon"; else ok "every keys capture is gated on the key policy"; fi
  # 2c. the gate's SKIP path, interactive, with a policy that would suspend; every other step is skipped by answer
  out=$(printf '\n\n\n%.0s' 1 >"$t/in"; printf 's\ns\n\n\n\n' >>"$t/in"; yes s | head -60 >>"$t/in"
    K114S_OWNER_STATE=$t/state2 K114S_LOGIND_VALUE=suspend K114S_SUSPEND_VALUE=hibernate bash "$0" --section B <"$t/in" 2>&1)
  [ "$(echo "$out" | grep -c 'SKIPPED: the')" = 3 ] && ok "failed key policy skips the power press and both key captures" || { no "gate SKIP path"; echo "$out" | grep -E 'SKIPPED|^---' | head -20; }
  # 3. dry run in a scratch state dir: exit 0, runs nothing, covers every issue of the checklist, log is private
  out=$(K114S_OWNER_STATE=$t/state bash "$0" --dry-run </dev/null 2>&1); rc=$?
  [ "$rc" = 0 ] && ok "dry run exits 0" || { no "dry run exit $rc"; echo "$out" | tail -5; }
  echo "$out" | grep -q 'AFTER THE SUMMARY' && ok "session-ending steps are listed after the summary" || no "no end-of-session list"
  for i in 7 18 23 24 26 27 28 29 30 31 32 33 34 37 38 39 40 41 43 44 46 47 48 49 51 52 53 54 55 56 57 58 59 60 61 62 67 68 69 70 71 72 75 89; do
    echo "$out" | grep -q "^#$i " || { no "summary lacks #$i"; bad=1; }
  done
  [ "$bad" = 0 ] && ok "summary has every issue"
  echo "$out" | grep -q 'FOLDED INTO TRIAL BOOTS' && ok "reboot items are listed as folded" || no "no folded reboot items"
  [ "$(stat -c %a "$t/state")" = 700 ] && [ "$(stat -c %a "$t"/state/session-*.log)" = 600 ] && ok "log directory 0700, log 0600" || no "log permissions"
  echo "$out" | grep -q 'dry-run: would run' && ok "dry run lists commands" || no "dry run lists no commands"
  [ "$bad" = 0 ] && echo "RESULT: OK" || echo "RESULT: FAIL"
  return $bad
}
[ "$selftest" = 1 ] && { selftest_run; exit $?; }

mkdir -p "$state" && chmod 700 "$state" || { echo "cannot create $state" >&2; exit 2; }
stamp=$(date +%Y%m%d-%H%M%S)
LOG=$state/session-$stamp.log
: >"$LOG"; chmod 600 "$LOG"
raw=$(mktemp "$state/.raw.XXXXXX"); trap 'rm -f "$raw"' EXIT
log() { printf '%s\n' "$*" | redact >>"$LOG"; }

# --- results -------------------------------------------------------------------------------------------------------
declare -A P F O S L D LINES   # per issue: pass, fail, observed, skipped or missing, listed, dry-run counts; text lines
bump() { # ARRAYNAME ISSUE
  local -n a=$1; a[$2]=$(( ${a[$2]:-0} + 1 )); }
record() { # ISSUES RESULT TITLE NOTE
  local i
  for i in $1; do
    case $2 in PASS) bump P "$i" ;; FAIL) bump F "$i" ;; OBSERVED) bump O "$i" ;; LISTED) bump L "$i" ;;
      DRY) bump D "$i" ;; *) bump S "$i" ;; esac
    LINES[$i]+="  - $2: $3${4:+ ($4)}"$'\n'
  done
  write_summary
}
seen="" endlist=() gok="" finished=0
write_summary() { [ -n "${stamp:-}" ] && summary | redact >"$state/summary-$stamp.md"; }
note_issues() { local i; [ -z "$only" ] || [ "$only" = "$cur" ] || return 0; for i in $1; do case " $seen " in *" $i "*) ;; *) seen+=" $i" ;; esac; done; }

cur="" quit=0
section() { cur=$1; [ -n "$only" ] && [ "$only" != "$1" ] && return; echo; echo "=== Section $1: $2"; log "=== Section $1: $2"; }
active() { [ "$quit" = 0 ] && { [ -z "$only" ] || [ "$only" = "$cur" ]; }; }

ask() { # PROMPT ALLOWED -> sets $ans; end of input counts as q
  local a
  while :; do
    read -r -p "$1" a || { ans=q; return; }
    a=${a,,}; case $a in "") a=enter ;; esac
    case " $2 " in *" $a "*) ans=$a; return ;; esac
    echo "    choose one of: $2"
  done
}

load() { # N SECONDS CMD... : N bounded CPU loads (yes) while CMD runs; the loads die with it
  local n=$1 s=$2 i rc pids=(); shift 2
  for ((i = 0; i < n; i++)); do timeout "$s" yes >/dev/null & pids+=($!); done
  "$@"; rc=$?
  kill "${pids[@]}" 2>/dev/null; wait 2>/dev/null
  return $rc
}

# step ISSUES TITLE WHAT-YOU-DO [-- COMMAND...]   (no command: a manual step you do and report on)
step() {
  local issues=$1 title=$2 what=$3 cmd=() miss="" a rc sug="" res note="" key=${KEY:-} need=${NEED:-}
  shift 3; [ "${1:-}" = -- ] && { shift; cmd=("$@"); }
  note_issues "$issues"
  active || return 0
  echo; echo "--- #${issues// /, #}  $title"
  [ -n "$what" ] && echo "    $what"
  [ ${#cmd[@]} -gt 0 ] && echo "    command: ${cmd[*]}"
  log "--- #$issues $title"
  for a in "${cmd[@]}"; do case $a in tests/*.sh|tests/*.py|linux/*) [ -e "$a" ] || miss=$a ;; esac; done
  if [ -n "$miss" ]; then
    echo "    MISSING on this checkout: $miss (use that issue's PR branch, or run after its PR merges)"
    record "$issues" MISSING "$title" "script not on this checkout"; log "MISSING $miss"; return 0
  fi
  if [ -n "$need" ]; then case " $gok " in *" $need "*) ;; *)
    echo "    SKIPPED: the '$need' check above did not pass, so this step is not offered"
    record "$issues" SKIP "$title" "'$need' check did not pass"; log "SKIP gated on $need"; return 0 ;; esac; fi
  if [ "$dry" = 1 ]; then
    [ -n "$key" ] && gok+=" $key"
    [ ${#cmd[@]} -gt 0 ] && echo "    dry-run: would run: ${cmd[*]}" || echo "    dry-run: manual step"
    record "$issues" DRY "$title"; return 0
  fi
  ask "    [Enter] do it, [s]kip, [q]uit: " "enter s q"
  case $ans in q) quit=1; return 0 ;; s) record "$issues" SKIP "$title"; log "SKIP"; return 0 ;; esac
  if [ ${#cmd[@]} -gt 0 ]; then
    "${cmd[@]}" 2>&1 | tee "$raw"; rc=${PIPESTATUS[0]}
    { echo "\$ ${cmd[*]}"; cat "$raw"; echo "exit $rc"; } | redact >>"$LOG"
    [ "$rc" = 0 ] && sug=p || sug=f
    [ "$rc" = 0 ] && [ -n "$key" ] && gok+=" $key"
    echo "    exit status $rc"
  fi
  ask "    result: [p]ass [f]ail [o]bserved (note for the issue) [s]kip${sug:+ (Enter = $sug)}: " "${sug:+enter} p f o s"
  [ "$ans" = enter ] && ans=$sug
  case $ans in p) res=PASS ;; f) res=FAIL ;; o) res=OBSERVED ;; *) res=SKIP ;; esac
  read -r -p "    one-line note (optional, redacted): " note </dev/stdin || note=""
  note=$(printf '%s' "$note" | redact)
  record "$issues" "$res" "$title" "$note"; log "RESULT $res ${note:+- $note}"
}

# listed ISSUES TEXT : a reboot item, only listed
listed() {
  note_issues "$1"; active || return 0
  echo "  * #${1// /, #}  $2"
  record "$1" LISTED "$2"; log "LISTED #$1 $2"
}

# --- per-issue summary ---------------------------------------------------------------------------------------------
summary() {
  local i st
  echo "## K114s owner session $stamp$([ "$dry" = 1 ] && echo ' (DRY RUN)')"
  echo
  for i in $(printf '%s\n' $seen | sort -n); do
    if [ "${F[$i]:-0}" -gt 0 ]; then st=FAIL
    elif [ "${S[$i]:-0}" -gt 0 ] && [ $(( ${P[$i]:-0} + ${O[$i]:-0} )) -gt 0 ]; then st=PARTIAL
    elif [ "${S[$i]:-0}" -gt 0 ]; then st="NOT RUN"
    elif [ "${O[$i]:-0}" -gt 0 ]; then st="OBSERVED, owner notes below"
    elif [ "${P[$i]:-0}" -gt 0 ]; then st=PASS
    elif [ "${L[$i]:-0}" -gt 0 ]; then st="FOLDED INTO TRIAL BOOTS"
    elif [ "$dry" = 1 ]; then st="DRY RUN"; else st="NOT RUN"; fi
    echo "#$i $st"
    printf '%s' "${LINES[$i]:-}"
  done
  echo
  echo "Left out on purpose (suspend, speakers, NVRAM or macOS): #50, #51 lid close, #34 suspend, #58 resume, #42, #64, #66, #48 firmware, #33 firmware match, #49 phase 6."
}
# later ISSUES TITLE TEXT : a step that ends the desktop session. Listed now, to be done after the summary is written.
later() {
  note_issues "$1"; active || return 0
  echo; echo "--- #${1// /, #}  $2"; echo "    LATER: this ends your session, so it is listed after the summary."
  record "$1" LATER "$2" "do it after the summary"; log "LATER #$1 $2"
  endlist+=("#${1// /, #}  $2"$'\n'"    $3")
}

finish() { # the summary, then the end-of-session list; also runs from the INT/HUP trap
  [ "$finished" = 1 ] && return; finished=1
  echo; echo "=================== RESULT SUMMARY ==================="
  summary | redact | tee -a "$LOG" | tee "$state/summary-$stamp.md"
  echo; echo "Log: $LOG"
  if [ ${#endlist[@]} -gt 0 ]; then
    echo; echo "=========== AFTER THE SUMMARY: steps that end this session ==========="
    echo "The summary is saved. Do these last, in a terminal you can lose; save your work first."
    printf '%s\n' "${endlist[@]}"
  fi
}
trap 'echo; echo "interrupted: writing the summary"; finish; exit 130' INT HUP TERM

# --- the session ---------------------------------------------------------------------------------------------------
hw=tests/hardware
echo "K114s owner session. Log: $LOG"
[ "$dry" = 1 ] && echo "DRY RUN: nothing is executed and nothing is asked."

section A "no hardware handling (about 5 min)"
step 89 "P6d before and after blocks" "P6d is merged. At the next attended 'omarchy update' run the P6d before and after blocks as merged. Report whether both behaved."
step 69 "Install the factory-reset gate" "In another terminal run: sudo bash linux/omarchy-patches-install   (an install: you do it, not this script)"
step 69 "Check the gate" "" -- bash -c "grep -q 'K114s local change: a factory reset' /usr/bin/omarchy-system-factory-reset && echo gated"
step 69 "Hide the reset menu row" "Add \"setup.reset\": {\"when\": \"false\"} to ~/.config/omarchy/extensions/omarchy-menu.jsonc. Do NOT run a reset until docs/platform-audit.md 'Qualifying it later' is met."
step 49 "Touch ID read-only check (optional)" "" -- bash $hw/k114s-touchid-check.sh
step 58 "Wi-Fi status" "" -- bash $hw/k114s-wifi-check.sh status
step 32 "Screen-capture check" "The script records your whole screen for 4 s and deletes the files." -- bash $hw/k114s-capture-check.sh --script
step 28 "Chromium GPU report, hardware" "Optional, headless. Expect PASS lines and exit 0." -- bash $hw/chromium-gpu-report.sh
step 28 "Chromium GPU report, software" "Optional, headless. Expect PASS lines and exit 0." -- bash $hw/chromium-gpu-report.sh --software
step 29 "Steam/FEX/muvm read-only probe" "Installs nothing." -- bash $hw/k114s-steam-fex-probe.sh

section B "pressing keys or watching (about 15 min)"
KEY=power step 70 "Power-key policy" "Expect POWER-KEY POLICY: ok. The next step is offered only if this passes." -- bash $hw/k114s-input-capture.sh status
NEED=power step 70 "Power button, one short press" "Press the power button ONCE, briefly, within 30 s. Do NOT hold it: a long press asks the SMC to restart. Say what appeared: the Omarchy power menu, a lock, or nothing. If the power menu opens, #70 can close." -- bash $hw/k114s-input-capture.sh power 30
step 46 "Input status" "" -- bash $hw/k114s-input-capture.sh status
step 46 "Gestures and palm rejection" "For 60 s: rest a palm on the pad while typing a sentence, then 2-, 3- and 4-finger swipes, a pinch and one click. Judge palm rejection by feel. For workspace swipes, uncomment the hl.gesture workspace line in the user input.lua first." -- bash $hw/k114s-input-capture.sh gestures 60
KEY=moon step "43 44" "Key policy (suspend and power keys)" "logind HandleSuspendKey, HandleSuspendKeyLongPress and HandlePowerKey must all be ignore. Both key-capture steps below are offered only if they are." -- bash $hw/k114s-input-capture.sh keypolicy
NEED=moon step 43 "Top-row keys" "Press mute, volume down, previous, next and the moon key." -- bash $hw/k114s-input-capture.sh keys 60
NEED=moon step 44 "Keyboard backlight keys" "Do NOT press the moon key. Press Ctrl+Brightness Up and Ctrl+Brightness Down and watch whether the light steps (the capture records the key presses). Then lock the screen, unlock, and confirm it blanks and restores." -- env K114S_NO_MOON=1 bash $hw/k114s-input-capture.sh keys 30
step 31 "Widevine probe" "Opens a Chromium window for a few seconds. If it fails: chromium --enable-logging=stderr --v=1 2>&1 | grep -i -E 'cdm|widevine'. If it passes: open a DRM page (headphones or a headset as the output, or the sink muted; never the speakers) and say whether video plays or is blank." -- bash $hw/k114s-widevine-probe.sh --headed
step 28 "WebGL window" "Run chromium chrome://gpu, then open https://get.webgl.org/. Confirm the window draws (not blank) and no 'GPU process crashed' infobar appears."
step 26 "Vulkan check with vkcube" "Needs vulkan-tools (install it yourself first). Watch the panel for a spinning cube; decide whether vulkan-tools joins the image package list." -- bash $hw/k114s-vulkan-check.sh --vkcube
step 55 "Thermal log under load (5 min)" "This step starts six bounded CPU loads itself." -- load 6 300 bash $hw/k114s-thermal-log.sh 5 60
step 34 "GPU soak (10 min)" "Load the GPU yourself meanwhile (a WebGL demo or workspace animations). A GPU hang may need a forced power-off." -- sudo bash $hw/k114s-gpu-qualify.sh 5 120
step 34 "GPU fault lines in the kernel log" "No lines is the pass." -- bash -c "sudo journalctl -k -b --no-pager | grep -i -E 'aurora.*(fault|timeout|hang|error)' || echo 'no aurora fault lines'"
later 7 "CPU-rendered session, titlebars" "Run rm ~/.config/k114s-gpu-desktop, log out and in. Run bash $hw/k114s-titlebars-nested-check.sh <path to the 0.4.0+m5-1 aarch64 package>; expect the 'background, top and overlay layer surfaces mapped' line, 10 PASS on the rebuild, nested SIGSEGV on stock, RESULT: OK. Then touch ~/.config/k114s-gpu-desktop and log out and in. Arm the plugin with install.sh only after."
later 26 "Zink retry (session restart, no reboot)" "Follow docs/vulkan-clients.md 'Owner step 2' exactly (per-kernel opt-in, timed revert, restart from outside the session, rollback from Ctrl+Option+Fn+F2). Do not run it while a display-plan D1 window is open. Then: bash $hw/k114s-vulkan-check.sh --after-zink --vkcube"

section C "plugging devices (about 20 min, overlaps A and B)"
step 71 "Which connector is the charger on" "State it: MagSafe or a USB-C port."
step 71 "Plug probe" "Unplug and replug MagSafe when it prompts. Note the LED colour: amber charging, green full." -- bash $hw/k114s-plug-probe.sh
step 57 "USB-C charge probe (3 min)" "Move the charger between left-front, right and MagSafe, one at a time (different wattages if you have them). Note the MagSafe LED. Plug a USB-C device into each port and see whether tps6598x-source-psy-* goes online=1." -- bash $hw/k114s-plug-probe.sh 180 usbc-charge
step 53 "Charge-limit status" "Read-only." -- bash $hw/k114s-charge-limit-test.sh status
step 53 "Charge-limit run" "Needs AC and battery above 80%. WRITES the SMC charge limit (80, then 100) and /etc/udev/macsmc-battery.conf, and puts back what it found. Expect PASS for end 80 / start 75 readback, then 100 restored." -- sudo bash $hw/k114s-charge-limit-test.sh run
step 53 "Charge limit by hand" "Run 'omarchy battery charge limit 80', watch the status leave Charging above 80%, then restore with 'omarchy battery charge limit 100'."
step "52 56" "Battery log (12 min)" "Leave the Mac idle. Unplug AC for 10 minutes or more, then replug. The profile column should go balanced on unplug and performance on replug. #52: no MISMATCH line. #56: note idle draw in W and the estimated hours." -- bash $hw/k114s-battery-log.sh 30 24
step 54 "Balanced profile on battery" "On battery run: powerprofilesctl set balanced"
step 54 "CPU frequency, idle" "" -- bash $hw/k114s-cpufreq-log.sh 2 15
step 54 "CPU frequency, under load" "This step starts four bounded CPU loads itself." -- load 4 40 bash $hw/k114s-cpufreq-log.sh 2 15
step 54 "Restore profile" "On AC run: powerprofilesctl set performance"
step "59 41" "Pair a headset yourself" "Put a headset in pairing mode. In bluetoothctl: power on, agent on, scan on, pair, trust, connect. This script never pairs."
step 41 "Bluetooth audio check, read-only" "Expect 0 BAD." -- bash $hw/k114s-bt-audio-check.sh --no-save
step 59 "Bluetooth check" "" -- bash $hw/k114s-bluetooth-check.sh
step "41 59" "A2DP for 60 s" "Make sure the HEADSET is the output, never the speakers. Play music yourself for 60 s with a download running; note dropouts." -- bash $hw/k114s-bt-audio-check.sh --listen --no-save
step 59 "Keyboard or mouse" "Check a Bluetooth keyboard or mouse works and reconnects after a power-cycle of the device."
step "41 59" "Hands-free profile" "pactl set-card-profile <card> headset-head-unit, then record or call on the headset. Note whether the HFP mic works. Expect failure (no SCO); record it as owner-observed."
step 40 "Platform data check" "Checks the headset source exists with priority.session 1. Needs a boot with a sound card." -- bash $hw/k114s-platform-data-check.sh
step 75 "Audio node names" "Same report: confirm alsa_output.platform-sound.HiFi__Headphones__sink, alsa_input.platform-sound.HiFi__Headset__source and effect_output.k114-mic. Needs speakerguardd #188 or a headphone-only trial." -- bash $hw/k114s-platform-data-check.sh
step 40 "Headset with a mic" "Record 5 s with pw-record --target <headset source>, unplug, replug. With it unplugged the default input must be the built-in array. Press the headset buttons and note what happens."
step 75 "Pop on headphones" "Headphones only: listen for a pop when playback starts and stops. Check the device names in the Omarchy audio panel."
step 37 "Headphone jack" "At low volume (wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.2) plug headphones in and out. Confirm Headphone Jack toggles (amixer -c AppleK114 controls, with headphones in and out, or the r3a --listen step below), the speakers stay silent and card AppleK114 appears."
step 39 "r3a audio, listen" "Check the shell mic list shows one 'MacBook Microphone' and no raw audio_effect.k114-mic. Record in an app and confirm both channels carry audio. No --play: nothing is played." -- bash $hw/k114s-r3a-audio-check.sh --listen --no-save
step 38 "Mic trial" "At the prompts: silent, count aloud 30 cm from the screen, clap near the left edge, clap near the right edge, count aloud again (mono). Play the mono take through HEADPHONES only, never the speakers. Say whether it is intelligible and the level and noise are acceptable." -- bash $hw/k114s-mic-trial.sh
step 60 "USB plug test" "Plug a flash drive, keyboard or USB Ethernet adapter (NOT a charger) into the LEFT-FRONT port when prompted, then flip and unplug as prompted. Repeat on the right port. Skip the left-back (debug) port. Say at which step the Mac hangs, if it does." -- bash $hw/k114s-usb-plug-test.sh

section D "needs a reboot: listed only, folded into the display trial boots"
active && echo "  Fold every item into the same candidate Stage 2 and one-boot trial as the display work, arm a one-boot way back first, and reboot once or twice in total. This script does not reboot."
listed 68 "boot-loader menu check, then snapshot-check after-menu"
listed 53 "charge-limit status after a reboot (100 until the #1615 uevent fix is booted)"
listed 72 "ATC0 left-back port trial (trial Stage 2 with K114S_R3_USB_ATC0), then k114s-atc0-plug-test.sh 90"
listed "37 38 39 40 75" "sound stage: Stage 2 with the /sound node, then the Section C audio checks (headphones only)"
listed 67 "AOP sensors tree (K114S_R3_AOP_SENSORS), then k114s-parity-check.sh sensors"
listed 62 "SD tree (K114S_R3_SD, alone), then k114s-parity-check.sh sd"
listed 30 "AVD tree (K114S_R3_AVD), then k114s-parity-check.sh avd and k114s-avd-decode-test.sh"
listed 51 "eDP tree with scale 2, then k114s-sleep-check.sh status"
listed 61 "USB4 tree (t6050-k114s-r3-usb4), then k114s-usb4-check.sh"
listed 33 "camera hand-off trial (K114S_R3_ISP), then k114s-camera-check.sh --capture"
listed 55 "fan write test (K114S_R3B_FAN_MANUAL), owner-attended"
listed 54 "PMP tunables trial (K114S_R3B_FAST_DIE, can hang)"
listed 18 "notch check after the DCP hand-off (platform-data-check)"
listed 32 "capture-check --script again after the DRM topology changes"
listed 23 "USB-C monitor on left-front with plug-probe.sh 120 monitor-left-front"
listed 24 "HDMI check with K114S_R3B_HDMI after the DCP hand-off"
listed 68 "snapshot boot trial once ESP space and a snapshot entry exist"
listed 47 "click-strength tuning on the kernel with linux #1959"
listed 48 "touchscreen trial once the upstream driver is verified"
listed 49 "SEP profile trial once upstream adds apple,k114s"

section E "not runnable yet (no build or dependency)"
listed 27 "after rusticl exists in a mesa-aurora build: clinfo, then media-smoke.sh"
listed 29 "after Vulkan proof and a go: muvm, FEX-Emu and omarchy-steam-fex, then a Steam launch"

finish
exit 0
