#!/bin/sh
# Check local/public readiness and the age of the newest complete restore bundle.
# Usage: check-zhouji-ops.sh [backup_dir] [public_base_url] [max_age_seconds]
set -eu
umask 077

backup_dir=${1:-/var/backups/zhouji}
public_url=${2:-https://zhouji.xiangdangdang.top}
max_age=${3:-129600}
local_url=${ZHOUJI_LOCAL_HEALTH_URL:-http://127.0.0.1:8011}
health_probe=${ZHOUJI_HEALTH_PROBE:-/usr/local/sbin/zhouji-health-probe}

case "$max_age" in
  ''|*[!0-9]*)
    printf 'backup maximum age must be a positive integer\n' >&2
    exit 1
    ;;
esac
if [ "$max_age" -le 0 ]; then
  printf 'backup maximum age must be a positive integer\n' >&2
  exit 1
fi

"$health_probe" "$local_url"
"$health_probe" "$public_url"

if [ ! -d "$backup_dir" ]; then
  printf 'backup directory is missing: %s\n' "$backup_dir" >&2
  exit 1
fi

newest_path=
newest_mtime=0
for candidate in "$backup_dir"/zhouji-*.bundle.tar.gz; do
  [ -f "$candidate" ] || continue
  modified=$(stat -c %Y "$candidate" 2>/dev/null || stat -f %m "$candidate" 2>/dev/null)
  if [ "$modified" -gt "$newest_mtime" ]; then
    newest_mtime=$modified
    newest_path=$candidate
  fi
done

if [ -z "$newest_path" ]; then
  printf 'no complete ZhouJi restore bundle found in %s\n' "$backup_dir" >&2
  exit 1
fi
if [ ! -s "$newest_path" ]; then
  printf 'newest restore bundle is empty: %s\n' "$newest_path" >&2
  exit 1
fi
if ! gzip -t "$newest_path" 2>/dev/null; then
  printf 'newest restore bundle is corrupted: %s\n' "$newest_path" >&2
  exit 1
fi

now=$(date +%s)
age=$((now - newest_mtime))
if [ "$age" -lt 0 ]; then
  printf 'newest restore bundle has a future timestamp: %s\n' "$newest_path" >&2
  exit 1
fi
if [ "$age" -gt "$max_age" ]; then
  printf 'newest restore bundle is stale (%s seconds): %s\n' "$age" "$newest_path" >&2
  exit 1
fi

validation_dir=$(mktemp -d "${TMPDIR:-/tmp}/zhouji-ops-check.XXXXXX")
trap 'rm -rf -- "$validation_dir"' EXIT HUP INT TERM
member_list="$validation_dir/members"
if ! tar -tzf "$newest_path" >"$member_list" 2>/dev/null; then
  printf 'newest restore bundle is not a readable tar archive: %s\n' "$newest_path" >&2
  exit 1
fi

unexpected_member=0
while IFS= read -r member; do
  case "$member" in
    database/|configuration/|secrets/|\
    database/zhouji.sql.gz|\
    configuration/api.env|\
    secrets/token-encryption-key|\
    secrets/apple-login.p8|\
    secrets/wechat-app-secret)
      ;;
    *)
      unexpected_member=1
      ;;
  esac
done <"$member_list"
if [ "$unexpected_member" -ne 0 ]; then
  printf 'newest restore bundle contains an unexpected member: %s\n' "$newest_path" >&2
  exit 1
fi

for required_member in \
  database/zhouji.sql.gz \
  configuration/api.env \
  secrets/token-encryption-key \
  secrets/apple-login.p8 \
  secrets/wechat-app-secret
do
  member_count=$(awk -v expected="$required_member" \
    '$0 == expected { count++ } END { print count + 0 }' "$member_list")
  if [ "$member_count" -ne 1 ]; then
    printf 'newest restore bundle is missing or duplicates a required member: %s\n' "$required_member" >&2
    exit 1
  fi
done

extract_nonempty_member() {
  member_name=$1
  output_name=$2
  if ! tar -xOf "$newest_path" "$member_name" >"$validation_dir/$output_name" 2>/dev/null; then
    return 1
  fi
  [ -s "$validation_dir/$output_name" ]
}

if ! extract_nonempty_member database/zhouji.sql.gz database.sql.gz ||
   ! gzip -t "$validation_dir/database.sql.gz" 2>/dev/null ||
   ! extract_nonempty_member configuration/api.env api.env ||
   ! extract_nonempty_member secrets/token-encryption-key token-encryption-key ||
   ! extract_nonempty_member secrets/apple-login.p8 apple-login.p8 ||
   ! extract_nonempty_member secrets/wechat-app-secret wechat-app-secret; then
  printf 'newest restore bundle has an unreadable or empty required member: %s\n' "$newest_path" >&2
  exit 1
fi

printf 'ZhouJi health and backup freshness checks passed: %s\n' "$newest_path"
