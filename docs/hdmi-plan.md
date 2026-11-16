# HDMI output (issue #24)

Status: blocked on the display hand-off (issues #2, #17 and the D1-D9 trials). Everything that can be
done without it is done: the ADT matches the J714s route, and a disabled dts draft exists.

Evidence labels: agent-run, owner-observed, upstream-reported, source-read.

## What the hardware is

The K114s HDMI port is a fixed route, the same design as the J714s: `dcpext3` (the fourth external display engine)
-> the `atc3` display crossbar -> ATC3 used as a four-lane DisplayPort PHY
with no USB controller -> an on-board DP-to-HDMI converter. The converter's HPD is a GPIO, not a DPTX
signal, so the kernel forwards its IRQ_HPD service requests itself (betizzel patch 0019).

## Agent-run: this Mac's ADT against the J714s patch (2026-11-15)

`sudo python3 -I tests/k114s-adt-hdmi-facts.py` read the "adt" MTD partition, read-only. 20 of 20 facts hold:

| Fact | K114s ADT | J714s (betizzel 0017, from its ADT) |
|---|---|---|
| `/port-hdmi0` | present (port-type 6) | same |
| `atc3-dpphy` | `atc-dpphy,t602x`, port-type 6, dfp endpoint 3, port 0 | same |
| converter HPD | aop-gpio0 pin 14, interrupt (14, 0x05000004) | same |
| `force-dpfu` | aop-gpio0 pin 15 | same (left undescribed) |
| `hdmi_pwr_en` | pKW8('pcIO', 0x800000, 0xf0000) | same |
| `dp2hdmi_pwr_en` | pKW8('pcIO', 0x0, 0x1a0000) | same |
| `dcpext3` | ufp endpoint 3, port 0 (crossbar state 6) | same |
| ATC3 USB | none (no usb-drd3, `atc3-dpxbar` is `atc-dpxbar,t6050`) | none |
| `atc-phy3` | 21 tunable properties for the loader to fill | n/a |

Also read: `atc1-dpphy` and `atc2-dpphy` are port-type 2 (USB-C), so the K114s has the same three USB-C plus one
fixed-DP ATC layout.

The self-test (`python3 -I tests/k114s-adt-hdmi-facts.py --self-test`) proves the checker passes a made-up J714s
route and fails on a wrong HPD pin.

## The draft

`dts/t6050-k114s-hdmi.dtsi` (macro `K114S_R3B_HDMI`, included by nothing) is betizzel 0017 ported to our names.
It has not been compiled: this machine has no kernel tree. Points to settle at the first compile:

1. The K114s SMC pcIO list (see `t6050-k114s-sd.dtsi`) already holds both converter outputs: output 0 is
   `dp2hdmi_pwr_en`, output 1 is `hdmi_pwr_en`. The J714s file adds them at 2 and 1. The draft uses 0 and 1
   and adds no list. source-read from our files only.
2. Whether the K114-K116 base reserves AOP GPIO 14 (the J714s base does, and the file frees it).
3. `apple,t6050-dp-phy`, the `dcpext3` HDMI properties and the converter forwarder exist only in betizzel's v272
   series (r3b, v272-11, and later; not r3a).
4. The draft's reg windows are checked against the ADT's `atc-phy3` addresses (agent-run); the power-domain labels
   (`ps_atc3_usb_aon`, `ps_atc3_common`, `ps_atc3_phymxwrap`) and `usb_drd3` are J714s names, not checked against
   the K114-K116 base until the first compile.

## What it needs, in order

1. The DCP hand-off on the internal panel (display lane). The loader hands over a dcpext engine only for a
   pinned firmware image; the K116s 27.2 image is excluded for the external-engine path (aura #226).
2. r3b (v272-11 or v272-12) as the booted kernel, plus patches 0018 and 0019 (in the same series).
3. The loader filling the ATC tunables of a dp-phy node (aura 0011 of betizzel's set).
4. The draft included in an r3b display tree, then a monitor trial.

## Upstream

- J714s HDMI is TripleU613/FatBoy721's (betizzel/omarchy-m5 series 0017-0019, v2 hold); aurora-silicon/linux
  #1581 (J614s needs dcpext2) is open; aura #53 (HDMI PHY tunables) merged. Our work is porting and verifying.
- The one K114s fact worth telling betizzel: the ADT matches the J714s route on every checked point, so the
  J714s file should port with only the pcIO indices changed.

## Owner steps (only after the hand-off works and an HDMI tree exists)

1. With nothing in the HDMI port: `bash tests/hardware/k114s-hdmi-check.sh` (expect the connector present, status disconnected, "no sink seen"; "no HDMI connector" means this boot has no HDMI tree).
2. Plug a monitor or TV into the HDMI port; run the script again; note whether a picture appears, the monitor
   model, the cable, and whether the monitor was asleep when plugged.
3. Unplug and plug again; run the script again.
Nothing else is safe to run before the hand-off: HDMI is a display-engine boot trial like D4.
