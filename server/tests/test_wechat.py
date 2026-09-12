import time
from unittest.mock import Mock

from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
import httpx
import pytest
from sqlalchemy import create_engine, select, update
from sqlalchemy.pool import StaticPool

from zhouji_api.app import create_app
from zhouji_api.apple import InvalidIdentity, ProviderUnavailable
from zhouji_api.models import accounts, metadata, sessions
from zhouji_api.wechat import WeChatProvider, WeChatSettings


@pytest.fixture
def setup():
    db = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    metadata.create_all(db)
    apple, wechat = Mock(), Mock()
    # Identical provider subjects must still produce separate accounts.
    apple.exchange.return_value = wechat.exchange.return_value = ('shared-subject', 'encrypted-refresh')
    with TestClient(create_app(engine=db, apple_provider=apple, wechat_provider=wechat)) as client:
        yield client, db, apple, wechat


def login(client, provider='wechat'):
    challenge = client.post(f'/api/v1/auth/{provider}/challenge').json()['challenge']
    body = {'challenge': challenge, 'code': 'one-use-code'}
    if provider == 'apple':
        body['identity_token'] = 'signed-identity'
    result = client.post(f'/api/v1/auth/{provider}', json=body)
    return result, body


def test_provider_bound_challenge_replay_and_isolated_accounts(setup):
    client, db, apple, wechat = setup
    c = client.post('/api/v1/auth/apple/challenge').json()['challenge']
    assert client.post('/api/v1/auth/wechat', json={'challenge': c, 'code': 'code'}).status_code == 401
    wechat.exchange.assert_not_called()
    a, _ = login(client, 'apple')
    w, body = login(client)
    assert a.status_code == w.status_code == 200
    assert w.json()['account']['provider'] == 'wechat'
    assert a.json()['account']['id'] != w.json()['account']['id']
    assert client.post('/api/v1/auth/wechat', json=body).status_code == 401
    again, _ = login(client)
    assert again.json()['account']['id'] == w.json()['account']['id']
    with db.connect() as conn:
        row = conn.execute(select(accounts).where(accounts.c.provider == 'wechat')).mappings().one()
        assert row['apple_subject'] is None and row['apple_refresh_encrypted'] is None
        assert row['wechat_refresh_encrypted'] == 'encrypted-refresh'


def test_wechat_profile_restore_logout_delete_do_not_revoke_apple(setup):
    client, db, apple, wechat = setup
    a, _ = login(client, 'apple')
    w, _ = login(client)
    h = {'Authorization': 'Bearer ' + w.json()['token']}
    assert client.patch('/api/v1/account/profile', headers=h,
                        json={'nickname': '微信小粥', 'avatar': 'leaf'}).status_code == 200
    with db.begin() as conn:
        conn.execute(update(accounts).where(accounts.c.provider == 'wechat').values(verified_at=1))
    assert client.get('/api/v1/account', headers=h).json()['nickname'] == '微信小粥'
    wechat.validate_refresh.assert_called_once_with('encrypted-refresh', 'shared-subject')
    apple.validate_refresh.assert_not_called()
    other, _ = login(client)
    assert client.post('/api/v1/auth/logout', headers=h).status_code == 204
    assert client.get('/api/v1/account', headers=h).status_code == 401
    h2 = {'Authorization': 'Bearer ' + other.json()['token']}
    assert client.delete('/api/v1/account', headers=h2).status_code == 204
    assert client.get('/api/v1/account', headers=h2).status_code == 401
    apple.revoke.assert_not_called()
    wechat.revoke.assert_not_called()
    assert client.get('/api/v1/account', headers={'Authorization': 'Bearer ' + a.json()['token']}).status_code == 200


def test_revoked_wechat_grant_clears_only_its_sessions(setup):
    client, db, apple, wechat = setup
    login(client, 'apple')
    w, _ = login(client)
    login(client)
    with db.begin() as conn:
        conn.execute(update(accounts).where(accounts.c.provider == 'wechat').values(verified_at=1))
    wechat.validate_refresh.side_effect = InvalidIdentity
    assert client.get('/api/v1/account', headers={'Authorization': 'Bearer ' + w.json()['token']}).status_code == 401
    with db.connect() as conn:
        assert len(conn.execute(select(sessions)).all()) == 1


def test_failed_exchange_is_consumed_and_no_credential_is_echoed(setup):
    client, db, apple, wechat = setup
    wechat.exchange.side_effect = ProviderUnavailable
    response, body = login(client)
    assert response.status_code == 503
    assert 'one-use-code' not in response.text
    assert response.headers['cache-control'] == 'no-store'
    assert client.post('/api/v1/auth/wechat', json=body).status_code == 401
    assert client.post('/api/v1/auth/wechat', json={'code': 'private-code'}).status_code == 422
    with db.connect() as conn:
        assert conn.execute(select(accounts)).first() is None


@pytest.fixture
def provider():
    return WeChatProvider(WeChatSettings('test-app', 'test-secret', Fernet.generate_key()))


def test_exchange_checks_grant_encrypts_refresh_and_validates_subject(provider):
    provider._get = Mock(side_effect=[{'openid': 'subject', 'access_token': 'access',
                                      'refresh_token': 'private-refresh', 'scope': 'snsapi_userinfo'}, {'errcode': 0}])
    subject, encrypted = provider.exchange('code')
    assert subject == 'subject' and 'private-refresh' not in encrypted
    assert provider.cipher.decrypt(encrypted.encode()) == b'private-refresh'
    assert provider._get.call_args_list[1].args == ('auth', {'access_token': 'access', 'openid': 'subject'})
    provider._get = Mock(return_value={'openid': 'other', 'access_token': 'access'})
    with pytest.raises(InvalidIdentity):
        provider.validate_refresh(encrypted, subject)


@pytest.mark.parametrize('payload', [{}, {'openid': '', 'scope': 'snsapi_userinfo'},
    {'openid': 'subject', 'access_token': 'access', 'refresh_token': 'refresh', 'scope': 'other'}])
def test_exchange_rejects_missing_identity_and_wrong_scope(provider, payload):
    provider._get = Mock(return_value=payload)
    with pytest.raises((InvalidIdentity, ProviderUnavailable)):
        provider.exchange('code')


@pytest.mark.parametrize('payload,error', [({'errcode': 40029}, InvalidIdentity),
    ({'errcode': 40163}, InvalidIdentity), ({'errcode': 40013}, ProviderUnavailable), ([], ProviderUnavailable)])
def test_official_api_errors_are_redacted(provider, monkeypatch, payload, error):
    client = Mock()
    client.get.return_value = httpx.Response(200, json=payload)
    factory = Mock()
    factory.return_value.__enter__ = Mock(return_value=client)
    factory.return_value.__exit__ = Mock(return_value=False)
    monkeypatch.setattr(httpx, 'Client', factory)
    with pytest.raises(error) as failure:
        provider._get('oauth2/access_token', {'secret': 'never-echo'})
    assert 'never-echo' not in str(failure.value)


def test_incomplete_auth_success_and_corrupt_encryption_fail_safely(provider):
    provider._get = Mock(return_value={})
    with pytest.raises(ProviderUnavailable):
        provider._validate_access('access', 'subject')
    with pytest.raises(ProviderUnavailable):
        provider.validate_refresh('broken-ciphertext', 'subject')


def test_optional_configuration_requires_all_private_files(monkeypatch, tmp_path):
    from zhouji_api.settings import ConfigurationError
    for name in ['ZHOUJI_WECHAT_APP_ID', 'ZHOUJI_WECHAT_APP_SECRET_PATH', 'ZHOUJI_TOKEN_ENCRYPTION_KEY_PATH']:
        monkeypatch.delenv(name, raising=False)
    assert WeChatSettings.from_environment() is None
    monkeypatch.setenv('ZHOUJI_WECHAT_APP_SECRET_PATH', str(tmp_path / 'missing'))
    with pytest.raises(ConfigurationError):
        WeChatSettings.from_environment()
