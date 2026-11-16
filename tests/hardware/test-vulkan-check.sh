#!/bin/bash
# Software test of k114s-vulkan-check.sh with stub tools and a fake environment (no GPU, no window).
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
mkdir "$t/bin"
for c in bash sh grep sed timeout; do ln -s "$(command -v $c)" "$t/bin/$c"; done
cat >"$t/bin/vulkaninfo" <<'S'
#!/bin/sh
case "$1" in --summary) echo "	deviceName = Apple M5 Pro (G17S B1)";; *) echo "queueFlags = QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT | QUEUE_TRANSFER_BIT";; esac
S
printf '#!/bin/sh\nexit 0\n' >"$t/bin/vkcube"; chmod +x "$t/bin"/vulkaninfo "$t/bin"/vkcube
run() { env_txt=$1; shift; PATH=$t/bin K114S_VK_ENV=$env_txt bash "$here/k114s-vulkan-check.sh" "$@" 2>&1; }
out=$(run $'ASAHI_M5_BRINGUP=1\nHOME=/x'); rc=$?
[[ $rc -eq 0 && $out == *"PASS vulkaninfo lists"* ]] && ok "native desktop passes" || bad "native desktop rc=$rc"
out=$(run $'ASAHI_M5_BRINGUP=0'); rc=$?
[[ $rc -eq 1 && $out == *"FAIL ASAHI_M5_BRINGUP"* ]] && ok "bring-up 0 fails" || bad "bring-up 0 rc=$rc"
out=$(run $'ASAHI_M5_BRINGUP=1' --after-zink); rc=$?
[[ $rc -eq 1 && $out == *"FAIL MESA_LOADER"* ]] && ok "--after-zink without zink fails" || bad "after-zink rc=$rc"
out=$(run $'ASAHI_M5_BRINGUP=1\nMESA_LOADER_DRIVER_OVERRIDE=zink' --after-zink --vkcube); rc=$?
[[ $rc -eq 0 && $out == *"desktop runs through zink"* && $out == *"vkcube ran"* ]] && ok "zink desktop plus vkcube passes" || bad "zink rc=$rc"
out=$(run $'ASAHI_M5_BRINGUP=1\nLIBGL_ALWAYS_SOFTWARE=1'); [[ $out == *"FAIL software rendering"* ]] && ok "forced software fails" || bad "software not caught"
[[ $fail -eq 0 ]] && echo "all ok"; exit $fail
