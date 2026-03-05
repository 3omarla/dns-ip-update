#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

#
# cf_update_dns.sh – update (or DDNS‑refresh) a single DNS record on Cloudflare
#
# Prerequisites:
#   • jq        – JSON parsing (pacman -S jq, apt install jq, …)
#   • curl      – HTTP requests (already on most systems)
#
# Required environment variables (export … in your shell or .env file):
#   CF_API_TOKEN      # Cloudflare API token with “Zone / DNS / Edit” permission
#   CF_ZONE_ID        # Zone identifier (32‑char hex)
#   CF_RECORD_ID      # DNS record identifier (32‑char hex)
#
# Optional env vars / CLI flags:
#   --name     my.example.com   (defaults to value already on Cloudflare)
#   --type     A|AAAA|CNAME     (defaults to record’s current type)
#   --ttl      300|3600|1       (1 == “Auto”; defaults to current TTL)
#   --proxied  true|false       (defaults to current value)
#   --ip       203.0.113.10     (skip autodetection and force this content)
#
# Usage examples:
#   export CF_API_TOKEN=... CF_ZONE_ID=... CF_RECORD_ID=...
#   ./cf_update_dns.sh                # update to current public IPv4
#   ./cf_update_dns.sh --ip 192.0.2.5 # force a specific address
#   ./cf_update_dns.sh --proxied false

echo "$(date "+%d/%m/%Y %H:%M:%S")"
set -euo pipefail

## ---------- helper functions ---------- ##
err()  { printf '❌  %s\n' "$*" >&2; exit 1; }
info() { printf '⏺  %s\n' "$*"; }

## ---------- parse flags ---------- ##
NAME='' TYPE='' TTL='' PROXIED='' NEW_IP=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --name)     NAME=$2;     shift 2 ;;
    --type)     TYPE=$2;     shift 2 ;;
    --ttl)      TTL=$2;      shift 2 ;;
    --proxied)  PROXIED=$2;  shift 2 ;;
    --ip)       NEW_IP=$2;   shift 2 ;;
    -h|--help)  grep -E '^#' "$0" | sed 's/^# *//' ; exit 0 ;;
    *) err "Unknown option $1" ;;
  esac
done

## ---------- required env vars ---------- ##
# CF_API_TOKEN="rZdyf5eL0SBh9BQy5DmiIMe9Nngy_laqyrHR6Fj-"
# CF_ZONE_ID="1c06a8f6621091f839f802fe87afb38c"
# CF_RECORD_ID="36527a20dfeee8bb321ccb584e8eb426"

: "${CF_API_TOKEN?Need CF_API_TOKEN}"
: "${CF_ZONE_ID?Need CF_ZONE_ID}"
: "${CF_RECORD_ID?Need CF_RECORD_ID}"

API="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$CF_RECORD_ID"
HDR=(-H "Authorization: Bearer $CF_API_TOKEN" -H 'Content-Type: application/json')

## ---------- fetch current record ---------- ##
info "Fetching current record …"
REC=$(curl -fsSL "${HDR[@]}" "$API")
CUR_IP=$(jq -r '.result.content' <<<"$REC")
[[ -z $NAME    ]] && NAME=$(jq -r '.result.name'    <<<"$REC")
[[ -z $TYPE    ]] && TYPE=$(jq -r '.result.type'    <<<"$REC")
[[ -z $TTL     ]] && TTL=$(jq -r '.result.ttl'      <<<"$REC")
[[ -z $PROXIED ]] && PROXIED=$(jq -r '.result.proxied' <<<"$REC")

## ---------- determine new IP if not forced ---------- ##
if [[ -z $NEW_IP ]]; then
  NEW_IP=$(curl -fsSL https://api.ipify.org)
  info "Detected public IP: $NEW_IP"
fi

if [[ $NEW_IP == "$CUR_IP" ]]; then
  info "No change – record already set to $NEW_IP. Exiting."
  exit 0
fi

## ---------- build JSON payload ---------- ##
PROXIED_BOOL=$( [[ "$PROXIED" == "true" ]] && echo true || echo false )
PAYLOAD=$(cat <<EOF
{
  "name":    "$NAME",
  "type":    "$TYPE",
  "ttl":     $TTL,
  "proxied": $PROXIED_BOOL,
  "content": "$NEW_IP",
  "comment": "Automated update via cf_update_dns.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

## Optional debug:
# echo "Payload:"
# echo "$PAYLOAD"

## ---------- update the record ---------- ##
info "Updating $NAME ($TYPE) to $NEW_IP …"
RESP=$(curl -fsSL -X PUT "${HDR[@]}" --data "$PAYLOAD" "$API")

if jq -e '.success' <<<"$RESP" >/dev/null; then
  info "✅  Update successful – DNS now points to $NEW_IP"
else
  err  "Update failed! Response was:\n$RESP"
fi
