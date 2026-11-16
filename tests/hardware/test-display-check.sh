#!/bin/bash
# Software test of k114s-display-check.sh against fake device-tree, sysfs, /dev, interrupt, kernel-log, systemctl and
# hyprctl stand-ins (no root, nothing real is read except uname). It proves the script's decisions for the three
# trial outcomes (refused, published, none), that a wrong outcome is BAD, and that it never prints a command line.
set -u
here=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d) || exit 2; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
SECRET='rd.luks.key=00000000-0000-0000-0000-000000000000=/k/unlock.file root=UUID=00000000'
K116S=3D6C8857-E6F1-3D2E-9DFF-587028AE0C6E; J714S=C51FB0C8-C45D-39B0-85BC-520E600FC950

mk() { # mk NAME OUTCOME: a fake machine after a boot with that outcome (refused, published or none)
  local d=$W/$1 o=$2
  mkdir -p "$d/dt/chosen" "$d/dt/soc/dcp@48ae00000" "$d/sys/class/drm" "$d/sys/class/graphics/fb0" "$d/sys/class/backlight" \
    "$d/sys/bus/platform/drivers/aurora/2300000000.gpu/drm/renderD128" "$d/dev/dri/by-path" "$d/bl"
  printf 'm1n1/boot-ctxr-disp.bin\0' > "$d/dt/chosen/aurora,trial"; printf '1.0.0b13-g22b71758-dirty\0' > "$d/dt/chosen/asahi,m1n1-stage2-version"
  { for i in 1 2 3 4 5; do echo "[ 1.0] DCP: T6050: __OS_LOG 0x1000f43c000+0x2c000 overlaps /memreserve/ 0x1000f400000+0x5174000"; done
    echo "[ 1.1] FDT: GPU: T6050 G17S 26B8125 enabled, fw-text at 0x10000ff8000"; echo "[ 1.1] chosen bootargs $SECRET"; } > "$d/loader.log"
  printf '[    0.07] [drm] Initialized simpledrm 1.0.0 for 10fd41b4000.framebuffer on minor 0\n[    0.00] Kernel command line: %s\n' "$SECRET" > "$d/dmesg"
  case $o in
    refused)
      printf 'refused\0' > "$d/dt/chosen/asahi,t6050-dcp-handoff"; printf 'disabled\0' > "$d/dt/soc/dcp@48ae00000/status"
      mkdir -p "$d/dt/display-subsystem"; printf 'disabled\0' > "$d/dt/display-subsystem/status"
      { echo "[ 1.2] DCP: T6050: DCP image $K116S is not $J714S"; echo "[ 1.2] DCP: T6050: internal display handoff refused; the boot framebuffer keeps the panel"; } >> "$d/loader.log" ;;
    none)
      printf 'disabled\0' > "$d/dt/soc/dcp@48ae00000/status"
      echo "[ 1.2] DCP: T6050: the device tree does not describe the internal display: no handoff" >> "$d/loader.log" ;;
    published)
      printf 'published\0' > "$d/dt/chosen/asahi,t6050-dcp-handoff"; printf 'okay\0' > "$d/dt/soc/dcp@48ae00000/status"
      printf '%s\0' "$K116S" > "$d/dt/soc/dcp@48ae00000/apple,firmware-uuid"
      printf '\000\000\000\033\000\000\000\002\000\000\000\000' > "$d/dt/soc/dcp@48ae00000/apple,firmware-compat"
      mkdir -p "$d/dt/display-subsystem"; printf 'okay\0' > "$d/dt/display-subsystem/status"
      { echo "[ 1.2] DCP: T6050: internal display handed off: firmware 27.2, bw-scratch 0x1+0x2, 2 clock(s), 1000 nits"
        echo "[ 1.2] DCP: T6050: external display engines not handed off on firmware 27.2"; } >> "$d/loader.log"
      mkdir -p "$d/sys/class/drm/card2-eDP-1" "$d/sys/module/appledrm/parameters" "$d/sys/class/backlight/apple-panel-bl"
      echo connected > "$d/sys/class/drm/card2-eDP-1/status"; echo 3024x1986 > "$d/sys/class/drm/card2-eDP-1/modes"; echo 0 > "$d/vrrcap"
      echo N > "$d/sys/module/appledrm/parameters/fw27_panel_vrr"; echo appledrmfb > "$d/sys/class/graphics/fb0/name"
      echo 1000 > "$d/sys/class/backlight/apple-panel-bl/max_brightness"; echo 500 > "$d/sys/class/backlight/apple-panel-bl/brightness"
      echo 500 > "$d/sys/class/backlight/apple-panel-bl/actual_brightness"; : > "$d/dev/dri/card2"; ln -s ../card2 "$d/dev/dri/by-path/platform-display-subsystem-card"
      printf '[    2.13] [drm] Initialized apple 1.0.0 for display-subsystem on minor 2\n[    2.14] apple-drm display-subsystem: no loader brightness reported; backlight starts at 500 nits without a panel change\n' >> "$d/dmesg" ;;
  esac
  if [ "$o" != published ]; then mkdir -p "$d/sys/class/drm/card0-Unknown-1"; echo simpledrmdrmfb > "$d/sys/class/graphics/fb0/name"; fi
  # a header with two CPUs, then the GPU receive line: the hwirq number (1043) must not be counted
  printf '           CPU0       CPU1\n 77:        100        200  AIC 1043 Level     2302600000.mailbox-recv\n 78:          5          5  AIC 1044 Level     2302e00000.mailbox-recv\n' > "$d/irq"
  cat > "$d/systemctl" <<SH
#!/bin/sh
echo no
SH
  if [ "$o" = published ]; then
    printf '#!/bin/sh\necho %s\n' "'[{\"name\":\"eDP-1\",\"width\":3024,\"height\":1986,\"refreshRate\":120.0,\"scale\":2.0,\"vrr\":false,\"currentFormat\":\"XRGB8888\"}]'" > "$d/hyprctl"
  else
    printf '#!/bin/sh\necho %s\n' "'[{\"name\":\"Unknown-1\",\"width\":3024,\"height\":1986,\"refreshRate\":60.0,\"scale\":2.0,\"vrr\":false,\"currentFormat\":\"XRGB8888\"}]'" > "$d/hyprctl"
  fi
  # the interrupt count rises while the script sleeps: a stand-in sleep bumps it
  mkdir -p "$d/bin"; printf '#!/bin/sh\nsed -i "s/        100        200/        400        500/" "%s"\n' "$d/irq" > "$d/bin/sleep"
  # the KMS connector property, as modetest -M apple -c prints it (the sysfs file does not exist on this kernel)
  printf '#!/bin/sh\necho "  23 CTM:"\nprintf "  50 vrr_capable:\\n\\t\\tflags: immutable range\\n\\t\\tvalues: 0 1\\n\\t\\tvalue: %%s\\n" "$(cat "%s/vrrcap")"\n' "$d" > "$d/bin/modetest"
  chmod +x "$d/systemctl" "$d/hyprctl" "$d/bin/sleep" "$d/bin/modetest"
}
run() { # run NAME EXPECT [ARGS...]
  local d=$W/$1; shift
  out=$(PATH=$d/bin:$PATH K114S_DT=$d/dt K114S_SYS=$d/sys K114S_DEV=$d/dev K114S_DMESG_FILE=$d/dmesg K114S_INTERRUPTS=$d/irq \
    K114S_MODETEST=$d/bin/modetest K114S_SYSTEMCTL=$d/systemctl K114S_HYPRCTL=$d/hyprctl K114S_BACKLIGHT_STATE=$d/bl \
    bash "$here/k114s-display-check.sh" --expect "$@" --loader-log "$d/loader.log" --wait 1 --hypr 2>&1); rc=$?
}
for o in refused published none; do
  mk "$o" "$o"; run "$o" "$o"
  ok "$o: exit 0 and no BAD on a matching boot" "$rc $(printf '%s\n' "$out" | grep -c '^BAD')" "0 0"
  ok "$o: the summary line" "$(printf '%s\n' "$out" | tail -1 | sed 's/: [0-9]* ok/: N ok/')" "display-check ($o): N ok, 0 BAD"
  ok "$o: the command line is never printed (kernel log and loader log both hold one)" "$(printf '%s\n' "$out" | grep -c -e 'luks' -e 'root=UUID')" 0
  ok "$o: the mailbox count excludes the hwirq column (300 -> 900)" "$(printf '%s\n' "$out" | grep -c 'rises: 300 -> 900')" 1
done
mk r refused; run r published; ok "a refused boot checked as published is BAD, exit 1" "$rc $(printf '%s\n' "$out" | grep -c '^BAD   /chosen/asahi,t6050-dcp-handoff is .refused.')" "1 1"
mk p published; run p refused; ok "a published boot checked as refused is BAD (the panel left simpledrm)" "$rc $(printf '%s\n' "$out" | grep -c 'a DCP card exists')" "1 1"
mk m published; echo 2560x1600 >> "$W/m/sys/class/drm/card2-eDP-1/modes"; run m published; ok "published: a mode that is not 3024 by 1986 or 1964 is BAD" "$rc $(printf '%s\n' "$out" | grep -c '^BAD   modes:')" "1 1"
mk v published; echo Y > "$W/v/sys/module/appledrm/parameters/fw27_panel_vrr"; run v published; ok "published: fw27_panel_vrr Y is BAD" "$rc $(printf '%s\n' "$out" | grep -c 'fw27_panel_vrr is .Y.')" "1 1"
mk b published; printf '#!/bin/sh\necho yes\n' > "$W/b/systemctl"; run b published; ok "published: systemd-backlight that ran (no drop-in) is BAD" "$rc $(printf '%s\n' "$out" | grep -c 'systemd-backlight for apple-panel-bl ran')" "1 1"
mk c published; echo "[    3.0] apple-drm display-subsystem: DCP has crashed" >> "$W/c/dmesg"; run c published; ok "published: a DCP crash in the kernel log is BAD" "$rc $(printf '%s\n' "$out" | grep -c '^BAD   kernel log: .*DCP has crashed')" "1 1"
mk x published; sed -i '/external display engines/d' "$W/x/loader.log"; run x published; ok "published: no 'external ... not handed off' line (not the K114s-pin loader) is BAD" "$rc $(printf '%s\n' "$out" | grep -c 'is this the K114s-pin loader')" "1 1"
mk f none; printf '#!/bin/sh\nexit 0\n' > "$W/f/bin/sleep"; run f none; ok "a GPU receive count that stays flat is BAD" "$rc $(printf '%s\n' "$out" | grep -c 'mailbox-recv does not rise')" "1 1"
mk h published; printf '#!/bin/sh\necho %s\n' "'[{\"name\":\"eDP-1\",\"width\":3024,\"height\":1986,\"refreshRate\":60.0,\"scale\":2.0,\"vrr\":false}]'" > "$W/h/hyprctl"; run h published
ok "published: Hyprland at 60 Hz is BAD" "$rc $(printf '%s\n' "$out" | grep -c '^BAD   hyprland: eDP-1')" "1 1"
mk j none; printf '#!/bin/sh\necho "HYPRLAND_INSTANCE_SIGNATURE not set"\n' > "$W/j/hyprctl"; run j none; ok "hyprctl without a session (sudo) is BAD, not a crash" "$rc $(printf '%s\n' "$out" | grep -c 'gave no JSON') $(printf '%s\n' "$out" | grep -c Traceback)" "1 1 0"
# D5 and D6 options: --floor (the brightness build) and --vrr on (the boot without the mask)
mk fl published; mkdir -p "$W/fl/dt/soc/dcp@48ae00000/panel"; printf '\000\000\000\012' > "$W/fl/dt/soc/dcp@48ae00000/panel/apple,min-brightness"
printf '[    2.20] apple-drm display-subsystem: brightness requests below 10 nits are raised to 10 nits\n' >> "$W/fl/dmesg"
run fl published --floor; ok "--floor on the brightness build: exit 0, the floor line and the tree property are ok" "$rc $(printf '%s\n' "$out" | grep -c '^ok    kernel: brightness requests below') $(printf '%s\n' "$out" | grep -c 'apple,min-brightness 10')" "0 1 1"
mk f0 published; run f0 published --floor; ok "--floor on the D4 build and tree is BAD twice" "$rc $(printf '%s\n' "$out" | grep -c '^BAD   kernel: no .brightness requests') $(printf '%s\n' "$out" | grep -c '^BAD   .*apple,min-brightness is not 10')" "1 1 1"
mk fi published; mkdir -p "$W/fi/dt/soc/dcp@48ae00000/panel"; printf '\000\000\000\012' > "$W/fi/dt/soc/dcp@48ae00000/panel/apple,min-brightness"
printf '[    2.20] apple-drm x: brightness requests below 10 nits are raised to 10 nits\n[    2.30] apple-drm x: brightness floor 10 ignored for a ceiling of 5\n[    2.40] dcp: unqualified IOMFB callback 590\n' >> "$W/fi/dmesg"
run fi published --floor; ok "--floor: a dropped floor and callback 590 are BAD" "$rc $(printf '%s\n' "$out" | grep -c '^BAD   kernel: the brightness floor was dropped') $(printf '%s\n' "$out" | grep -c '^BAD   kernel: unqualified IOMFB callback 590')" "1 1 1"
mk nf published; run nf published; ok "without --floor the floor line is not looked for" "$rc $(printf '%s\n' "$out" | grep -c 'brightness requests below')" "0 0"
mk vo published; echo Y > "$W/vo/sys/module/appledrm/parameters/fw27_panel_vrr"; echo 1 > "$W/vo/vrrcap"
run vo published --vrr on; ok "--vrr on: fw27_panel_vrr Y and vrr_capable 1 are ok" "$rc $(printf '%s\n' "$out" | grep -c 'ok    vrr_capable 1') $(printf '%s\n' "$out" | grep -c 'fw27_panel_vrr = Y')" "0 1 1"
run vo published; ok "the default (--vrr off) calls that same boot BAD twice" "$rc $(printf '%s\n' "$out" | grep -c '^BAD   vrr_capable is .1., expected 0') $(printf '%s\n' "$out" | grep -c '^BAD   appledrm.fw27_panel_vrr is .Y.')" "1 1 1"
mk vm published; run vm published --vrr on; ok "--vrr on on a masked boot is BAD twice" "$rc $(printf '%s\n' "$out" | grep -c '^BAD   vrr_capable is .0., expected 1') $(printf '%s\n' "$out" | grep -c '^BAD   appledrm.fw27_panel_vrr is .N.')" "1 1 1"
mk vh published; printf '#!/bin/sh\necho %s\n' "'[{\"name\":\"eDP-1\",\"width\":3024,\"height\":1986,\"refreshRate\":120.0,\"scale\":2.0,\"vrr\":true,\"currentFormat\":\"XRGB8888\"}]'" > "$W/vh/hyprctl"
echo Y > "$W/vh/sys/module/appledrm/parameters/fw27_panel_vrr"; echo 1 > "$W/vh/vrrcap"
run vh published --vrr on; ok "--vrr on: Hyprland with vrr true is ok" "$rc $(printf '%s\n' "$out" | grep -c '^ok    hyprland: eDP-1')" "0 1"
mk vk published; cp "$W/vh/hyprctl" "$W/vk/hyprctl"; run vk published; ok "--vrr off: Hyprland with vrr true is BAD" "$rc $(printf '%s\n' "$out" | grep -c '^BAD   hyprland: eDP-1')" "1 1"
mk vu published; rm "$W/vu/bin/modetest"; run vu published; ok "published: an unreadable vrr_capable (no modetest) is BAD, not skipped" "$rc $(printf '%s\n' "$out" | grep -c "^BAD   vrr_capable is 'unreadable'")" "1 1"
bash "$here/k114s-display-check.sh" --expect published --vrr maybe >/dev/null 2>&1; ok "an unknown --vrr value is refused" "$?" 2
bash "$here/k114s-display-check.sh" --expect maybe >/dev/null 2>&1; ok "an unknown expectation is refused" "$?" 2
echo "display-check test: $pass passed, $fail failed"
[ "$fail" = 0 ]
