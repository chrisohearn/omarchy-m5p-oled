#!/bin/bash
# linux/k114s-boot status on fake ESPs: roles, a pending one-shot, a default that names nothing. No root, no real ESP.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd); tool=$here/linux/k114s-boot; fails=0
t=$(mktemp -d); trap 'rm -r -- "$t" </dev/null' EXIT
mk() { # $1 dir, $2 default_entry
  mkdir -p "$1/esp/m1n1" "$1/efivars"; printf 'stage2' > "$1/esp/m1n1/boot-ctxr.bin"; printf 'spent\nm1n1/x.bin\n' > "$1/esp/aura-try"
  cat > "$1/esp/limine.conf" <<C
timeout: 0
default_entry: $2
/+Omarchy
comment: machine-id=00000000000000000000000000000000
  //linux-k114s
  comment: Kernel version: 7.3.0-test-new-ARCH
  comment: kernel-id=linux-k114s
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux-k114s.efi#aa
  //linux-k114s-r3b
  comment: Kernel version: 7.3.0-test-old-ARCH
  comment: kernel-id=linux-k114s-r3b
  protocol: efi
  path: boot():/EFI/Linux/omarchy_linux-k114s-r3b.efi#bb
C
}
run() { K114S_ESP=$1/esp K114S_EFIVARS=$1/efivars bash "$tool" status; }
want() { if grep -q -- "$2" <<<"$1"; then echo "ok   $3"; else echo "FAIL $3"; echo "$1"; fails=$((fails+1)); fi; }
mk "$t/a" Omarchy/linux-k114s; o=$(run "$t/a")
want "$o" 'Main    Omarchy/linux-k114s ' "default entry is Main"
want "$o" 'Backup  Omarchy/linux-k114s-r3b' "the other kernel is Backup"
want "$o" 'Next boot: Main (no test boot pending)' "no one-shot: next boot is Main"
want "$o" 'Stage 2: the configured' "Stage 2 configured"
mk "$t/b" Omarchy/linux-k114s-r3b; o=$(run "$t/b")
want "$o" 'Main    Omarchy/linux-k114s-r3b' "roles follow default_entry"
mk "$t/c" Omarchy/linux-k114s; printf '\x07\0\0\0' > "$t/c/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"
printf 'Omarchy.linux-k114s-r3b' | sed 's/./&\x00/g' >> "$t/c/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"; o=$(run "$t/c")
want "$o" 'Test    Omarchy/linux-k114s-r3b' "a pending one-shot marks Test"
want "$o" 'Next boot: the Test entry once (Omarchy.linux-k114s-r3b)' "next boot is the Test entry"
mk "$t/d" Omarchy/gone; o=$(run "$t/d")
want "$o" "WARNING: default_entry 'Omarchy/gone' names no kernel entry" "a default naming nothing is flagged"
mk "$t/e" Omarchy/linux-k114s; printf 'armed\nm1n1/boot-ctxr-t.bin\n' > "$t/e/esp/aura-try"; o=$(run "$t/e")
want "$o" 'Stage 2: test file m1n1/boot-ctxr-t.bin armed' "an armed aura-try is shown"
u16() { printf '%s' "$1" | sed 's/./&\x00/g'; }
mk "$t/f" 2; o=$(run "$t/f")
want "$o" 'Main    Omarchy/linux-k114s ' "a numeric default resolves to its entry (index 2 = linux-k114s)"
want "$o" 'note: default_entry is index 2, which is Omarchy/linux-k114s' "the index is explained"
mk "$t/g" X; sed -i '/^default_entry/d' "$t/g/esp/limine.conf"; o=$(run "$t/g"); rc=$?
want "$o" 'WARNING: limine.conf has no default_entry' "a missing default_entry is reported, not a silent exit"
mk "$t/h" Omarchy/linux-k114s; sed -i 's/^timeout: 0/timeout: 0\nremember_last_entry: yes/' "$t/h/esp/limine.conf"; o=$(run "$t/h")
want "$o" 'remember_last_entry is on' "remember_last_entry is flagged"
mk "$t/i" Omarchy/linux-k114s; { printf 'UBEF'; u16 OtherVar; printf '\0\0'; u16 LoaderEntryOneShot; printf '\0\0'; u16 Omarchy.linux-k114s-r3b; printf '\0\0'; } > "$t/i/esp/ubootefi.var"; o=$(run "$t/i")
want "$o" 'Test    Omarchy/linux-k114s-r3b' "a one-shot held only in U-Boot's file is decoded and marked Test"
mk "$t/j" Omarchy/linux-k114s; rm "$t/j/esp/aura-try"; o=$(run "$t/j")
want "$o" 'Stage 2: the configured m1n1/boot-ctxr.bin' "the configured Stage 2 is shown without aura-try"
mk "$t/k" Omarchy/linux-k114s; { printf '\x06\0\0\0'; u16 Omarchy.linux-k114s-r3b; } > "$t/k/efivars/LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"; o=$(run "$t/k")
want "$o" 'Backup  Omarchy/linux-k114s-r3b      7.3.0-test-old-ARCH   <- running now' "the running entry comes from LoaderEntrySelected"
[ $fails = 0 ] && echo "test-k114s-boot: all passed" || { echo "test-k114s-boot: $fails failed"; exit 1; }
