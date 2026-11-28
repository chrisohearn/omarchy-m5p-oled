#!/bin/bash
# Exercise the modules CLI with a synthetic kernel and a stand-in for QEMU.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -r -- "$fixture" </dev/null' EXIT

obj=$fixture/obj
mkdir -p "$fixture"/{bin,logs} "$obj"/{arch/arm64/boot,include/config,source}
printf 'synthetic image\n' > "$obj/arch/arm64/boot/Image"
printf '7.3.0-fixture\n' > "$obj/include/config/kernel.release"
cat > "$fixture/env.sh" <<'ENV'
B=$K114S_BUILD_ROOT
kmake() { :; }
ENV

cat > "$fixture/bin/qemu-system-aarch64" <<'QEMU'
#!/bin/bash
printf 'unfiltered serial diagnostic\n' >&2
printf 'K114S-TEST modprobe ok=1 failed=1\n'
if [[ $SMOKE_MARKER == yes ]]; then
  printf 'K114S-TEST end\n'
fi
if [[ $SMOKE_QEMU_EXIT == timeout ]]; then
  exec sleep 30
fi
exit "$SMOKE_QEMU_EXIT"
QEMU

export SMOKE_REAL_TEE
SMOKE_REAL_TEE=$(command -v tee)
cat > "$fixture/bin/tee" <<'TEE'
#!/bin/bash
set -e
"$SMOKE_REAL_TEE" "$@"
exit "$SMOKE_TEE_EXIT"
TEE
chmod +x "$fixture/bin/"{qemu-system-aarch64,tee}

check() {
  local label=$1 qemu_exit=$2 marker=$3 expected=$4 tee_exit=${5:-0}
  local output=$fixture/$label.out log=$fixture/$label.log status=0
  local log_override=$log
  if [[ $label == emulator-error ]]; then
    log_override=
    log=$fixture/logs/qemu-smoke-failed.log
  fi

  PATH="$fixture/bin:$PATH" TMPDIR="$fixture" K114S_BUILD_ROOT="$fixture" \
    K114S_QEMU_TIMEOUT=2 K114S_QEMU_LOG="$log_override" \
    SMOKE_QEMU_EXIT="$qemu_exit" SMOKE_MARKER="$marker" SMOKE_TEE_EXIT="$tee_exit" \
    "$repo/build/native/k114s-qemu-smoke" modules "$obj" "$repo/build/qemu-test-init" \
    > "$output" 2>&1 || status=$?

  if [[ $status != "$expected" ]]; then
    cat "$output" >&2
    printf '%s: expected exit %s, got %s\n' "$label" "$expected" "$status" >&2
    exit 1
  fi
  if [[ $expected == 0 ]]; then
    grep -Fq 'k114s-qemu-smoke: PASS (modules run completed' "$output"
  else
    grep -Fq 'k114s-qemu-smoke: FAIL' "$output"
  fi
  grep -Fxq 'K114S-TEST modprobe ok=1 failed=1' "$output"
  grep -Fxq 'unfiltered serial diagnostic' "$log"
  if grep -Fxq 'unfiltered serial diagnostic' "$output"; then
    printf '%s: unfiltered serial leaked into the console output\n' "$label" >&2
    exit 1
  fi
  if [[ $marker == yes ]]; then
    grep -Fxq 'K114S-TEST end' "$log"
  fi
  printf '%s: wrapper exit %s (expected %s)\n' "$label" "$status" "$expected"
}

check success 0 yes 0
check emulator-error 1 yes 1
check emulator-timeout timeout yes 1
check missing-marker 0 no 1
check tee-error 0 yes 1 1

grep -Fq 'QEMU/timeout exit=1, tee exit=0' "$fixture/emulator-error.out"
grep -Fq 'QEMU/timeout exit=124, tee exit=0' "$fixture/emulator-timeout.out"
grep -Fq 'QEMU/timeout exit=0, tee exit=1' "$fixture/tee-error.out"
