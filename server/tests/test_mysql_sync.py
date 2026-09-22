"""Opt-in integration test: creates and drops only its own isolated MySQL DB.

ZHOUJI_TEST_MYSQL_CONFIG=/etc/mysql/debian.cnf python -m pytest tests/test_mysql_sync.py
Never reads production account/content rows. Credentials never enter output.
"""
import configparser
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import time
from unittest.mock import Mock
import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text, URL

from zhouji_api.app import create_app
from zhouji_api.sync import purge_soft_deleted


@pytest.fixture
def isolated_mysql():
    config_path = os.environ.get('ZHOUJI_TEST_MYSQL_CONFIG')
    if not config_path:
        pytest.skip('requires explicit MySQL admin configuration; isolated database only')
    config = configparser.ConfigParser(interpolation=None)
    config.read(config_path)
    values = config['client']
    url = URL.create('mysql+pymysql', username=values.get('user'), password=values.get('password'),
                     host=values.get('host', 'localhost'), query={'charset': 'utf8mb4'})
    admin = create_engine(url, hide_parameters=True)
    name = 'zhouji_verify_' + uuid.uuid4().hex
    engine = create_engine(url.set(database=name), hide_parameters=True)
    try:
        with admin.begin() as conn:
            conn.execute(text(f'CREATE DATABASE `{name}` CHARACTER SET utf8mb4'))
        with engine.begin() as conn:
            for migration in sorted((Path(__file__).parents[1] / 'migrations').glob('*.sql')):
                sql = '\n'.join(line for line in migration.read_text().splitlines()
                                if not line.lstrip().startswith('--'))
                for statement in sql.split(';'):
                    if statement.strip():
                        conn.execute(text(statement))
        yield engine
    finally:
        engine.dispose()
        with admin.begin() as conn:
            conn.execute(text(f'DROP DATABASE IF EXISTS `{name}`'))
        admin.dispose()


def test_mysql_simultaneous_first_push_and_purge_cursor(isolated_mysql):
    provider = Mock()
    provider.exchange.return_value = ('isolated-test-subject', 'test-refresh')
    client = TestClient(create_app(engine=isolated_mysql, apple_provider=provider))
    challenge = client.post('/api/v1/auth/apple/challenge').json()
    login = client.post('/api/v1/auth/apple', json={
        'challenge': challenge['challenge'], 'code': 'test-code', 'identity_token': 'test-token',
    })
    assert login.status_code == 200
    headers = {'Authorization': 'Bearer ' + login.json()['token']}
    now = int(time.time())
    entity = str(uuid.uuid4())

    def push(title):
        return client.post('/api/v1/sync/push', headers=headers, json={'changes': [{
            'client_op_id': str(uuid.uuid4()), 'entity_type': 'task', 'entity_id': entity,
            'op': 'upsert', 'version': 1, 'updated_at': now, 'payload': {'title': title},
        }]})

    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(push, ['device A edit', 'device B edit']))
    assert all(r.status_code == 200 for r in responses)
    assert sum(len(r.json()['applied']) for r in responses) == 1
    assert sum(len(r.json()['conflicts']) for r in responses) == 1
    deletion = client.post('/api/v1/sync/push', headers=headers, json={'changes': [{
        'client_op_id': str(uuid.uuid4()), 'entity_type': 'task', 'entity_id': entity,
        'op': 'delete', 'version': 2, 'updated_at': now - 8 * 86400, 'payload': {},
    }]})
    assert deletion.status_code == 200
    cursor = deletion.json()['applied'][0]['server_seq']
    assert client.get('/api/v1/sync/status', headers=headers).json()['soft_deleted_count'] == 1
    assert purge_soft_deleted(isolated_mysql) == 1
    assert push('stale device edit').json()['applied'] == []
    assert client.get('/api/v1/sync/status', headers=headers).json()['latest_seq'] == cursor
    assert client.delete('/api/v1/account', headers=headers).status_code == 204
    with isolated_mysql.connect() as conn:
        assert conn.execute(text('SELECT COUNT(*) FROM sync_tombstones')).scalar_one() == 0
