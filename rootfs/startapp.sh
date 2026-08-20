#!/bin/sh
set -eu

mkdir -p "$(dirname "${RCLONE_CONFIG:-/config/rclone/rclone.conf}")"
export TERMINAL="${TERMINAL:-xterm}"

exec /usr/bin/rclone-browser
