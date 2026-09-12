import time
from unittest.mock import Mock

from cryptography.fernet import Fernet
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from fastapi.testclient import TestClient
import httpx
import jwt
import pytest
from sqlalchemy import create_engine, select, update
from sqlalchemy.pool import StaticPool

from zhouji_api.app import create_app
from zhouji_api.apple import AppleProvider, AppleSettings, InvalidIdentity, ProviderUnavailable
from zhouji_api.auth import digest
from zhouji_api.models import accounts, challenges, metadata, sessions


@pytest.fixture
def setup():
    db = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    metadata.create_all(db)
    provider = Mock()
    provider.exchange.return_value = ('test-subject', 'encrypted-refresh')
    with TestClient(create_app(engine=db, apple_provider=provider)) as client:
        yield client, db, provider


def login(client):
    challenge = client.post('/api/v1/auth/apple/challenge').json()
    body = {'challenge': challenge['challenge'], 'code': 'one-use-code', 'identity_token': 'signed-token'}
    response = client.post('/api/v1/auth/apple', json=body)
    return response, body, challenge


def test_login_repeat_identity_logout_and_storage(setup):
    client, db, provider = setup
    first, body, challenge = login(client)
    assert first.status_code == 200
    result = first.json()
    provider.exchange.assert_called_with('one-use-code', 'signed-token', challenge['nonce'])
    headers = {'Authorization': 'Bearer ' + result['token']}
    assert client.get('/api/v1/account', headers=headers).json() == result['account']
    second, _, _ = login(client)
    assert second.json()['account'] == result['account']
    assert second.json()['token'] != result['token']
    with db.connect() as conn:
        row = conn.execute(select(sessions).where(sessions.c.token_hash == digest(result['token']))).mappings().one()
        assert result['token'] not in repr(row)
        assert len(conn.execute(select(accounts)).all()) == 1
    assert client.post('/api/v1/auth/apple', json=body).status_code == 401
    assert client.post('/api/v1/auth/logout', headers=headers).status_code == 204
    assert client.post('/api/v1/auth/logout', headers=headers).status_code == 204
    assert client.get('/api/v1/account', headers=headers).status_code == 401
    assert client.get('/api/v1/account', headers={'Authorization': 'Bearer ' + second.json()['token']}).status_code == 200


def test_invalid_expired_challenge_and_failed_exchange_are_consumed(setup):
    client, db, provider = setup
    c = client.post('/api/v1/auth/apple/challenge').json()
    with db.begin() as conn:
        conn.execute(update(challenges).values(expires_at=1))
    body = {'challenge': c['challenge'], 'code': 'x', 'identity_token': 'private-token'}
    assert client.post('/api/v1/auth/apple', json=body).status_code == 401
    provider.exchange.assert_not_called()
    provider.exchange.side_effect = InvalidIdentity
    response, body, _ = login(client)
    assert response.status_code == 401
    provider.exchange.reset_mock()
    assert client.post('/api/v1/auth/apple', json=body).status_code == 401
    provider.exchange.assert_not_called()


def test_validation_errors_and_database_errors_never_echo_tokens(setup):
    client, db, provider = setup
    response = client.post('/api/v1/auth/apple', json={'identity_token': 'secret-never-echo'})
    assert response.status_code == 422
    assert 'secret-never-echo' not in response.text
    assert response.headers['cache-control'] == 'no-store'
    provider.exchange.side_effect = ProviderUnavailable
    response, _, _ = login(client)
    assert response.status_code == 503
    with db.connect() as conn:
        assert conn.execute(select(accounts)).first() is None


def test_expired_session_and_cross_account_isolation(setup):
    client, db, provider = setup
    first, _, _ = login(client)
    provider.exchange.return_value = ('different-apple-user', 'other-encrypted')
    second, _, _ = login(client)
    h1 = {'Authorization': 'Bearer ' + first.json()['token']}
    h2 = {'Authorization': 'Bearer ' + second.json()['token']}
    assert first.json()['account']['id'] != second.json()['account']['id']
    assert client.delete('/api/v1/account', headers=h1).status_code == 204
    assert client.get('/api/v1/account', headers=h1).status_code == 401
    assert client.get('/api/v1/account', headers=h2).status_code == 200
    with db.begin() as conn:
        conn.execute(update(sessions).values(expires_at=1))
    assert client.get('/api/v1/account', headers=h2).status_code == 401


def test_delete_requires_recent_auth_and_preserves_account_if_revoke_fails(setup):
    client, db, provider = setup
    result, _, _ = login(client)
    headers = {'Authorization': 'Bearer ' + result.json()['token']}
    provider.revoke.side_effect = ProviderUnavailable
    assert client.delete('/api/v1/account', headers=headers).status_code == 503
    assert client.get('/api/v1/account', headers=headers).status_code == 200
    provider.revoke.side_effect = None
    with db.begin() as conn:
        conn.execute(update(sessions).values(created_at=1))
    assert client.delete('/api/v1/account', headers=headers).status_code == 403
    with db.begin() as conn:
        conn.execute(update(sessions).values(created_at=int(time.time())))
    assert client.delete('/api/v1/account', headers=headers).status_code == 204
    with db.connect() as conn:
        assert conn.execute(select(accounts)).first() is None
        assert conn.execute(select(sessions)).first() is None


def test_daily_apple_revocation_invalidates_all_sessions(setup):
    client, db, provider = setup
    result, _, _ = login(client)
    login(client)
    with db.begin() as conn:
        conn.execute(update(accounts).values(verified_at=1))
    provider.validate_refresh.side_effect = InvalidIdentity
    headers = {'Authorization': 'Bearer ' + result.json()['token']}
    assert client.get('/api/v1/account', headers=headers).status_code == 401
    with db.connect() as conn:
        assert conn.execute(select(sessions)).first() is None


def test_rate_limit(setup):
    client, _, _ = setup
    for _ in range(20):
        assert client.post('/api/v1/auth/apple/challenge').status_code == 200
    assert client.post('/api/v1/auth/apple/challenge').status_code == 429


@pytest.fixture
def apple():
    settings = AppleSettings('test-team', 'test-client', 'test-kid', ec.generate_private_key(ec.SECP256R1()), Fernet.generate_key())
    provider = AppleProvider(settings)
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    provider.keys = Mock()
    provider.keys.get_signing_key_from_jwt.return_value.key = private.public_key()
    def token(**changes):
        claims = {'iss': 'https://appleid.apple.com', 'aud': 'test-client', 'sub': 'subject',
                  'exp': int(time.time()) + 300, 'iat': int(time.time()), 'nonce': 'expected', **changes}
        return jwt.encode(claims, private, algorithm='RS256', headers={'kid': 'fixture'})
    return provider, token


@pytest.mark.parametrize('changes', [{'aud':'wrong'}, {'iss':'wrong'}, {'exp':1}, {'nonce':'wrong'}, {'sub':''}])
def test_verifies_apple_signature_issuer_audience_expiry_and_nonce(apple, changes):
    provider, token = apple
    with pytest.raises(InvalidIdentity):
        provider.verify(token(**changes), 'expected')


def test_rejects_wrong_signature_missing_claim_and_algorithm_confusion(apple):
    provider, token = apple
    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    forged = jwt.encode({'sub':'subject'}, other, algorithm='RS256')
    for value in [forged, jwt.encode({'sub':'subject'}, 'test-key'*8, algorithm='HS256'), 'invalid']:
        with pytest.raises(InvalidIdentity):
            provider.verify(value)
    assert provider.verify(token(), 'expected')['sub'] == 'subject'


def test_exchange_binds_both_tokens_and_encrypts_refresh(apple):
    provider, token = apple
    provider._post = Mock(return_value={'id_token': token(), 'refresh_token': 'private-refresh'})
    subject, encrypted = provider.exchange('code', token(), 'expected')
    assert subject == 'subject' and 'private-refresh' not in encrypted
    assert provider.cipher.decrypt(encrypted.encode()) == b'private-refresh'
    provider._post.return_value['id_token'] = token(sub='different')
    with pytest.raises(InvalidIdentity):
        provider.exchange('code', token(), 'expected')


def test_client_secret_is_short_lived_es256_and_empty_revoke_body_is_success(apple, monkeypatch):
    provider, _ = apple
    secret = provider.client_secret()
    claims = jwt.decode(secret, provider.settings.private_key.public_key(), algorithms=['ES256'],
                        audience='https://appleid.apple.com', issuer='test-team')
    assert claims['sub'] == 'test-client' and claims['exp'] - claims['iat'] == 300
    assert jwt.get_unverified_header(secret)['kid'] == 'test-kid'
    factory = Mock()
    factory.return_value.__enter__ = Mock(return_value=Mock(post=Mock(return_value=httpx.Response(200))))
    factory.return_value.__exit__ = Mock(return_value=False)
    monkeypatch.setattr(httpx, 'Client', factory)
    provider.revoke(provider.cipher.encrypt(b'private-refresh').decode())
