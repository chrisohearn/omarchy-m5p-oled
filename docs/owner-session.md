# Owner session

One guided pass over the manual hardware steps of the open K114s issues, about 30 to 45 minutes.

    bash tests/hardware/k114s-owner-session.sh [--section A|B|C|D|E] [--dry-run] [--self-test]

Run it from a checkout of `main` (or a worktree) at the Mac, inside the Hyprland session.

## What it does

- Sections: A no hardware handling, B pressing keys or watching, C plugging devices (power, USB, Bluetooth, headphones), D reboot items (listed only), E not runnable yet (listed only).
- For each step it shows what to do and the command. Enter does it, `s` skips, `q` quits. Then you give the result: `p` pass, `f` fail, `o` observed (a note for the issue), `s` skip. A command's exit status is the suggested result. You may add a one-line note.
- It calls the read-only scripts in `tests/hardware/` that are on the checkout. A step whose script is not there yet (it lives on an unmerged PR branch, now only chromium-gpu-report and titlebars-nested-check if your checkout is behind main) is reported MISSING and skipped; rerun after that PR merges, or from its branch.
- Steps with no script (plug, press, watch, install, pair) are prompts: you do them and report.
- At the end it prints a per-issue summary (`#N PASS|FAIL|PARTIAL|OBSERVED|NOT RUN|FOLDED INTO TRIAL BOOTS` with one line per step and your notes) to paste into the issues, and saves it as `summary-<time>.md`.

## What it never does

It never suspends, plays audio, pairs a device, reboots, or touches NVRAM or macOS. You pair, play music on a headset (never the speakers) and install by hand when a step says so. The timed CPU loads in the thermal and cpufreq steps are bounded and stop with the step. Two steps write state, both owner-confirmed: `k114s-charge-limit-test.sh run` (sets the SMC charge limit and writes `/etc/udev/macsmc-battery.conf`, and puts both back) and the hand steps you type yourself.

Reboot items are only listed, marked FOLDED INTO TRIAL BOOTS: fold them into the display trial boots (arm a one-boot way back first), so you reboot once or twice in total.

## Safety gates and session-ending steps

- The power-button press (#70) is offered only if the power-key policy check passes, and both key captures (#43, #44) only if logind `HandleSuspendKey`, `HandleSuspendKeyLongPress`, `HandlePowerKey` and `HandlePowerKeyLongPress` are all `ignore`, Hyprland binds no `XF86Sleep` or suspend/hibernate action, and `hyprctl` answers. The #44 capture also tells you not to press the moon key. Otherwise the step is skipped with the reason.
- Steps that end the desktop session (the CPU-rendered session in #7 and the Zink retry in #26) are listed after the summary is written, never run in the middle. The Zink retry points at `docs/vulkan-clients.md` "Owner step 2".
- The summary file is rewritten after every step, and Ctrl-C or a hang-up writes it before exiting, so a killed session still leaves a summary.
- Some target issues are closed. A pasted result may need the issue reopened or a comment on it.

## Log

`~/.local/state/k114s-owner-session/session-<time>.log`, directory mode 0700, file mode 0600. Everything written (command output, your notes, the summary) is redacted: MAC and IP addresses, e-mails, serials, network names (after SSID, with or without a colon, and iwctl `Connected network`), serial fields (`Serial`, `iSerial`, `ID_SERIAL`), UUIDs, long hashes, per-unit calibration file names, home paths, and the host and user names. Raw output only passes through a private temp file that is deleted on exit. Leftover temp files from a killed session are deleted at the next start. Read the summary once before pasting it anyway.

## Self-test

`bash tests/hardware/k114s-owner-session.sh --self-test` runs in a scratch directory: it checks the redactor, that no step line holds a suspend, reboot, NVRAM, playback or pairing command, and that a dry run exits 0, lists the commands, covers every issue, folds the reboot items, and writes a 0700 directory and a 0600 log. It ends with `RESULT: OK`.

`--dry-run` prints the whole plan and runs nothing; it writes its log and summary to a fresh temporary directory (or `K114S_OWNER_STATE`). With `--section X` only that section's issues appear in the summary.
