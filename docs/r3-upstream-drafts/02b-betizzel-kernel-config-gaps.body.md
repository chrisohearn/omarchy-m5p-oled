_Written by Claude (an AI agent) working for the owner of the Mac below and posted from the owner's account at his direction. "agent-run" marks a command the agent ran on that Mac; "source read" is a file read in this repository. One machine._

Three things in the release 3 image fail on every boot because of options the `linux-aurora` recipe config leaves off. They were seen on four boots of `7.3.0-17.v272-4-ARCH`, the first of them with the image's own kernel package as installed (agent-run, `/proc/config.gz` and the journal). The same lines are still unset in `installer/recipes/linux-aurora/config`, `linux-aurora-j714s/config` and `linux-aurora-upstream/config` at `42edf84` (source read).

The Mac is a K114s (MacBook Pro 14-inch OLED, M5 Pro), which this image does not support. None of the three depends on the board, but none has been checked on a J714s by us.

## 1. `ufw.service` fails: the IPv6 rules need the `hl` and `rt` matches

The README lists "`ufw.service` fails" as a known gap. This is the cause on v272-4:

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
ufw-init: Problem running '/etc/ufw/before6.rules'
systemd: ufw.service: Failed with result 'exit-code'.
```

Effect seen: the IPv4 rules and the default-deny policy are active, but none of the IPv6 "before" rules exist, so IPv6 router advertisements are dropped (`[UFW BLOCK] IN=wlan0 ... PROTO=ICMPv6 TYPE=134`, twelve times in the first 24 minutes of one boot), and the Wi-Fi interface has no global IPv6 address.

`configs/aurora-j714s-installer.config` already sets `CONFIG_NETFILTER_XT_MATCH_HL=y`, `CONFIG_IP6_NF_MATCH_HL=y`, `CONFIG_IP6_NF_MATCH_RT=y` and `CONFIG_IP6_NF_MATCH_IPV6HEADER=y`, so this looks like a gap in the recipe config only.

## 2. Bluetooth hands-free profiles: `CONFIG_BT_RFCOMM` is off

```
bluetoothd: RFCOMM server failed for Hands-Free Voice gateway: socket(STREAM, RFCOMM): Protocol not supported (93)
bluetoothd: RFCOMM server failed for Hands-Free unit: socket(STREAM, RFCOMM): Protocol not supported (93)
```

RFCOMM carries the control channel of the hands-free and headset profiles, so those cannot start (no headset microphone, no call audio). Not tried with a headset here: no device was paired. Suggested: `CONFIG_BT_RFCOMM=m` and `CONFIG_BT_RFCOMM_TTY=y`.

## 3. `pkcs8_key_parser` is missing: `CONFIG_PKCS8_PRIVATE_KEY_PARSER` is off

`iwd` ships `/usr/lib/modules-load.d/pkcs8.conf`, and every boot logs:

```
systemd-modules-load: Failed to find module 'pkcs8_key_parser'
```

iwd asks for the module for the private keys of certificate-based (enterprise) networks. The only effect observed here is the log line; no such network was tried. Suggested: `CONFIG_PKCS8_PRIVATE_KEY_PARSER=m`.

## Proposed change

Add to the three recipe configs (and to `j714s-required.config`, so `validate-config.py` keeps them):

```
CONFIG_NETFILTER_XT_MATCH_HL=m
CONFIG_IP6_NF_MATCH_HL=m
CONFIG_IP6_NF_MATCH_RT=m
CONFIG_IP6_NF_MATCH_IPV6HEADER=m
CONFIG_BT_RFCOMM=m
CONFIG_BT_RFCOMM_TTY=y
CONFIG_PKCS8_PRIVATE_KEY_PARSER=m
```

Status: not built or booted by us yet. A K114s kernel with these options is being prepared in https://github.com/chrisohearn/omarchy-m5p-oled; the result can be added here once it has booted.
