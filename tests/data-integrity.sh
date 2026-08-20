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

assert_manifest() {
    root="$1"
    expected="$2"
    actual="$(manifest "$root")"
    [ "$actual" = "$expected" ] || {
        echo "Expected manifest:" >&2
        printf '%s\n' "$expected" >&2
        echo "Actual manifest:" >&2
        printf '%s\n' "$actual" >&2
        fail "manifest mismatch for $root"
    }
}

assert_same_tree() {
    left="$1"
    right="$2"
    expected="$(manifest "$left")"
    assert_manifest "$right" "$expected"
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

src_before="$(manifest "$src")"
rclone copy "$src" "$dst"
assert_manifest "$src" "$src_before"
assert_same_tree "$src" "$dst"

printf 'destination sentinel\n' > "$dst/do-not-delete.txt"
printf 'overwritten\n' > "$src/plain.txt"
src_before="$(manifest "$src")"
rclone copy "$src" "$dst"
assert_manifest "$src" "$src_before"
[ -f "$dst/do-not-delete.txt" ] || fail "copy deleted an unrelated destination file"
rm "$dst/do-not-delete.txt"
assert_same_tree "$src" "$dst"

move_src="$workdir/move-src"
move_dst="$workdir/move-dst"
mkdir -p "$move_src/nested" "$move_dst"
printf 'move me\n' > "$move_src/nested/file.txt"
move_before="$(manifest "$move_src")"
rclone move "$move_src" "$move_dst"
[ -z "$(find "$move_src" -type f -print -quit)" ] || fail "move left source files behind"
assert_manifest "$move_dst" "$move_before"

sync_src="$workdir/sync-src"
sync_dst="$workdir/sync-dst"
mkdir -p "$sync_src" "$sync_dst"
printf 'keep\n' > "$sync_src/keep.txt"
printf 'new-content\n' > "$sync_src/current.txt"
printf 'keep\n' > "$sync_dst/keep.txt"
printf 'old\n' > "$sync_dst/current.txt"
printf 'remove\n' > "$sync_dst/obsolete.txt"
sync_before="$(manifest "$sync_src")"
rclone sync "$sync_src" "$sync_dst"
assert_manifest "$sync_src" "$sync_before"
assert_same_tree "$sync_src" "$sync_dst"
[ ! -e "$sync_dst/obsolete.txt" ] || fail "sync did not remove obsolete fixture file"

echo "Disposable rclone copy/overwrite/move/sync integrity tests passed."
