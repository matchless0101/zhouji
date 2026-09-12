import hashlib
import secrets
import time
import uuid
import unicodedata
from typing import Literal
from collections import defaultdict, deque
from threading import Lock

from fastapi import APIRouter, Header, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import delete, insert, select, update
from sqlalchemy.exc import IntegrityError

from .apple import InvalidIdentity, ProviderUnavailable
from .models import accounts, challenges, sessions


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class AppleLogin(BaseModel):
    model_config = ConfigDict(extra='forbid')
    challenge: str = Field(min_length=32, max_length=128)
    code: str = Field(min_length=1, max_length=4096)
    identity_token: str = Field(min_length=1, max_length=16384)


class WeChatLogin(BaseModel):
    model_config = ConfigDict(extra='forbid')
    challenge: str = Field(min_length=32, max_length=128)
    code: str = Field(min_length=1, max_length=4096)


class ProfileUpdate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    nickname: str = Field(max_length=100)
    avatar: Literal['sunrise', 'leaf', 'moon', 'ocean', 'flower', 'mountain']

    @field_validator('nickname')
    @classmethod
    def valid_nickname(cls, value):
        value = unicodedata.normalize('NFC', value.strip())
        if not 1 <= len(value) <= 20:
            raise ValueError('nickname length')
        for char in value:
            category = unicodedata.category(char)
            if category in ('Cc', 'Cs', 'Zl', 'Zp') or (category == 'Cf' and char not in '\u200c\u200d'):
                raise ValueError('nickname contains control characters')
        if not any(unicodedata.category(char)[0] in 'LNSP' for char in value):
            raise ValueError('nickname must be visible')
        return value


def public_account(account):
    return {'id': account['id'], 'provider': account['provider'],
            'nickname': account['nickname'], 'avatar': account['avatar']}


class RateLimiter:
    """One-process deployment; bounded memory. Nginx is also the body-size boundary."""
    def __init__(self):
        self.entries = defaultdict(deque)
        self.lock = Lock()

    def check(self, key):
        now = time.monotonic()
        with self.lock:
            for old in list(self.entries):
                while self.entries[old] and self.entries[old][0] <= now - 60:
                    self.entries[old].popleft()
                if not self.entries[old]:
                    del self.entries[old]
            if len(self.entries) >= 10000 and key not in self.entries:
                raise HTTPException(429, '请求过于频繁，请稍后重试')
            bucket = self.entries[key]
            if len(bucket) >= 20:
                raise HTTPException(429, '请求过于频繁，请稍后重试', headers={'Retry-After': '60'})
            bucket.append(now)


def auth_router(database, apple_provider, wechat_provider=None):
    router = APIRouter(prefix='/api/v1')
    limiter = RateLimiter()

    providers = {'apple': apple_provider, 'wechat': wechat_provider}

    def available(name):
        provider = providers.get(name)
        if provider is None:
            raise HTTPException(503, '此登录方式尚未配置')
        return provider

    def authenticate(authorization):
        if not authorization or not authorization.startswith('Bearer ') or len(authorization) > 256:
            raise HTTPException(401, '请重新登录')
        token_hash = digest(authorization[7:])
        with database.connect() as conn:
            session = conn.execute(select(sessions).where(sessions.c.token_hash == token_hash,
                                                          sessions.c.expires_at > int(time.time()))).mappings().first()
            if session:
                account = conn.execute(select(accounts).where(accounts.c.id == session['account_id'])).mappings().first()
            else:
                account = None
        if not account:
            raise HTTPException(401, '请重新登录')
        return session, account

    def new_challenge(request, name):
        available(name)
        limiter.check(request.client.host if request.client else 'unknown')
        now = int(time.time())
        token, nonce = secrets.token_urlsafe(32), secrets.token_hex(32)
        with database.begin() as conn:
            conn.execute(delete(challenges).where(challenges.c.expires_at <= now))
            conn.execute(delete(sessions).where(sessions.c.expires_at <= now))
            conn.execute(insert(challenges).values(id_hash=digest(token), nonce=nonce, provider=name, expires_at=now+300))
        return {'challenge': token, 'nonce': nonce, 'expires_at': now+300}

    def consume_challenge(body, request, name):
        limiter.check(request.client.host if request.client else 'unknown')
        with database.begin() as conn:
            match = (challenges.c.id_hash == digest(body.challenge)) & (challenges.c.provider == name)
            row = conn.execute(select(challenges).where(match, challenges.c.expires_at > int(time.time()))).mappings().first()
            consumed = conn.execute(delete(challenges).where(match))
            if not row or consumed.rowcount != 1:
                raise HTTPException(401, '登录请求已过期，请重试')
        return row

    def issue_session(name, subject, encrypted):
        now = int(time.time())
        token = secrets.token_urlsafe(32)
        expires = now + 30 * 86400
        subject_column = accounts.c[name + '_subject']
        credentials = {name + '_subject': subject, name + '_refresh_encrypted': encrypted}
        # A provider identity never merges into a different provider's account implicitly.
        for attempt in range(2):
            try:
                with database.begin() as conn:
                    account = conn.execute(select(accounts).where(subject_column == subject).with_for_update()).mappings().first()
                    account_id = account['id'] if account else str(uuid.uuid4())
                    if account:
                        conn.execute(update(accounts).where(accounts.c.id == account_id).values(**credentials, verified_at=now))
                    else:
                        conn.execute(insert(accounts).values(id=account_id, provider=name, **credentials,
                                                              created_at=now, verified_at=now))
                    conn.execute(insert(sessions).values(token_hash=digest(token), account_id=account_id,
                                                         created_at=now, expires_at=expires))
                    result_account = conn.execute(select(accounts).where(accounts.c.id == account_id)).mappings().one()
                break
            except IntegrityError:
                if attempt:
                    raise
        return {'token': token, 'expires_at': expires, 'account': public_account(result_account)}

    @router.post('/auth/apple/challenge')
    def apple_challenge(request: Request):
        return new_challenge(request, 'apple')

    @router.post('/auth/wechat/challenge')
    def wechat_challenge(request: Request):
        return new_challenge(request, 'wechat')

    @router.post('/auth/apple')
    def login(body: AppleLogin, request: Request):
        provider = available('apple')
        row = consume_challenge(body, request, 'apple')
        try:
            subject, encrypted = provider.exchange(body.code, body.identity_token, row['nonce'])
        except InvalidIdentity:
            raise HTTPException(401, 'Apple 授权无效，请重试') from None
        except ProviderUnavailable:
            raise HTTPException(503, '暂时无法连接 Apple，请稍后重试') from None
        return issue_session('apple', subject, encrypted)

    @router.post('/auth/wechat')
    def wechat_login(body: WeChatLogin, request: Request):
        provider = available('wechat')
        consume_challenge(body, request, 'wechat')
        try:
            subject, encrypted = provider.exchange(body.code)
        except InvalidIdentity:
            raise HTTPException(401, '微信授权无效，请重试') from None
        except ProviderUnavailable:
            raise HTTPException(503, '微信登录暂不可用，请稍后重试') from None
        return issue_session('wechat', subject, encrypted)

    @router.get('/account')
    def me(authorization: str | None = Header(default=None)):
        session, account = authenticate(authorization)
        name = account['provider']
        provider = available(name)
        now = int(time.time())
        if account['verified_at'] <= now - 86400:
            try:
                provider.validate_refresh(account[name + '_refresh_encrypted'], account[name + '_subject'])
            except InvalidIdentity:
                with database.begin() as conn:
                    conn.execute(delete(sessions).where(sessions.c.account_id == account['id']))
                raise HTTPException(401, '登录授权已失效，请重新登录') from None
            except ProviderUnavailable:
                raise HTTPException(503, '暂时无法验证登录，请稍后重试') from None
            with database.begin() as conn:
                conn.execute(update(accounts).where(accounts.c.id == account['id']).values(verified_at=now))
        return public_account(account)

    @router.patch('/account/profile')
    def edit_profile(body: ProfileUpdate, authorization: str | None = Header(default=None)):
        # Use the authenticated account only; also perform the same provider revalidation as /account.
        current = me(authorization)
        with database.begin() as conn:
            result = conn.execute(update(accounts).where(accounts.c.id == current['id']).values(
                nickname=body.nickname, avatar=body.avatar))
            if result.rowcount != 1:
                raise HTTPException(401, '请重新登录')
            account = conn.execute(select(accounts).where(accounts.c.id == current['id'])).mappings().one()
        return public_account(account)

    @router.post('/auth/logout', status_code=204)
    def logout(authorization: str | None = Header(default=None)):
        # Idempotent logout, including expired sessions.
        if authorization and authorization.startswith('Bearer ') and len(authorization) <= 256:
            with database.begin() as conn:
                conn.execute(delete(sessions).where(sessions.c.token_hash == digest(authorization[7:])))
        return Response(status_code=204)

    @router.delete('/account', status_code=204)
    def remove(authorization: str | None = Header(default=None)):
        session, account = authenticate(authorization)
        name = account['provider']
        provider = available(name)
        if session['created_at'] < int(time.time()) - 600:
            raise HTTPException(403, '为保护账户，请退出后重新登录，再注销账户')
        try:
            if name == 'apple':
                provider.revoke(account['apple_refresh_encrypted'])
            # WeChat documents no equivalent revocation endpoint. Delete our account
            # and encrypted grant, and explain manual WeChat permission removal in the UI.
        except ProviderUnavailable:
            raise HTTPException(503, 'Apple 授权撤销未完成，请稍后重试') from None
        with database.begin() as conn:
            conn.execute(delete(sessions).where(sessions.c.account_id == account['id']))
            conn.execute(delete(accounts).where(accounts.c.id == account['id']))
        return Response(status_code=204)

    return router
