#!/bin/bash
# Refuse to publish what must stay private. Run before every push:  build/check-publishable.sh
# Checks the files git would publish (tracked and staged) in this repository.
set -u
cd "$(dirname "$0")/.." || exit 2
bad=0
flag() { echo "check-publishable: $1"; bad=1; }
files=$( { git ls-files; git ls-files -o --exclude-standard; } | sort -u)   # untracked files too: a new file is checked before git add
[ -n "$files" ] || { echo "check-publishable: nothing tracked"; exit 2; }
# 1. no binaries: kernels, modules, device tree blobs, loader images, firmware, archives, installers
while IFS= read -r f; do
  case "$f" in
    *.bin|*.ko|*.dtb|*.dtbo|*.efi|*.im4m|*.im4p|*.ipsw|*.img|*.gz|*.zst|*.xz|*.zip|*.pkg|*.dmg|*.cpio|*.tar|*.macho|Image*|*.pyc)
      flag "binary or archive: $f" ;;
  esac
  if [ -f "$f" ] && [ "$(wc -c < "$f")" -gt 400000 ]; then flag "larger than 400 kB: $f"; fi
  if [ -f "$f" ] && LC_ALL=C grep -qP '\x00' "$f" 2>/dev/null; then flag "not a text file: $f"; fi
done <<< "$files"
# 2. no private strings
pattern='/Users/[a-z]|/home/[a-z][a-z0-9]*/|BEGIN [A-Z ]*PRIVATE KEY|gh[opsu]_[A-Za-z0-9]{20,}|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.(me|com|net|org|io)\b|([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}|HmCA-[0-9]'
hits=$(echo "$files" | tr '\n' '\0' | xargs -0 grep -n -I -E "$pattern" 2>/dev/null |
  grep -v -E 'noreply@anthropic\.com|users\.noreply\.github\.com|@localhost|build/check-publishable\.sh|git@github\.com' || true)
if [ -n "$hits" ]; then echo "$hits" | cut -c1-200; flag "private-looking strings (above)"; fi
# 2b. the owner's own private terms, kept outside the repository (one extended regex per line;
#     ${XDG_CONFIG_HOME:-~/.config}/omarchy-m5p-oled/publish-deny), so the list itself is never published
deny=${K114S_PUBLISH_DENY:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-m5p-oled/publish-deny}
if [ -r "$deny" ]; then
  # This file is a byte-for-byte public Omarchy r8044 base, not local settings.
  # Keep the exception limited to the pinned file in both the index and worktree.
  upstream_base=patches/omarchy/0002-agents-panel-room-left-pace-and-model-rows.base/share/omarchy/shell/plugins/agents/Panel.qml
  upstream_blob=db31b66873ee503f9945c25cc4393dcfd100d75e
  expected_index=$(printf '100644 %s 0\t%s' "$upstream_blob" "$upstream_base")
  public_base_exact=0
  if [[ -f $upstream_base && ! -L $upstream_base ]] &&
     [[ $(git ls-files --stage -- "$upstream_base") == "$expected_index" ]] &&
     [[ $(git hash-object --no-filters -- "$upstream_base") == "$upstream_blob" ]]; then
    public_base_exact=1
  fi
  n=0
  while IFS= read -r p; do
    n=$((n+1))
    case "$p" in ''|'#'*) continue ;; esac
    echo | grep -E -e "$p" >/dev/null 2>&1; [ $? -le 1 ] || { flag "the local deny list has a line that is not a valid extended regex (line $n)"; continue; }
    h=$(echo "$files" | tr '\n' '\0' | xargs -0 grep -l -I -E -e "$p" 2>/dev/null || true)
    if [[ $public_base_exact == 1 ]]; then
      h=$(printf '%s\n' "$h" | grep -Fxv -- "$upstream_base" || true)
    fi
    [ -z "$h" ] || { echo "$h"; flag "a term from the local deny list is in the files above"; }
  done < "$deny"
fi
# 3. nothing of Apple's by name
for f in $files; do
  case "$f" in *ftab*.bin|*tpmtfw*|*adt*.bin|*BuildManifest*) flag "Apple file: $f" ;; esac
done
[ "$bad" = 0 ] && echo "check-publishable: ok ($(echo "$files" | wc -l | tr -d ' ') files)"
exit $bad
