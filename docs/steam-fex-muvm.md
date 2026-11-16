# Steam / FEX / muvm feasibility on the K114s (issue #29)

Status: **unsupported until** the items under "Blockers" are proven. Nothing here was installed or run;
every fact below is a read-only check on the running r3a kernel on 2026-11-15 (agent-run) unless it
says otherwise.

## How the M1/M2 path works (upstream-reported)

`omarchy-steam-fex` starts Steam (x86) under FEX inside a `muvm` microVM (libkrun, KVM). GPU access
inside the VM goes through virtio-gpu with DRM native context: the guest Mesa talks to the host's
DRM render node through virglrenderer's Asahi renderer. The host needs 16K pages, KVM and a render
node whose uAPI virglrenderer understands.

## Findings

| Check | Result | Verdict |
|---|---|---|
| Host page size (`getconf PAGESIZE`, `CONFIG_ARM64_16K_PAGES=y`) | 16384 | meets muvm |
| `/dev/kvm` | present; kernel log: all CPUs started at EL2, `kvm [1]` initialises, nested-virt trap tables loaded | KVM available |
| KVM caveats in dmesg | "Non-architectural vgic", "GICv3 sysreg trapping enabled (reduced performance)", "Known broken GICv3 SEIS implementation" | works, slower; guest boot is untested |
| `CONFIG_KVM=y`, `CONFIG_KVM_GUEST_MEMFD=y`, `CONFIG_VHOST_VSOCK=m` | set | ok |
| `CONFIG_DRM_ASAHI=y`, `DRM_ASAHI_M5` not set, `DRM_ASAHI_G18` not set | host driver is the aurora driver; `/dev/dri/renderD128` is the render node | see Blockers |
| `CONFIG_DRM_VIRTIO_GPU` | not set | host side does not need it; the guest kernel is libkrunfw's |
| Packages (`pacman -Si`) | `omarchy-steam-fex 1.0.0-4`, `steam 1.0.0.87-2` (omarchy; `steam` 20241231-4 (any) is also in asahi-alarm, and pacman takes the omarchy one because `[omarchy]` is listed before `[asahi-alarm]` in pacman.conf; the owner trial must confirm with `pacman -Si steam`); `muvm 0.7.0-1`, `FEX-Emu 2604-1`, `fex-emu-rootfs-arch`, `mesa-fex-emu-overlay-{x86_64,i386}` (asahi-alarm); `libkrun 1.19.8`, `libkrunfw 5.6.2`, `virglrenderer 1.3.0` (extra); all aarch64 | all installable |
| Installed now | none of steam, muvm, FEX, libkrun | nothing to remove |
| Host Mesa | `mesa-aurora 26.3.0_devel.20261109.j714s2`, needs `ASAHI_M5_BRINGUP=1`; Vulkan device `Apple M5 Pro (G17S B1)` (docs/r3-gpu-result.md) | Vulkan on host is only an off-screen probe |

## Blockers

1. **Native context on the aurora uAPI is unproven.** Whether `virglrenderer` 1.3.0 (extra, generic
   build) includes the Asahi DRM renderer, and whether that renderer speaks aurora's uAPI on a T6050
   (G17S) device, could not be read from the package metadata (`pacman -F` databases are not synced
   and syncing writes to the system). No upstream PR in aurora-silicon/aura mentions FEX, steam or muvm.
   This is the upstream question below.
2. **Vulkan proof on the desktop** (separate parity item): the host render node works for GL and an
   off-screen Vulkan probe, not yet for games.
3. **KVM guest boot** is unproven on T6050 (GIC virtualisation is in the reduced-performance
   sysreg-trapping mode here). The K116s KVM work (linux #1728, J813) is the reference.
4. Risk: a muvm or GPU hang may need a power-cycle (owner-needed).

## Support statement (for the matrix, owner to merge)

Steam via FEX/muvm: **unsupported until** an owner trial shows `muvm` boots a guest on this kernel and
native-context GPU access works against the aurora render node. Prerequisites in place: 16K pages,
`/dev/kvm`, all packages available. Missing: proof.

## Owner trial (stages, stop at the first failure)

Run `bash tests/hardware/k114s-steam-fex-probe.sh` first; it is read-only and needs no install. It reads the kernel log with plain `dmesg` and falls back to `sudo -n dmesg`.
Stage 2 (install `muvm`, `FEX-Emu`, `omarchy-steam-fex`, hold them) and stage 3 (launch Steam) wait for a go
and for Vulkan proof.
