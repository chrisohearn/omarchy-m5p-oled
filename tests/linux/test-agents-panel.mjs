import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";

const patch = new URL("../../patches/omarchy/0002-agents-panel-room-left-pace-and-model-rows.patch", import.meta.url);
const base = new URL(patch.href.replace(/\.patch$/, ".base/share/omarchy/shell/plugins/agents/Panel.qml"));
const bridge = new URL("../../patches/omarchy-stable/0002-stable-agents-account-provider.patch", import.meta.url);

function applyPatch(source, patchFile) {
  return execFileSync("patch", ["-s", "-f", "-F0", "-o", "-", source, fileURLToPath(patchFile)], { encoding: "utf8" });
}

function stablePanel() {
  const directory = mkdtempSync(join(tmpdir(), "agents-panel-test-"));
  try {
    const source = join(directory, "Panel.qml");
    writeFileSync(source, applyPatch(fileURLToPath(base), patch));
    return applyPatch(source, bridge);
  } finally {
    rmSync(directory, { recursive: true });
  }
}

const panel = process.argv[2] ? readFileSync(process.argv[2], "utf8") : stablePanel();
assert.doesNotMatch(panel, /root\.displayWindows\(\{ limits: accountBlock\.modelData/);
const functions = [
  "needsSignIn", "usageNote", "windowIsLong", "windowSpanMs", "windowTitle",
  "limitWindow", "windowTitleSpanMs", "limitWindows", "scopedPart", "displayWindows",
  "resetMsFor", "leftShare", "paceLeftShare", "applyWeeklyCap",
];
if (panel.includes("function signedOut(")) functions.push("signedOut");
const now = Date.parse("2026-01-01T10:00:00Z");
const root = { nowMs: now, clamp: (value, min, max) => Math.max(min, Math.min(max, value)) };
const { displayWindows, leftShare, paceLeftShare, usageNote } = runInNewContext(
  functions.map(name => {
    const source = panel.match(new RegExp(`^  function ${name}\\([\\s\\S]*?^  }`, "m"));
    assert.ok(source, `Missing panel function ${name}`);
    return source[0];
  }).join("\n") + "\n({ displayWindows, leftShare, paceLeftShare, usageNote })",
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
const session = (providerId, record) => displayWindows({ providerId, ...record }, record)
  .find(window => window.title === "Session");

const exhausted = snapshot(0, 1, "");
assert.equal(leftShare(session("claude", exhausted)), 0, "weekly exhaustion overrides apparent session headroom");
assert.equal(session("claude", exhausted).resetAt, "", "a missing session clock does not predict a reset");
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
