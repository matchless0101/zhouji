from unittest.mock import Mock
import configparser
import os
from pathlib import Path
import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, text, URL
from sqlalchemy.pool import StaticPool

from zhouji_api.app import create_app
from zhouji_api.models import metadata


@pytest.fixture
def password_setup():
    database = create_engine('sqlite://', connect_args={'check_same_thread': False},
                             poolclass=StaticPool, hide_parameters=True)
    @event.listens_for(database, 'connect')
    def foreign_keys(conn, record):
        conn.execute('PRAGMA foreign_keys=ON')
    metadata.create_all(database)
    apple, wechat = Mock(), Mock()
    apple.exchange.return_value = ('apple-test-subject', 'encrypted-apple')
    wechat.exchange.return_value = ('wechat-test-subject', 'encrypted-wechat')
    with TestClient(create_app(engine=database, apple_provider=apple, wechat_provider=wechat)) as client:
        yield client, database, apple, wechat
    database.dispose()


def apply_migrations(connection, *, after=0, through=999):
    for migration in sorted((Path(__file__).parents[1] / 'migrations').glob('*.sql')):
        number = int(migration.name.split('_')[0])
        if not after < number <= through:
            continue
        sql = '\n'.join(line for line in migration.read_text().splitlines()
                        if not line.lstrip().startswith('--'))
        for statement in sql.split(';'):
            if statement.strip():
                connection.execute(text(statement))


@pytest.fixture
def mysql_factory():
    location = os.environ.get('ZHOUJI_TEST_MYSQL_CONFIG')
    if not location:
        pytest.skip('requires explicit MySQL admin configuration; isolated database only')
    config = configparser.ConfigParser(interpolation=None)
    config.read(location)
    values = config['client']
    url = URL.create('mysql+pymysql', username=values.get('user'), password=values.get('password'),
        host=values.get('host', 'localhost'), port=int(values.get('port', '3306')), query={'charset':'utf8mb4'})
    admin = create_engine(url, hide_parameters=True)
    owned = []
    def make(through=999):
        name = 'zhouji_verify_' + uuid.uuid4().hex
        engine = create_engine(url.set(database=name), hide_parameters=True)
        with admin.begin() as conn:
            conn.execute(text(f'CREATE DATABASE `{name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci'))
        owned.append((name,engine))
        with engine.begin() as conn:
            apply_migrations(conn,through=through)
        return engine
    try:
        yield make
    finally:
        for name, engine in owned:
            engine.dispose()
            with admin.begin() as conn:
                conn.execute(text(f'DROP DATABASE IF EXISTS `{name}`'))
        admin.dispose()


@pytest.fixture
def isolated_mysql(mysql_factory):
    return mysql_factory()
