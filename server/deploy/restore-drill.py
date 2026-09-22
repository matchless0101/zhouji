#!/usr/bin/env python3
"""Restore a trusted local ZhouJi bundle into a disposable database, never production.

Run using the API virtualenv as root. No credentials or row contents are printed.
The only database this script creates/drops has a freshly generated name.
"""
import argparse
import configparser
import gzip
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import uuid

from cryptography.fernet import Fernet
from sqlalchemy import URL, create_engine, text


MEMBERS = (
    'database/zhouji.sql.gz', 'configuration/api.env',
    'secrets/token-encryption-key', 'secrets/apple-login.p8', 'secrets/wechat-app-secret',
)


class DrillValidationError(ValueError):
    """Only fixed, secret-free validation messages may use this type."""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--mysql-config', default='/etc/mysql/debian.cnf')
    parser.add_argument('--mysql-socket', help='Use the same explicit local socket for Python and mysql CLI')
    parser.add_argument('--source-database', default='zhouji')
    args = parser.parse_args()
    os.umask(0o077)
    started = time.monotonic()
    database = 'zhouji_restore_' + uuid.uuid4().hex
    config = configparser.ConfigParser(interpolation=None)
    config.read(args.mysql_config)
    client = config['client']
    socket = args.mysql_socket or client.get('socket')
    if not socket and client.get('host', 'localhost') == 'localhost':
        socket = next((path for path in ('/var/run/mysqld/mysqld.sock', '/tmp/mysql.sock')
                       if Path(path).exists()), None)
    connect_args = {'unix_socket': socket} if socket else {}
    admin = create_engine(URL.create(
        'mysql+pymysql', username=client.get('user'), password=client.get('password'),
        host=client.get('host', 'localhost'), port=int(client.get('port', '3306')),
    ), connect_args=connect_args, hide_parameters=True)
    created = False
    try:
        with tempfile.TemporaryDirectory(prefix='zhouji-restore-') as temporary:
            root = Path(temporary)
            with tarfile.open(args.bundle, 'r:gz') as archive:
                for name in MEMBERS:
                    member = archive.getmember(name)
                    if not member.isfile() or member.size <= 0:
                        raise DrillValidationError('missing or nonregular restore member')
                    target = root / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.extractfile(member) as source, target.open('wb') as output:
                        shutil.copyfileobj(source, output)
            sql_path = root / 'restore.sql'
            with gzip.open(root / MEMBERS[0], 'rb') as source, sql_path.open('wb') as output:
                shutil.copyfileobj(source, output)
            # Refuse a dump that could select/recreate the original database.
            with sql_path.open() as sql:
                for line in sql:
                    if re.match(r'\s*(USE\s|CREATE\s+DATABASE\s|DROP\s+DATABASE\s)', line, re.I):
                        raise DrillValidationError('dump contains database selection statements')
            with admin.begin() as connection:
                connection.execute(text(f'CREATE DATABASE `{database}` CHARACTER SET utf8mb4'))
                created = True
            with sql_path.open('rb') as source:
                mysql = ['mysql', f'--defaults-extra-file={args.mysql_config}']
                if socket:
                    mysql += [f'--socket={socket}', '--protocol=SOCKET']
                else:
                    mysql += ['--protocol=TCP', f'--host={client.get("host", "localhost")}',
                              f'--port={client.get("port", "3306")}']
                result = subprocess.run(
                    [*mysql, database],
                    stdin=source, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                )
            if result.returncode:
                raise RuntimeError('isolated SQL import failed')
            counts = {}
            with admin.connect() as connection:
                def tables(schema):
                    return connection.execute(text(
                        'SELECT TABLE_NAME FROM information_schema.TABLES '
                        'WHERE TABLE_SCHEMA=:schema AND TABLE_TYPE=\'BASE TABLE\' ORDER BY TABLE_NAME'
                    ), {'schema': schema}).scalars().all()
                restored_tables = tables(database)
                if restored_tables != tables(args.source_database):
                    raise DrillValidationError('restored table list differs from current source')
                for table in restored_tables:
                    if not re.fullmatch(r'[A-Za-z0-9_]+', table + args.source_database):
                        raise DrillValidationError('unexpected identifier')
                    restored = connection.execute(text(f'SELECT COUNT(*) FROM `{database}`.`{table}`')).scalar_one()
                    current = connection.execute(text(f'SELECT COUNT(*) FROM `{args.source_database}`.`{table}`')).scalar_one()
                    counts[table] = {'restored': restored, 'current': current}
                    if restored != current:
                        raise DrillValidationError('row counts differ; repeat using a fresh backup after checking writes')
                cipher = Fernet((root / 'secrets/token-encryption-key').read_bytes().strip())
                checked = 0
                for row in connection.execute(text(
                    f'SELECT apple_refresh_encrypted, wechat_refresh_encrypted FROM `{database}`.auth_accounts'
                )):
                    for encrypted in row:
                        if encrypted:
                            cipher.decrypt(encrypted.encode())
                            checked += 1
                if checked == 0:
                    assert cipher.decrypt(cipher.encrypt(b'isolated-key-check')) == b'isolated-key-check'
            report = {
                'bundle': args.bundle.name, 'tables': counts, 'decrypted_tokens': checked,
                'key_check': 'stored_tokens' if checked else 'synthetic_round_trip_only',
                'elapsed_seconds': round(time.monotonic() - started, 3),
                'production_data_changed': False,
            }
        # Report success only after cleanup below also succeeds.
    finally:
        if created:
            with admin.begin() as connection:
                connection.execute(text(f'DROP DATABASE `{database}`'))
        admin.dispose()
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # DB driver exceptions may include secrets even with hidden SQL parameters.
        detail = str(error) if isinstance(error, DrillValidationError) else type(error).__name__
        print(f'restore drill failed: {detail}; no production restore performed', flush=True)
        raise SystemExit(1) from None
