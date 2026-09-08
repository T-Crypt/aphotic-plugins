#!/usr/bin/env bash
# Finds every loopback/wildcard TCP port on this machine that currently
# answers HTTP, and merges the result into a small persisted list keyed
# by port. A port that stops answering is kept and marked offline rather
# than dropped, so a service the user just doesn't have running right
# now still shows up, dimmed, instead of vanishing.
#
# Usage:
#   scan.sh                -- scan, merge, print the merged state as JSON
#   scan.sh clear-offline   -- drop every currently-offline entry, print the result
set -euo pipefail

STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/aphotic/plugins/dev-ports"
STATE_FILE="$STATE_DIR/services.json"
mkdir -p "$STATE_DIR"
[[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"

if [[ "${1:-}" == "clear-offline" ]]; then
    jq 'with_entries(select(.value.status != "offline"))' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    cat "$STATE_FILE"
    exit 0
fi

command -v ss >/dev/null 2>&1 || { cat "$STATE_FILE"; exit 0; }
command -v curl >/dev/null 2>&1 || { cat "$STATE_FILE"; exit 0; }

now=$(date +%s)
found=$(jq -n '{}')

while IFS= read -r line; do
    [[ "$line" == LISTEN* ]] || continue
    addr_port=$(awk '{print $4}' <<<"$line")
    port="${addr_port##*:}"
    [[ "$port" =~ ^[0-9]+$ ]] || continue
    addr="${addr_port%:*}"
    # Only this machine's own reach -- loopback and wildcard binds.
    case "$addr" in
        127.0.0.1|*%lo|0.0.0.0|'[::1]'|'[::]') ;;
        *) continue ;;
    esac

    # curl already writes "000" via -w on a failed connect; it also exits
    # non-zero in that case, so the fallback only covers the rarer case
    # where it produces no output at all.
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 0.6 "http://127.0.0.1:${port}/" 2>/dev/null || true)
    code="${code:-000}"
    [[ "$code" != "000" ]] || continue

    name=$(grep -oE '"[^"]+"' <<<"$line" | head -1 | tr -d '"' || true)
    [[ -n "$name" ]] || name="unknown"

    found=$(jq --arg port "$port" --arg name "$name" --arg code "$code" --arg now "$now" \
        '.[$port] = {name: $name, port: ($port | tonumber), httpCode: $code, last_seen: ($now | tonumber), status: "online"}' \
        <<<"$found")
done < <(ss -tlnHp 2>/dev/null)

persisted=$(cat "$STATE_FILE")
stale=$(jq 'with_entries(.value.status = "offline")' <<<"$persisted")
merged=$(jq -s '.[0] * .[1]' <(echo "$stale") <(echo "$found"))

echo "$merged" > "$STATE_FILE"
echo "$merged"
