#!/usr/bin/env bash
set -euo pipefail

API_URL="${1:-}"
if [ -z "$API_URL" ]; then
  echo "Usage: bash verify.sh https://<api-id>.execute-api.eu-west-2.amazonaws.com" >&2
  exit 1
fi

echo "[1/3] POST create"
RESP=$(curl -sS -X POST "$API_URL/" -H 'Content-Type: application/json' -d '{"url":"example.com"}')
CODE=$(echo "$RESP" | jq -r '.shortcode')
echo "shortcode=$CODE"

echo "[2/3] GET redirect (headers)"
curl -sS -D - "$API_URL/$CODE" -o /dev/null | sed -n '1,10p'

echo "[3/3] Follow redirect"
curl -sS -L "$API_URL/$CODE" -o /dev/null -w 'Final URL: %{url_effective} | HTTP %{http_code}\n'
