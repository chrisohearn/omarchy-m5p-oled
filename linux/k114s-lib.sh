# K114s (omarchy-m5p-oled): shared functions of the r3 update tooling. Sourced, never run.
#
# Every path hangs off K114S_ROOT (empty on the live system) so the tests can run the same code
# against a fake root as a normal user. Nothing in here writes when it is sourced.
#
#   $LIB   /usr/local/lib/omarchy-k114s   the tools and their data (holds.list, release-criteria.conf, ...)
#   $ETC   /etc/omarchy-k114s             the owner's settings and deliberate-override markers
#   $VAR   /var/lib/omarchy-k114s         state: releases, rollback sets, recovery sets, boot records
#   $RUN   /run/omarchy-k114s             the one-transaction permit (gone at every boot)
ROOT=${K114S_ROOT:-}
LIB=$ROOT/usr/local/lib/omarchy-k114s
ETC=$ROOT/etc/omarchy-k114s
VAR=$ROOT/var/lib/omarchy-k114s
RUN=$ROOT/run/omarchy-k114s
ESP=$ROOT/boot/efi
PACCONF=$ROOT/etc/pacman.conf
PACMAN=${K114S_PACMAN:-pacman}
STAGE2_REL=m1n1/boot-ctxr.bin           # the configured Stage 2: what the loader boots unless a trial is armed
STAGE2_TRY_REL=m1n1/boot-ctxr-try.bin   # a Stage 2 candidate k114s-release puts beside it for a one-boot trial
AURA_TRY_REL=aura-try                   # the loader's one-boot trial marker at the ESP root: "armed\n<path>\n"
PERMIT=$RUN/permit

# pacman pointed at the root in use. The live system needs no extra arguments.
PACMAN_ARGS=()
if [[ -n $ROOT ]]; then
  PACMAN_ARGS=(--root "$ROOT" --dbpath "$ROOT/var/lib/pacman" --config "$PACCONF" --cachedir "$ROOT/var/cache/pacman/pkg" --logfile "$ROOT/var/log/pacman.log")
fi
DBPATH=${ROOT}/var/lib/pacman

k114s_name=${0##*/}
say() { echo "$k114s_name: $*"; }
warn() { echo "$k114s_name: $*" >&2; }
die() { warn "$*"; exit 1; }
sum() { sha256sum "$1" 2>/dev/null | cut -c1-64; }
size() { stat -c %s "$1" 2>/dev/null || echo 0; }
now() { date -u +%Y%m%dT%H%M%SZ; }
valid_name() { [[ $1 =~ ^[A-Za-z0-9@._+-]+$ ]]; }
need_root() { [[ $(id -u) == 0 || -n ${K114S_ROOT:-} ]] || die "run with sudo"; }

# --- settings ---------------------------------------------------------------------------------
# release.conf is KEY=value lines; it is read, never sourced, so nothing in it can run.
setting() { # setting KEY DEFAULT
  local value=
  if [[ -r $ETC/release.conf ]]; then
    value=$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\{0,1\}\([A-Za-z0-9._:,/ -]*\)\"\{0,1\}[[:space:]]*\$/\1/p" "$ETC/release.conf" | tail -n 1)
  fi
  echo "${value:-$2}"
}
enabled() { [[ $(setting "$1" "$2") =~ ^(yes|on|true|1)$ ]]; }

# --- package lists ----------------------------------------------------------------------------
list_names() { # the valid package names in FILE (first word of each line), sorted, comments ignored
  [[ -f $1 ]] || return 0
  awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$1" | { grep -E '^[A-Za-z0-9@._+-]+$' || true; } | LC_ALL=C sort -u
}
boot_class_names() { # packages whose change is a change of the boot chain: never released for good (they are re-checked at every version)
  { printf '%s\n' linux-aurora m1n1-aurora uboot-aurora
    awk '$1 == "package" && $3 ~ /^boot-/ { print $2 }' "$(data_file release-criteria.conf)" 2>/dev/null || true; } | LC_ALL=C sort -u
}
held_names() { # what is held now: holds.list (or the boot stack when it is missing) minus what was released (a boot-chain package is never "released")
  local released
  released=$(list_names "$LIB/released.list" | { grep -Fxv -f <(boot_class_names) || true; })
  { if [[ -f $LIB/holds.list ]]; then list_names "$LIB/holds.list"; else printf '%s\n' linux-aurora m1n1-aurora uboot-aurora; fi; } |
    { if [[ -n $released ]]; then grep -Fxv -f <(printf '%s\n' "$released") || true; else cat; fi; } | LC_ALL=C sort -u
}
is_held() { held_names | grep -Fxq "$1"; }
installed_version() { # the installed version of exactly this package name, from pacman's local database
  # (find, not a shell glob: the release check calls this with globbing switched off)
  local dir
  while IFS= read -r dir; do
    [[ -f $dir/desc ]] || continue
    [[ $(awk '/^%NAME%$/ { getline; print; exit }' "$dir/desc") == "$1" ]] || continue
    awk '/^%VERSION%$/ { getline; print; exit }' "$dir/desc"
    return 0
  done < <(find "$DBPATH/local/" -mindepth 1 -maxdepth 1 -type d -name "$1-*" 2>/dev/null)
  return 1
}
local_db_dir() { # the local database folder of an installed package
  local version
  version=$(installed_version "$1") || return 1
  echo "$DBPATH/local/$1-$version"
}

# --- the ESP ----------------------------------------------------------------------------------
esp_free() { # free bytes on the ESP; K114S_ESP_FREE overrides (tests)
  if [[ -n ${K114S_ESP_FREE:-} ]]; then echo "$K114S_ESP_FREE"; return; fi
  df -B1 --output=avail "$ESP" 2>/dev/null | tail -n 1 | tr -d ' '
}
esp_is_mounted() { [[ -n ${K114S_ROOT:-} ]] || findmnt -n "$ESP" >/dev/null 2>&1; }
limine_conf() { echo "$ESP/limine.conf"; }
# limine-snapper-sync (enabled on the Mac) writes snapshot boot files into <ESP>/<machine-id>/limine_history
# and limine.conf whenever a snapshot is made, under the mutex /run/lock/boot-partition.lock.
snapper_sync_on() { [[ -e $ROOT/etc/limine-snapper-sync.conf ]]; }
snapshot_bytes() { du -sb "$ESP"/*/limine_history 2>/dev/null | awk '{ n += $1 } END { print n + 0 }'; }
boot_lock() { # take the mutex the Limine tools use before an edit of the ESP or limine.conf; held until the process ends or boot_unlock
  # "boot_lock soft" returns 1 instead of dying, for the steps after a package transaction, which must not be cut short
  mkdir -p "$ROOT/run/lock"
  exec 8> "$ROOT/run/lock/boot-partition.lock"
  flock -w "${K114S_LOCK_WAIT:-120}" 8 && return 0
  [[ ${1:-} != soft ]] || return 1
  die "limine-snapper-sync or limine-entry-tool holds the boot partition lock; nothing changed, try again in a moment"
}
boot_unlock() { flock -u 8 2>/dev/null || true; }
uki_prefix() { # CUSTOM_UKI_NAME from /etc/default/limine, read not sourced
  local name
  name=$(sed -n 's/^[[:space:]]*CUSTOM_UKI_NAME[[:space:]]*=[[:space:]]*"\{0,1\}\([a-z0-9]*\)"\{0,1\}.*/\1/p' "$ROOT/etc/default/limine" 2>/dev/null | tail -n 1)
  echo "${name:-omarchy}"
}
standard_uki_rel() { echo "EFI/Linux/$(uki_prefix)_${1:-linux-aurora}.efi"; }

# limine.conf: an entry starts with "/" (sub-entries with more slashes); Limine numbers every
# entry in file order, directories and sub-entries included, and default_entry is that number,
# or an entry path such as "Omarchy/linux-k114s" (names joined by "/", the "+" of an expanded
# folder is not part of a name; Limine 12.9.6 common/menu.c find_entry_by_path). A path keeps
# naming the same entry when entries are added or removed in front of it (docs/r3a-promotion.md).
limine_default() { # the value as written: an index or a path. The option name in any case, as Limine and k114s-boot-once read it
  awk 'tolower(substr($0, 1, 14)) == "default_entry:" { v = substr($0, 15); sub(/^[ \t]+/, "", v); print v; exit }' "$1"
}
limine_paths() { # one line per entry, in Limine's numbering: INDEX<TAB>PATH
  awk '{ line = $0; sub(/^[[:space:]]+/, "", line) }
    line ~ /^\// { n++; match(line, /^\/+/); d = RLENGTH; name = substr(line, d + 1); sub(/^\+/, "", name); sub(/^[ \t]+/, "", name)
      nm[d] = name; p = nm[1]; for (i = 2; i <= d; i++) p = p "/" nm[i]; print n "\t" p }' "$1"
}
limine_default_index() { # the number of the entry default_entry names; nothing if it names none (or uses an escape)
  local value
  value=$(limine_default "$1")
  if [[ $value =~ ^[0-9]+$ ]]; then echo "$value"; return 0; fi
  [[ -n $value && $value != *[\\#]* ]] || return 0
  limine_paths "$1" | awk -F'\t' -v want="$value" '$2 == want { print $1; exit }'
}
limine_path_of() { # the entry path of entry INDEX; nothing if a name needs an escape (/, \ or #)
  limine_paths "$1" | awk -F'\t' -v want="$2" '$1 == want { if ($2 !~ /[\\#]/) print $2; exit }'
}
limine_entry_of() { # the number of the entry whose path names EFI file REL; nothing if none or several
  awk -v want="$2" '
    /^[[:space:]]*\// { n++ }
    /^[[:space:]]*path:/ && index($0, want) { hits++; found = n }
    END { if (hits == 1) print found }' "$1"
}
limine_title_of() { awk -v want="$2" '/^[[:space:]]*\// { n++; if (n == want) { sub(/^[[:space:]]*\/+\+?/, ""); print; exit } }' "$1"; }
limine_set_default() { # point default_entry at entry INDEX, in place, through a temp file on the same filesystem
  # A default written as a path stays a path (the path of that entry), so that an entry the hook adds in front later
  # cannot move it; a numeric default stays a number.
  local conf=$1 index=$2 count tmp value
  count=$(grep -c -E '^[[:space:]]*/' "$conf" || true)
  [[ $index =~ ^[0-9]+$ ]] && ((index >= 1 && index <= count)) || return 1
  grep -q -i '^default_entry:' "$conf" || return 1
  value=$index
  if [[ ! $(limine_default "$conf") =~ ^[0-9]+$ ]]; then value=$(limine_path_of "$conf" "$index"); [[ -n $value ]] || return 1; fi
  tmp=$conf.k114s-new
  K114S_VALUE=$value awk 'tolower(substr($0, 1, 14)) == "default_entry:" && !done { print "default_entry: " ENVIRON["K114S_VALUE"]; done = 1; next } { print }' "$conf" > "$tmp" &&
    [[ $(limine_default_index "$tmp") == "$index" ]] && sync "$tmp" && mv -f "$tmp" "$conf" || { rm -f "$tmp"; return 1; }
}
limine_remove_entry_block() { # print CONF without the top-level entry that boots EFI file REL
  # The block runs from its comment marker ("### K114s ..." directly above, if any) or its title
  # line to the line before the next top-level entry or marker. Only a flat entry is taken out:
  # a block with sub-entries ("//name", a menu folder such as "/+Omarchy") is printed unchanged,
  # because other entries live in it. The caller checks the result before it uses it.
  awk -v want="$2" '
    function flush(    i) { if (!(drop && subs == 0)) for (i = 1; i <= n; i++) print block[i]; n = 0; drop = 0; subs = 0 }
    /^###/ { flush(); block[++n] = $0; marker = 1; next }
    /^\/[^\/]/ { if (!marker) flush(); marker = 0; block[++n] = $0; inside = 1; next }
    { if (inside || n) { block[++n] = $0; if ($0 ~ /^[[:space:]]*\/\//) subs++; if (index($0, want) && $0 ~ /^[[:space:]]*path:/) drop = 1 } else print }
    END { flush() }' "$1"
}

# --- the booted kernel ------------------------------------------------------------------------
running_release() { echo "${K114S_UNAME_R:-$(uname -r)}"; }
running_version() { if [[ -n ${K114S_PROC_VERSION:-} ]]; then echo "$K114S_PROC_VERSION"; else cat /proc/version; fi; }
image_version() { # the "Linux version ..." banner inside a kernel image or UKI; empty when it holds none in plain text
  # An image carries the text more than once; the copy with the build number ("#1 SMP ...") is the
  # one /proc/version shows. (Read from this Mac's kernel 2026-11-14: the first copy has a bare "#".)
  { LC_ALL=C grep -a -o 'Linux version [0-9][ -~]*' "$1" 2>/dev/null || true; } |
    awk '/ #[0-9]+ / { print; found = 1; exit } NR == 1 { first = $0 } END { if (!found && NR) print first }'
}
image_is_running() { # is FILE the kernel that is running? 0 yes; 1 no; 2 cannot tell (no banner in plain text)
  [[ -n $(image_version "$1") ]] || return 2
  LC_ALL=C grep -a -F -q -- "$(running_version)" "$1"
}
boot_id() { # this boot's id (the kernel makes a new one at every start)
  if [[ -n ${K114S_BOOT_ID:-} ]]; then echo "$K114S_BOOT_ID"; else tr -d '-' < /proc/sys/kernel/random/boot_id 2>/dev/null; fi
}
booted_uki() { # the EFI path of the image the stub was started from, as "EFI/Linux/x.efi"; empty if unknown
  local var=${K114S_EFI_STUB_ID:-}
  if [[ -z $var ]]; then
    for var in /sys/firmware/efi/efivars/StubImageIdentifier-*; do [[ -r $var ]] && break; var=; done
  fi
  [[ -n $var && -r $var ]] || return 0
  # 4 attribute bytes, then UTF-16LE. Limine hands the stub "/\EFI\Linux\name.efi" on this Mac
  # (read 2026-11-14): backslashes become slashes, doubled and leading ones go.
  tail -c +5 "$var" | tr -d '\0' | tr '\\' '/' | tr -s '/' | sed 's#^/##'
}

# --- the booted Stage 2 -----------------------------------------------------------------------
# The loader (Aura) boots the configured m1n1/boot-ctxr.bin, unless a file "aura-try" at the ESP
# root holds "armed\n<path>\n": then it marks the file "spent", boots <path> ONCE under its
# watchdog, and tells Linux in chosen/aurora,trial. A trial that hangs is reset onto the
# configured file. (Seen on this Mac 2026-11-14: m1n1/boot-ctxr-r3-gpu.bin booted this way.)
booted_trial() { # what the loader booted once in place of the configured Stage 2; empty on an ordinary boot
  if [[ -n ${K114S_AURA_TRIAL+set} ]]; then echo "$K114S_AURA_TRIAL"; return 0; fi     # tests
  local file=$ROOT/proc/device-tree/chosen/aurora,trial
  [[ -r $file ]] || return 0
  tr -d '\0' < "$file"
}
booted_stage2() { # the ESP path of the Stage 2 image this boot came through; "?" when a trial names something else
  local trial
  trial=$(booted_trial)
  if [[ -z $trial ]]; then echo "$STAGE2_REL"
  elif [[ $trial =~ ^[A-Za-z0-9._/-]+$ && $trial != /* && $trial != *..* ]]; then echo "$trial"
  else echo "?"; fi
}
booted_stage2_sum() { # the SHA-256 of that image as it is on the ESP now; "unknown" when it cannot be read
  local rel
  rel=$(booted_stage2)
  if [[ $rel != "?" && -f $ESP/$rel ]]; then sum "$ESP/$rel"; else echo unknown; fi
}
aura_try_path() { [[ -f $ESP/$AURA_TRY_REL ]] && sed -n 2p "$ESP/$AURA_TRY_REL" 2>/dev/null || true; }     # the path a marker names, armed or spent
aura_try_armed() { # the path an ARMED marker names; nothing when there is no marker or it is spent
  [[ -f $ESP/$AURA_TRY_REL && $(sed -n 1p "$ESP/$AURA_TRY_REL" 2>/dev/null) == armed ]] || return 0
  aura_try_path
}
aura_try_arm() { # aura_try_arm REL: arm the loader's one-boot trial of ESP file REL (written beside, then renamed)
  [[ $1 =~ ^m1n1/boot-ctxr-[A-Za-z0-9._-]+\.bin$ && -s $ESP/$1 ]] || return 1
  printf 'armed\n%s\n' "$1" > "$ESP/$AURA_TRY_REL.k114s-new" && sync "$ESP/$AURA_TRY_REL.k114s-new" && mv -f "$ESP/$AURA_TRY_REL.k114s-new" "$ESP/$AURA_TRY_REL" &&
    [[ $(aura_try_armed) == "$1" ]]
}
aura_try_clear() { # aura_try_clear REL: take the marker away when it names REL (armed or spent); another's is left alone
  [[ -f $ESP/$AURA_TRY_REL && $(aura_try_path) == "$1" ]] || return 0
  rm -f "$ESP/$AURA_TRY_REL"
}
# Trials of the boot chain that are not k114s-release's own. Seen on this Mac 2026-11-14:
#   /etc/omarchy-k114s/stage2-trial   "<path>\n<sha256>\n": a standing Stage 2 trial, re-armed at every
#                                     clean shutdown after a boot that came through it (stage2-rearm)
#   /etc/omarchy-k114s/trial-default  a one-boot boot-menu trial (trial-default-revert puts default 1 back)
STANDING_TRIAL=$ETC/stage2-trial
ENTRY_TRIAL=$ETC/trial-default
foreign_trial() { # foreign_trial [OUR_REL]: describe another trial under way; nothing when there is none
  local ours=${1:-} armed
  if [[ -s $STANDING_TRIAL ]]; then echo "a standing Stage 2 trial of $(sed -n 1p "$STANDING_TRIAL") ($STANDING_TRIAL, armed again after each good start through it)"; return 0; fi
  [[ ! -e $ENTRY_TRIAL ]] || { echo "a one-boot boot-menu trial ($ENTRY_TRIAL)"; return 0; }
  armed=$(aura_try_armed)
  if [[ -n $armed && $armed != "$ours" ]]; then echo "an armed one-boot Stage 2 trial of $armed ($ESP/$AURA_TRY_REL)"; return 0; fi
  if [[ -n $(booted_trial) && $(booted_trial) != "$ours" ]]; then echo "this boot came through a one-boot Stage 2 trial of $(booted_trial)"; fi
  return 0
}
kv() { awk -v k="$2" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }' "$1" 2>/dev/null || true; }   # kv FILE KEY: the rest of the first "KEY ..." line

# --- notifications ----------------------------------------------------------------------------
notify() { # notify URGENCY TITLE BODY: to every graphical session; never fails, never blocks long
  enabled NOTIFY yes || return 0
  # tests: a fake root, or K114S_NOTIFY_LOG, gets the text in a file instead of on a desktop
  if [[ -n ${K114S_ROOT:-}${K114S_NOTIFY_LOG:-} ]]; then echo "notify[$1]: $2: $3" >> "${K114S_NOTIFY_LOG:-$VAR/notify.log}" 2>/dev/null || true; return 0; fi
  if [[ $(id -u) != 0 ]]; then
    timeout 5 notify-send -u "$1" -a "K114s updates" "$2" "$3" 2>/dev/null || true
    return 0
  fi
  local uid user
  for bus in /run/user/*/bus; do
    [[ -S $bus ]] || continue
    uid=${bus#/run/user/}; uid=${uid%/bus}
    user=$(id -nu "$uid" 2>/dev/null) || continue
    timeout 5 runuser -u "$user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
      notify-send -u "$1" -a "K114s updates" "$2" "$3" 2>/dev/null || true
  done
}

# --- data files -------------------------------------------------------------------------------
# The installed copy under $LIB wins; a tool run from a checkout falls back to the file beside it.
data_file() { if [[ -f $LIB/$1 ]]; then echo "$LIB/$1"; else echo "${HERE:-$LIB}/$1"; fi; }
tool() { if [[ -x $LIB/$1 ]]; then echo "$LIB/$1"; else echo "${HERE:-$LIB}/$1"; fi; }
json_string() { # a JSON string literal for $1
  local text=$1
  text=${text//\\/\\\\}; text=${text//\"/\\\"}; text=${text//$'\t'/ }; text=${text//$'\n'/ }; text=${text//$'\r'/}
  printf '"%s"' "$(printf '%s' "$text" | tr -d '\000-\037')"
}
