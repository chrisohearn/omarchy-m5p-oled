#!/bin/bash
# K114s Widevine probe (issue #31). Read-only: checks the CDM files, then starts Chromium with a
# throwaway profile (mktemp, deleted on exit) and a local page on 127.0.0.1, and asks the page for
# the com.widevine.alpha key system over the DevTools protocol. Chromium on Linux only uses the
# component-registered CDM after a restart (first launch writes WidevineCdm/latest-component-updated-
# widevine-cdm in the profile, the next launch reads it), so the profile is warmed with one headless
# launch before the probed one. It plays nothing and touches no network.
#
#   k114s-widevine-probe.sh            headless Chromium (opens no window; agent-safe)
#   k114s-widevine-probe.sh --headed   a real Chromium window opens for a few seconds (owner run)
#
# Result lines: PASS (key system supported), FAIL (NotSupportedError after 20 s of retries), SKIP (tool missing).
# Exit status: 0 no FAIL, 1 FAIL. Needs node (global WebSocket, node 22 or newer) and chromium.
set -u
mode=--headless=new
case ${1:-} in "") ;; --headed) mode= ;; *) sed -n '2,12p' "$0"; exit 2 ;; esac
echo "== CDM files"
cdm=${WIDEVINE_ROOT:-}/usr/lib/chromium/WidevineCdm
lib=$cdm/_platform_specific/linux_arm64/libwidevinecdm.so
if [[ -f $lib ]] && file -L "$lib" | grep -q 'ARM aarch64'; then echo "PASS arm64 CDM present"; else echo "FAIL no arm64 CDM under /usr/lib/chromium"; exit 1; fi
grep -E '"version"|x-cdm-(codecs|host-versions)' "$cdm/manifest.json" | sed 's/^ */  /'
command -v node >/dev/null && command -v chromium >/dev/null || { echo "SKIP node or chromium missing"; exit 0; }
echo "== key system probe (${mode:---headed})"
exec node --input-type=module - "$mode" <<'JS'
import http from 'node:http';
import {spawn} from 'node:child_process';
import {existsSync, mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const sleep = ms => new Promise(r => setTimeout(r, ms));
const srv = http.createServer((q, r) => { r.setHeader('content-type', 'text/html'); r.end('<!doctype html><title>wv</title>'); });
await new Promise(r => srv.listen(0, '127.0.0.1', r));
const dir = mkdtempSync(join(tmpdir(), 'wv-'));
const args = ['--no-sandbox', '--user-data-dir=' + dir, '--remote-debugging-port=0', '--no-first-run', '--no-default-browser-check', 'about:blank'];
const warm = spawn('chromium', ['--headless=new', ...args], {stdio: 'ignore'});
for (let i = 0; i < 25 && !existsSync(join(dir, 'WidevineCdm', 'latest-component-updated-widevine-cdm')); i++) await sleep(200);
warm.kill(); await sleep(500); rmSync(join(dir, 'DevToolsActivePort'), {force: true});
if (process.argv[2]) args.unshift(process.argv[2]);
const ch = spawn('chromium', args, {stdio: 'ignore'});
let rc = 1;
try {
  let port;
  for (let i = 0; i < 50 && !port; i++) { try { port = readFileSync(join(dir, 'DevToolsActivePort'), 'utf8').split('\n')[0]; } catch { await sleep(200); } }
  const tabs = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => ws.onopen = r);
  let id = 0; const pend = {};
  ws.onmessage = m => { const d = JSON.parse(m.data); pend[d.id]?.(d); };
  const send = (method, params) => new Promise(r => { const i = ++id; pend[i] = r; ws.send(JSON.stringify({id: i, method, params})); });
  await send('Page.navigate', {url: `http://localhost:${srv.address().port}/`});
  await sleep(1000);
  const expr = `(async()=>{const c=ct=>[{initDataTypes:['cenc'],videoCapabilities:[ct]}];
const cfg={sw:c({contentType:'video/mp4; codecs="avc1.42E01E"',robustness:'SW_SECURE_CRYPTO'}),plain:c({contentType:'video/mp4; codecs="avc1.42E01E"'}),vp9:[{initDataTypes:['webm'],videoCapabilities:[{contentType:'video/webm; codecs="vp09.00.10.08"'}]}]};
for(let n=0;n<40;n++){const r={};for(const k in cfg){try{await navigator.requestMediaKeySystemAccess('com.widevine.alpha',cfg[k]);r[k]='ok'}catch(e){r[k]=e.name}}
try{await navigator.requestMediaKeySystemAccess('org.w3.clearkey',cfg.plain);r.clearkey='ok'}catch(e){r.clearkey=e.name}
if(r.sw==='ok'||r.plain==='ok'||n===39)return JSON.stringify({tries:n+1,secure:isSecureContext,...r});await new Promise(r=>setTimeout(r,500))}})()`;
  const r = JSON.parse((await send('Runtime.evaluate', {expression: expr, awaitPromise: true, returnByValue: true})).result.result.value);
  console.log('INFO ' + JSON.stringify(r));
  const ok = r.sw === 'ok' || r.plain === 'ok';
  console.log(ok ? 'PASS com.widevine.alpha key system supported' : 'FAIL com.widevine.alpha: ' + r.plain + (r.clearkey === 'ok' ? ' (clearkey works, so EME itself is fine)' : ''));
  rc = ok ? 0 : 1;
} catch (e) { console.log('FAIL probe error: ' + e.message); }
ch.kill(); srv.close(); rmSync(dir, {recursive: true, force: true});
process.exit(rc);
JS
