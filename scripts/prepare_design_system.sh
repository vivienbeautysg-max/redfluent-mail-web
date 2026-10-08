#!/usr/bin/env bash
# Redfluent Mail (v0.39.3-rf6, hardened in rf7): materialise the design system package with our patch.
#
# pubspec.yaml points `linagora_design_flutter` (dependency_overrides) at
# third_party/linagora_design_flutter. That directory is generated, not committed: this script
# fetches upstream https://github.com/linagora/linagora-design-flutter at the pinned commit below
# (the one Twake Mail v0.39.3 resolved, pubspec.lock before rf6), applies
# patchs/linagora_design_flutter-font-fallback.patch with `git apply` (fails on any mismatch) and
# copies the package files there. The patch is the only difference from upstream.
# Run from the repository root; scripts/prebuild.sh calls it before `flutter pub get`.
#
# $DEST/.prepared records the pinned commit, the patch blob, the copied paths and a SHA-256 of every
# file it wrote: the directory is reused only if all of them still match, and the script only ever
# deletes a $DEST that carries this marker (never a directory it did not make). A lock directory
# keeps two runs from building at the same time; the new tree is built in a unique temporary
# directory next to $DEST and moved into place.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0

REF=0d402e4f5a371cd88fb1a0671e2c7d902aaa2918
URL=https://github.com/linagora/linagora-design-flutter.git
PATCH=patchs/linagora_design_flutter-font-fallback.patch
DEST=third_party/linagora_design_flutter
FILES="lib assets pubspec.yaml LICENSE README.md CHANGELOG.md"

[ -f "$PATCH" ] || { echo "run from the repository root ($PATCH not found)" >&2; exit 1; }
STAMP="$REF $(git hash-object "$PATCH") $FILES"

tree_sha() {   # SHA-256 over every file of $1 except the marker, in a stable order
  (cd "$1" && find . -type f ! -name .prepared -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256) \
    | shasum -a 256 | cut -d' ' -f1
}

mkdir -p "$(dirname "$DEST")"
LOCK="$DEST.lock"
mkdir "$LOCK" 2>/dev/null || { echo "$LOCK exists: another run is preparing $DEST (remove it if that run died)" >&2; exit 1; }
tmp=""; new=""
trap 'rm -rf ${tmp:+"$tmp"} ${new:+"$new"}; rmdir "$LOCK"' EXIT

if [ -f "$DEST/.prepared" ] && [ "$(head -1 "$DEST/.prepared")" = "$STAMP" ] \
   && [ "$(sed -n 2p "$DEST/.prepared")" = "$(tree_sha "$DEST")" ]; then
  echo "[design system] $DEST up to date ($REF + patch)"
  exit 0
fi
if [ -e "$DEST" ] && [ ! -f "$DEST/.prepared" ]; then
  echo "$DEST exists but was not made by this script (no .prepared marker) - not touching it" >&2
  exit 1
fi

tmp=$(mktemp -d)
new=$(mktemp -d "$DEST.new.XXXXXX")

git -C "$tmp" init -q
git -C "$tmp" fetch -q --depth 1 "$URL" "$REF"
git -C "$tmp" checkout -q FETCH_HEAD
[ "$(git -C "$tmp" rev-parse HEAD)" = "$REF" ] || { echo "fetched commit is not $REF" >&2; exit 1; }
git -C "$tmp" apply --whitespace=nowarn "$PWD/$PATCH"

for f in $FILES; do
  cp -R "$tmp/$f" "$new/"
done
printf '%s\n%s\n' "$STAMP" "$(tree_sha "$new")" > "$new/.prepared"
rm -rf "$DEST"
mv "$new" "$DEST"
echo "[design system] $DEST = $URL@$REF + $PATCH"
