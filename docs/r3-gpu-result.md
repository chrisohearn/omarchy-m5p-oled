# GPU on the K114s: hardware result (2026-11-14)

The Apple GPU of the MacBook Pro 14-inch OLED, M5 Pro (`apple,k114s`, G17S) runs, and the Hyprland
desktop composites on it. This is step 2 of [r3-display-gpu.md](r3-display-gpu.md): the `r3-gpu`
device tree (r1 plus the GPU nodes only) with the **installed** loader and the **running** kernel.
No new kernel and no new loader were needed. The panel is still the boot framebuffer (60 Hz, no
brightness control); the display coprocessor is the next step.

Evidence labels: owner-observed, agent-run.

## What ran

| Piece | Value |
| --- | --- |
| Kernel | `7.3.0-17.v272-4-ARCH`, `K114S-R1` (unchanged) |
| Loader | aura `1.0.0b13-g22b71758-dirty` (unchanged) |
| Device tree | `dts/t6050-k114s-r3-gpu.dts`, built blob sha256 `2c870ba9f5963f5a…cda5` |
| Stage 2 | loader + that one tree + U-Boot, sha256 `9825a10317866865…b8fc`, 4,440,237 bytes |
| Mesa | `mesa-aurora` / `vulkan-aurora` `26.3.0_devel.20261109.j714s2` with `ASAHI_M5_BRINGUP=1` |
| Compositor | `hyprland-m5` 0.57.2-2, `aquamarine` 0.16.0 |

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| The tree against this Mac's Apple device tree (`tests/k114s-adt-display-facts.py --dtb`) | every GPU register and interrupt matches | agent-run, before the boot |
| Loader | admits the GPU: firmware build 26B8125, node `status = "okay"` | agent-run (`/proc/device-tree`) |
| Kernel | `aurora 2300000000.gpu: GPU firmware: 27.2 (26B8125), G17S`, `M5 primary/secondary initdata acknowledged`, `[drm] Initialized aurora 1.0.0`; `/dev/dri/renderD128` | agent-run (`dmesg`), four boots |
| Off-screen probe | OpenGL renderer `Apple M5 Pro (G17S B1)`; Vulkan device `Apple M5 Pro (G17S B1)`; through zink: `zink Vulkan 1.4(Apple M5 Pro (G17S B1) (AURORA_BOREALIS))` | agent-run |
| Nested Hyprland on the native OpenGL driver | ran 40 s, three clients on the GPU's DRM device, about 4 % of a core, no kernel messages | agent-run |
| Desktop session on the native OpenGL driver | Omarchy's renderer check reports `Apple M5 Pro (G17S B1)`; Hyprland about 6 % of a core, against about 300 % on llvmpipe; animations, blur and shadows back on | agent-run; "worked" owner-observed |
| Kernel log during all of it | no GPU fault, timeout or error line | agent-run |

Not tested: suspend (blocked on purpose, see below), sustained GPU load, power and thermals,
video decode, Vulkan clients, external displays.

## How it was tried: aura-try

The installed loader has a one-boot trial: a file `aura-try` at the root of the EFI partition
holding `armed\n<path>\n` makes the first loader stage boot `<path>` once in place of the
configured Stage 2. It marks the file `spent` before it reads the image, runs the trial under its
178-second watchdog and tells Linux through `chosen/aurora,trial`. A trial that hangs is reset onto
the configured image. So the proven `m1n1/boot-ctxr.bin` (sha256 `45a5dbef…`) was never
overwritten: the candidate sits beside it as `m1n1/boot-ctxr-r3-gpu.bin`.

`linux/gpu-desktop/stage2-rearm` (with `k114s-stage2-rearm.service`) re-arms the trial at every
clean shutdown, but only when the boot that is ending came up through that trial. A boot that fell
back, or a forced power-off, leaves the Mac on the proven Stage 2 until someone arms it again.
This is how the Mac keeps booting with the GPU today.

## What it took to get the desktop onto the GPU

Three separate things kept the session on llvmpipe while everything looked fine. Each cost a
desktop restart to find, so they are written down here.

1. **The session moves onto the GPU by itself, and a guard is needed first.** With one render
   node on the system, aquamarine gives the boot-framebuffer card the GPU's render node and
   Hyprland takes it. `linux/gpu-desktop/70-k114s-gpu-desktop` (a systemd user environment
   generator) keeps the session on the CPU unless `~/.config/k114s-gpu-desktop` exists, and
   `70-k114s-greeter-software.conf` keeps the SDDM greeter on the CPU (it gets no
   `ASAHI_M5_BRINGUP`, so Mesa would refuse the device and the greeter would not start).
2. **User environment generators run without `HOME`.** The first version of the guard looked for
   the opt-in under `$HOME`, never found it, and forced software rendering every time. It now
   resolves the home directory with `getent`.
3. **uwsm puts the old environment back.** At session stop uwsm restores the user manager's
   environment to its `env_pre` snapshot from before the first session of the boot. A change made
   with `systemctl --user unset-environment`, or by re-running the generators, is undone a second
   later, and `systemctl restart sddm` starts the next session with the old values. Only a fresh
   user manager picks up new generator output: `linux/gpu-desktop/gpu-desktop-restart` stops SDDM,
   ends the user's manager and starts SDDM again.

The zink route (`echo zink > ~/.config/k114s-gpu-desktop`) was tried once before points 2 and 3
were understood. That attempt ended in a black screen about three minutes in, when the shell could
not create a graphics context (`ZINK: vkEnumeratePhysicalDevices failed`,
`QRhiGles2: Failed to create context`). The environment still said `ASAHI_M5_BRINGUP=0` in that
session, which is enough to explain the Vulkan failure; zink has not been retried on the desktop
with a correct environment. The native driver is what runs now.

## Precautions in force

- **No suspend.** `suspend.target`, `hibernate.target`, `hybrid-sleep.target` and
  `suspend-then-hibernate.target` are masked. Without the mailbox-interrupt patches (#1844) a
  suspend with the GPU active is expected to hang or panic, and the refusal that stops suspend on
  this Mac today comes too late to protect the GPU.
- The proven Stage 2 stays the configured one.
- The driver prints "Experimental M5 HAL300 integration enabled; general rendering is
  unqualified". Treat rendering faults as possible.

## Install (root), as done on the machine

```sh
install -m 755 linux/gpu-desktop/70-k114s-gpu-desktop /etc/systemd/user-environment-generators/
install -m 644 linux/gpu-desktop/70-k114s-greeter-software.conf /etc/sddm.conf.d/
install -m 755 linux/gpu-desktop/stage2-rearm linux/gpu-desktop/gpu-desktop-restart /usr/local/lib/omarchy-k114s/
install -m 644 linux/gpu-desktop/k114s-stage2-rearm.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now k114s-stage2-rearm.service
systemctl mask suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
# the Stage 2 candidate next to the proven one, then the trial:
cp boot-ctxr-r3-gpu.bin /boot/efi/m1n1/ && sha256sum /boot/efi/m1n1/boot-ctxr-r3-gpu.bin
printf '%s\n%s\n' m1n1/boot-ctxr-r3-gpu.bin <sha256> > /etc/omarchy-k114s/stage2-trial
printf 'armed\nm1n1/boot-ctxr-r3-gpu.bin\n' > /boot/efi/aura-try && sync -f /boot/efi
```

After the GPU boot: `touch ~/.config/k114s-gpu-desktop`, then `gpu-desktop-restart` as root.
Check with `omarchy-hw-software-rendering --print` (exit status 1 and an "Apple M5 Pro" renderer
mean the GPU). Remove `70-k114s-greeter-software.conf` before the display coprocessor step, whose
greeter must use the GPU.

## Still to do

- Make `r3-gpu` the configured Stage 2 once it has soaked, and teach the macOS tool and the
  Stage 2 hook about it (both still pin the r1 tree).
- Kernel patches #1844, then lift the suspend block with the sleep work.
- The display coprocessor step: native mode, 120 Hz, brightness.
