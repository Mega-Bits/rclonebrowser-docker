#!/bin/sh
set -eu

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

case "$workdir" in
    /tmp/*) ;;
    *) fail "refusing destructive test outside /tmp: $workdir" ;;
esac

manifest() {
    root="$1"
    (
        cd "$root"
        find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
            sha256sum "$file"
        done
    )
}

assert_same_tree() {
    left="$1"
    right="$2"
    left_manifest="$workdir/left.sha256"
    right_manifest="$workdir/right.sha256"
    manifest "$left" > "$left_manifest"
    manifest "$right" > "$right_manifest"
    diff -u "$left_manifest" "$right_manifest"
}

src="$workdir/copy-src"
dst="$workdir/copy-dst"
mkdir -p "$src/nested" "$dst"
printf 'plain\n' > "$src/plain.txt"
printf 'space\n' > "$src/nested/space name.txt"
unicode_name="unicode-$(printf '\303\237').txt"
printf 'unicode\n' > "$src/nested/$unicode_name"
: > "$src/empty.txt"
dd if=/dev/zero of="$src/nested/one-megabyte.bin" bs=1M count=1 status=none

rclone copy "$src" "$dst"
assert_same_tree "$src" "$dst"

printf 'overwritten\n' > "$src/plain.txt"
rclone copy "$src" "$dst"
assert_same_tree "$src" "$dst"

move_src="$workdir/move-src"
move_dst="$workdir/move-dst"
mkdir -p "$move_src/nested" "$move_dst"
printf 'move me\n' > "$move_src/nested/file.txt"
manifest "$move_src" > "$workdir/move-before.sha256"
rclone move "$move_src" "$move_dst"
[ -z "$(find "$move_src" -type f -print -quit)" ] || fail "move left source files behind"
manifest "$move_dst" > "$workdir/move-after.sha256"
diff -u "$workdir/move-before.sha256" "$workdir/move-after.sha256"

sync_src="$workdir/sync-src"
sync_dst="$workdir/sync-dst"
mkdir -p "$sync_src" "$sync_dst"
printf 'keep\n' > "$sync_src/keep.txt"
printf 'new\n' > "$sync_src/current.txt"
printf 'keep\n' > "$sync_dst/keep.txt"
printf 'old\n' > "$sync_dst/current.txt"
printf 'remove\n' > "$sync_dst/obsolete.txt"
rclone sync "$sync_src" "$sync_dst"
assert_same_tree "$sync_src" "$sync_dst"
[ ! -e "$sync_dst/obsolete.txt" ] || fail "sync did not remove obsolete fixture file"

echo "Disposable rclone copy/overwrite/move/sync integrity tests passed."
