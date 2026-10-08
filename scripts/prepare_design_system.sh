#!/usr/bin/env bash
# Redfluent Mail (v0.39.3-rf6): materialise the design system package with our patch.
#
# pubspec.yaml points `linagora_design_flutter` (dependency_overrides) at
# third_party/linagora_design_flutter. That directory is generated, not committed: this script
# fetches upstream https://github.com/linagora/linagora-design-flutter at the pinned commit below
# (the one Twake Mail v0.39.3 resolved, pubspec.lock before rf6), applies
# patchs/linagora_design_flutter-font-fallback.patch with `git apply` (fails on any mismatch) and
# copies the package files there. The patch is the only difference from upstream.
# Run from the repository root; scripts/prebuild.sh calls it before `flutter pub get`.
set -euo pipefail

REF=0d402e4f5a371cd88fb1a0671e2c7d902aaa2918
URL=https://github.com/linagora/linagora-design-flutter.git
PATCH=patchs/linagora_design_flutter-font-fallback.patch
DEST=third_party/linagora_design_flutter

[ -f "$PATCH" ] || { echo "run from the repository root ($PATCH not found)" >&2; exit 1; }
STAMP="$REF $(git hash-object "$PATCH")"
if [ -f "$DEST/.prepared" ] && [ "$(cat "$DEST/.prepared")" = "$STAMP" ]; then
  echo "[design system] $DEST up to date ($REF + patch)"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
git -C "$tmp" fetch -q --depth 1 "$URL" "$REF"
git -C "$tmp" checkout -q FETCH_HEAD
[ "$(git -C "$tmp" rev-parse HEAD)" = "$REF" ] || { echo "fetched commit is not $REF" >&2; exit 1; }
git -C "$tmp" apply --whitespace=nowarn "$PWD/$PATCH"

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST.new"
mkdir "$DEST.new"
for f in lib assets pubspec.yaml LICENSE README.md CHANGELOG.md; do
  cp -R "$tmp/$f" "$DEST.new/"
done
echo "$STAMP" > "$DEST.new/.prepared"
rm -rf "$DEST"
mv "$DEST.new" "$DEST"
echo "[design system] $DEST = $URL@$REF + $PATCH"
