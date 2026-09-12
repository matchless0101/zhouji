#!/bin/sh
# Dump zhouji MySQL database to a timestamped local file.
# Credentials are never printed. Run as a user that can read the password file.
#
# Usage:
#   ZHOUJI_DB_PASSWORD_FILE=/etc/zhouji-db-password \
#   ZHOUJI_DB_USER=zhouji_app \
#   ZHOUJI_DB_NAME=zhouji \
#   backup-zhouji-db.sh /var/backups/zhouji
set -eu
out_dir=${1:?usage: backup-zhouji-db.sh /var/backups/zhouji}
password_file=${ZHOUJI_DB_PASSWORD_FILE:-/etc/zhouji-db-password}
db_user=${ZHOUJI_DB_USER:-zhouji_app}
db_name=${ZHOUJI_DB_NAME:-zhouji}
db_host=${ZHOUJI_DB_HOST:-127.0.0.1}
db_port=${ZHOUJI_DB_PORT:-3306}

if [ ! -r "$password_file" ]; then
  printf 'cannot read password file: %s\n' "$password_file" >&2
  exit 1
fi

mkdir -p "$out_dir"
stamp=$(date +%Y%m%d-%H%M%S)
target="$out_dir/zhouji-$stamp.sql.gz"
# MYSQL_PWD is used only for this process; not written to logs.
MYSQL_PWD=$(cat "$password_file") mysqldump \
  --host="$db_host" \
  --port="$db_port" \
  --user="$db_user" \
  --single-transaction \
  --routines \
  --triggers \
  --default-character-set=utf8mb4 \
  "$db_name" | gzip >"$target"
chmod 600 "$target"
printf 'backup written: %s\n' "$target"
