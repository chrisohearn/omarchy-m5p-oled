#!/bin/bash
# K114s snapshot-boot checks for the owner to run on the Mac. See docs/r3-snapshot-boot.md (issue #68).
#
#   sudo k114s-snapshot-check.sh status     read-only: ESP budget, Limine snapshot entries, which snapshots
#                                           carry the installed kernels, what Limine advertises for
#                                           boot-menu requests (bootctl)
#   k114s-snapshot-check.sh budget TOTAL USED UKI...   pure arithmetic (bytes); no system access
#   sudo k114s-snapshot-check.sh after      run AFTER booting a Snapshots entry: says whether this boot is
#                                           a snapshot boot and whether the overlay is in place
#   sudo k114s-snapshot-check.sh after-menu run after 'systemctl reboot --boot-loader-menu=0': says which
#                                           entry booted (an unattended default boot means it was ignored)
#
# Nothing here writes anything. The output holds no serial numbers, addresses or network names.
set -u

limit=${K114S_LIMIT_PERCENT:-85}
guard_kib=${K114S_GUARD_KIB:-86016}   # the pacman space guard (docs/esp-space.md)

budget() {
  local total=$1 used=$2; shift 2
  local uki sum=0 n=0 pct free
  echo "ESP: total=$total used=$used free=$((total - used)) bytes"
  for uki in "$@"; do
    sum=$((sum + uki)); n=$((n + 1))
    pct=$(awk -v u=$((used + sum)) -v t="$total" 'BEGIN{printf "%.1f", u*100/t}')
    free=$((total - used - sum))
    printf 'after %d snapshot UKI(s) (+%d bytes): %s%% used, %d free; ' "$n" "$sum" "$pct" "$free"
    if awk -v p="$pct" -v l="$limit" 'BEGIN{exit !(p<=l)}'; then printf 'under the %s%% limit; ' "$limit"; else printf 'OVER the %s%% limit (limine-snapper-sync refuses); ' "$limit"; fi
    if [ "$free" -ge $((guard_kib * 1024)) ]; then echo "pacman guard ok"; else echo "pacman guard BLOCKS package transactions"; fi
  done
}

status() {
  local esp=${K114S_ESP:-/boot/efi} conf total used snap
  conf=$esp/limine.conf
  [ "$(id -u)" -eq 0 ] || { echo "run with sudo (the ESP is root-only)"; return 1; }
  read -r total used < <(df -B1 --output=size,used "$esp" | tail -1)
  echo "== Limine snapshot entries"
  if grep -q '^/Snapshots' "$conf"; then awk '/^\//{s=($0 ~ /^\/Snapshots/)} s && /^  \//{n++} END{print "entries under Snapshots: " n+0}' "$conf"; else echo "no Snapshots section in limine.conf"; fi
  echo "== UKIs on the ESP"
  # shellcheck disable=SC2046
  sizes=()
  for u in $(find "$esp" -name '*.efi' -path '*Linux*' -not -path '*limine_history*' 2>/dev/null); do s=$(stat -c %s "$u"); echo "kernel $(basename "$u") $s"; sizes+=("$s"); done
  for u in $(find "$esp" -name '*.efi' -path '*limine_history*' 2>/dev/null); do echo "snapshot (already counted in used) $(basename "$u") $(stat -c %s "$u")"; done
  echo "== budget if every current kernel UKI were copied once"
  budget "$total" "$used" "${sizes[@]}"
  echo "== snapshots versus installed kernels (first 12 hex of sha256)"
  for snap in /.snapshots/*/snapshot; do
    [ -d "$snap" ] || continue
    echo "snapshot $(basename "$(dirname "$snap")"):"
    for k in "$snap"/usr/lib/modules/*/vmlinuz; do
      [ -e "$k" ] || continue
      h=$(sha256sum "$k" | cut -c1-12)
      m=no; for b in /boot/vmlinuz-*; do [ "$(sha256sum "$b" | cut -c1-12)" = "$h" ] && m="yes ($(basename "$b"))"; done
      echo "  $(basename "$(dirname "$k")") $h same as /boot: $m"
    done
  done
  echo "== Limine boot-menu support (bootctl)"
  bootctl status --no-pager 2>/dev/null | grep -E 'Product:|One-shot menu timeout' || echo "bootctl reports nothing"
  echo "== EFI variables saved across reset (efi-vars service)"
  systemctl is-active omarchy-mac-efi-vars
  ls /sys/firmware/efi/efivars | grep -E '^(RTStorageVolatile|VarToFile)' || echo "missing"
}

after() {
  echo "cmdline snapshot hints: $(grep -o -E 'snapshot[^ ]*|overlay[^ ]*' /proc/cmdline | tr '\n' ' ')"
  echo "root mount: $(findmnt -no FSTYPE,OPTIONS / | cut -c1-120)"
  systemctl is-active omarchy-mac-snapshot-overlay.service 2>&1 | sed 's/^/overlay unit: /'
  echo "kernel: $(uname -r)"
  systemctl --failed --no-legend | sed 's/^/failed: /'
  journalctl -b -p warning --no-pager -q 2>/dev/null | grep -c -E 'Oops|WARNING' | sed 's/^/oops or WARNING lines: /'
}

after_menu() {
  echo "kernel: $(uname -r)"
  echo "uptime: $(uptime -p)"
  echo "last booted entry var: $(od -An -c /sys/firmware/efi/efivars/LimineLastBootedEntry-03884334-1756-4978-9c8c-86fb8998b4ea 2>/dev/null | tr -d ' \n' | cut -c1-80)"
  echo "If you saw the Limine menu and the countdown did not boot by itself, the request worked."
}

case ${1:-} in
  budget) shift; budget "$@" ;;
  status) status ;;
  after) after ;;
  after-menu) after_menu ;;
  *) sed -n '2,13p' "$0"; exit 2 ;;
esac
