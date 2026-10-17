import time

import pytest
from sqlalchemy import create_engine, insert, select, delete
from sqlalchemy.exc import IntegrityError

from zhouji_api.models import metadata, accounts, sessions, challenges


@pytest.fixture
def database():
    engine = create_engine('sqlite://')
    with engine.connect() as conn:
        conn.exec_driver_sql('PRAGMA foreign_keys=ON')
    metadata.create_all(engine)
    yield engine
    engine.dispose()


def account_values(key, **changes):
    return dict(id=key, provider='password', created_at=int(time.time()),
                verified_at=int(time.time()), **changes)


def test_password_account_with_optional_wechat_constraint(database):
    with database.begin() as conn:
        conn.execute(insert(accounts).values(**account_values('plain')))
        conn.execute(insert(accounts).values(**account_values(
            'bound', wechat_subject='wx-subject', wechat_refresh_encrypted='encrypted')))
    for changes in (
        {'wechat_subject': 'half'},
        {'wechat_refresh_encrypted': 'half'},
        {'apple_subject': 'not-permitted'},
        {'wechat_subject': 'wx-subject', 'wechat_refresh_encrypted': 'other'},
    ):
        with pytest.raises(IntegrityError), database.begin() as conn:
            conn.execute(insert(accounts).values(**account_values('invalid', **changes)))


def test_password_credentials_unique_and_deleted_with_account(database):
    assert 'auth_password_credentials' in metadata.tables
    credentials = metadata.tables['auth_password_credentials']
    with database.begin() as conn:
        for key in ('a', 'b'):
            conn.execute(insert(accounts).values(**account_values(key)))
        conn.execute(insert(credentials).values(account_id='a', username='alice',
            password_hash='not-plaintext', recovery_hash='digest', updated_at=1))
    with pytest.raises(IntegrityError), database.begin() as conn:
        conn.execute(insert(credentials).values(account_id='b', username='alice',
            password_hash='other', recovery_hash='other', updated_at=1))
    with database.begin() as conn:
        conn.execute(delete(accounts).where(accounts.c.id == 'a'))
        assert conn.execute(select(credentials)).first() is None


def test_legacy_session_and_challenge_remain_insertable(database):
    assert 'auth_method' in sessions.c
    assert 'purpose' in challenges.c
    with database.begin() as conn:
        conn.execute(insert(accounts).values(id='old', provider='wechat',
            wechat_subject='old-wx', wechat_refresh_encrypted='encrypted',
            created_at=1, verified_at=1))
        conn.execute(insert(sessions).values(token_hash='x'*64, account_id='old',
                                            created_at=1, expires_at=9999999999))
        conn.execute(insert(challenges).values(id_hash='y'*64, nonce='n',
                                               provider='wechat', expires_at=9999999999))
        assert conn.execute(select(sessions)).mappings().one()['auth_method'] == 'legacy'
        assert conn.execute(select(challenges)).mappings().one()['purpose'] == 'login'
