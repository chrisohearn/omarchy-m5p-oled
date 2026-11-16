#!/bin/bash
# OWNER-AT-THE-MAC, after a boot of a tree that includes dts/t6050-k114s-avd.dtsi (issue #30).
# Decodes the same short synthetic clip in software and on the Apple Video Decoder (ffmpeg, VAAPI
# through libva-v4l2_request-avd) and compares the md5 of the frames. Upstream reports equal output
# at 1080p for H.264, HEVC and VP9 on the K116s; this checks the same on the K114s.
# Bounded: every decode has a timeout (-k 5). Nothing is installed and no system state changes;
# clips and logs live in a mktemp directory that is deleted on exit. No root needed.
#
#   tests/hardware/k114s-avd-decode-test.sh                 h264 hevc vp9 at 1920x1080, 2 s
#   tests/hardware/k114s-avd-decode-test.sh h264            one codec
#   tests/hardware/k114s-avd-decode-test.sh --software-only prove the clip and md5 steps without the decoder (works on any boot)
#   AVD_SIZE=1280x720 tests/hardware/k114s-avd-decode-test.sh   other sizes (above 1080p and 10-bit are untested upstream: #1995; #1936, the ring-wrap fix, is merged but not in the installed base)
# Exit: 0 every codec equal, 1 a mismatch or decode failure, 2 usage or a missing tool, 3 no decoder (SKIP).
set -u
size=${AVD_SIZE:-1920x1080}
sw_only=0 codecs=()
for a in "$@"; do
  case $a in
    --software-only) sw_only=1 ;;
    h264|hevc|vp9) codecs+=("$a") ;;
    *) sed -n '2,13p' "$0"; exit 2 ;;
  esac
done
[ ${#codecs[@]} -gt 0 ] || codecs=(h264 hevc vp9)
for t in ffmpeg timeout md5sum mktemp; do command -v "$t" >/dev/null || { echo "FAIL missing tool: $t"; exit 2; }; done
enclist=$(ffmpeg -hide_banner -encoders 2>/dev/null)
for c in "${codecs[@]}"; do
  case $c in h264) e=libx264 ;; hevc) e=libx265 ;; vp9) e=libvpx-vp9 ;; esac
  grep -qw "$e" <<<"$enclist" || { echo "FAIL missing encoder: $e"; exit 2; }
done
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fail=0
pass() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }; info() { echo "INFO $1"; }

if [ $sw_only -eq 0 ]; then
  ls /dev/media* >/dev/null 2>&1 || { echo "SKIP no /dev/media*: this boot has no decoder (not the AVD tree). Use --software-only to test the script."; exit 3; }
  dev=${AVD_RENDER_NODE:-$(ls /dev/dri/renderD* 2>/dev/null | head -1)}
  [ -n "$dev" ] || { echo "FAIL no render node"; exit 2; }
  export LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME:-v4l2_request}
  info "decoder: VAAPI driver $LIBVA_DRIVER_NAME on $dev (a device path only; no address is printed)"
fi

enc() { # codec out
  case $1 in
    h264) timeout -k 5 120 ffmpeg -v error -f lavfi -i "testsrc2=size=$size:rate=30:duration=2" -c:v libx264 -preset veryfast -pix_fmt yuv420p -y "$2" ;;
    hevc) timeout -k 5 120 ffmpeg -v error -f lavfi -i "testsrc2=size=$size:rate=30:duration=2" -c:v libx265 -preset veryfast -pix_fmt yuv420p -x265-params log-level=error -y "$2" ;;
    vp9)  timeout -k 5 120 ffmpeg -v error -f lavfi -i "testsrc2=size=$size:rate=30:duration=2" -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -pix_fmt yuv420p -y "$2" ;;
  esac
}
for c in "${codecs[@]}"; do
  case $c in vp9) f=$tmp/$c.webm ;; *) f=$tmp/$c.mkv ;; esac
  enc "$c" "$f" 2>"$tmp/enc.log" && [ -s "$f" ] || { bad "$c: could not make the test clip ($(head -c 200 "$tmp/enc.log"))"; continue; }
  sw=$(timeout -k 5 120 ffmpeg -v error -hwaccel none -i "$f" -vf format=nv12 -f md5 - 2>"$tmp/sw.log") || { bad "$c: software decode failed"; continue; }
  info "$c software  ${sw#MD5=}"
  [ $sw_only -eq 1 ] && { pass "$c: clip and software md5 ok"; continue; }
  hw=$(timeout -k 5 120 ffmpeg -v error -hwaccel vaapi -hwaccel_device "$dev" -hwaccel_output_format vaapi -i "$f" -vf hwdownload,format=nv12 -f md5 - 2>"$tmp/hw.log"); rc=$?
  if [ $rc -ne 0 ]; then bad "$c: vaapi decode exit $rc: $(head -c 300 "$tmp/hw.log" | tr '\n' ' ')"; continue; fi
  info "$c vaapi     ${hw#MD5=}"
  [ "$sw" = "$hw" ] && pass "$c: hardware frames equal software at $size" || bad "$c: md5 differs (hardware decode is not bit-exact here; look at it with mpv before judging)"
done
info "next: judge a real video in mpv by eye: mpv --hwdec=vaapi-copy --hwdec-codecs=h264,hevc,vp9 <file> (see docs/r3-avd-decode.md)"
exit $fail
