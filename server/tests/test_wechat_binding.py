import time

from sqlalchemy import select, update

from zhouji_api.apple import InvalidIdentity
from zhouji_api.models import accounts, password_credentials
from test_password_auth import register, headers, login, PASSWORD, NEW_PASSWORD


def wx_login(client):
    challenge = client.post('/api/v1/auth/wechat/challenge').json()['challenge']
    return client.post('/api/v1/auth/wechat', json={'challenge':challenge, 'code':'wx-code'})


def binding_challenge(client, session):
    result = client.post('/api/v1/account/wechat/binding/challenge', headers=headers(session), json={'password':PASSWORD})
    assert result.status_code == 200, result.text
    return result.json()['challenge']


def complete_binding(client, session, challenge):
    return client.post('/api/v1/account/wechat/binding', headers=headers(session), json={'challenge':challenge,'code':'wx-code'})


def test_bind_then_wechat_login_same_account(password_setup):
    client, db, _, _ = password_setup
    current = register(client)['session']
    response = complete_binding(client, current, binding_challenge(client,current))
    assert response.status_code == 200
    assert response.json()['account']['id'] == current['account']['id']
    via_wx = wx_login(client).json()
    assert via_wx['account']['id'] == current['account']['id']
    assert via_wx['account']['has_password'] is True
    assert via_wx['account']['provider'] == 'wechat'
    assert login(client).json()['account']['provider'] == 'password'
    assert complete_binding(client,current,binding_challenge(client,current)).status_code == 200
    with db.connect() as conn:
        assert len(conn.execute(select(accounts)).all()) == 1


def test_binding_rejects_foreign_session_and_login_challenge(password_setup):
    client, _, _, _ = password_setup
    current = register(client)['session']
    pending = binding_challenge(client,current)
    second = login(client).json()
    assert complete_binding(client,second,pending).status_code == 401
    ordinary = client.post('/api/v1/auth/wechat/challenge').json()['challenge']
    assert complete_binding(client,current,ordinary).status_code == 401
    assert client.get('/api/v1/account',headers=headers(current)).json()['wechat_bound'] is False


def test_existing_independent_wechat_account_is_not_merged(password_setup):
    client, db, _, _ = password_setup
    original = wx_login(client).json()
    current = register(client)['session']
    response = complete_binding(client,current,binding_challenge(client,current))
    assert response.status_code == 409
    assert response.json()['detail']['code'] == 'wechat_in_use'
    assert wx_login(client).json()['account']['id'] == original['account']['id']
    with db.connect() as conn:
        assert len(conn.execute(select(accounts)).all()) == 2


def test_late_binding_after_logout_or_password_change_fails(password_setup):
    client, _, _, wechat = password_setup
    current = register(client)['session']
    pending = binding_challenge(client,current)
    def exchange_after_logout(code):
        assert client.post('/api/v1/auth/logout',headers=headers(current)).status_code == 204
        return 'late-subject', 'encrypted'
    wechat.exchange.side_effect = exchange_after_logout
    assert complete_binding(client,current,pending).status_code == 401
    current = login(client).json()
    assert client.get('/api/v1/account',headers=headers(current)).json()['wechat_bound'] is False
    pending = binding_challenge(client,current)
    changed = client.post('/api/v1/account/password/change',headers=headers(current),json={'password':PASSWORD,'new_password':NEW_PASSWORD})
    assert changed.status_code == 200
    assert complete_binding(client,current,pending).status_code == 401


def test_unbind_and_revocation_preserve_password_sessions(password_setup):
    client, db, _, wechat = password_setup
    password_session = register(client)['session']
    assert complete_binding(client,password_session,binding_challenge(client,password_session)).status_code == 200
    wx_session = wx_login(client).json()
    with db.begin() as conn:
        conn.execute(update(accounts).values(verified_at=1))
    wechat.validate_refresh.side_effect = InvalidIdentity
    assert client.get('/api/v1/account',headers=headers(wx_session)).status_code == 401
    assert client.get('/api/v1/account',headers=headers(password_session)).status_code == 200
    wechat.validate_refresh.side_effect = None
    wx_session = wx_login(client).json()
    response = client.request('DELETE','/api/v1/account/wechat/binding',headers=headers(wx_session),json={'password':PASSWORD})
    assert response.status_code == 200
    assert response.json()['session']['account']['provider'] == 'password'
    assert response.json()['account']['wechat_bound'] is False
    assert response.json()['account']['id'] == password_session['account']['id']
    assert client.get('/api/v1/account',headers=headers(wx_session)).status_code == 401
    assert client.get('/api/v1/account',headers=headers(password_session)).status_code == 200
    with db.connect() as conn:
        assert conn.execute(select(password_credentials)).first() is not None


def test_delete_during_binding_cannot_restore_account(password_setup):
    client, db, _, wechat = password_setup
    current = register(client)['session']
    pending = binding_challenge(client,current)
    def exchange_after_delete(code):
        assert client.delete('/api/v1/account',headers=headers(current)).status_code == 204
        return 'deleted-subject', 'encrypted'
    wechat.exchange.side_effect = exchange_after_delete
    assert complete_binding(client,current,pending).status_code == 401
    with db.connect() as conn:
        assert conn.execute(select(accounts)).first() is None


def test_old_refresh_failure_cannot_revoke_new_binding_session(password_setup):
    client, db, _, wechat = password_setup
    current = register(client)['session']
    assert complete_binding(client,current,binding_challenge(client,current)).status_code == 200
    old_wx = wx_login(client).json()
    with db.begin() as conn:
        conn.execute(update(accounts).values(verified_at=1))
    new_wx = []
    def revoke_old_grant(encrypted, subject):
        # Another authorization refreshes the same identity while the older request is pending.
        wechat.exchange.return_value = ('wechat-test-subject', 'new-encrypted-grant')
        new_wx.append(wx_login(client).json())
        raise InvalidIdentity
    wechat.validate_refresh.side_effect = revoke_old_grant
    client.get('/api/v1/account',headers=headers(old_wx))
    wechat.validate_refresh.side_effect = None
    assert client.get('/api/v1/account',headers=headers(new_wx[0])).status_code == 200


def test_binding_that_expires_during_exchange_is_rejected(password_setup, monkeypatch):
    client, _, _, wechat = password_setup
    current = register(client)['session']
    now = [int(time.time())]
    monkeypatch.setattr('zhouji_api.wechat_binding.time.time', lambda: now[0])
    pending = binding_challenge(client, current)
    def slow_exchange(code):
        now[0] += 301
        return 'late-subject', 'encrypted'
    wechat.exchange.side_effect = slow_exchange
    response = complete_binding(client, current, pending)
    assert response.status_code == 401
    assert client.get('/api/v1/account', headers=headers(current)).json()['wechat_bound'] is False


def legacy_wechat_session(db, account):
    import hashlib
    from sqlalchemy import insert
    from zhouji_api.models import sessions
    token = 'legacy-wechat-test-token'
    with db.begin() as conn:
        conn.execute(insert(sessions).values(token_hash=hashlib.sha256(token.encode()).hexdigest(),
            account_id=account['id'], created_at=int(time.time()), expires_at=int(time.time()) + 3600))
    return {'token': token}


def test_legacy_wechat_session_on_bound_password_account_cannot_survive_unbinding(password_setup):
    client, db, _, _ = password_setup
    current = register(client)['session']
    assert complete_binding(client, current, binding_challenge(client, current)).status_code == 200
    legacy = legacy_wechat_session(db, current['account'])
    assert client.get('/api/v1/account', headers=headers(legacy)).json()['provider'] == 'wechat'
    response = client.request('DELETE', '/api/v1/account/wechat/binding', headers=headers(legacy), json={'password': PASSWORD})
    assert response.status_code == 200
    assert response.json()['session']['account']['provider'] == 'password'
    assert client.get('/api/v1/account', headers=headers(legacy)).status_code == 401
    assert client.get('/api/v1/account', headers=headers(current)).status_code == 200


def test_platform_revocation_includes_legacy_wechat_sessions_on_password_account(password_setup):
    client, db, _, wechat = password_setup
    current = register(client)['session']
    assert complete_binding(client, current, binding_challenge(client, current)).status_code == 200
    legacy = legacy_wechat_session(db, current['account'])
    with db.begin() as conn:
        conn.execute(update(accounts).values(verified_at=1))
    wechat.validate_refresh.side_effect = InvalidIdentity
    assert client.get('/api/v1/account', headers=headers(legacy)).status_code == 401
    assert client.get('/api/v1/account', headers=headers(current)).status_code == 200
