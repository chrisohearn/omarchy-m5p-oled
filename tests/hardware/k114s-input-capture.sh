#!/bin/bash
# K114s input capture for the OWNER to run ON the Mac, inside the Hyprland session. Read-only:
# it opens evdev nodes for reading (no grab, no ioctl that writes), never writes to /sys, LEDs,
# the haptic actuator or logind. Covers issues #43 (top row), #44 (keyboard backlight keys),
# #70 (power button), #46 (gestures, palm). See docs/matrix.md.
#
#   k114s-input-capture.sh status               no root: LEDs, pwm period, input devices, binds,
#                                               power-key policy. Exit 1 if the policy is wrong.
#   k114s-input-capture.sh keypolicy            no root: exit 1 unless logind ignores HandleSuspendKey,
#                                               HandleSuspendKeyLongPress, HandlePowerKey and
#                                               HandlePowerKeyLongPress, and Hyprland binds no XF86Sleep or
#                                               suspend/hibernate action (hyprctl must answer). The moon key
#                                               must never suspend the Mac.
#   k114s-input-capture.sh keys [SECONDS]       sudo for /dev/input. Press every top-row key, Fn,
#                                               Ctrl+brightness, the moon key. Default 60 s. Runs keypolicy
#                                               first and leaves the moon key out if it fails.
#   k114s-input-capture.sh power [SECONDS]      sudo. One SHORT press of the power button. Never
#                                               hold it: a long press asks the SMC to restart.
#   k114s-input-capture.sh gestures [SECONDS]   sudo. Rest a palm while typing, then 2/3/4-finger
#                                               swipes, a pinch, a click. Default 60 s.
#
# The output holds no serial numbers, addresses or network names. Needs python3 (stdlib only).
# Test hooks (tests/hardware/test-input-capture.sh only): K114S_PROC_INPUT, K114S_DEV_DIR,
# K114S_BINDS_JSON, K114S_LOGIND_VALUE, K114S_LOGIND_DIRS, K114S_LEDS, K114S_PWM_DT, K114S_NO_SUDO,
# K114S_SUSPEND_VALUE, K114S_SUSPEND_LP_VALUE, K114S_POWER_LP_VALUE, K114S_HYPR_LUA_DIRS.
# The Lua scan reads the Hyprland and Omarchy config dirs; it cannot see a bind that runs an external script.
# K114S_NO_MOON=1 makes the keys prompt leave out the moon key (the owner session sets it when it did not
# verify that logind ignores the suspend key).
set -u
proc=${K114S_PROC_INPUT:-/proc/bus/input/devices}
leds=${K114S_LEDS:-/sys/class/leds}
dt=${K114S_PWM_DT:-/proc/device-tree/led-controller}
logind_dirs=${K114S_LOGIND_DIRS:-/etc/systemd/logind.conf.d /usr/lib/systemd/logind.conf.d /run/systemd/logind.conf.d}

# Decodes a /proc/bus/input/devices bit line (hex words, highest first) into bit numbers.
py() { python3 -I -c "$1" "${@:2}"; }

power_policy() { # prints the verdict, returns 1 on a problem
  local val files= bad=0 f d
  val=${K114S_LOGIND_VALUE:-$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager HandlePowerKey 2>/dev/null | sed -n 's/^s "\(.*\)"$/\1/p')}
  echo "logind HandlePowerKey (effective): ${val:-unknown}"
  local all aur
  # shellcheck disable=SC2086
  all=$(for d in $logind_dirs; do ls "$d"/*.conf 2>/dev/null; done)
  [ -n "$all" ] && files=$(echo "$all" | xargs grep -l -E '^[[:space:]]*HandlePowerKey=' 2>/dev/null)
  for f in $files; do echo "  sets it: $f -> $(grep -h -E '^[[:space:]]*HandlePowerKey=' "$f" | tail -1)"; done
  # aurora-sep's 50-aurora-sep.conf sets HandlePowerKey=suspend and wins over Omarchy's ignore
  # (aurora-silicon/linux #1877, upstream-reported). Fail on that name wherever it sits.
  # shellcheck disable=SC2086
  aur=$(for d in $logind_dirs; do ls "$d"/*aurora-sep* 2>/dev/null; done)
  for f in $aur; do echo "  aurora-sep drop-in present: $f"; done
  [ -n "$aur" ] && bad=1
  [ "$val" = ignore ] || bad=1
  if [ $bad = 0 ]; then echo "POWER-KEY POLICY: ok (Hyprland gets XF86PowerOff, logind ignores it)"
  else echo "POWER-KEY POLICY: FAIL (a short press would be handled by logind, not by the Omarchy power menu)"; fi
  return $bad
}

bind_policy() { # Hyprland must bind no XF86Sleep, keycode 150 or suspend action; fails when hyprctl does not answer
  local json=${K114S_BINDS_JSON:-} rc
  # Lua configs report arg as an opaque number, so the Lua sources are scanned as well
  # An array, so a HOME or OMARCHY_PATH with a space stays one path. The test hook is a space-separated list.
  local -a dirs
  if [ -n "${K114S_HYPR_LUA_DIRS:-}" ]; then read -ra dirs <<<"$K114S_HYPR_LUA_DIRS"
  # Omarchy keeps its generated Lua (toggles, current theme) under ~/.local/state/omarchy; directories are scanned recursively
  else dirs=("$HOME/.config/hypr" "$HOME/.config/omarchy" "${OMARCHY_PATH:-/usr/share/omarchy}/default/hypr" "$HOME/.local/state/omarchy"); fi
  if [ -z "$json" ]; then json=$(mktemp); hyprctl binds -j >"$json" 2>/dev/null; fi
  py '
import json,re,sys,glob,os
try: b=json.load(open(sys.argv[1]))
except Exception: print("hyprland binds: unavailable (run inside the Hyprland session)"); sys.exit(1)
sus=r"suspend|hibernate|hybrid-sleep|(systemctl|loginctl)\s+sleep"
bad=[]
for x in b:
    text=" ".join(str(x.get(k,"")) for k in ("dispatcher","arg","description"))
    if x.get("key")=="XF86Sleep" or x.get("keycode")==150 or re.search(sus,text,re.I):
        bad.append("hyprland bind can suspend: %s code=%s %s %s"%(x.get("key"),x.get("keycode"),x.get("dispatcher",""),x.get("description","")))
for d in sys.argv[2:]:
    for f in glob.glob(os.path.join(d,"**","*.lua"),recursive=True):
        for n,l in enumerate(open(f,errors="replace"),1):
            if not l.lstrip().startswith("--") and re.search(sus,l,re.I):
                bad.append("hyprland lua can suspend: %s:%d"%(os.path.basename(f),n))
for m in bad: print(m)
print("hyprland binds: %s"%("FAIL" if bad else "no suspend bind"))
sys.exit(1 if bad else 0)
' "$json" "${dirs[@]}"; rc=$?
  [ -n "${K114S_BINDS_JSON:-}" ] || rm -f "$json"
  return $rc
}

key_policy() { # prints each setting, returns 1 unless all are ignore
  local bad=0 p v
  for p in HandleSuspendKey HandleSuspendKeyLongPress HandlePowerKey HandlePowerKeyLongPress; do
    case $p in
      HandleSuspendKey) v=${K114S_SUSPEND_VALUE:-} ;;
      HandleSuspendKeyLongPress) v=${K114S_SUSPEND_LP_VALUE:-} ;;
      HandlePowerKeyLongPress) v=${K114S_POWER_LP_VALUE:-} ;;
      *) v=${K114S_LOGIND_VALUE:-} ;;
    esac
    [ -n "$v" ] || v=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager "$p" 2>/dev/null | sed -n 's/^s "\(.*\)"$/\1/p')
    echo "logind $p: ${v:-unknown}"
    [ "$v" = ignore ] || bad=1
  done
  bind_policy || bad=1
  [ $bad = 0 ] && echo "KEY POLICY: ok (no key press can suspend)" || echo "KEY POLICY: FAIL (a key press could suspend the Mac)"
  return $bad
}

leds_report() {
  local d n
  for d in "$leds"/*kbd_backlight* "$leds"/*logo*; do
    [ -e "$d" ] || continue
    n=${d##*/}
    echo "led $n: $(cat "$d/brightness" 2>/dev/null)/$(cat "$d/max_brightness" 2>/dev/null) trigger=$(grep -o '\[[^]]*\]' "$d/trigger" 2>/dev/null)"
  done
  [ -d "$dt" ] && py '
import struct,sys,os,glob
for n in sorted(glob.glob(sys.argv[1]+"/led-*")):
    r=lambda p: open(n+"/"+p,"rb").read() if os.path.exists(n+"/"+p) else None
    p=r("pwms"); lab=(r("label") or b"?").rstrip(b"\0").decode()
    if p and len(p)>=12:
        ph,ch,per=struct.unpack(">3I",p[:12]); hz=1e9/per if per else 0
        print("dt %s: pwm phandle %d channel %d period %d ns (%.1f kHz) max-brightness %s default-state %s"%(lab,ph,ch,per,hz/1e3,
          struct.unpack(">I",r("max-brightness"))[0] if r("max-brightness") else "-",(r("default-state") or b"absent").rstrip(b"\0").decode()))
' "$dt"
}

binds_report() { # which XF86 keys Hyprland has bound, with modifiers
  local json=${K114S_BINDS_JSON:-}
  if [ -z "$json" ]; then json=$(mktemp); hyprctl binds -j >"$json" 2>/dev/null; fi
  py '
import json,sys
try: b=json.load(open(sys.argv[1]))
except Exception: print("binds: hyprctl unavailable (run inside the Hyprland session)"); sys.exit(0)
for k in ("XF86AudioMute","XF86AudioLowerVolume","XF86AudioRaiseVolume","XF86AudioMicMute","XF86AudioPrev","XF86AudioPlay","XF86AudioNext",
          "XF86MonBrightnessDown","XF86MonBrightnessUp","XF86KbdBrightnessDown","XF86KbdBrightnessUp","XF86KbdLightOnOff","XF86Sleep","XF86PowerOff"):
    m=[(x["modmask"],x.get("description","")) for x in b if x["key"]==k]
    mods={0:"",1:"SHIFT+",4:"CTRL+",8:"ALT+",64:"SUPER+"}
    print("bind %-24s %s"%(k,"; ".join(mods.get(a,"mod%d+"%a)+d for a,d in m) if m else "NOT BOUND"))
' "$json"
  [ -n "${K114S_BINDS_JSON:-}" ] || rm -f "$json"
}

status() {
  echo "machine: $(tr '\0' ' ' </proc/device-tree/compatible 2>/dev/null)"
  echo "kernel: $(uname -r)"
  leds_report
  py '
import re,sys
txt=open(sys.argv[1]).read()
for blk in txt.split("\n\n"):
    n=re.search(r"N: Name=\"(.*)\"",blk)
    if not n: continue
    out=[]
    for key in ("EV","KEY","ABS","SW","FF","PROP"):
        m=re.search(r"B: %s=(.*)"%key,blk)
        if not m: continue
        bits=[]
        for i,w in enumerate(reversed(m.group(1).split())):
            v=int(w,16); bits+=[i*64+b for b in range(64) if v>>b&1]
        out.append("%s=%s"%(key,bits if key!="KEY" or len(bits)<12 else "%d codes"%len(bits)))
    h=re.search(r"H: Handlers=(.*)",blk)
    print("input %s [%s]: %s"%(n.group(1),re.sub(r"\b(sysrq|kbd|leds)\b","",h.group(1)).strip() if h else "?"," ".join(out)))
    abs_=re.search(r"B: ABS=(.*)",blk)
    if abs_ and "multi-touch" in n.group(1):
        v=int("".join(w.zfill(16) for w in abs_.group(1).split()),16)
        print("  ABS_MT_TOOL_TYPE (code 55) advertised: %s  (no = the pad cannot tell libinput a contact is a palm)"%("yes" if v>>55&1 else "no"))
' "$proc"
  binds_report
  power_policy
}

capture() { # MODE SECONDS
  local mode=$1 secs=$2 runner=(sudo)
  [ -n "${K114S_NO_SUDO:-}" ] && runner=()
  if [ "$mode" = keys ]; then
    key_policy || { K114S_NO_MOON=1; echo "The key policy failed, so the moon key is left out of this capture."; }
    binds_report; echo
  fi
  [ "$mode" = power ] && { power_policy; echo; }
  case $mode in
    keys) if [ -n "${K114S_NO_MOON:-}" ]; then
            echo "Press now, for $secs s: mute, vol down, vol up, previous, play/pause, next, brightness down/up,"
            echo "Ctrl+brightness down/up, Fn, mic-mute if there is one. Do NOT press the moon key. Do not hold anything."
          else
            echo "Press now, for $secs s: mute, vol down, vol up, previous, play/pause, next, brightness down/up,"
            echo "Ctrl+brightness down/up, the moon key, Fn, mic-mute if there is one. Do not hold anything."
          fi;;
    power) echo "Press the power button ONCE, briefly, within $secs s. Then say what appeared (power menu, lock, nothing). Do not hold it.";;
    gestures) echo "For $secs s: rest a palm on the pad while typing a sentence; then 2-, 3- and 4-finger swipes, a pinch, one click.";;
  esac
  "${runner[@]}" env K114S_PROC_INPUT="$proc" K114S_DEV_DIR="${K114S_DEV_DIR:-/dev/input}" python3 -I -c '
import os,re,select,struct,sys,time
mode,secs=sys.argv[1],float(sys.argv[2]); proc=os.environ["K114S_PROC_INPUT"]; devdir=os.environ["K114S_DEV_DIR"]
want={"keys":["Apple MTP keyboard","Apple SMC power/lid events"],"power":["Apple SMC power/lid events"],
      "gestures":["Apple MTP multi-touch","Apple MTP keyboard"]}[mode]
nodes={}
for blk in open(proc).read().split("\n\n"):
    n=re.search(r"N: Name=\"(.*)\"",blk); h=re.search(r"H: Handlers=.*\b(event\d+)",blk)
    if n and h and n.group(1) in want: nodes[n.group(1)]=h.group(1)
if len(nodes)!=len(want): sys.exit("input device missing: want %s, found %s"%(want,list(nodes)))
fds={os.open(devdir+"/"+e,os.O_RDONLY|os.O_NONBLOCK):n for n,e in nodes.items()}
NAMES={113:"KEY_MUTE XF86AudioMute",114:"KEY_VOLUMEDOWN XF86AudioLowerVolume",115:"KEY_VOLUMEUP XF86AudioRaiseVolume",
 163:"KEY_NEXTSONG XF86AudioNext",164:"KEY_PLAYPAUSE XF86AudioPlay",165:"KEY_PREVIOUSSONG XF86AudioPrev",
 224:"KEY_BRIGHTNESSDOWN XF86MonBrightnessDown",225:"KEY_BRIGHTNESSUP XF86MonBrightnessUp",142:"KEY_SLEEP XF86Sleep",
 116:"KEY_POWER XF86PowerOff",248:"KEY_MICMUTE XF86AudioMicMute",228:"KEY_KBDILLUMTOGGLE XF86KbdLightOnOff",
 229:"KEY_KBDILLUMDOWN XF86KbdBrightnessDown",230:"KEY_KBDILLUMUP XF86KbdBrightnessUp",29:"KEY_LEFTCTRL",97:"KEY_RIGHTCTRL",
 464:"KEY_FN",240:"KEY_UNKNOWN",217:"KEY_SEARCH"}
TOP=[113,114,115,163,164,165,224,225,142,248]
press={}; held=set(); chord={}; t0=time.time(); presses={}; tool=set(); slots={}; maxc=0; maxmaj=0; maxprs=0
btn={}; keycount=0; slot=0; sw=[]; events=0; tid={}
def name(c): return NAMES.get(c,"code %d"%c)
end=t0+secs
while time.time()<end and fds:
    r,_,_=select.select(list(fds),[],[],0.2)
    for fd in r:
        try: d=os.read(fd,24*64)
        except OSError as e:   # ENODEV when the device resets or resumes mid-capture: keep the summary
            print("%s went away mid-capture (%s); the summary covers what was read"%(fds[fd],e.strerror)); del fds[fd]; break
        if not d: del fds[fd]; break   # a regular file (test) ends; a device never does
        for i in range(0,len(d)-23,24):
            _,_,t,c,v=struct.unpack("@llHHi",d[i:i+24]); events+=1; dev=fds.get(fd,"")
            if t==1:
                if mode=="gestures":
                    if "keyboard" in dev: keycount+=v==1
                    else: btn[c]=btn.get(c,0)+(v==1)
                    continue
                if v==1:
                    held.add(c); presses[c]=presses.get(c,0)+1
                    if c in TOP+[116] and (29 in held or 97 in held): chord[c]=chord.get(c,0)+1
                    print("%6.2fs press   %s"%(time.time()-t0,name(c)),flush=True)
                elif v==0:
                    held.discard(c); print("%6.2fs release %s"%(time.time()-t0,name(c)),flush=True)
            elif t==5 and mode!="gestures": print("%6.2fs switch %d=%d"%(time.time()-t0,c,v),flush=True)
            elif t==3 and mode=="gestures":
                if c==0x2f: slot=v
                elif c==0x39:
                    if v<0: slots.pop(slot,None)
                    else: slots[slot]=1
                    maxc=max(maxc,len(slots))
                elif c==0x30: maxmaj=max(maxmaj,v)
                elif c in (0x3a,0x18): maxprs=max(maxprs,v)
                elif c==0x37: tool.add(v)
if mode=="gestures":
    print("contacts: max simultaneous %d; ABS_MT_TOOL_TYPE values seen: %s; max touch major %d (range 0-5000); max pressure %d (range 0-6000)"%(maxc,sorted(tool) or "none",maxmaj,maxprs))
    print("buttons: "+", ".join("%s x%d"%({272:"BTN_LEFT click",330:"BTN_TOUCH",333:"BTN_TOOL_DOUBLETAP",334:"BTN_TOOL_TRIPLETAP",335:"BTN_TOOL_QUADTAP",325:"BTN_TOOL_FINGER"}.get(c,"code %d"%c),n) for c,n in sorted(btn.items())))
    print("keystrokes typed during the capture: %d; events read: %d"%(keycount,events))
else:
    for c in (TOP if mode=="keys" else [116]):
        print("%-8s %s presses=%d%s"%("SEEN" if presses.get(c) else "MISSING",name(c),presses.get(c,0)," (with Ctrl: %d)"%chord[c] if c in chord else ""))
    others=sorted(set(presses)-set(TOP)-{116})
    if others and mode=="keys": print("other codes: "+", ".join(name(c)+" x%d"%presses[c] for c in others))
' "$mode" "$secs"
}

case ${1:-status} in
  status) status ;;
  keypolicy) key_policy ;;
  keys|power|gestures) capture "$1" "${2:-$([ "$1" = power ] && echo 30 || echo 60)}" ;;
  *) sed -n '2,27p' "$0"; exit 2 ;;
esac
