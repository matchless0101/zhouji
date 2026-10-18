import time

from sqlalchemy import delete, select, update

from zhouji_api.models import accounts, password_credentials, sessions
from test_password_auth import PASSWORD, NEW_PASSWORD, headers, login, register
from test_wechat_binding import wx_login


def setup_password(client, current, username='alice', password=PASSWORD):
    return client.post('/api/v1/account/password/setup', headers=headers(current),
                       json={'username': username, 'password': password})


def test_wechat_setup_preserves_identity_profile_and_creation_provider(password_setup):
    client, db, _, _ = password_setup
    original = wx_login(client).json()
    client.patch('/api/v1/account/profile', headers=headers(original), json={'nickname': '原账户', 'avatar': 'leaf'})
    result = setup_password(client, original, ' Alice ')
    assert result.status_code == 200
    added = result.json()
    account = added['session']['account']
    assert account['id'] == original['account']['id'] and account['provider'] == 'wechat'
    assert account['nickname'] == '原账户' and account['avatar'] == 'leaf'
    assert account['has_password'] and account['wechat_bound'] and account['username'] == 'alice'
    assert added['recovery_code'] and client.get('/api/v1/account', headers=headers(original)).status_code == 401
    assert login(client).json()['account']['id'] == account['id']
    assert wx_login(client).json()['account']['id'] == account['id']
    with db.connect() as conn:
        rows = conn.execute(select(accounts)).mappings().all()
        assert len(rows) == 1 and rows[0]['provider'] == 'wechat'
        credential = conn.execute(select(password_credentials)).mappings().one()
        assert credential['password_hash'] != PASSWORD and credential['recovery_hash'] != added['recovery_code']


def test_setup_username_conflict_does_not_change_wechat_account(password_setup):
    client, db, _, _ = password_setup
    registered = register(client)
    original = wx_login(client).json()
    assert setup_password(client, original, 'ALICE').status_code == 409
    current = client.get('/api/v1/account', headers=headers(original))
    assert current.status_code == 200 and not current.json()['has_password']
    assert login(client).json()['account']['id'] == registered['session']['account']['id']
    with db.connect() as conn:
        assert len(conn.execute(select(password_credentials)).all()) == 1


def test_setup_cannot_overwrite_existing_password(password_setup):
    client, _, _, _ = password_setup
    first = setup_password(client, wx_login(client).json()).json()
    result = setup_password(client, first['session'], 'bravo', NEW_PASSWORD)
    assert result.status_code == 409
    assert login(client).status_code == 200
    assert login(client, 'bravo', NEW_PASSWORD).status_code == 401


def test_setup_requires_authenticated_recent_wechat_session(password_setup):
    client, db, _, _ = password_setup
    assert client.post('/api/v1/account/password/setup', json={'username':'alice','password':PASSWORD}).status_code == 401
    pending = client.post('/api/v1/auth/apple/challenge').json()['challenge']
    apple = client.post('/api/v1/auth/apple', json={'challenge':pending,'code':'code','identity_token':'token'}).json()
    assert setup_password(client, apple).status_code == 409
    current = wx_login(client).json()
    with db.begin() as conn:
        conn.execute(update(sessions).where(sessions.c.account_id == current['account']['id']).values(created_at=int(time.time())-601))
    response = setup_password(client, current)
    assert response.status_code == 403 and response.json()['detail']['code'] == 'recent_wechat_login_required'
    with db.connect() as conn:
        assert conn.execute(select(password_credentials)).first() is None


def test_session_revoked_during_hash_cannot_add_password(password_setup, monkeypatch):
    from zhouji_api import passwords
    client, db, _, _ = password_setup
    current = wx_login(client).json()
    original = passwords.hash_password
    def hash_then_revoke(value):
        hashed = original(value)
        with db.begin() as conn:
            conn.execute(delete(sessions).where(sessions.c.account_id == current['account']['id']))
        return hashed
    monkeypatch.setattr(passwords, 'hash_password', hash_then_revoke)
    assert setup_password(client, current).status_code == 401
    with db.connect() as conn:
        assert conn.execute(select(password_credentials)).first() is None


def test_setup_rechecks_recent_authorization_after_hash(password_setup, monkeypatch):
    from zhouji_api import passwords
    client, db, _, _ = password_setup
    current = wx_login(client).json()
    original = passwords.hash_password
    def hash_then_age(value):
        hashed = original(value)
        with db.begin() as conn:
            conn.execute(update(sessions).where(sessions.c.account_id == current['account']['id']).values(created_at=int(time.time())-601))
        return hashed
    monkeypatch.setattr(passwords, 'hash_password', hash_then_age)
    assert setup_password(client, current).status_code == 403
    with db.connect() as conn:
        assert conn.execute(select(password_credentials)).first() is None


def test_original_wechat_can_recover_and_unbind_after_setup(password_setup):
    client, db, _, _ = password_setup
    original = wx_login(client).json()
    result = setup_password(client, original).json()
    body = {'username':'alice','recovery_code':result['recovery_code'],'new_password':NEW_PASSWORD}
    assert client.post('/api/v1/auth/password/recover', json=body).status_code == 200
    current = login(client, password=NEW_PASSWORD).json()
    unbound = client.request('DELETE', '/api/v1/account/wechat/binding', headers=headers(current), json={'password':NEW_PASSWORD})
    assert unbound.status_code == 200 and not unbound.json()['account']['wechat_bound']
    assert login(client, password=NEW_PASSWORD).json()['account']['id'] == original['account']['id']
    with db.connect() as conn:
        row = conn.execute(select(accounts)).mappings().one()
        assert row['provider'] == 'wechat' and row['wechat_subject'] is None
