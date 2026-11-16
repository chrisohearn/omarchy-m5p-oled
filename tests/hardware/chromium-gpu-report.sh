#!/bin/bash
# Headless Chromium GPU report for issue #28. Starts Chromium without a window (--headless=new, a
# temp profile, a loopback debugging port the browser picks itself), reads the chrome://gpu feature
# status through the DevTools protocol, checks for GPU-process crash lines, and stops. With --software
# it repeats the run with the environment the repo's 70-k114s-gpu-desktop guard sets (LIBGL_ALWAYS_SOFTWARE=1
# GBM_ALWAYS_SOFTWARE=1 ASAHI_M5_BRINGUP=0) and expects hardware acceleration to be off. No window opens
# on the screen; nothing is installed or changed. Chromium may still read ~/.config/chromium-flags.conf
# and touch ~/.pki/nssdb. Needs chromium, node (22+, for WebSocket) and curl.
#   chromium-gpu-report.sh             GPU run: expects Canvas, Compositing, Rasterization, WebGL hardware accelerated
#   chromium-gpu-report.sh --software  fallback run: expects software only
# Why not --dump-dom chrome://gpu: that prints only the unrendered page shell.
# Exit 0 = pass, 1 = fail, 2 = skipped (tool missing, or the session is already on the CPU guard).
set -u
mode=gpu; [[ ${1:-} == --software ]] && mode=sw
for c in chromium node curl; do command -v "$c" >/dev/null || { echo "SKIP $c missing"; exit 2; }; done
node -e 'process.exit(typeof WebSocket=="function"?0:1)' 2>/dev/null || { echo "SKIP node has no WebSocket (needs 22+)"; exit 2; }
if [[ $mode == gpu && ( ${LIBGL_ALWAYS_SOFTWARE:-} == 1 || ${ASAHI_M5_BRINGUP:-} == 0 ) ]]; then
  echo "SKIP this session is on the CPU guard (LIBGL_ALWAYS_SOFTWARE=1 or ASAHI_M5_BRINGUP=0); a GPU run would fail by design"; exit 2
fi
tmp=$(mktemp -d) || exit 2
cpid=
trap '[[ -n $cpid ]] && kill "$cpid" 2>/dev/null; sleep 1; rm -rf "$tmp"' EXIT
env=(); [[ $mode == sw ]] && env=(LIBGL_ALWAYS_SOFTWARE=1 GBM_ALWAYS_SOFTWARE=1 ASAHI_M5_BRINGUP=0)
env XDG_CACHE_HOME="$tmp/cache" "${env[@]}" timeout -k 5 60 chromium --headless=new --enable-gpu --use-angle=gl-egl \
  --allow-chrome-scheme-url --user-data-dir="$tmp/prof" --no-first-run --remote-debugging-port=0 \
  --enable-logging=stderr --v=0 about:blank >/dev/null 2>"$tmp/err" &
cpid=$!
port=
for _ in $(seq 40); do port=$(head -1 "$tmp/prof/DevToolsActivePort" 2>/dev/null); [[ -n $port ]] && break; sleep 0.5; done
[[ -n $port ]] || { echo "FAIL chromium opened no debugging port"; exit 1; }
curl -s -X PUT "localhost:$port/json/new?chrome://gpu" >/dev/null
cat >"$tmp/cdp.mjs" <<'J'
const t=(await (await fetch(`http://localhost:${process.argv[2]}/json`)).json()).find(x=>x.url.startsWith('chrome://gpu'));
const ws=new WebSocket(t.webSocketDebuggerUrl);
let id=0;
const ask=()=>ws.send(JSON.stringify({id:++id,method:"Runtime.evaluate",params:{expression:"document.querySelector('info-view')?.shadowRoot?.textContent||''",returnByValue:true}}));
ws.onopen=ask;
ws.onmessage=m=>{const v=JSON.parse(m.data).result.result.value;if(v.includes('Canvas:')){console.log(v);process.exit(0)}setTimeout(ask,500)};
setTimeout(()=>process.exit(3),20000);
J
node "$tmp/cdp.mjs" "$port" >"$tmp/gpu.txt" 2>&1
txt=$(tr '\n' ' ' <"$tmp/gpu.txt" | sed 's/\*/\n/g')
echo "$txt" | grep -E '^ *(Canvas|Compositing|Rasterization|WebGL|WebGPU|Video Decode|Vulkan):' | sed 's/^ */  /'
tr -s '[:space:]' ' ' <"$tmp/gpu.txt" | grep -oE 'GL_RENDERER *:.{0,90}' | sed 's/GL_VERSION.*//; s/^/  /' | head -1
crash=$(grep -ciE 'gpu process (exited|crashed)|GPU process isn.t usable|Lost UI shared context' "$tmp/err")
echo "  GPU-process crash lines in the log: $crash"
fail=0
if ! grep -q 'Canvas:' "$tmp/gpu.txt"; then
  echo "FAIL chrome://gpu page empty or unreadable"; fail=1
elif [[ $mode == gpu ]]; then
  for f in Canvas Compositing Rasterization WebGL; do
    echo "$txt" | grep -qE "^ *$f: Hardware accelerated" && echo "PASS $f hardware accelerated" || { echo "FAIL $f not hardware accelerated"; fail=1; }
  done
  grep -qiE 'GL_RENDERER *:.*(SwiftShader|llvmpipe|softpipe)' "$tmp/gpu.txt" && { echo "FAIL software renderer in GPU mode"; fail=1; }
else
  for f in Canvas Rasterization; do
    echo "$txt" | grep -qE "^ *$f: Software only" || { echo "FAIL $f still accelerated"; fail=1; }
  done
  echo "$txt" | grep -qE '^ *WebGL: Hardware accelerated' && { echo "FAIL WebGL still accelerated"; fail=1; }
  r=$(tr -s '[:space:]' ' ' <"$tmp/gpu.txt" | grep -oE 'GL_RENDERER *:.{0,90}' | head -1)
  [[ -z $r ]] || echo "$r" | grep -qiE 'SwiftShader|llvmpipe|softpipe' || { echo "FAIL GL_RENDERER is not a software renderer"; fail=1; }
  [[ $fail -eq 0 ]] && echo "PASS software fallback is software"
fi
[[ $crash -eq 0 ]] && echo "PASS no GPU-process crash lines" || { echo "FAIL GPU process crash lines"; fail=1; }
exit $fail
