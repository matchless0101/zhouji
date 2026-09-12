#!/bin/sh
# ZhouJi API readiness probe. Exit 0 only when /ready returns HTTP 200.
# Usage: health-probe.sh [base_url]
#   base_url defaults to http://127.0.0.1:8011
set -eu
base=${1:-http://127.0.0.1:8011}
url="${base%/}/api/v1/health/ready"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM
code=$(curl --silent --show-error --output "$tmp" --write-out '%{http_code}' --max-time 8 "$url" || echo 000)
if [ "$code" != "200" ]; then
  printf 'zhouji-api health failed: HTTP %s at %s\n' "$code" "$url" >&2
  exit 1
fi
printf 'zhouji-api healthy: %s\n' "$url"
