"""Apple OAuth adapter. No credentials or provider responses are logged."""
from dataclasses import dataclass, field
import hmac
import os
from pathlib import Path
import time

import httpx
import jwt
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from .settings import ConfigurationError


class InvalidIdentity(Exception):
    pass


class ProviderUnavailable(Exception):
    pass


@dataclass(frozen=True)
class AppleSettings:
    team_id: str
    client_id: str
    key_id: str = field(repr=False)
    private_key: bytes = field(repr=False)
    encryption_key: bytes = field(repr=False)

    @classmethod
    def from_environment(cls):
        keys = ['ZHOUJI_APPLE_TEAM_ID', 'ZHOUJI_APPLE_CLIENT_ID', 'ZHOUJI_APPLE_KEY_ID',
                'ZHOUJI_APPLE_PRIVATE_KEY_PATH', 'ZHOUJI_TOKEN_ENCRYPTION_KEY_PATH']
        if not any(os.environ.get(k) for k in keys):
            return None
        if not all(os.environ.get(k) for k in keys):
            raise ConfigurationError('Apple 登录配置不完整')
        try:
            private = Path(os.environ[keys[3]]).read_bytes()
            encryption = Path(os.environ[keys[4]]).read_bytes().strip()
            key = serialization.load_pem_private_key(private, password=None)
            if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
                raise ValueError
            Fernet(encryption)
        except (OSError, ValueError, TypeError):
            raise ConfigurationError('Apple 私钥或令牌加密配置无效') from None
        return cls(*(os.environ[k] for k in keys[:3]), private, encryption)


class AppleProvider:
    def __init__(self, settings: AppleSettings):
        self.settings = settings
        self.cipher = Fernet(settings.encryption_key)
        self.keys = jwt.PyJWKClient('https://appleid.apple.com/auth/keys', timeout=8)

    def client_secret(self):
        now = int(time.time())
        return jwt.encode({'iss': self.settings.team_id, 'iat': now, 'exp': now + 300,
                           'aud': 'https://appleid.apple.com', 'sub': self.settings.client_id},
                          self.settings.private_key, algorithm='ES256',
                          headers={'kid': self.settings.key_id})

    def verify(self, token: str, nonce: str | None = None):
        try:
            # Pin the algorithm independently of the untrusted header/JWK metadata.
            if jwt.get_unverified_header(token).get('alg') != 'RS256':
                raise InvalidIdentity
            key = self.keys.get_signing_key_from_jwt(token).key
            claims = jwt.decode(token, key, algorithms=['RS256'],
                                audience=self.settings.client_id, issuer='https://appleid.apple.com',
                                options={'require': ['exp', 'iat', 'sub', 'iss', 'aud']}, leeway=10)
            if not isinstance(claims['sub'], str) or not 1 <= len(claims['sub']) <= 255:
                raise InvalidIdentity
            if nonce is not None and not hmac.compare_digest(str(claims.get('nonce', '')), nonce):
                raise InvalidIdentity
            return claims
        except jwt.PyJWKClientConnectionError:
            raise ProviderUnavailable from None
        except jwt.PyJWTError:
            raise InvalidIdentity from None

    def _post(self, endpoint, data):
        try:
            with httpx.Client(timeout=10, follow_redirects=False) as client:
                response = client.post('https://appleid.apple.com/auth/' + endpoint,
                                       data={'client_id': self.settings.client_id,
                                             'client_secret': self.client_secret(), **data})
            if response.status_code >= 500 or response.status_code == 429:
                raise ProviderUnavailable
            if endpoint == 'revoke' and response.status_code == 200:
                return {}
            payload = response.json()
            if not isinstance(payload, dict):
                raise ProviderUnavailable
            if payload.get('error') == 'invalid_grant':
                raise InvalidIdentity
            if response.status_code != 200 or payload.get('error'):
                raise ProviderUnavailable
            return payload
        except (httpx.HTTPError, ValueError):
            raise ProviderUnavailable from None

    def exchange(self, code, identity_token, nonce):
        claims = self.verify(identity_token, nonce)
        payload = self._post('token', {'grant_type': 'authorization_code', 'code': code})
        if not isinstance(payload.get('id_token'), str) or not isinstance(payload.get('refresh_token'), str):
            raise ProviderUnavailable
        exchanged = self.verify(payload['id_token'], nonce)
        if not hmac.compare_digest(claims['sub'], exchanged['sub']):
            raise InvalidIdentity
        return claims['sub'], self.cipher.encrypt(payload['refresh_token'].encode()).decode()

    def validate_refresh(self, encrypted, subject):
        refresh = self.cipher.decrypt(encrypted.encode()).decode()
        payload = self._post('token', {'grant_type': 'refresh_token', 'refresh_token': refresh})
        if not isinstance(payload.get('id_token'), str):
            raise ProviderUnavailable
        claims = self.verify(payload['id_token'])
        if not hmac.compare_digest(claims['sub'], subject):
            raise InvalidIdentity

    def revoke(self, encrypted):
        refresh = self.cipher.decrypt(encrypted.encode()).decode()
        try:
            self._post('revoke', {'token': refresh, 'token_type_hint': 'refresh_token'})
        except InvalidIdentity:
            # An already-invalid grant does not prevent removal of the local account.
            pass
