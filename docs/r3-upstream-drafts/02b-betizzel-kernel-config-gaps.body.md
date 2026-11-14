_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction. "agent-run" marks a command the agent ran on that Mac; "source read" is a file read in this repository. One machine._

Three things fail at boot on the release 3 image because of options the `linux-aurora` recipe config leaves off. The same lines are still unset in `installer/recipes/linux-aurora/config`, `linux-aurora-j714s/config` and `linux-aurora-upstream/config` at `42edf84` (source read). Release 4 lists the same kernel package (`linux-aurora 7.3.0.aurora17.v272-4`); it was not run here.

The Mac is a K114s (MacBook Pro 14-inch OLED, M5 Pro), which this image does not support, booted with our own K114s device tree. None of the three depends on the board, but none has been checked on a J714s by us.

Where they were seen (agent-run, the journal of four boots of `7.3.0-17.v272-4-ARCH`):

- **Boot 1** ran the image's own kernel package as installed. Items 1 and 3 are in its journal. Item 2 is not: no Bluetooth controller came up on this Mac with that kernel, and bluetoothd logged nothing about RFCOMM. The package has no `rfcomm.ko`, `xt_hl.ko`, `ip6t_rt.ko` or `pkcs8_key_parser.ko` (`pacman -Ql linux-aurora`).
- **Boots 2 to 4** ran a local rebuild: the same source and `linux-j714s-27.2.patch`, the recipe's `config` unchanged, plus aurora-silicon/linux #1568 (trackpad). All three items are in each journal. Its `/proc/config.gz` has the same set options as `linux-aurora-j714s/config` at `omarchy-j714s-3`, compiler probes aside.

For comparison, Omarchy's own `linux-aurora 7.2.11.aurora16-1` has all of them: `xt_hl`, `ip6t_rt` and `rfcomm` as modules, `pkcs8_key_parser` built in (agent-run, that package's file list and `modules.builtin`).

## 1. `ufw.service` fails: the IPv6 rules need the `hl` and `rt` matches

The README and the release notes list "`ufw.service` fails" as a known gap. This is the cause on v272-4:

```
# CONFIG_NETFILTER_XT_MATCH_HL is not set
# CONFIG_IP6_NF_MATCH_HL is not set
# CONFIG_IP6_NF_MATCH_RT is not set
```

ufw 0.36.2's stock `/etc/ufw/before6.rules` uses `-m hl` in 22 rules (neighbour and router discovery among them) and `-m rt` in 3 (the RH0 drop). `ip6tables-restore` rejects the file as a whole:

```
ufw-init: Warning: Extension rt revision 0 not supported, missing kernel module?
ufw-init: Warning: Extension hl revision 0 not supported, missing kernel module?
ufw-init: ip6tables-restore v1.8.13 (nf_tables):
ufw-init: line 24: RULE_APPEND failed (No such file or directory): rule in chain ufw6-before-input
[...]
ufw-init: Problem running '/etc/ufw/before6.rules'
systemd: ufw.service: Failed with result 'exit-code'.
```

(`/usr/lib` is owned by root here, so this is not the earlier cause noted in `docs/installer-stones.md`.)

Effect seen (agent-run; the rule set itself was not listed, that needs root): the start script carries on after the error, so the firewall is partly up. IPv4 behaves as configured: blocks are logged and `ping 127.0.0.1` answers. On IPv6 the default-deny policy is in place without any of the "before" rules:

- `ping ::1` gets no reply. The loopback accept is line 20 of the same file and needs neither match.
- Router and neighbour advertisements are dropped (`[UFW BLOCK] IN=wlan0 ... PROTO=ICMPv6 TYPE=134` 28 times and `TYPE=136` 14 times in the 81 minutes of boot 2, and again on boots 3 and 4).
- The Wi-Fi interface has only a link-local IPv6 address and no IPv6 default route.

`configs/aurora-j714s-installer.config` already sets `CONFIG_NETFILTER_XT_MATCH_HL=y`, `CONFIG_IP6_NF_MATCH_HL=y`, `CONFIG_IP6_NF_MATCH_RT=y` and `CONFIG_IP6_NF_MATCH_IPV6HEADER=y`, so this looks like a gap in the recipe config only.

## 2. Bluetooth hands-free profiles: `CONFIG_BT_RFCOMM` is off

```
bluetoothd: src/profile.c:ext_start_servers() RFCOMM server failed for Hands-Free Voice gateway: socket(STREAM, RFCOMM): Protocol not supported (93)
bluetoothd: src/profile.c:ext_start_servers() RFCOMM server failed for Hands-Free unit: socket(STREAM, RFCOMM): Protocol not supported (93)
```

RFCOMM carries the control channel of the hands-free and headset profiles, so those cannot start (no headset microphone, no call audio). Not tried with a headset here: no device was paired. Suggested: `CONFIG_BT_RFCOMM=m` and `CONFIG_BT_RFCOMM_TTY=y`.

## 3. `pkcs8_key_parser` is missing: `CONFIG_PKCS8_PRIVATE_KEY_PARSER` is off

`iwd` ships `/usr/lib/modules-load.d/pkcs8.conf`, and every boot logs:

```
systemd-modules-load: Failed to find module 'pkcs8_key_parser'
```

iwd asks for the module for the private keys of certificate-based (enterprise) networks. The only effect observed here is the log line; no such network was tried. Suggested: `CONFIG_PKCS8_PRIVATE_KEY_PARSER=m` (or `=y`, as in Omarchy's kernel).

## Proposed change

Set in the three recipe configs, and add to each recipe's `j714s-required.config` so `validate-config.py` fails the build if Kconfig drops them:

```
CONFIG_NETFILTER_XT_MATCH_HL=m
CONFIG_IP6_NF_MATCH_HL=m
CONFIG_IP6_NF_MATCH_RT=m
CONFIG_BT_RFCOMM=m
CONFIG_BT_RFCOMM_TTY=y
CONFIG_PKCS8_PRIVATE_KEY_PARSER=m
```

Optional: `CONFIG_IP6_NF_MATCH_IPV6HEADER=m`. ufw's stock rules do not use it; it is named only because the installer config and Omarchy's kernel have it.

Status: not built or booted by us yet. A K114s kernel with these options is being prepared in https://github.com/chrisohearn/omarchy-m5p-oled; the result can be added here once it has booted.
