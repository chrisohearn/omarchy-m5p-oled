#!/bin/bash
# Exercise the real camera helper with only synthetic DT/sysfs and video devices.
set -euo pipefail
command -v bwrap >/dev/null || { echo "SKIP camera check: bubblewrap is required"; exit 77; }
helper=$(realpath "$(dirname "$0")/k114s-camera-check.sh")
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
dt="$fixture/dt"
isp="$dt/soc/isp@580000000"
sys="$fixture/sys"
mkdir -p "$isp" "$sys/video2/device" "$sys/video9/device" "$fixture/bin" "$fixture/tmp"
printf 'apple,k114s\0apple,k114\0' > "$dt/compatible"
printf 'okay\0' > "$isp/status"
printf '\0\0\0\272' > "$isp/apple,platform-id"
printf 'gpio\0wdt\0' > "$isp/reg-names"
ln -s /bus/platform/drivers/avd "$sys/video2/device/driver"
ln -s /bus/platform/drivers/apple-isp "$sys/video9/device/driver"
cat > "$fixture/bin/ffmpeg" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@" > "$CAPTURE_CALL"
printf 'fixture frame' > "${@: -1}"
exit "$CAPTURE_STATUS"
MOCK
chmod +x "$fixture/bin/ffmpeg"

run_case() {
  local label=$1 has_isp=$2 capture_status=$3 want_status=$4 want_message=$5
  local status=0
  local -a devices=(--dev-bind /dev/null /dev/video2)
  if (( has_isp )); then devices+=(--dev-bind /dev/null /dev/video9); fi
  rm -f -- "$fixture/ffmpeg-call"
  bwrap --ro-bind / / --dev /dev "${devices[@]}" \
    --tmpfs /proc --ro-bind "$dt" /proc/device-tree \
    --tmpfs /sys --ro-bind "$sys" /sys/class/video4linux \
    --tmpfs /run --bind "$fixture" /run/camera-check --bind "$fixture/tmp" /tmp --unshare-net --die-with-parent \
    --setenv TMPDIR /tmp --setenv PATH /run/camera-check/bin:/usr/bin \
    --setenv CAPTURE_CALL /run/camera-check/ffmpeg-call --setenv CAPTURE_STATUS "$capture_status" \
    -- /usr/bin/bash "$helper" --capture > "$fixture/result" 2>&1 || status=$?
  if [[ $status != "$want_status" ]] || ! grep -Fq "$want_message" "$fixture/result"; then
    cat "$fixture/result" >&2
    printf 'FAIL %s (exit %s, expected %s)\n' "$label" "$status" "$want_status" >&2
    exit 1
  fi
  printf 'ok   %s\n' "$label"
}

run_case 'AVD is not a camera' 0 0 1 'Apple ISP capture device absent'
test ! -e "$fixture/ffmpeg-call"
run_case 'ISP without a light description refuses capture' 1 0 1 'physical camera activity light description is missing'
test ! -e "$fixture/ffmpeg-call"
printf 'gpio\0wdt\0cil\0' > "$isp/reg-names"
printf '\0\0\0\1' > "$isp/apple,cil-config"
run_case 'failed capture cleans up the partial image' 1 1 1 'no frame saved'
grep -Fxq /dev/video9 "$fixture/ffmpeg-call"
test -z "$(find "$fixture/tmp" -mindepth 1 -print -quit)"
run_case 'ISP with a light description captures from the ISP only' 1 0 0 'one local frame saved'
grep -Fxq /dev/video9 "$fixture/ffmpeg-call"
printf 'apple,k114s-unexpected\0' > "$dt/compatible"
run_case 'wrong board refuses capture' 1 0 1 'expected a K114s device tree'
test ! -e "$fixture/ffmpeg-call"
