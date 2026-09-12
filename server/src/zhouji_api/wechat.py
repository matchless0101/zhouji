"""Official WeChat OAuth endpoints; provider credentials never enter responses/logs."""
from dataclasses import dataclass, field
import hmac
import logging
import os
from pathlib import Path
import re

import httpx
from cryptography.fernet import Fernet, InvalidToken

from .apple import InvalidIdentity, ProviderUnavailable
from .settings import ConfigurationError


@dataclass(frozen=True)
class WeChatSettings:
    app_id: str = field(repr=False)
    app_secret: str = field(repr=False)
    encryption_key: bytes = field(repr=False)

    @classmethod
    def from_environment(cls):
        names = ['ZHOUJI_WECHAT_APP_ID', 'ZHOUJI_WECHAT_APP_SECRET_PATH']
        if not any(os.environ.get(k) for k in names):
            return None
        if not all(os.environ.get(k) for k in names) or not os.environ.get('ZHOUJI_TOKEN_ENCRYPTION_KEY_PATH'):
            raise ConfigurationError('微信登录配置不完整')
        try:
            app_id = os.environ[names[0]].strip()
            secret = Path(os.environ[names[1]]).read_text().strip()
            encryption = Path(os.environ['ZHOUJI_TOKEN_ENCRYPTION_KEY_PATH']).read_bytes().strip()
            if not re.fullmatch(r'wx[0-9a-fA-F]{16}', app_id) or not secret:
                raise ValueError
            Fernet(encryption)
        except (OSError, ValueError):
            raise ConfigurationError('微信登录私有配置无效') from None
        return cls(app_id, secret, encryption)


class WeChatProvider:
    def __init__(self, settings: WeChatSettings):
        self.settings = settings
        self.cipher = Fernet(settings.encryption_key)
        # The official OAuth GET endpoints put secrets in query parameters.
        # Prevent httpx's informational request logging from exposing those URLs.
        logging.getLogger('httpx').setLevel(logging.WARNING)
        logging.getLogger('httpcore').setLevel(logging.WARNING)

    def _get(self, endpoint, parameters):
        try:
            with httpx.Client(timeout=10, follow_redirects=False) as client:
                response = client.get('https://api.weixin.qq.com/sns/' + endpoint, params=parameters)
            if response.status_code != 200:
                raise ProviderUnavailable
            payload = response.json()
            if not isinstance(payload, dict):
                raise ProviderUnavailable
            error = payload.get('errcode', 0)
            if error in (40029, 40163, 40030, 42002, 40001, 40003, 40014, 42001):
                raise InvalidIdentity
            if error != 0:
                raise ProviderUnavailable
            return payload
        except (httpx.HTTPError, ValueError):
            raise ProviderUnavailable from None

    def _validate_access(self, access, subject):
        payload = self._get('auth', {'access_token': access, 'openid': subject})
        if payload.get('errcode') != 0:
            raise ProviderUnavailable

    def exchange(self, code):
        payload = self._get('oauth2/access_token', {
            'appid': self.settings.app_id, 'secret': self.settings.app_secret,
            'code': code, 'grant_type': 'authorization_code'})
        subject, refresh, access = (payload.get(k) for k in ('openid', 'refresh_token', 'access_token'))
        if not isinstance(subject, str) or not 1 <= len(subject) <= 255:
            raise InvalidIdentity
        if not isinstance(refresh, str) or not refresh or not isinstance(access, str) or not access:
            raise ProviderUnavailable
        if 'snsapi_userinfo' not in str(payload.get('scope', '')).split(','):
            raise InvalidIdentity
        self._validate_access(access, subject)
        return subject, self.cipher.encrypt(refresh.encode()).decode()

    def validate_refresh(self, encrypted, subject):
        try:
            refresh = self.cipher.decrypt(encrypted.encode()).decode()
        except (InvalidToken, ValueError, UnicodeError):
            raise ProviderUnavailable from None
        payload = self._get('oauth2/refresh_token', {
            'appid': self.settings.app_id, 'grant_type': 'refresh_token', 'refresh_token': refresh})
        if not isinstance(payload.get('openid'), str) or not hmac.compare_digest(payload['openid'].encode(), subject.encode()):
            raise InvalidIdentity
        access = payload.get('access_token')
        if not isinstance(access, str) or not access:
            raise ProviderUnavailable
        self._validate_access(access, subject)
