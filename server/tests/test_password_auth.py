from sqlalchemy import select

from zhouji_api.models import accounts, password_credentials, sessions

PASSWORD = 'a safe initial password'
NEW_PASSWORD = 'a different safe password'


def register(client, username='alice'):
    response = client.post('/api/v1/auth/password/register', json={'username': username, 'password': PASSWORD})
    assert response.status_code == 200, response.text
    return response.json()


def headers(session):
    return {'Authorization': 'Bearer ' + session['token']}


def login(client, username='alice', password=PASSWORD):
    return client.post('/api/v1/auth/password/login', json={'username': username, 'password': password})


def test_register_login_profile_logout_delete(password_setup):
    client, db, _, _ = password_setup
    result = register(client, ' Alice ')
    first = result['session']
    account = first['account']
    assert account['username'] == 'alice'
    assert account['provider'] == 'password'
    assert account['has_password'] is True and account['wechat_bound'] is False
    assert account['nickname'] == '粥记用户' and account['avatar'] == 'sunrise'
    assert client.get('/api/v1/account', headers=headers(first)).json() == account
    assert 'password_hash' not in str(account) and 'recovery_hash' not in str(account)
    assert client.post('/api/v1/auth/password/register', json={'username': 'ALICE', 'password': PASSWORD}).status_code == 409
    second = login(client).json()
    assert second['account']['id'] == account['id']
    assert client.patch('/api/v1/account/profile', headers=headers(second), json={'nickname':'新昵称', 'avatar':'leaf'}).status_code == 200
    assert client.post('/api/v1/auth/logout', headers=headers(first)).status_code == 204
    assert client.get('/api/v1/account', headers=headers(first)).status_code == 401
    assert client.delete('/api/v1/account', headers=headers(second)).status_code == 204
    assert client.get('/api/v1/account', headers=headers(second)).status_code == 401
    with db.connect() as conn:
        assert conn.execute(select(accounts)).first() is None
        assert conn.execute(select(password_credentials)).first() is None
        assert conn.execute(select(sessions)).first() is None


def test_recovery_consumes_code_and_revokes_all_sessions(password_setup):
    client, _, _, _ = password_setup
    result = register(client)
    second = login(client).json()
    body = {'username':'alice', 'recovery_code':result['recovery_code'], 'new_password':NEW_PASSWORD}
    reset = client.post('/api/v1/auth/password/recover', json=body)
    assert reset.status_code == 200
    assert reset.json()['recovery_code'] != result['recovery_code']
    assert client.post('/api/v1/auth/password/recover', json=body).status_code == 401
    assert login(client).status_code == 401
    assert login(client, password=NEW_PASSWORD).status_code == 200
    for session in (result['session'], second):
        assert client.get('/api/v1/account', headers=headers(session)).status_code == 401


def test_change_and_rotate_issue_replacement_session(password_setup):
    client, _, _, _ = password_setup
    result = register(client)
    old = result['session']
    change = client.post('/api/v1/account/password/change', headers=headers(old), json={'password':PASSWORD,'new_password':NEW_PASSWORD})
    assert change.status_code == 200
    assert change.json()['account']['id'] == old['account']['id']
    assert client.get('/api/v1/account', headers=headers(old)).status_code == 401
    rotated = client.post('/api/v1/account/password/recovery-code', headers=headers(change.json()), json={'password':NEW_PASSWORD})
    assert rotated.status_code == 200
    assert rotated.json()['recovery_code'] != result['recovery_code']
    assert client.get('/api/v1/account', headers=headers(change.json())).status_code == 401
    assert client.get('/api/v1/account', headers=headers(rotated.json()['session'])).status_code == 200


def test_lost_response_does_not_reactivate_old_recovery(password_setup):
    client, _, _, _ = password_setup
    result = register(client)
    body = {'username':'alice','recovery_code':result['recovery_code'],'new_password':NEW_PASSWORD}
    assert client.post('/api/v1/auth/password/recover', json=body).status_code == 200
    current = login(client, password=NEW_PASSWORD).json()
    assert client.post('/api/v1/auth/password/recover', json=body).status_code == 401
    assert client.post('/api/v1/account/password/recovery-code', headers=headers(current), json={'password':NEW_PASSWORD}).status_code == 200


def test_errors_never_echo_secrets_and_bad_login_is_not_session_expiry(password_setup):
    client, _, _, _ = password_setup
    result = register(client)
    response = login(client, password='a deliberately wrong password')
    assert response.status_code == 401
    assert response.json()['detail']['code'] == 'invalid_credentials'
    assert client.get('/api/v1/account', headers=headers(result['session'])).status_code == 200
    for path, body in (
        ('auth/password/register', {'username':'bad','password':'secret-short'}),
        ('auth/password/recover', {'username':'alice','recovery_code':'secret-code','new_password':NEW_PASSWORD}),
        ('auth/password/login', {'username':'alice','password':PASSWORD,'unexpected':'private'}),
    ):
        response = client.post('/api/v1/'+path, json=body)
        assert response.status_code in (401, 422)
        assert PASSWORD not in response.text and NEW_PASSWORD not in response.text
        assert 'secret-code' not in response.text and 'secret-short' not in response.text


def test_wrong_password_counter_survives_app_restart(password_setup):
    client, db, apple, wechat = password_setup
    register(client)
    for _ in range(5):
        assert login(client, password='wrong but long password').status_code == 401
    from fastapi.testclient import TestClient
    from zhouji_api.app import create_app
    with TestClient(create_app(engine=db, apple_provider=apple, wechat_provider=wechat)) as restarted:
        assert login(restarted).status_code == 429


def test_deleted_session_cannot_remove_account_after_password_recovery(password_setup, monkeypatch):
    from zhouji_api.account_sessions import AccountSessions
    client, _, _, _ = password_setup
    registered = register(client)
    current = registered['session']
    original = AccountSessions.authenticate
    intercepted = False

    def authenticate_then_recover(self, authorization, conn=None, *, lock=False):
        nonlocal intercepted
        result = original(self, authorization, conn, lock=lock)
        if conn is None and authorization == headers(current)['Authorization'] and not intercepted:
            intercepted = True
            response = client.post('/api/v1/auth/password/recover', json={
                'username': 'alice', 'recovery_code': registered['recovery_code'], 'new_password': NEW_PASSWORD})
            assert response.status_code == 200
        return result

    monkeypatch.setattr(AccountSessions, 'authenticate', authenticate_then_recover)
    assert client.delete('/api/v1/account', headers=headers(current)).status_code == 401
    assert login(client, password=NEW_PASSWORD).status_code == 200
