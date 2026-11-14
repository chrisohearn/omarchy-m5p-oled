# omarchy-hyprland-titlebars, rebuilt for hyprland-m5

The channel's `omarchy-hyprland-titlebars` is compiled against stock Hyprland headers. On a
machine that runs betizzel/omarchy-m5's `hyprland-m5` it loads, and takes the compositor down on
the first click on a floating workspace. This directory builds the same plugin source against the
installed `hyprland-m5` headers, as a pacman package that replaces the channel's and is not
replaced by it. The full account is in `docs/r3-titlebars.md`.

| File | What it is |
| --- | --- |
| `PKGBUILD` | the package: `omarchy-hyprland-titlebars 1:0.4.0+m5-1`, depends on `hyprland-m5=0.57.2-2` |
| `abi-probe.cpp` | compiled (never run) during the build: the `Monitor::CMonitor` offsets the plugin sees; does not compile against stock headers |
| `build.sh` | builds the package as a normal user, in an emptied environment, into a directory you name |
| `nested-test.sh` | runs the plugin's own verifier against a `titlebars.so` in a disposable nested Hyprland, with a layer surface so that the fault shows |
| `titlebars-abi-check` | says whether the installed `titlebars.so` was compiled against the installed Hyprland binary; `--disarm` moves a mismatched one aside |
| `02-k114s-titlebars-abi.hook` | optional pacman hook that runs `titlebars-abi-check --disarm` after the plugin or Hyprland changes |
| `test-abi-check.sh` | tests of `titlebars-abi-check` in throwaway roots |

## Build (no root)

```bash
packaging/omarchy-hyprland-titlebars-m5/build.sh ~/k114s-build/titlebars
```

Needs `base-devel`, `cmake`, `pkgconf` and the installed `hyprland-m5` (its headers are in
`/usr/include/hyprland`). The build stops when the headers are not `hyprland-m5 0.57.2-2` or when
`Monitor::CMonitor` is not laid out as the recipe expects. The package file name contains a colon
(the epoch); quote it.

## Test before it goes anywhere near the session's compositor (no root)

```bash
d=$(mktemp -d)
bsdtar -xf ~/k114s-build/titlebars/pkg/omarchy-hyprland-titlebars-1:0.4.0+m5-1-aarch64.pkg.tar.xz -C "$d"
packaging/omarchy-hyprland-titlebars-m5/nested-test.sh "$d/usr/lib/omarchy-hyprland-titlebars/titlebars.so"
```

A 1280x800 window opens for about half a minute and closes again. Ten `PASS` lines and
`nested-test: PASSED` is the result to expect. The channel's build fails the same test at the
first titlebar press, with a crash report of the nested Hyprland in the artifacts directory.

## Install (root, the lead's step)

Installing arms it: Omarchy loads `/usr/lib/omarchy-hyprland-titlebars/titlebars.so` the next
time a workspace floats. See "Install and rollback" in `docs/r3-titlebars.md`.

## When to rebuild

Whenever `hyprland-m5` changes, even by a pkgrel: pacman will refuse to upgrade it while this
package depends on the old one. Read the new headers against the old (`diff -r`), move
`_hyprland_ver` and, when `Monitor::CMonitor` moved again, the `_abi_` values in the `PKGBUILD`,
bump `pkgrel`, build, run `nested-test.sh`, install both in one transaction. A new plugin release
moves `_plugin` and its checksum, and the pinned tag in `nested-test.sh`.

## Provenance

The recipe follows omacom/omarchy-pkgs `pkgbuilds/omarchy-hyprland-titlebars` (MIT, Ryan Hughes
and Omarchy contributors). The plugin source is omacom/omarchy-hyprland-titlebars `v0.4.0`
(a fork of Hypr Development's hyprbars, BSD-3-Clause, with Omarchy's changes under MIT); it is
downloaded at build time, unchanged, and not kept in this repository. `nested-test.sh` runs that
repository's `tools/verify.py` with two additions made at run time. Everything else here is this
repository's, MIT.
