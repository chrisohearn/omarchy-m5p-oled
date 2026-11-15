#!/bin/bash
# Every r3 script parses, and the hook, unit and data files have the shape their readers expect.
#   usage: k114s-syntax.sh [LINUX_DIR]
set -u
. "$(dirname "$0")/r3-lib.sh" "${1:-}"
for f in k114s-lib.sh k114s-guard k114s-holds k114s-repackage k114s-recovery-set k114s-release-check k114s-release k114s-boot-success \
    k114s-modules-cleanup k114s-tooling-install hooks/pre-refresh-pacman-k114s-holds hooks/post-update-k114s-release-check; do
  ok "bash parses $f" "$(bash -n "$L/$f" 2>&1)" ""
done
for f in update-boot-ctxr-k114s k114s-booted-esp; do ok "sh parses $f" "$(sh -n "$L/$f" 2>&1)" ""; done
if command -v dash >/dev/null; then for f in update-boot-ctxr-k114s k114s-booted-esp; do ok "dash parses $f" "$(dash -n "$L/$f" 2>&1)" ""; done; fi
for f in k114s-fdt k114s-binscan; do ok "python compiles $f" "$(python3 -I -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$L/$f" 2>&1)" ""; done
ok "python compiles the test device-tree writer" "$(python3 -I -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$T/mkfdt.py" 2>&1)" ""
for f in k114s-guard k114s-holds k114s-repackage k114s-recovery-set k114s-release-check k114s-release k114s-boot-success k114s-modules-cleanup \
    k114s-fdt k114s-binscan k114s-tooling-install hooks/pre-refresh-pacman-k114s-holds hooks/post-update-k114s-release-check; do
  ok "$f is executable in the repository" "$(test -x "$L/$f"; echo $?)" 0
done
# what the installer copies exists, and it copies everything a tool sources or calls
for f in $(sed -n '/^TOOLS=(/,/)/p; /^DATA=(/,/)/p; /^NEW_HOOKS=(/,/)/p; /^UNIT_FILES=(/,/)/p; /^OTHER=(/,/)/p' "$L/k114s-tooling-install" | tr -d '()' | sed 's/^[A-Z_]*=//' | tr -s ' \n' '\n\n' | grep . | grep -v '[$=]'); do
  ok "installer names a file that exists: $f" "$(test -f "$L/$f"; echo $?)" 0
done
ok "every k114s-* tool in the repository is installed by the installer" "$(for f in "$L"/k114s-*; do b=${f##*/}; case $b in k114s-tooling-install | *.service | *.timer | *.path) continue ;; esac; grep -q -w -- "$b" "$L/k114s-tooling-install" || echo "$b"; done)" ""
ok "every data file a tool reads is installed" "$(for d in $(grep -h -o -E '(data_file |\$LIB/|\$lib/)[a-z0-9.-]+\.(list|conf|required|default)' "$L"/k114s-* | sed -E 's/^(data_file |\$LIB\/|\$lib\/)//' | sort -u); do case $d in holds.list | released.list | release.conf) continue ;; esac; grep -q -w -- "$d" "$L/k114s-tooling-install" || echo "$d"; done)" ""
# list files: one valid name (or the documented shape) per line
for f in holds.default protected.list; do ok "$f: package names only" "$(grep -v -E '^[[:space:]]*(#|$)' "$L/$f" | grep -c -v -E '^[A-Za-z0-9@._+-]+$')" 0; done
ok "rivals.list: RIVAL HELD pairs" "$(grep -v -E '^[[:space:]]*(#|$)' "$L/rivals.list" | awk 'NF != 2' | wc -l | tr -d ' ')" 0
ok "noextract.list: PATH PACKAGE GLOB" "$(grep -v -E '^[[:space:]]*(#|$)' "$L/noextract.list" | awk 'NF != 3 || $1 ~ /^\//' | wc -l | tr -d ' ')" 0
ok "extras.list: relative paths" "$(grep -v -E '^[[:space:]]*(#|$)' "$L/extras.list" | grep -c -E '^/|\.\.')" 0
ok "release.conf: KEY=value lines only" "$(grep -v -E '^[[:space:]]*(#|$)' "$L/release.conf" | grep -c -v -E '^[A-Z0-9_]+=[A-Za-z0-9._:,/ -]*$')" 0
ok "every held default is protected from removal or has criteria" "$(for p in $(grep -v -E '^[[:space:]]*(#|$)' "$L/holds.default"); do grep -q -x "$p" "$L/protected.list" || grep -q "^package $p " "$L/release-criteria.conf" || echo "$p"; done)" ""
ok "every default hold has release criteria (none can be held for ever by oversight)" "$(for p in $(grep -v -E '^[[:space:]]*(#|$)' "$L/holds.default"); do grep -q "^package $p " "$L/release-criteria.conf" || echo "$p"; done)" ""
finish "r3 syntax and data checks"
