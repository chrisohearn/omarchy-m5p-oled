#!/bin/bash
# Headless Chromium GPU report for issue #28. Starts Chromium without a window (--headless=new, a
# temp profile, a random debugging port on loopback), reads the chrome://gpu feature status through
# the DevTools protocol, checks for GPU-process crash lines, and stops. With --software it repeats
# the run with LIBGL_ALWAYS_SOFTWARE=1 (the omarchy-mac wrapper path when no render node is usable)
# and expects hardware acceleration to be off. No window opens on the screen; nothing is installed
# or changed. Needs chromium, node (22+, for WebSocket) and curl.
#   chromium-gpu-report.sh             GPU run: expects Canvas, Compositing, Rasterization, WebGL hardware accelerated
#   chromium-gpu-report.sh --software  fallback run: expects software only
# Why not --dump-dom chrome://gpu: that prints only the unrendered page shell. Exit 0 = pass, 1 = fail, 2 = tool missing.
set -u
mode=gpu; [[ ${1:-} == --software ]] && mode=sw
for c in chromium node curl; do command -v "$c" >/dev/null || { echo "SKIP $c missing"; exit 2; }; done
tmp=$(mktemp -d) || exit 2
port=$((20000 + RANDOM % 20000))
cpid=
trap '[[ -n $cpid ]] && kill "$cpid" 2>/dev/null; sleep 1; rm -rf "$tmp"' EXIT
env=(); [[ $mode == sw ]] && env=(LIBGL_ALWAYS_SOFTWARE=1)
env XDG_CACHE_HOME="$tmp/cache" "${env[@]}" timeout -k 5 60 chromium --headless=new --enable-gpu --use-angle=gl-egl \
  --allow-chrome-scheme-url --user-data-dir="$tmp/prof" --no-first-run --remote-debugging-port=$port \
  --enable-logging=stderr --v=0 about:blank >/dev/null 2>"$tmp/err" &
cpid=$!
for _ in $(seq 20); do curl -s "localhost:$port/json/version" >/dev/null && break; sleep 0.5; done
curl -s -X PUT "localhost:$port/json/new?chrome://gpu" >/dev/null
sleep 6
cat >"$tmp/cdp.mjs" <<'J'
const t=(await (await fetch(`http://localhost:${process.argv[2]}/json`)).json()).find(x=>x.url.startsWith('chrome://gpu'));
const ws=new WebSocket(t.webSocketDebuggerUrl);
ws.onopen=()=>ws.send(JSON.stringify({id:1,method:"Runtime.evaluate",params:{expression:"document.querySelector('info-view').shadowRoot.textContent",returnByValue:true}}));
ws.onmessage=m=>{console.log(JSON.parse(m.data).result.result.value);process.exit(0)};
setTimeout(()=>process.exit(3),15000);
J
node "$tmp/cdp.mjs" "$port" >"$tmp/gpu.txt" 2>&1
txt=$(tr '\n' ' ' <"$tmp/gpu.txt" | sed 's/\*/\n/g')
echo "$txt" | grep -E '^ *(Canvas|Compositing|Rasterization|WebGL|WebGPU|Video Decode|Vulkan):' | sed 's/^ */  /'
tr -s '[:space:]' ' ' <"$tmp/gpu.txt" | grep -oE 'GL_RENDERER *:.{0,90}' | sed 's/GL_VERSION.*//; s/^/  /' | head -1
crash=$(grep -ciE 'gpu process (exited|crashed)|GPU process isn.t usable|Lost UI shared context' "$tmp/err")
echo "  GPU-process crash lines in the log: $crash"
fail=0
if [[ $mode == gpu ]]; then
  for f in Canvas Compositing Rasterization WebGL; do
    echo "$txt" | grep -qE "^ *$f: Hardware accelerated" && echo "PASS $f hardware accelerated" || { echo "FAIL $f not hardware accelerated"; fail=1; }
  done
  grep -qiE 'GL_RENDERER *:.*(SwiftShader|llvmpipe|softpipe)' "$tmp/gpu.txt" && { echo "FAIL software renderer in GPU mode"; fail=1; }
else
  echo "$txt" | grep -qE '^ *(Canvas|Rasterization): Software only' && echo "PASS software fallback is software" || { echo "FAIL fallback still accelerated"; fail=1; }
fi
[[ $crash -eq 0 ]] && echo "PASS no GPU-process crash lines" || { echo "FAIL GPU process crash lines"; fail=1; }
exit $fail
