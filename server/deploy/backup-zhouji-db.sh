#!/bin/sh
# Create an atomic ZhouJi database dump and a same-generation restore bundle.
# Credentials and dump diagnostics are never written to stdout or stderr.
#
# Usage:
#   backup-zhouji-db.sh /var/backups/zhouji
set -eu
umask 077
COPYFILE_DISABLE=1
export COPYFILE_DISABLE

out_dir=${1:?usage: backup-zhouji-db.sh /var/backups/zhouji}
db_name=${ZHOUJI_DB_NAME:-zhouji}
db_host=${ZHOUJI_DB_HOST:-127.0.0.1}
db_port=${ZHOUJI_DB_PORT:-3306}
db_host_override=${ZHOUJI_DB_HOST:-}
db_port_override=${ZHOUJI_DB_PORT:-}
db_user=${ZHOUJI_DB_USER:-zhouji_app}
mysql_defaults_file=${ZHOUJI_MYSQL_DEFAULTS_FILE:-/etc/mysql/debian.cnf}
password_file=${ZHOUJI_DB_PASSWORD_FILE:-/etc/zhouji-db-password}

api_env_file=${ZHOUJI_API_ENV_FILE:-/etc/zhouji/api.env}
token_key_file=${ZHOUJI_TOKEN_ENCRYPTION_KEY_FILE:-/etc/zhouji/token-encryption-key}
apple_key_file=${ZHOUJI_APPLE_PRIVATE_KEY_FILE:-/etc/zhouji/apple-login.p8}
wechat_secret_file=${ZHOUJI_WECHAT_APP_SECRET_FILE:-/etc/zhouji/wechat-app-secret}

require_nonempty_file() {
  if [ ! -r "$1" ] || [ ! -s "$1" ]; then
    printf 'required backup input is missing or empty: %s\n' "$1" >&2
    exit 1
  fi
}

require_nonempty_file "$api_env_file"
require_nonempty_file "$token_key_file"
require_nonempty_file "$apple_key_file"
require_nonempty_file "$wechat_secret_file"

mkdir -p "$out_dir"
chmod 700 "$out_dir"
work_dir=$(mktemp -d "$out_dir/.zhouji-backup.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM

mkdir -p \
  "$work_dir/bundle/database" \
  "$work_dir/bundle/configuration" \
  "$work_dir/bundle/secrets"

dump_file="$work_dir/zhouji.sql"
dump_error="$work_dir/mysqldump.stderr"

# Do not use --databases: restore operators must create and select an isolated
# target database explicitly, and the dump must not switch back to production.
dump_database() {
  if [ -r "$mysql_defaults_file" ]; then
    # Preserve the defaults file's socket/host unless an operator explicitly
    # requests a network override. Ubuntu's maintenance account commonly uses
    # socket authentication from this file.
    set -- "--defaults-extra-file=$mysql_defaults_file"
    if [ -n "$db_host_override" ]; then
      set -- "$@" "--host=$db_host_override"
    fi
    if [ -n "$db_port_override" ]; then
      set -- "$@" "--port=$db_port_override"
    fi
    set -- "$@" \
      --single-transaction \
      --routines \
      --events \
      --triggers \
      --hex-blob \
      --set-gtid-purged=OFF \
      --no-tablespaces \
      --default-character-set=utf8mb4 \
      "$db_name"
    mysqldump "$@" >"$dump_file" 2>"$dump_error"
    return
  fi

  if [ -n "${ZHOUJI_DB_PASSWORD:-}" ]; then
    db_password=$ZHOUJI_DB_PASSWORD
  elif [ -r "$password_file" ] && [ -s "$password_file" ]; then
    db_password=$(cat "$password_file")
  else
    printf 'no readable MySQL defaults file or database password was provided\n' >&2
    return 1
  fi

  MYSQL_PWD=$db_password
  export MYSQL_PWD
  mysqldump \
    --host="$db_host" \
    --port="$db_port" \
    --user="$db_user" \
    --single-transaction \
    --routines \
    --events \
    --triggers \
    --hex-blob \
    --set-gtid-purged=OFF \
    --no-tablespaces \
    --default-character-set=utf8mb4 \
    "$db_name" >"$dump_file" 2>"$dump_error"
}

if ! dump_database; then
  printf 'database dump failed; no backup was published\n' >&2
  exit 1
fi

gzip -c "$dump_file" >"$work_dir/bundle/database/zhouji.sql.gz"
cp "$api_env_file" "$work_dir/bundle/configuration/api.env"
cp "$token_key_file" "$work_dir/bundle/secrets/token-encryption-key"
cp "$apple_key_file" "$work_dir/bundle/secrets/apple-login.p8"
cp "$wechat_secret_file" "$work_dir/bundle/secrets/wechat-app-secret"
chmod 600 \
  "$work_dir/bundle/database/zhouji.sql.gz" \
  "$work_dir/bundle/configuration/api.env" \
  "$work_dir/bundle/secrets/token-encryption-key" \
  "$work_dir/bundle/secrets/apple-login.p8" \
  "$work_dir/bundle/secrets/wechat-app-secret"

stamp=$(date +%Y%m%d-%H%M%S)
sql_target="$out_dir/zhouji-$stamp.sql.gz"
bundle_target="$out_dir/zhouji-$stamp.bundle.tar.gz"
if [ -e "$sql_target" ] || [ -e "$bundle_target" ]; then
  printf 'backup target already exists for timestamp %s\n' "$stamp" >&2
  exit 1
fi

tar -C "$work_dir/bundle" -czf "$work_dir/zhouji.bundle.tar.gz" \
  database configuration secrets
chmod 600 "$work_dir/zhouji.bundle.tar.gz"

# The bundle is published last and therefore acts as the completion marker.
mv "$work_dir/bundle/database/zhouji.sql.gz" "$sql_target"
mv "$work_dir/zhouji.bundle.tar.gz" "$bundle_target"
printf 'backup written: %s\nrestore bundle written: %s\n' "$sql_target" "$bundle_target"
