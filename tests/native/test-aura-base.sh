#!/bin/bash
# Exercise setup's Aura section with a local source repo and patch series.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
scratch=$(mktemp -d)
trap 'rm -r -- "$scratch" </dev/null' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$scratch/gitconfig" GIT_ALLOW_PROTOCOL=file

upstream=$scratch/upstream
export B="$scratch/build" rec="$scratch/recipe"
mkdir -p "$B/aura" "$rec/m1n1-aurora-j714s"
git config --global user.name "Aura fixture"
git config --global user.email aura-fixture@localhost
git config --global url."file://$upstream".insteadOf https://github.com/aurora-silicon/aura.git
git init -q -b main "$upstream"
echo pinned > "$upstream/source"
git -C "$upstream" add source
git -C "$upstream" commit -qm pin
AURA_PIN=$(git -C "$upstream" rev-parse HEAD)
for step in first last; do
  echo "$step" >> "$upstream/source"
  git -C "$upstream" commit -qam "$step patch"
done
AURA_BASE_TREE=$(git -C "$upstream" rev-parse 'HEAD^{tree}')
export AURA_PIN AURA_BASE_TREE
git -C "$upstream" format-patch --stdout "$AURA_PIN" > "$rec/m1n1-aurora-j714s/aura-j714s-27.2.patch"

block=$scratch/aura-setup.sh
{
  echo 'set -euo pipefail'
  echo 'say() { echo "setup: $*"; }'
  awk '/^# 9\. Aura/{copy = 1} /^cat <<MSG/{copy = 0} copy' "$repo/build/native/setup.sh"
} > "$block"

bash "$block"
bash "$block"
checkout=$B/aura/base
[[ $(git -C "$checkout" rev-parse 'refs/heads/base^{tree}') == "$AURA_BASE_TREE" ]]

expect_refusal() {
  local output
  if output=$(bash "$block" 2>&1); then
    echo "Aura setup accepted $1" >&2
    exit 1
  fi
  [[ $output == *"$B/aura/base"* && $output == *"backup path"* && $output == *"rerun setup"* ]]
}

mkdir -p "$scratch/wrong-tree/aura"
B="$scratch/wrong-tree" AURA_BASE_TREE="$(git -C "$upstream" rev-parse "$AURA_PIN^{tree}")" \
  expect_refusal "a fresh checkout with a mismatched tree"
[[ $(git -C "$scratch/wrong-tree/aura/base" rev-parse 'refs/heads/base^{tree}') == "$AURA_BASE_TREE" ]]

# Model an interrupted base branch while leaving HEAD at the completed tree.
git -C "$checkout" checkout -q --detach
partial=$(git -C "$checkout" rev-parse 'refs/heads/base~1')
git -C "$checkout" branch -f base "$partial"
echo preserved > "$checkout/local-notes"
expect_refusal "a partially patched base branch"
[[ $(git -C "$checkout" rev-parse refs/heads/base) == "$partial" ]]
[[ $(cat "$checkout/local-notes") == preserved ]]

mv -- "$checkout" "$checkout-backup"
bash "$block"
[[ $(git -C "$checkout" rev-parse 'refs/heads/base^{tree}') == "$AURA_BASE_TREE" ]]
[[ $(cat "$checkout-backup/local-notes") == preserved ]]

echo 'Aura base setup checks passed.'
