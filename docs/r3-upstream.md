# r3: upstream reports, drafted 2026-11-14

> Update, 2026-11-14: items 1, 1b, 2a to 2e and 3 have since been posted. URLs and read-back are
> in [r3-upstream-post.md](r3-upstream-post.md). The rest of this page is the drafting record.

Drafts of the reports [UPSTREAM.md](../UPSTREAM.md) calls for after the r2c boots. **Nothing here
had been posted when this was written.** Each destination's contributing rules, templates and AI policy were read, and
each was searched for an earlier report of the same thing. The exact texts are in
[`r3-upstream-drafts/`](r3-upstream-drafts/). Evidence labels as in UPSTREAM.md: owner-observed,
agent-run (a command run by the AI agent on the Mac), source read (a file read in the named
repository; no hardware claim).

## Summary

| # | Destination | Earlier report | Form | Decision |
| --- | --- | --- | --- | --- |
| 1 | aurora-silicon/linux [discussion 142](https://github.com/aurora-silicon/linux/discussions/142), as a reply under [our comment](https://github.com/aurora-silicon/linux/discussions/142#discussioncomment-19618807) | ours, no replies yet; no other K114s report or issue | reply | **post** |
| 1b | aurora-silicon/linux [#1568](https://github.com/aurora-silicon/linux/pull/1568) (open draft) | none for K114s; the PR says "verified on one board only" | comment, after 1 | **post** |
| 2a | betizzel/omarchy-m5 issues | none | new issue | **post** |
| 2b | betizzel/omarchy-m5 issues | README lists "`ufw.service` fails" without a cause; RFCOMM and PKCS8 not mentioned | new issue | **post** |
| 2c | aurora-silicon/speakerguardd issues | [#102](https://github.com/aurora-silicon/speakerguardd/issues/102) is a different delay (the switch test on a Mac with speakers) | new issue | **post** |
| 2d | betizzel/omarchy-m5 issues | none | new issue, after 2c | **post** |
| 2e | betizzel/omarchy-m5 issues | none | new issue, after 3 | **post** |
| 3 | omacom/omarchy issues (Bug form) | [#9853](https://github.com/omacom/omarchy/issues/9853) and PR [#9878](https://github.com/omacom/omarchy/pull/9878): same template copy, repositories instead of holds | new issue | **post** |
| 4a | pingdotgg/t3code [#11731](https://github.com/pingdotgg/t3code/issues/11731) (closed, not planned, "outside T3 Code") | this is the earlier report | comment | **post** |
| 4b | electron/electron issues | none found | new issue | **hold** |
| n/a | libyuv (Chromium tracker) | bug 558654023, fixed by libyuv `fab11704cda6` on 2026-09-09 | nothing to send | **hold** |
| n/a | omacom/omarchy, titlebars plugin loaded on a fork | [#17391](https://github.com/omacom/omarchy/issues/17391) is a real version mismatch being refused | nothing to send | **hold** |
| n/a | omacom/omarchy pull request for item 3 | | not written | **hold** |
| n/a | aurora-silicon/linux pull request with the K114s N1, USB-C and SMC nodes | | offered in item 1 | **hold** |

Why the holds:

- **4b.** Electron's AI Tool Policy (electron/governance `policy/ai.md`) requires a human in the
  loop and forbids agents posting issues by themselves. The draft is for the owner to read, check
  and file himself. It also has no Fiddle test case, which the form asks for.
- **libyuv.** Already reported and fixed upstream.
- **Titlebars at omacom.** The plugin's own version check is the guard; a fork that keeps the
  stock commit hash defeats it. The cause is in `hyprland-m5` (item 2a).
- **omacom pull request.** Keeping `IgnorePkg` across a refresh is a design choice: the script's
  purpose is to restore defaults, and the maintainers already give a hook for holds. Not "small
  and clearly correct", so it is proposed in the issue and left to them.
- **K114s device tree pull request.** UPSTREAM.md makes it depend on a USB device enumerating, and
  none has been plugged in. Kernel patches also need the owner's own `Signed-off-by`.

## Destination rules that shaped the drafts

| Destination | What was read | Consequence |
| --- | --- | --- |
| aurora-silicon/linux | `CONTRIBUTING.md`, the discussion's report template, `Documentation/process/coding-assistants.rst` | Template block kept; pass / fail / not tested per action; literal error lines, no log dumps; no `Signed-off-by` from an agent |
| betizzel/omarchy-m5 | README ("Open an issue"), issues 1, 3, 6, PRs 2, 4, 5, 7 | Issues are enabled and are the preferred route; the maintainer gathers patches himself and keeps authorship. No AI policy. No PR opened |
| aurora-silicon/speakerguardd | README, issue 102, `packaging/session/speakerguardd-gate` at `v2` `04169c44` | Plain issue, timing table and cause as in 102 |
| omacom/omarchy | `.github/ISSUE_TEMPLATE/bug.yml`, `AGENTS.md`, `default/agents/skills/omarchy/contributing.md` | "Validated bugs only"; body uses the form's two headings; AI-written reviews are normal there |
| omacom/omarchy-mac-pkgs, omarchy-mac-installer | `CONTRIBUTING.md`, `AGENTS.md`, `image-builder/builder/test_image_pin.py` | The pin is omarchy-mac-installer's, the refresh is omarchy's: reported at omarchy |
| pingdotgg/t3code | `CONTRIBUTING.md`, issue forms | "Help us find things we can close"; one comment on the existing issue, no new issue, no PR |
| electron/electron | bug form, `CONTRIBUTING.md`, governance `policy/ai.md` | Hold, see above |

## Facts corrected while preparing these

Checked on the Mac on 2026-11-14 (agent-run unless noted). Where they differ from the brief, the
drafts use these.

1. **Three boots, not two.** 13:51, 15:12 and 15:24 MST, all on the `K114S-R1` kernel.
2. **USB-C is "not tested", not "failed".** `dwc3-apple` is bound to both controllers and Type-C
   `port0`/`port1` exist. `dwc3-apple.c` at `a34d26c2` says it stays in `DWC3_APPLE_PROBE_PENDING`
   and defers the first dwc3 probe "until we get the first cable connected event". Nothing has been
   plugged in, so an empty `/sys/bus/usb/devices` says nothing yet. Plug a device into the
   left-front or right port before treating this as a fault.
3. **Wi-Fi band.** 5180 MHz on the 15:24 boot.
4. **ufw.** 25 rules fail, not four: 22 use `-m hl` and 3 use `-m rt`. The options are
   `CONFIG_NETFILTER_XT_MATCH_HL`, `CONFIG_IP6_NF_MATCH_HL` and `CONFIG_IP6_NF_MATCH_RT`. Router
   advertisements are being dropped and `wlan0` has no global IPv6 address. It also fails with the
   image's own kernel build (first boot, 2026-11-13).
5. **Speaker gate.** Upstream of the 15 s wait is aurora-silicon/speakerguardd, not betizzel's
   recipe. A local drop-in already skips the units on the 15:24 boot (userspace 46.3 s before, 1.2 s
   after).
6. **Titlebars.** Confirmed with `offsetof` against the installed headers (0x7b0, and 0x790 with
   the three members removed), and in the plugin: `inputIsValid()` passes `monitor + 0x7c0` and
   `+ 0x7d8`. All five recorded aborts have that frame. The image build installs both packages.
7. **libyuv.** The instruction is at virtual address `0x6b4754c`, file offset `0x6b3754c`. The
   function is `I210ToARGBRow_SME`. Fixed upstream; Chromium 155 and later have it; Electron 45.3.3
   (Chromium 156) has it; Electron 44.x (Chromium 152) does not. T3 Code nightly
   `0.1.10-nightly.20261114.4695` pins Electron 44.10.1.
8. **"dev branch".** Edge's `omarchy-dev 4.0.0.r7859.g9ac0883` is built from the default branch
   `quattro`; `origin/dev` last moved in September. The refresh script is the same in v4.5.0 and
   at `quattro` `2bab9efd`.
9. **Refresh hazard.** Omarchy already offers `pre-refresh-pacman` hooks for holds, and the
   test-image pin comes from omarchy-mac-installer's own image builder. Edge's
   `linux-aurora 7.2.11.aurora16-1` has 115 device trees, none for T6050.
10. **`update-verify` ran** at 14:12:14 during the incident; its output was not kept.

## Evidence behind each draft

| Draft | Claim | Label |
| --- | --- | --- |
| 1, 1b | Pointer and clicks with #1568 | owner-observed (13:51 and 15:12 boots) |
| 1, 1b | `Touch MT ready`, `magicmouse` bind, clamp line, 3 of 3 boots | agent-run |
| 1 | N1 functions enumerate; `wlan0` connects 3 of 3 boots; 5180 MHz, traffic counters | agent-run |
| 1 | `hci0` present and powered, nothing paired | agent-run |
| 1 | Fans, voltages, 276 temperatures, four at -127 °C, 20 flat at 25 °C | agent-run |
| 1 | Battery values; `manufacture_year` -95 lines | agent-run |
| 1 | 18 CPUs | agent-run |
| 1 | USB-C controllers bound, no root hub, no device tried | agent-run; driver behaviour is source read |
| 1 | Device tree and Stage 2 hashes | recorded by the apply tool (`manifests/`) |
| 2a | Five aborts, frame in `inputIsValid()` | agent-run |
| 2a | Offsets, commit hash, plugin disassembly | agent-run |
| 2a | Image installs both packages; Omarchy v4.5.0 loads the plugin | agent-run (`pacman.log`); source read |
| 2b | Three unset options; journal lines on four boots | agent-run |
| 2b | Recipe configs at `42edf84` | source read |
| 2c | 15 s per gate call, 30.3 s before logins, three boots | agent-run |
| 2c | Gate logic | source read; installed file identical to upstream |
| 2d | Install and boot through the admitted installer build | owner-observed |
| 2d | Trackpad failure lines on the stock kernel | agent-run (first boot's journal) |
| 2d | `omarchy-m5` patches apply at `42edf84` | agent-run (`git apply --check`), no build |
| 2e, 3 | Eight downgrades, hooks that ran | agent-run (`pacman.log`) |
| 2e, 3 | No T6050 tree in the channel kernel package | agent-run (cached package's file list) |
| 2e, 3 | Script behaviour, pin source | source read |
| 4a, 4b | Disassembly, CPU features, four crash records | agent-run |
| 4a, 4b | libyuv fix and where it landed | source read (libyuv history, Chromium and Electron `DEPS`) |

Nothing in these drafts is claimed to work because it compiled, and no fix is offered as tested:
the config change, the gate change, the three hyprland-m5 options and the refresh change are all
marked as not built or not run.

## Posting order and commands (for the lead; nothing has been run)

Bodies are the files in `r3-upstream-drafts/`. Three bodies carry placeholders to fill from the
previous post's URL: `LINK-DISCUSSION-REPLY` (1b), `LINK-SPEAKERGUARDD` (2d), `LINK-OMACOM` (2e).
After each post, read it back and record the URL in `ledger/outgoing.json`.

```sh
D=docs/r3-upstream-drafts
# 1  reply under our discussion comment
gh api graphql -f query='mutation($d:ID!,$r:ID!,$b:String!){addDiscussionComment(input:{discussionId:$d,replyToId:$r,body:$b}){comment{url}}}' \
  -f d=D_kwDOUcXvw84ApsKc -f r=DC_kwDOUcXvw84BK1v3 -F b=@$D/01-aurora-discussion-142-followup.body.md
# 1b after filling LINK-DISCUSSION-REPLY
gh pr comment 1568 -R aurora-silicon/linux --body-file $D/01b-aurora-pr1568-crosslink.body.md
# 2c
gh issue create -R aurora-silicon/speakerguardd --title "gate: with no sound node in the device tree every call waits the full 15 s, holding logins about 30 s on each boot" --body-file $D/02c-speakerguardd-gate-wait-no-sound-node.body.md
# 2a, 2b
gh issue create -R betizzel/omarchy-m5 --title "hyprland-m5 0.57.2-2 changes CMonitor's layout but reports stock Hyprland's commit, so the stock titlebars plugin loads and Hyprland aborts on a click" --body-file $D/02a-betizzel-hyprland-m5-plugin-abi.body.md
gh issue create -R betizzel/omarchy-m5 --title "linux-aurora recipe config: ufw's IPv6 rules cannot load (no hl/rt matches), no RFCOMM, no pkcs8_key_parser" --body-file $D/02b-betizzel-kernel-config-gaps.body.md
# 3
gh issue create -R omacom/omarchy --title "Apple Silicon: channel switch and refresh pacman drop IgnorePkg holds, then downgrade the kernel, m1n1 and U-Boot unattended" --body-file $D/03-omacom-omarchy-refresh-drops-ignorepkg.body.md
# 2d after filling LINK-SPEAKERGUARDD, 2e after filling LINK-OMACOM
gh issue create -R betizzel/omarchy-m5 --title "K114s (14-inch OLED, M5 Pro) on release 3: what works, and apple,k114s installer admission on offer" --body-file $D/02d-betizzel-k114s-report-and-admission.body.md
gh issue create -R betizzel/omarchy-m5 --title "A channel switch or omarchy refresh pacman removes the image's IgnorePkg pin and downgrades the kernel, m1n1 and U-Boot" --body-file $D/02e-betizzel-channel-refresh-drops-pin.body.md
# 4a
gh issue comment 11731 -R pingdotgg/t3code --body-file $D/04a-t3code-11731-comment.body.md
```

Item 4b is filed by the owner through Electron's web form, not by a command.

## Suggested registry rows (the lead owns UPSTREAM.md and the ledger)

- "HID product 0x0361 for the Trackpad26 gate of #1830": stays `candidate`. r1a has not booted.
- "K114s N1, USB-C and SMC device tree sections": N1 and SMC are `hardware-confirmed`; USB-C is
  not. Offered in item 1; a pull request waits for a USB device and the owner's sign-off.
- "`apple,k114s` admission in the installer build": dependency met; item 2d.
- New rows for 2a, 2b, 2c, 2e, 3 and 4a.

## Risks

- Nine posts to five repositories from one account in one sitting can read as automation. Each says
  it was written by an AI agent. Spacing them, or folding 2a and 2b into 2d, is a fair alternative.
- Item 3 reports a first-party mechanism seen on a third-party image and an unsupported model.
  The body says so in its first lines; maintainers may still close it as unsupported.
- Item 4a comments on a closed issue. It adds the owner, the fix and the versions, which the
  thread lacks.
- The T6050 claim about the channel kernel was read from the package this Mac cached on
  2026-11-14. A later channel kernel may differ.
