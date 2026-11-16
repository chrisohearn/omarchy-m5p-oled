#!/bin/bash
# K114s trackpad click strength (issue #47). See docs/click-strength.md.
#
#   k114s-click-strength.sh status          no root: haptic driver, module parameter, device tree
#   sudo k114s-click-strength.sh set P R    write click_strength=P,R (1-255 each) to the live driver
#   sudo k114s-click-strength.sh clear      write 0,0: back to the device tree / firmware strength
#
# set and clear need a kernel that carries aurora-silicon/linux #1959 (the click_strength module
# parameter). Without it the script says so and writes nothing. A value is a hardware write to the
# trackpad actuator and lasts until cleared or the next boot; it is never written to a file here.
set -u
param=${K114S_HAPTIC_PARAM:-/sys/module/hid_apple_mtp_haptic/parameters/click_strength}
mod=${K114S_HAPTIC_MODULE:-/sys/module/hid_apple_mtp_haptic}
dt=${K114S_DT:-/proc/device-tree}

status() {
  echo "kernel: $(uname -r)"
  if [[ -d $mod ]]; then echo "driver: hid_apple_mtp_haptic loaded"; else echo "driver: hid_apple_mtp_haptic NOT loaded"; fi
  if [[ -r $param ]]; then
    echo "click_strength parameter: $(cat "$param") (0,0 = device tree or firmware value)"
  else
    echo "click_strength parameter: absent (kernel has no #1959; the click uses the firmware value)"
  fi
  local n
  n=$(find "$dt" -name 'apple,click-strength' 2>/dev/null | wc -l)
  echo "apple,click-strength properties in the device tree: $n"
}

need_param() {
  [[ -w $param ]] || { echo "refused: $param is not writable (no #1959 in this kernel, or not root)" >&2; exit 2; }
}

case ${1:-} in
  status) status ;;
  set)
    [[ ${2:-} =~ ^[0-9]+$ && ${3:-} =~ ^[0-9]+$ ]] || { echo "usage: set PRESS RELEASE (1-255)" >&2; exit 2; }
    (( $2 >= 1 && $2 <= 255 && $3 >= 1 && $3 <= 255 )) || { echo "refused: values must be 1-255" >&2; exit 2; }
    need_param
    echo "$2,$3" >"$param" && echo "click_strength now $(cat "$param"); press the pad and judge it" ;;
  clear)
    need_param
    echo "0,0" >"$param" && echo "click_strength now $(cat "$param")" ;;
  *) echo "usage: $0 status | set PRESS RELEASE | clear" >&2; exit 2 ;;
esac
