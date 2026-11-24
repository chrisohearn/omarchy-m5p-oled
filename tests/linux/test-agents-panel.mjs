import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";

const patch = new URL("../../patches/omarchy/0002-agents-panel-room-left-pace-and-model-rows.patch", import.meta.url);
const base = new URL(patch.href.replace(/\.patch$/, ".base/"));
const pluginPath = "share/omarchy/shell/plugins/agents";

function readPlugin(panelPath, mainPath = join(dirname(panelPath), "Main.qml")) {
  return [readFileSync(panelPath, "utf8"), readFileSync(mainPath, "utf8")];
}

function patchedBase() {
  const directory = mkdtempSync(join(tmpdir(), "agents-panel-test-"));
  try {
    cpSync(base, directory, { recursive: true });
    execFileSync("patch", ["-s", "-f", "-F0", "-p1", "-d", directory, "-i", fileURLToPath(patch)]);
    return readPlugin(join(directory, pluginPath, "Panel.qml"));
  } finally {
    rmSync(directory, { recursive: true });
  }
}

const [panel, main] = process.argv[2] ? readPlugin(process.argv[2], process.argv[3]) : patchedBase();
assert.match(main, /accounts: displayAccounts\(source\)/, "the panel receives provider-tagged account limits");

function functionSource(file, name) {
  const source = file.match(new RegExp(`^  function ${name}\\([\\s\\S]*?^  }`, "m"));
  assert.ok(source, `Missing function ${name}`);
  return source[0];
}

const displayAccounts = runInNewContext(functionSource(main, "displayAccounts") + "\ndisplayAccounts");
const functions = [
  "needsSignIn", "usageNote", "windowIsLong", "windowSpanMs", "windowTitle",
  "limitWindow", "windowTitleSpanMs", "limitWindows", "scopedPart", "displayWindows",
  "resetMsFor", "leftShare", "paceLeftShare", "applyWeeklyCap",
];
if (panel.includes("function signedOut(")) functions.push("signedOut");
const now = Date.parse("2026-01-01T10:00:00Z");
const root = { nowMs: now, clamp: (value, min, max) => Math.max(min, Math.min(max, value)) };
const { displayWindows, leftShare, paceLeftShare, usageNote } = runInNewContext(
  functions.map(name => functionSource(panel, name)).join("\n") + "\n({ displayWindows, leftShare, paceLeftShare, usageNote })",
  {
    root,
    helpDisplayText: value => value || "",
    statusDisplayText: value => value,
    Commons: { I18n: { t: (key, fallback) => fallback ?? key } },
  },
);

const sessionReset = "2026-01-01T13:00:00Z";
const weeklyReset = "2026-01-02T13:00:00Z";
const expired = "2026-01-01T09:00:00Z";
const snapshot = (sessionUsed, weekUsed, sessionEnd = sessionReset, weekEnd = weeklyReset) => ({
  limits: [
    { label: "Session (5-hour)", percent: sessionUsed, resetsAt: sessionEnd },
    { label: "Weekly (7-day)", percent: weekUsed, resetsAt: weekEnd },
    { label: "Fable Weekly", title: "Fable Weekly", percent: 0.25, resetsAt: weekEnd },
  ],
});
const session = (providerId, record) => displayWindows({ providerId, ...record })
  .find(window => window.title === "Session");

const exhausted = snapshot(0, 1, "");
assert.equal(leftShare(session("claude", exhausted)), 0, "weekly exhaustion overrides apparent session headroom");
assert.equal(session("claude", exhausted).resetAt, "", "a missing session clock does not predict a reset");
const nested = (providerId, account) => {
  const [row] = displayAccounts({ id: providerId, accounts: [account] });
  // Stable and earlier Edge use only the limits in the nested repeater.
  return displayWindows({ limits: row.limits }).find(window => window.title === "Session");
};
assert.equal(leftShare(nested("claude", exhausted)), 0, "a nested Claude row applies the weekly cap");
assert.equal(leftShare(nested("codex", exhausted)), 0, "a nested Codex row applies the weekly cap");
assert.equal(leftShare(nested("grok", exhausted)), 1, "another provider keeps its own windows");
assert.equal(exhausted.limits[0].providerId, undefined, "the collector record is never changed");
const single = displayWindows({ providerId: "claude", ...snapshot(0.4, 1) });
assert.equal(single[0].weeklyBlocked, true, "the session row is labelled as blocked");
assert.equal(single[0].resetAt, weeklyReset, "a later weekly reset controls the session");
assert.equal(paceLeftShare(single[0]), -1, "a blocked session has no pace marker");
assert.equal(leftShare(single[2]), 0.75, "standalone model allowances keep their own values");
assert.equal(session("codex", snapshot(1, 1, weeklyReset, sessionReset)).resetAt, weeklyReset);
assert.equal(session("codex", snapshot(0.6, 1, weeklyReset, sessionReset)).resetAt, sessionReset);
assert.equal(leftShare(session("claude", snapshot(0.4, 0.9))), 0.6);
assert.equal(leftShare(session("claude", snapshot(0.4, 1, sessionReset, expired))), 0.6);
assert.equal(leftShare(session("other", snapshot(0.4, 1))), 0.6);
assert.equal(usageNote({ stale: true }), "Showing the last known limits.");
assert.equal(usageNote({ limitsStale: true, authHelpText: "HTTP 429" }), "HTTP 429");
assert.equal(usageNote({ stale: true, usageStatusText: "Sign-in expired" }), "Sign-in expired");
assert.equal(usageNote({ stale: false, usageStatusText: "Sign-in expired" }), "");
assert.equal(usageNote({ stale: false }), "");
console.log("Agents panel quota checks passed");
