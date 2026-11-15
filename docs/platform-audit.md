# Platform audit: first boot, startup disk, snapshots, factory reset

Issues #63, #64, #68 and #69 (Omarchy Apple Silicon parity map, 2026-11-15). Everything here was
read off the running K114s (agent-run, 2026-11-15) with read-only commands, some of them through
`sudo cat`, `sudo ls`, `sudo du`, `sudo lsinitcpio` and the verifier below run as root. Nothing was
written to the machine, no mount was made, nothing was started, enabled or rebooted. Evidence
labels: **agent-run**, **owner-observed**, **upstream-reported**, **replica** (a software test
against a fixture), **inferred** (read from code or state, not seen happening).

Versions read: `omarchy-mac` 0.2.3-2, `omarchy-mac-boot` 20261104-1, `aurora-bless` 0.4.4.aurora2-1,
`limine` 12.9.6-1, `limine-snapper-sync` 1.32.1-2, `snapper` 0.13.2-2, `omarchy-dev`
4.0.0.r7859.g9ac0883-1, kernel 7.3.0-17.v272-4.

## Summary

| Issue | Finding | Verdict |
| --- | --- | --- |
| #63 first boot | setup-system ran to its last line, first boot and owner provisioning both finished, no step failed. Three effects the baseline expects are not delivered on this Mac, none by a failure: Electron wrappers (the runtime has no helper), the Apple mpv default (another package owns the file), the Wi-Fi resume fix (the chip test cannot match the N1). | verifier written and run; **partly done** (the `installer/` patch audit against upstream was not part of this pass) |
| #64 startup disk | `aurora-bless` needs `/dev/mtd/by-name/nvram`. The booted tree has no flash node and no `nvram` alias; the K114s ADT has the NVRAM region, identical to the J775D's. Not the J714s or K116s: neither carries the node in this kernel base. | cause **found**; node **drafted, not built**; the write test is **blocked on the owner** |
| #68 snapshots | Limine has **no** snapshot entry, so no Snapshots boot is possible today. Each would cost a 77 MiB UKI on an ESP with 84 MiB free, and the pacman guard already wants 84 MiB free. `LIMIT_USAGE_PERCENT=85` is what refuses them. | a Snapshots boot is **not safe to enable** here; keep the limit at 85 |
| #69 factory reset | `@factory` exists. The reset would replace the Limine menu with the stock template (dropping the K114s repair entry), rebuild the boot files from the image, and erase the system. Its own kernel check should refuse here first, but only after several steps. | **hide it until qualified**: patch 0003 refuses the command on the K114s; the menu row needs a one-line user extension |

## First boot: omarchy-mac-setup-system and -setup-user (#63)

### Where they run

`omarchy-lifecycle-dispatch setup-system` (root, on every install, hardware rerun and image first
boot, with `image-first-boot` meaning no network) execs `/usr/bin/omarchy-mac-setup-system`.
`setup-user` runs as the user at the end of user finalization and again in first run, and
`post-install <browser|steam>` reruns `omarchy-mac-setup-user` after a browser install. All of it
exits at once unless `omarchy-hw-apple-silicon` passes.

### Every effect, and what this Mac shows

`tests/hardware/omarchy-mac-setup-verify.sh` checks each row (root for the ones marked R).

| Script | Effect it should leave | This Mac (agent-run, root, read-only) |
| --- | --- | --- |
| setup-system | `options brcmfmac feature_disable=0x82000` removed from `/etc/modprobe.d/brcmfmac.conf`; migration marker `1789172112-initramfs-pending` written only if it removed it | no quirk line; file absent; marker absent |
| setup-system | `/etc/mpv/mpv.conf`: an unedited copy of the earlier omarchy-mac default (sha256 `9e186dd8...`) is replaced by the current default (`hwdec=vaapi-copy`, `vo=gpu`, `gpu-sw=yes`) | **WARN**: the file is `omarchy-settings-dev`'s (`hwdec=auto-safe`), so tmpfiles never copied the Apple default and setup leaves a file it does not recognise. mpv decodes in software here; `gpu-sw=yes` is not set |
| setup-system | `omarchy-wifi-resume-fix.service` enabled plus marker `/var/lib/omarchy-mac/wifi-configured`, only where `wifi-supported` passes | unit disabled, no marker. `wifi-supported` matches Broadcom IDs `14e4:4425/4433/4434`; the N1 is `106b:1902`, so it can never pass here. Harmless: the unit's `ExecCondition` is the same test, and suspend is blocked anyway (docs/r3-sleep-lid.md) |
| setup-system | `speakersafetyd.service` preset applied once, marker `/var/lib/omarchy-mac/speaker-safety-configured` | marker present, unit `enabled`, state `inactive`: a local drop-in (`90-k114s.conf`) requires `/usr/share/speakersafetyd/apple/k114.conf`, which does not exist. Intended; the speakers stay muted until protection data exists (docs/r3-audio-protection.md). Nothing here changes that |
| setup-system | `wifi.backend=iwd` in NetworkManager (package file `20-omarchy-mac-wifi.conf`), iwd reads `/etc/iwd` then the omarchy-mac default (6 GHz joins off) | backend is iwd. iwd's environment points at `/usr/lib/omarchy-aurora/iwd-n1` instead: `omarchy-aurora-firmware`'s `30-aurora-n1-6ghz.conf` replaces the list on purpose (N1, 6 GHz on). INFO. 6 GHz is untried here (docs/matrix.md) |
| setup-system (R) | `wifi-iwd-profiles`: one iwd profile per saved NetworkManager WPA network | 1 iwd profile, 1 saved connection (R; names not read) |
| setup-system | `omarchy-cmd-electron-gl-wrap` wrappers in `/usr/local/bin` for Chromium, 1Password and Cursor, when installed | **WARN**: the runtime has no such helper, so the install log says "Skipping Electron launchers". Chromium 157 is installed and has no wrapper; that only matters where the GPU has no render node. Same for setup-user's desktop-entry repair |
| setup-system | Steam FEX launcher where Steam is installed (online only) | Steam not installed: N/A |
| setup-system | its last output (`systemctl cat`, `NetworkManager --print-config`, `appledrm` options) | in `/var/log/omarchy-install.log` (world-readable): present, then "Completed: platform-setup.sh" |
| first boot | `pending` gone, no `last-error`, keyring recorded, `/var/log/omarchy-mac-first-boot.log` ends in `committed` | all true (R for the log: 83 lines, no failure). `mac-first-boot/deferred-steps` is left behind: the encryption conversion token |
| owner provisioning | `/var/log/omarchy-provision-owner.log` ends in "first-boot setup complete" | true (R). Two lines match fail/error: unit text `Restart=on-failure` and one `cat: write error: Broken pipe`; the rest is mise's offline "no versions found" noise |
| package files | omarchy-mac, omarchy-mac-boot, aurora-bless | `pacman -Qkk`: 99, 127 and 8 files, 0 altered |
| setup-user | `--disable-features=AcceleratedVideoDecoder` in each Chromium-family `*-flags.conf` | present in `chromium-flags.conf` |
| setup-user | `omarchy-asahi-mic.service` linked into the user's `graphical-session.target.wants`, marker `mac-microphone-configured` | both present, unit active |
| setup-user | `omarchy-audio-watchdog.service` (package-wanted by the graphical session) | active |

Result of the run: `0 FAIL`, with the four WARN/INFO lines above. The only item that was not run is
`--mount-factory` (it mounts the btrfs top level, read only, and is for the owner; see #69).

### Running it again

```bash
tests/hardware/omarchy-mac-setup-verify.sh          # no root; per-user units too
sudo tests/hardware/omarchy-mac-setup-verify.sh     # adds the log tails and the iwd profile count
```

Read only. Output is counts and verdicts; log tails have UUIDs, hex and MACs masked. Test:
`tests/hardware/test-setup-verify.sh` (12 checks against a fixture root; a good fixture passes and
each effect turns into a FAIL when removed). The "earlier mpv default" branch cannot be built in a
fixture (it hashes a file this repository does not hold), so that one line is untested.

### Not done in this pass

The `installer/` patches were not re-audited against `omacom/omarchy-mac-installer` or betizzel
release 4. This Mac's own first boot is evidence that the installed image path works; it does not
audit the patches.

## Startup disk selection: aurora-bless (#64)

### What it expects (agent-run, from the binary and its help)

- Default device `/dev/mtd/by-name/nvram` (`-d/--device` overrides it). The string is in the
  binary beside `apple-nvram/src/mtd.rs`, `v1v2.rs` and `v3.rs`.
- To list or choose volumes it also reads the GPT of `/dev/nvme0n1`.
- Modes: `--get-boot`, `--set-boot NAME|INDEX`, `--set-boot-macos`, `--next` (next boot only),
  `--clear-next`, `--list-volumes`. A write fails with "Failed to save new nvram contents".
- Run without root it stops at "Failed to collect boot candidates, try running with sudo?"
  (agent-run). It was not run as root: even `--get-boot` first reads the disk and then the NVRAM.

### What the booted tree has (agent-run)

| Check | Result |
| --- | --- |
| `/proc/mtd` | three entries only: `aura_stage1.log`, `aura_stage2.log` and `adt` (type `ram`, from the loader). No `nvram` |
| `/dev/mtd/by-name/` | `adt`, `aura_stage1.log`, `aura_stage2.log` |
| `/proc/device-tree/aliases` | `atcphy1 atcphy2 bluetooth0 gpu serial0 wifi0`. No `nvram` alias |
| `/proc/device-tree/soc@200000000/spi@505118000` | present, compatible `apple,t6050-qspi`, `apple,t8140-qspi`, **`status = "disabled"`**, no `flash@0` child |
| `/proc/device-tree/chosen` | no `nvram-bank-count` or `nvram-bank-size` (the loader fills them only where the alias exists) |
| kernel config | `CONFIG_SPI_APPLE_QSPI=m`, `CONFIG_MTD_SPI_NOR=y`, `CONFIG_MTD_OF_PARTS=y`, `CONFIG_MTD_PARTITIONED_MASTER` not set. The module `spi-apple-qspi.ko` ships |

### What the K114s ADT has (agent-run, a copy of the `adt` partition read with `sudo cat`, kept outside the repository)

`/arm-io/qspi` (`qspi,qspimc`, register block `0x305118000`, chip select 0) has a child `spinor`
(`nor-flash,spi`) with a child `anvram` (`nvram,nor`): `reg = <0x700000 0xc0000>`, 12 banks of
64 KiB (`nvram-bank-count 12`, `nvram-bank-size 0x10000`), board-id 0x14, `nvram-raw 1`. That is
the same region and size the K116s-base tree uses for the J775D. The NVRAM payload was not read.

### What the other trees carry (agent-run, kernel tree `aurora-silicon/linux` at the K116s work copy)

Only `t6050-j775d.dts` has the node (alias `nvram`, `&qspi` enabled, `flash@0` `jedec,spi-nor`
at 25 MHz, single wire, partition `nvram@700000` `status = "disabled"` for the loader to fill). Its
comment says the controller's T8140 policy "admits programs and erases only inside this partition".
`t6050-j714s.dts`, `t6050-j716s.dts`, `t6050-k114s.dts` and `t6050-k116s.dts` carry no
NVRAM node. The issue's premise that the J714s and K116s trees have one is not what this base
shows; the laptops of the M1/M2 generation get theirs from `spi1-nvram.dtsi`, the T6050 desktop from
the J775D file.

### Draft node (NOT built, NOT linted, NOT booted)

For `dts/t6050-k114s-*.dtsi` or a K114s overlay, copied from the J775D file:

```dts
/ {
	aliases {
		nvram = &nvram;
	};
};

&qspi {
	status = "okay";

	flash@0 {
		compatible = "jedec,spi-nor";
		reg = <0>;
		spi-max-frequency = <25000000>;
		spi-rx-bus-width = <1>;
		spi-tx-bus-width = <1>;

		partitions {
			compatible = "fixed-partitions";
			#address-cells = <1>;
			#size-cells = <1>;

			nvram: partition@700000 {
				label = "nvram";
				reg = <0x0 0x0>;	/* filled by the loader from ADT anvram */
				status = "disabled";
			};
		};
	};
};
```

Open questions before anyone builds it (none answerable offline):

1. Does the **Aura** loader fill the partition (`dt_set_nvram`) the way m1n1 does? The J775D
   comment names m1n1 only. If it does not, the partition stays empty and the node does nothing.
2. The J775D file's `flash@0` has `reg = <0>`; its comment also says the flash is "spinor's CS0
   (second cell 0x19)". The K114s `function-spi_cs0` and `spinor` reg match, but nobody has
   booted a K114s tree with the controller on.
3. It exposes a writable window of the boot flash. docs/brightness-boot-stage.md already says this
   needs its own review. A wrong `--set-boot` write can need Recovery.

Verdict: the missing node is the cause (agent-run). Turning it on is a boot-affecting change for
the owner; it stays unbuilt here. Draft upstream report text is in the appendix.

## Snapshot boot entries (#68)

### State (agent-run, root read-only)

- `snapper` config `root`, two snapshots: #1 "K114s baseline image ... KEEP", #2 "BROKEN: mid Edge
  refresh 14:11, stock kernel, no holds: do not restore" (cleanup `number`, limit 5).
- `limine-snapper-sync` and `limine-snapper-watcher` active. `/etc/limine-snapper-sync.conf`:
  `LIMIT_USAGE_PERCENT=85`, `RESTORE_METHOD=replace`. `/etc/default/limine`: `ENABLE_UKI=yes`,
  `BOOT_ORDER="linux-aurora, *, *fallback, Snapshots"`.
- `/boot/efi/limine.conf` (the file this Mac reads): the repair entry block, then the Omarchy
  entry for `linux-aurora`. **No Snapshots section, no snapshot entry.**
  `limine_history/snapshots.json`: `lastSnapshotID 1`, `snapshotEntries []`. The journal for the
  sync service shows only start and stop lines.
- Both snapshot roots carry `usr/lib/modules/*/vmlinuz` and `pkgbase` `linux-aurora`, so a missing
  kernel is not what stops entries. #1 carries 7.3.0-17.v272-4 (the image's kernel); #2 carries
  7.2.11-16-1 (the stock kernel that broke the Mac). **The kernel on `/boot` is not the one in #1**:
  `pacman -Qkk linux-aurora` reports `vmlinuz` altered (sha256 and mtime), and `/boot/vmlinuz-linux-aurora`
  differs from snapshot #1's. This Mac boots a kernel of its own.
- The initramfs on `/boot` (listed with `lsinitcpio`) contains `omarchy-mac-snapshot-overlay`, its
  service and `overlay.ko`, so a snapshot root would get its tmpfs overlay (inferred from the unit;
  no snapshot has been booted).
  The snapshot-check hooks (04 and 99) and the Limine gate (05) are installed.

### What a Snapshots boot would use

A Limine snapshot entry (with `ENABLE_UKI=yes`) boots a UKI copy stored on the ESP per snapshot
(upstream-reported behaviour of limine-snapper-sync; not run here, the tool is a compiled program).
That UKI holds a kernel and an initramfs; it has **no device tree** (agent-run: sections of
`omarchy_linux-aurora.efi` are `.linux`, `.initrd`, `.cmdline`, `.osrel`, `.uname`, `.sbat` and
code, no `.dtb`). The device tree, Stage 2, U-Boot and the pinned K114s DTB live outside any
snapshot, on the ESP (`m1n1/`, `k114s-repair/`, `aurora/`); a snapshot boot reuses them. So the
Stage 2 and DTB do not move; what changes is the **kernel** (the image's, without this Mac's own
changes) and the **initramfs**.

### ESP budget (agent-run numbers, model by arithmetic)

ESP: 510,872 KiB; used 425,244 KiB (83.2 percent); free 85,628 KiB. Biggest users: `EFI/Linux`
187,604 KiB (two UKIs: 77,396 KiB and 109,204 KiB), `vendorfw` 110,232, `asahi` 88,144, `m1n1` 28,468.
The pacman guard `01-k114s-esp-space` needs 86,016 KiB (84 MiB) free, so **it already blocks every
package transaction by 388 KiB** (the same finding as docs/r3-integration.md; the free figure
there was 87.7 MB a day earlier).

| Snapshot UKIs of 77,396 KiB | Used | Free | At or under 85 percent | Pacman guard (86,016 KiB free) |
| --- | --- | --- | --- | --- |
| 0 | 83.2 % | 85,628 | yes | no (short by 388) |
| 1 | 98.4 % | 8,232 | **no** | no |
| 2 | 113.5 % | does not fit | no | no |

The 85 percent line leaves 8,997 KiB of headroom, so a single snapshot UKI exceeds it by about 68,400 KiB.
That is the most likely reason the sync has produced no entry (inferred, not proven: the tool was
not run). Holding one snapshot **and** the pacman guard needs 163,412 KiB free, 77,784 KiB more than
now.

### Is a Snapshots boot safe here?

**Not to enable.** Reasons, strongest first:

1. It cannot be had without breaking the ESP budget, and a full ESP is the 2026-11-14 incident's
   mechanism (a pruned snapshot UKI).
2. The entry would boot the image's kernel, not this Mac's; whether that kernel boots with the
   present Stage 2 and the pinned DTB has never been tried.
3. Snapshot #2 must never be offered: its kernel is the stock one that broke the Mac.
4. `omarchy-mac-snapshot-check` lets a restore through only from a snapshot booted from the Limine
   menu, which is the same dependency.

What holds today: the check hooks, the overlay unit and the gate are in place; `default_entry: 1`
is the kernel entry; `BOOT_ORDER` puts Snapshots last. Nothing offers a snapshot, so nothing can
boot one by mistake.

**`LIMIT_USAGE_PERCENT`: keep 85.** It is the thing refusing entries. Do not raise it: the
arithmetic above shows any value that admits one UKI (above 98.4) leaves 8 MiB free and breaks every
update. To make Snapshots usable, raise free space to about 163 MiB (163,412 KiB), that is about
76 MiB (77,784 KiB) more than now. That is an owner decision, not made here. Do not free it from
`vendorfw`: it holds `firmware.cpio`, `firmware.tar`, `manifest.txt` and a `u-boot` directory, the
Linux vendor-firmware bundle the initramfs uses (Wi-Fi, Bluetooth and others), not macOS data.
Deleting `omarchy_linux-aurora-k114s.efi` (109,204 KiB) would be enough on size alone, but it is
the kernel the `### K114s repair` Limine entry boots, this Mac's recovery route (see #69), so offer
that only once another recovery route exists.

### Replica or QEMU test

Not run. The replica route in this repository has no Limine-and-snapper layer; the check that
matters (the sync's decision under a full ESP) needs the compiled tool and a writable ESP, which
this pass may not touch. The arithmetic above is the model.

### Owner at the Mac (OWNER, writes and reboots; not run)

Only after the ESP has room. `systemctl reboot --boot-loader-menu` (checks that
`omarchy-mac-efi-vars` saved the variable) and one snapshot entry boot, with a forced power-off and
the default entry ready. Read first: `sudo cat /boot/efi/limine.conf`; `df /boot/efi`.

## Factory reset (#69)

### What the menu does (agent-run)

`Setup > Reset Computer` (`setup.reset`) is shown when `/` is btrfs. Its `when` is in
`/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc`, owned by `omarchy-settings-dev`. The action
runs `omarchy-system-factory-reset` (owned by `omarchy-dev`), which, in order:

1. mounts the btrfs top level (writable);
2. requires `@factory`, which **exists** here (subvolume 261, generation 17, so from the image's first boot);
3. asks the dispatcher whether the boot package owns the four reset operations (it does);
4. asks the owner to type `reset`;
5. masks `limine-snapper-sync`, clones `@factory`, scrubs identity and accounts, **edits
   `@factory` in place** (account scrub) and adds a temporary unlock key;
6. calls `reset-prepare`, `reset-verify`, swaps `@` for the clone, then `reset-commit`.

### What omarchy-mac-boot does against the K114s layout (inferred from the scripts; none of it run)

| Step | K114s consequence |
| --- | --- |
| `factory_kernel_coherent` | needs the factory root's `linux-aurora` `vmlinuz` byte-identical to `/boot/vmlinuz-linux-aurora`. `/boot` holds this Mac's own kernel, so for an image-built `@factory` it should **fail and refuse** ("The factory system's kernel differs"). Snapshot #1 (taken from the image) differs from `/boot`; `@factory` itself could not be read without a mount, so this is inferred. `--mount-factory` in the verifier answers it |
| `reset_limine_menu` | copies the stock `limine.conf` template over `/boot/efi/limine.conf`. The `### K114s repair` block (the repair entry that is this Mac's recovery route) is **dropped**; only the old machine-id's history directory is removed |
| `rebuild_factory_boot` | `mkinitcpio -P` and `omarchy-mac-boot-update` inside the factory root: new initramfs and UKI from the image's package set, with a kernel command line derived from the **factory** root's `/etc/default/grub`. This Mac's own kernel command-line edits (the K114s boot arguments) are local and would not be in it |
| `backup_live_boot_files` | copies `EFI/Linux` (187 MiB) and the initramfs to `/run` (tmpfs) for rollback; the ESP then needs room for a new UKI with 84 MiB free |
| `reset-verify` | checks the Limine menu names a matching UKI and, on an encrypted root, that the factory root's boot configuration will unlock the disk at the next boot (not evaluated here; inferred from the script) |
| kept | m1n1 and U-Boot ("a reset replaces neither firmware nor device trees"), so the Stage 2, `boot-ctxr.bin` and the pinned DTB survive |
| lost with `@` | everything local in the root: pacman holds and hooks (`00-k114s-hold-guard`, `01-k114s-esp-space`, `03-k114s-omarchy-patches`, `96-omarchy-j714s-boot-ctxr`), the `k114s-*` units, `/usr/local/lib/omarchy-k114s`, the local `/etc/default/grub` edit, the K114s package state. The ESP side stays, so the ESP and the root disagree afterwards |
| data | the reset scrubs the accounts, provisioning is armed with `wipe-pending`, and the prompt says it erases the system: treat it as losing the owner's accounts and data |

### Decision: hide it until qualified

Yes. It is destructive, has never run on this Mac, and its likely behaviour on this layout is either
a refusal after steps have already been taken (cloned `@factory`, edited the baseline, added an unlock
key, all rolled back by the script when it fails) or, if the kernel check were ever satisfied, a
boot menu without the repair entry. No part of it is a feature the owner is missing today.

How, in the style of docs/omarchy-patches.md:

- **Patch** `patches/omarchy/0003-factory-reset-off-on-k114s-until-qualified.patch`. It stops
  `omarchy-system-factory-reset` (an `omarchy-dev` file) when `/proc/device-tree/compatible`
  lists `apple,k114s` and `/etc/omarchy-k114s/factory-reset-qualified` does not exist, before sudo,
  before the top-level mount and before any question, with a message and exit 1. Only the K114s is
  affected. Create the marker, as root, after a qualified reset only.
- **The gate holds only while the patch still fits.** `linux/omarchy-patches-apply` prints "does not
  fit this Omarchy build ... Nothing was written" and exits 0 when an `omarchy-dev` update moves the
  lines around it. The command is then stock again, and the menu row would run the real reset. So
  the menu-row user extension below is a required companion step, not an optional one, and 0003
  should be re-checked after every Omarchy update (the verifier has no 0003 check; read the
  `sudo bash linux/omarchy-patches-install` output for "applied", or run
  `grep -q 'K114s local change: a factory reset' /usr/bin/omarchy-system-factory-reset`).
- **The menu row cannot be patched**, because the mechanism refuses files owned by
  `omarchy-settings-dev`. Omarchy has a user extension for exactly this. To hide the row, put this
  in `~/.config/omarchy/extensions/omarchy-menu.jsonc` (OWNER; not applied by this pass):

  ```jsonc
  "setup.reset": {"when": "false"}
  ```

  Without it the row stays visible; it prints the refusal only while 0003 fits.
- **Test** `tests/linux/test-factory-reset-gate.sh` (10 checks, replica: the patched copy of the
  installed command, with the device-tree and marker paths pointed at fixtures; the gate sits before
  sudo, a K114s without the marker stops with exit 1 and the message, with the marker or on another
  Mac or with no device tree it falls through to the next check). Also checked by hand in a fake
  root: `linux/omarchy-patches-install` installs 0003 as "applied" and `--undo` gives back the
  shipped file byte for byte (agent-run); `tests/linux/test-omarchy-patches.sh linux` passes (67).

Install is the owner's usual command (`sudo bash linux/omarchy-patches-install`), unchanged. It was
**not** installed on the Mac in this pass.

### Qualifying it later (OWNER; not run)

Prerequisites, all open: a full recovery set (the repair entry reachable from macOS, a second
copy of `/boot/efi`, `snapper` snapshots 1 and 2 kept, the owner's data off the Mac); the ESP freed
to more than the 84 MiB guard plus 77 MiB; `sudo tests/hardware/omarchy-mac-setup-verify.sh
--mount-factory` showing `@factory` carries the kernel on `/boot` (or the K114s kernel built into
the factory image); the K114s repair entry and local command-line edits carried by a reset-time
hook; a replica run of `reset-prepare` and `reset-verify` against the K114s boot files. Until
all of that is in, the marker file is not created.

## Appendix: draft upstream report (for the root to file; NOT filed)

Target: aurora-silicon/linux (K114s device tree) and aura (loader), or this repository's issue
tracker for the local tree.

> **t6050-k114s: NVRAM (boot NOR) not exposed, so asahi-bless/aurora-bless cannot select a boot volume**
>
> On a K114s (MacBook Pro 14", M5 Pro, `apple,k114s`), `aurora-bless` 0.4.4 looks for
> `/dev/mtd/by-name/nvram`. `/proc/mtd` lists only the loader's `aura_stage1.log`,
> `aura_stage2.log` and `adt`. The booted device tree has `spi@505118000`
> (`apple,t6050-qspi`) with `status = "disabled"`, no flash child and no `nvram` alias.
> The Apple device tree has the region: `/arm-io/qspi/spinor/anvram`, `reg = <0x700000 0xc0000>`,
> 12 banks of 64 KiB, the same as `t6050-j775d.dts` (the only T6050 tree that enables it).
> Question: does the Aura loader fill the `nvram` partition from the ADT as m1n1's `dt_set_nvram`
> does? If so, the J775D block (alias, `&qspi` enabled, `flash@0` with a fixed-partitions
> `nvram@700000`) is what the K114s tree needs; the controller policy limits writes to that
> partition. Not tested; this machine was not booted with it.
