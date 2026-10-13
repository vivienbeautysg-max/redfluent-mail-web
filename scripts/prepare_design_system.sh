#!/usr/bin/env bash
# Redfluent Mail (v0.39.3-rf6, hardened in rf7 and after it): materialise the design system package with our patch.
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
# file it wrote: the directory is reused only if all of them still match (a hash that cannot be
# computed is an error, never a match), and the script only ever deletes a $DEST that carries this
# marker (never a directory it did not make).
# Lock: $DEST.lock is a directory whose `owner` file names the run holding it ("PID machine-id
# boot-id"; machine-id = the macOS hardware UUID, else /etc/machine-id, else the host name). A run
# that finds it waits, up to LOCK_WAIT seconds (default 1200), while that run may be alive, then uses
# $DEST if it is up to date. A lock of this machine whose run is gone (written before the last boot,
# or that PID no longer runs: SIGKILL, power loss) or that names no run (a lock left by rf7's script)
# is removed and taken; a lock of another machine or container is only waited for, then reported.
# Locks change hands only while holding $DEST.lock.guard, a directory kept for milliseconds (one
# older than a minute is left over and removed). The new tree is built in a unique directory next to
# $DEST and swapped in with two renames: the old tree is moved aside first, put back if the new one
# cannot take its place or the run is stopped in between, and removed last. Directories a killed run
# left ($DEST.prepare-new.XXXXXX, $DEST.prepare-old.XXXXXX) are removed once a new tree is ready.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0
export GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=60   # a stalled fetch fails instead of holding the lock

REF=0d402e4f5a371cd88fb1a0671e2c7d902aaa2918
URL=https://github.com/linagora/linagora-design-flutter.git
PATCH=patchs/linagora_design_flutter-font-fallback.patch
DEST=third_party/linagora_design_flutter
FILES="lib assets pubspec.yaml LICENSE README.md CHANGELOG.md"
LOCK="$DEST.lock"
GUARD="$DEST.lock.guard"
LOCK_WAIT=${LOCK_WAIT:-1200}

[ -f "$PATCH" ] || { echo "run from the repository root ($PATCH not found)" >&2; exit 1; }
STAMP="$REF $(git hash-object "$PATCH") $FILES"

tree_sha() {   # SHA-256 over every file of $1 except the marker, in a stable order; fails instead of printing a non-hash
  local sum
  sum=$( (cd "$1" && find . -type f ! -path ./.prepared -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256) \
    | shasum -a 256 | cut -d' ' -f1) || return 1
  [[ $sum =~ ^[0-9a-f]{64}$ ]] || return 1
  echo "$sum"
}

current() {   # 0: $DEST is what this script makes; 1: it is not; 2: its files cannot be hashed
  local want have
  [ -f "$DEST/.prepared" ] && [ "$(head -1 "$DEST/.prepared")" = "$STAMP" ] || return 1
  want=$(sed -n 2p "$DEST/.prepared")
  [[ $want =~ ^[0-9a-f]{64}$ ]] || return 1
  have=$(tree_sha "$DEST") || return 2
  [ "$have" = "$want" ]
}

boot_id() { cat /proc/sys/kernel/random/boot_id 2>/dev/null || sysctl -n kern.bootsessionuuid 2>/dev/null || true; }
machine_id() {   # first of: the macOS hardware UUID, /etc/machine-id, the host name (stable across reboots and renames)
  { ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | sed -n 's/.*"IOPlatformUUID" = "\([^"]*\)".*/\1/p'
    cat /etc/machine-id 2>/dev/null; uname -n; } | awk 'NF && !n++ { print $1 }'
}
MACHINE=$(machine_id); BOOT=$(boot_id)
ME="$$ $MACHINE $BOOT"

gone() {   # 0 if the run named by owner line $1 is certainly not running
  local pid machine boot err
  [ -n "$1" ] || return 0                                     # no run named (rf7's lock)
  [ "$1" != "$ME" ] || return 0                               # an earlier run that had our PID in this boot
  set -f; set -- $1; set +f
  pid=${1:-}; machine=${2:-}; boot=${3:-}
  [ "$machine" = "$MACHINE" ] || return 1                     # another machine or container: cannot tell
  [ -z "$boot" ] || [ "$boot" = "$BOOT" ] || return 0         # written before this boot (reboot, power loss)
  case $pid in ''|0|*[!0-9]*) return 1 ;; esac
  err=$(export LC_ALL=C; kill -0 "$pid" 2>&1) && return 1
  case $err in *"No such process"*) return 0 ;; esac
  return 1                                                    # it runs as another user
}

take() {   # holding $GUARD: take $LOCK if it is free or its run is gone; else 1 with $holder set
  holder=""
  if [ -e "$LOCK" ] || [ -L "$LOCK" ]; then
    [ -d "$LOCK" ] || { echo "$LOCK is not a lock directory - remove it" >&2; exit 1; }
    if [ -e "$LOCK/owner" ]; then
      holder=$(cat "$LOCK/owner") || { echo "cannot read $LOCK/owner" >&2; exit 1; }
    fi
    gone "$holder" || return 1
    rm -rf "$LOCK" || { echo "cannot remove the stale lock $LOCK" >&2; exit 1; }
    echo "[design system] removed the lock of a run that is gone (${holder:-no run named})" >&2
  fi
  mkdir "$LOCK" || exit 1
  locked=1
  echo "$ME" > "$LOCK/owner" || { echo "cannot write $LOCK/owner" >&2; exit 1; }
}

lock() {
  local start=$SECONDS misses=0 said="" err
  holder=""
  while :; do
    if err=$(mkdir "$GUARD" 2>&1); then
      guarded=1; misses=0
      if take; then rmdir "$GUARD"; guarded=""; return 0; fi
      rmdir "$GUARD"; guarded=""
    elif [ -e "$GUARD" ]; then   # held for milliseconds: one older than a minute was left by a killed run
      misses=0
      [ -z "$(find "$GUARD" -maxdepth 0 -mmin +1 -print -delete 2>/dev/null)" ] \
        || echo "[design system] removed $GUARD left by a killed run" >&2
    else   # mkdir failed and nothing is there: permissions, read-only or full file system (3 times in a row)
      misses=$((misses + 1))
      [ "$misses" -lt 3 ] || { echo "cannot create the lock $GUARD: $err" >&2; exit 1; }
    fi
    [ $((SECONDS - start)) -lt "$LOCK_WAIT" ] || {
      echo "$LOCK still held after ${LOCK_WAIT}s by: ${holder:-?} (remove $LOCK if that run is not running)" >&2
      exit 1
    }
    if [ -z "$said" ] && { [ -n "$holder" ] || [ $((SECONDS - start)) -ge 5 ]; }; then
      echo "[design system] waiting for $LOCK (held by ${holder:-?})" >&2; said=1
    fi
    sleep 1
  done
}

unlock() {   # our lock only (or one we made but could not write the owner of); owner file first
  local o
  o=$(cat "$LOCK/owner" 2>/dev/null) || o=""
  [ -z "$o" ] || [ "$o" = "$ME" ] || return 0
  rm -f "$LOCK/owner"; rmdir "$LOCK" 2>/dev/null
}

cleanup() {   # every step runs, whatever failed before it
  set +e
  if [ -n "$old" ] && [ -d "$old/tree" ] && [ ! -e "$DEST" ]; then   # stopped between the two renames
    mv "$old/tree" "$DEST" && echo "[design system] previous $DEST put back" >&2
  fi
  rm -rf ${tmp:+"$tmp"} ${new:+"$new"} ${old:+"$old"}
  [ -z "$guarded" ] || rmdir "$GUARD"
  [ -z "$locked" ] || unlock
}

if current; then
  echo "[design system] $DEST up to date ($REF + patch)"
  exit 0
fi

mkdir -p "$(dirname "$DEST")"
tmp=""; new=""; old=""; locked=""; guarded=""
trap cleanup EXIT
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
lock

rc=0; current || rc=$?
case $rc in
  0) echo "[design system] $DEST up to date ($REF + patch)"; exit 0 ;;
  2) echo "cannot hash the files of $DEST (shasum, sort -z and xargs -0 are needed)" >&2; exit 1 ;;
esac
if [ -e "$DEST" ] && [ ! -f "$DEST/.prepared" ]; then
  echo "$DEST exists but was not made by this script (no .prepared marker) - not touching it" >&2
  exit 1
fi

tmp=$(mktemp -d)
new=$(mktemp -d "$DEST.prepare-new.XXXXXX")
chmod 755 "$new"   # mktemp -d makes it 0700

git -C "$tmp" init -q
git -C "$tmp" fetch -q --depth 1 "$URL" "$REF"
git -C "$tmp" checkout -q FETCH_HEAD
[ "$(git -C "$tmp" rev-parse HEAD)" = "$REF" ] || { echo "fetched commit is not $REF" >&2; exit 1; }
git -C "$tmp" apply --whitespace=nowarn "$PWD/$PATCH"

for f in $FILES; do
  cp -R "$tmp/$f" "$new/"
done
sum=$(tree_sha "$new") || { echo "cannot hash the files of $new (shasum, sort -z and xargs -0 are needed)" >&2; exit 1; }
printf '%s\n%s\n' "$STAMP" "$sum" > "$new/.prepared"

for d in "$DEST".prepare-new.?????? "$DEST".prepare-old.??????; do   # left by a run killed while building or swapping
  [ "$d" = "$new" ] || [ ! -e "$d" ] || rm -rf "$d"
done
if [ -e "$DEST" ]; then
  old=$(mktemp -d "$DEST.prepare-old.XXXXXX")
  mv "$DEST" "$old/tree"
fi
# $DEST must not exist here: mv onto an existing directory would move $new inside it.
if [ -e "$DEST" ] || ! mv "$new" "$DEST"; then
  echo "could not move $new to $DEST" >&2
  exit 1   # cleanup puts the previous tree back if $DEST is free
fi
new=""
echo "[design system] $DEST = $URL@$REF + $PATCH"
