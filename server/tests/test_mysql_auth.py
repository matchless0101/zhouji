from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock
import time

from fastapi.testclient import TestClient
from sqlalchemy import insert, select, text

from zhouji_api.app import create_app
from zhouji_api.models import accounts, sessions, password_credentials
from conftest import apply_migrations
from test_password_auth import register, headers, login, PASSWORD, NEW_PASSWORD
from test_wechat_binding import binding_challenge, complete_binding


def client_for(db):
    apple, wechat = Mock(), Mock()
    apple.exchange.return_value = ('apple-mysql', 'encrypted')
    wechat.exchange.return_value = ('wx-mysql', 'encrypted-wx')
    return TestClient(create_app(engine=db,apple_provider=apple,wechat_provider=wechat))


def test_mysql_migration_preserves_legacy_sessions(mysql_factory):
    db = mysql_factory(through=5)
    with db.begin() as conn:
        conn.execute(insert(accounts).values(id='legacy-wx',provider='wechat',wechat_subject='old-subject',
            wechat_refresh_encrypted='encrypted',created_at=1,verified_at=int(time.time())))
        conn.execute(insert(sessions).values(token_hash='a'*64,account_id='legacy-wx',created_at=1,expires_at=9999999999))
        apply_migrations(conn,after=5)
        row = conn.execute(select(sessions)).mappings().one()
        assert row['token_hash'] == 'a'*64 and row['auth_method'] == 'wechat'
        assert conn.execute(select(accounts.c.wechat_subject)).scalar_one() == 'old-subject'
    with client_for(db) as client:
        assert register(client)['session']['account']['provider'] == 'password'
        assert client.get('/api/v1/health/ready').status_code == 200


def test_mysql_recovery_code_has_one_winner(isolated_mysql):
    with client_for(isolated_mysql) as client:
        result = register(client)
        body={'username':'alice','recovery_code':result['recovery_code'],'new_password':NEW_PASSWORD}
        with ThreadPoolExecutor(max_workers=2) as pool:
            responses=list(pool.map(lambda _:client.post('/api/v1/auth/password/recover',json=body),range(2)))
        assert sorted(r.status_code for r in responses) == [200,401]
        assert login(client,password=NEW_PASSWORD).status_code == 200
        assert client.get('/api/v1/account',headers=headers(result['session'])).status_code == 401


def test_mysql_two_accounts_cannot_bind_same_wechat(isolated_mysql):
    with client_for(isolated_mysql) as client:
        first,second=register(client,'alice')['session'],register(client,'bravo')['session']
        pending=[(first,binding_challenge(client,first)),(second,binding_challenge(client,second))]
        with ThreadPoolExecutor(max_workers=2) as pool:
            responses=list(pool.map(lambda pair:complete_binding(client,*pair),pending))
        assert sorted(r.status_code for r in responses) == [200,409]
        with isolated_mysql.connect() as conn:
            assert len(conn.execute(select(accounts).where(accounts.c.wechat_subject=='wx-mysql')).all()) == 1
            assert len(conn.execute(select(password_credentials)).all()) == 2


def test_mysql_change_password_racing_login_revokes_old_session(isolated_mysql):
    with client_for(isolated_mysql) as client:
        first=register(client)['session']
        def change():
            return client.post('/api/v1/account/password/change',headers=headers(first),
                               json={'password':PASSWORD,'new_password':NEW_PASSWORD})
        with ThreadPoolExecutor(max_workers=2) as pool:
            changing=pool.submit(change)
            logging=pool.submit(login,client)
            changed,logged=changing.result(),logging.result()
        assert changed.status_code == 200
        assert logged.status_code in (200,401)
        if logged.status_code == 200:
            assert client.get('/api/v1/account',headers=headers(logged.json())).status_code == 401
        assert login(client,password=NEW_PASSWORD).status_code == 200


def test_mysql_delete_and_binding_leave_no_orphan(isolated_mysql):
    with client_for(isolated_mysql) as client:
        current=register(client)['session']
        pending=binding_challenge(client,current)
        with ThreadPoolExecutor(max_workers=2) as pool:
            binding=pool.submit(complete_binding,client,current,pending)
            deleting=pool.submit(client.delete,'/api/v1/account',headers=headers(current))
            bound,deleted=binding.result(),deleting.result()
        assert deleted.status_code == 204
        assert bound.status_code in (200,401)
        with isolated_mysql.connect() as conn:
            for table in ('auth_accounts','auth_password_credentials','auth_sessions','auth_challenges'):
                assert conn.execute(text(f'SELECT COUNT(*) FROM {table}')).scalar_one()==0
