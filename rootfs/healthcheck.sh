#!/bin/sh
set -eu

process_running=0
for comm in /proc/[0-9]*/comm; do
    [ -r "$comm" ] || continue
    name="$(cat "$comm" 2>/dev/null || :)"
    if [ "$name" = "rclone-browser" ]; then
        process_running=1
        break
    fi
done

if [ "$process_running" -ne 1 ]; then
    echo "rclone-browser process is not running" >&2
    exit 1
fi

curl_probe() {
    curl --silent --output /dev/null \
        --connect-timeout 2 \
        --max-time 4 \
        "$@"
}

if curl_probe http://127.0.0.1:5800/; then
    exit 0
fi

if curl_probe --insecure https://127.0.0.1:5800/; then
    exit 0
fi

echo "web UI is not reachable on localhost:5800" >&2
exit 1
