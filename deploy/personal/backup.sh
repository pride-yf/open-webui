#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

[[ -f .env && -d data ]] || { echo 'Missing .env or data directory.' >&2; exit 1; }
docker compose config --quiet
mkdir -p backups
archive="backups/open-webui-$(date -u +%Y%m%dT%H%M%SZ)-$$.tar.gz"
running="$(docker compose ps --status running -q open-webui)"
stopped=0
finish() {
    status=$?
    trap - EXIT
    if [[ "$stopped" == 1 ]]; then
        if ! docker compose start open-webui; then
            echo 'Automatic restart failed; run docker compose up -d.' >&2
            status=1
        fi
    fi
    exit "$status"
}
trap finish EXIT
if [[ -n "$running" ]]; then
    stopped=1
    docker compose stop -t 60 open-webui
fi
# SQLite must be copied with the service stopped. Include the whole data directory.
tar -czf "$archive" -- .env compose.yaml data
chmod 600 "$archive"
echo "Backup created: $archive"
echo 'Contains API credentials and chat data. Store an additional copy off this server.'

