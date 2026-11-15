#!/bin/bash
# SPDX-License-Identifier: MIT
# omarchy-m5p-oled: try a titlebars.so in a disposable nested Hyprland, never in the session's own.
#
#   nested-test.sh <titlebars.so> [--source DIR] [--artifacts DIR] [--no-layer]
#
# Runs the plugin's own verifier (omacom/omarchy-hyprland-titlebars tools/verify.py) with the
# installed Hyprland binary as a nested compositor: a normal window of the running session, with
# its own runtime directory, home, config and control socket. The verifier loads the library into
# that instance only, maps test windows in it and drives real pointer presses on their titlebars
# through a virtual pointer of the nested instance. A library built against the wrong Hyprland
# headers dies there on the first press, and takes only the nested instance with it.
#
# The verifier alone cannot see that fault: its nested instance has no layer surfaces, so the
# lists the plugin reads from the wrong place are empty either way. This script therefore also
# maps layer surfaces in the nested instance before the first press: a background one (a
# wallpaper) and a small one each on the top layer (the bar) and the overlay layer (notifications),
# the two lists the plugin's hit test walks (inputIsValid reads TOP and OVERLAY). The small ones
# sit in the bottom corners with no exclusive zone, so the verifier's geometry is unchanged.
# --no-layer leaves all three out.
#
# What it does to the session it runs in: one 1280x800 window appears for about half a minute and
# takes focus, as any newly opened window does. Nothing else: no hyprctl command is sent to the
# session's compositor, its config is not read or written, no systemd, D-Bus or logind call is
# made, Xwayland is off in the nested instance, and the nested Hyprland cannot leave a core dump
# or a crash notification (its crash report, if any, is copied to the artifacts directory).
#
# Needs no root. Needs: Hyprland hyprctl foot grim wayland-scanner cc python3, the gtk4 and
# gtk4-layer-shell development files (for the layer surfaces), and a Wayland session whose
# compositor offers zwp_linux_dmabuf_v1 (Hyprland does) and renders on the CPU: the GPU desktop's
# native driver cannot yet back a nested compositor (the script says so when that is why it failed).
set -euo pipefail

die() { echo "nested-test: $*" >&2; exit 2; }
PLUGIN_TAG=v0.4.0
PLUGIN_SHA256=275cef436530b3cd2e665b199d8df142e78fde4c00067d99676068e2c6f40e69
PLUGIN_URL=https://github.com/omacom/omarchy-hyprland-titlebars/archive/refs/tags/$PLUGIN_TAG.tar.gz

library='' source_dir='' artifacts='' layer=yes
while (($#)); do
  case $1 in
    --source) source_dir=${2:?}; shift 2 ;;
    --artifacts) artifacts=${2:?}; shift 2 ;;
    --no-layer) layer=no; shift ;;
    -h|--help) sed -n '3,31p' "$0"; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) [[ -z $library ]] || die "one library at a time"; library=$1; shift ;;
  esac
done
[[ -n $library && -f $library ]] || die "give the titlebars.so to test"
library=$(realpath "$library")
[[ -n ${WAYLAND_DISPLAY:-} && -n ${XDG_RUNTIME_DIR:-} ]] || die "run this inside the Wayland session (WAYLAND_DISPLAY, XDG_RUNTIME_DIR)"
for tool in Hyprland hyprctl foot grim wayland-scanner cc python3; do
  command -v "$tool" > /dev/null || die "$tool is missing"
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
artifacts=${artifacts:-$(mktemp -d -t titlebars-nested.XXXXXX)}
mkdir -p "$artifacts" "$work/home" "$work/tools"

# The verifier: from a checkout, or the release tarball this package is built from.
if [[ -z $source_dir ]]; then
  command -v curl > /dev/null || die "curl is missing (or pass --source DIR)"
  curl -fsSL -o "$work/plugin.tar.gz" "$PLUGIN_URL"
  echo "$PLUGIN_SHA256  $work/plugin.tar.gz" | sha256sum -c --quiet || die "the plugin tarball does not match its checksum"
  mkdir "$work/plugin"
  tar -xzf "$work/plugin.tar.gz" -C "$work/plugin" --strip-components=1
  source_dir=$work/plugin
fi
for file in verify.py pointer.c wlr-virtual-pointer-unstable-v1.xml; do
  [[ -f $source_dir/tools/$file ]] || die "$source_dir/tools/$file is missing"
  cp "$source_dir/tools/$file" "$work/tools/"
done

# Additions to the verifier, nothing taken out. In its nested config: no Xwayland (it would claim
# a display number in /tmp/.X11-unix), and none of the first-run dialogs a fresh home brings up.
# Before its first window: the layer surfaces, when NESTED_TEST_LAYER names their client.
cat > "$work/patch-verifier.py" <<'PATCH'
import sys

path = sys.argv[1]
text = open(path).read()
config_anchor = 'hl.monitor({ output = "", mode = "1280x800@60", position = "0x0", scale = 1 })\n'
config_extra = 'hl.config({ xwayland = { enabled = false }, ecosystem = { no_update_news = true, no_donation_nag = true } })\n'
window_anchor = "    terminal = subprocess.Popen(['foot', '--app-id=omarchy-titlebars-isolated-test'"
layer_step = """    if os.environ.get('NESTED_TEST_LAYER'):
      for namespace, layer in (('background', 'background'), ('top', 'top'), ('overlay', 'overlay')):
        subprocess.Popen([os.environ['NESTED_TEST_LAYER'], 'nested-test-' + namespace, layer], env=env, stdout=log, stderr=log)
      for namespace in ('background', 'top', 'overlay'):
        for _ in range(150):
          if 'nested-test-' + namespace in ctl('layers'):
            break
          time.sleep(.1)
        else:
          raise RuntimeError('The ' + namespace + ' layer surface did not map')
      print('nested-test: background, top and overlay layer surfaces mapped in the nested instance', flush=True)
"""
if text.count(config_anchor) != 1 or text.count(window_anchor) != 1:
    sys.exit('nested-test: the verifier changed, review nested-test.sh against it')
text = text.replace(config_anchor, config_anchor + config_extra).replace(window_anchor, layer_step + window_anchor)
open(path, 'w').write(text)
PATCH
python3 -I "$work/patch-verifier.py" "$work/tools/verify.py"

layer_client=''
if [[ $layer == yes ]]; then
  pkg-config --exists gtk4 gtk4-layer-shell-0 ||
    die "the gtk4-layer-shell development files are missing (--no-layer runs without them, but then proves little)"
  cat > "$work/layer.c" <<'C'
// A layer-shell client: layer.c NAMESPACE background|top|overlay. Background covers the output (a
// wallpaper); top and overlay are 20x20 in a bottom corner (the right one for top, the left one
// for overlay) with no exclusive zone, so no window the verifier places is moved or covered.
#include <gtk/gtk.h>
#include <gtk4-layer-shell.h>
#include <string.h>
int main(int argc, char **argv) {
  if (argc != 3) return 2;
  gtk_init();
  GtkWindow *window = GTK_WINDOW(gtk_window_new());
  gtk_layer_init_for_window(window);
  gtk_layer_set_namespace(window, argv[1]);
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  if (!strcmp(argv[2], "background")) {
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_BACKGROUND);
    for (int edge = 0; edge < GTK_LAYER_SHELL_EDGE_ENTRY_NUMBER; edge++)
      gtk_layer_set_anchor(window, edge, TRUE);
    gtk_layer_set_exclusive_zone(window, -1);
  } else if (!strcmp(argv[2], "top") || !strcmp(argv[2], "overlay")) {
    gtk_layer_set_layer(window, argv[2][0] == 't' ? GTK_LAYER_SHELL_LAYER_TOP : GTK_LAYER_SHELL_LAYER_OVERLAY);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
    gtk_layer_set_anchor(window, argv[2][0] == 't' ? GTK_LAYER_SHELL_EDGE_RIGHT : GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_exclusive_zone(window, 0);
    gtk_window_set_default_size(window, 20, 20);
  } else return 2;
  gtk_window_present(window);
  g_main_loop_run(g_main_loop_new(NULL, FALSE));
  return 0;
}
C
  # gtk4-layer-shell has to come before libwayland-client in the link order.
  # shellcheck disable=SC2046
  cc -O1 -o "$work/layer" "$work/layer.c" $(pkg-config --cflags gtk4 gtk4-layer-shell-0) -lgtk4-layer-shell $(pkg-config --libs gtk4)
  layer_client=$work/layer
fi

# A nested Hyprland that dies must not reach systemd-coredump: no core file, no journal entry, no
# "process crashed" notification in the session. Its own crash report still gets written.
cat > "$work/nodump.c" <<'C'
#include <sys/prctl.h>
__attribute__((constructor)) static void nodump(void) { prctl(PR_SET_DUMPABLE, 0); }
C
cc -shared -fPIC -O1 -o "$work/nodump.so" "$work/nodump.c"

echo "nested-test: library   $library"
echo "nested-test: sha256    $(sha256sum "$library" | cut -d' ' -f1)"
echo "nested-test: Hyprland  $(command -v Hyprland) ($(pacman -Qo "$(command -v Hyprland)" 2> /dev/null | sed 's/.* is owned by //'))"
echo "nested-test: layer     $layer"
echo "nested-test: artifacts $artifacts"

# A clean environment: the session's display to draw the nested window on, and nothing that
# would let the nested instance or its clients reach the session's services.
status=0
env -i \
  PATH=/usr/local/bin:/usr/bin \
  LANG="${LANG:-C.UTF-8}" \
  HOME="$work/home" \
  XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
  XDG_DATA_DIRS=/usr/local/share:/usr/share \
  LIBSEAT_BACKEND=seatd \
  HYPRLAND_NO_RT=1 \
  GDK_BACKEND=wayland \
  GSK_RENDERER=cairo \
  GTK_A11Y=none \
  LD_PRELOAD="$work/nodump.so" \
  NESTED_TEST_LAYER="$layer_client" \
  python3 -I "$work/tools/verify.py" "$library" --artifacts "$artifacts" || status=$?

[[ -z $layer_client ]] || pkill -f -- "^$layer_client " 2> /dev/null || true
if compgen -G "$work/home/.cache/hyprland/hyprlandCrashReport*" > /dev/null; then
  cp "$work"/home/.cache/hyprland/hyprlandCrashReport* "$artifacts/"
  echo "nested-test: the nested Hyprland crashed; its report is in $artifacts"
fi
if ((status)); then
  echo "nested-test: FAILED (verifier exit $status). Last lines of the nested compositor's log:"
  tail -n 15 "$artifacts/compositor.log" 2> /dev/null | cut -c1-200 || true
  if grep -q -E 'CREATE_DUMB failed|HAL300' "$artifacts/compositor.log" 2> /dev/null; then
    echo "nested-test: the session renders on the GPU (~/.config/k114s-gpu-desktop), and a nested compositor cannot allocate or render there."
    echo "nested-test: run this from a CPU-rendered session: rm ~/.config/k114s-gpu-desktop and log in again (or boot r1), then touch it again afterwards."
  fi
else
  echo "nested-test: PASSED"
fi
exit "$status"
