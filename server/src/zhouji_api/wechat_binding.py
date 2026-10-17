import hashlib
import secrets
import time

from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import delete, insert, select, update
from sqlalchemy.exc import IntegrityError

from .apple import InvalidIdentity, ProviderUnavailable
from .models import accounts, challenges, sessions
from .password_auth import PasswordBody, auth_failure, checked_password, lock_credential, request_source


class BindBody(BaseModel):
    model_config = ConfigDict(extra='forbid')
    challenge: str = Field(min_length=32, max_length=128, repr=False)
    code: str = Field(min_length=1, max_length=4096, repr=False)


def wechat_binding_router(database, session_service, wechat_provider, limits):
    router = APIRouter()

    def provider():
        if wechat_provider is None:
            raise HTTPException(503, '微信授权暂不可用，请稍后重试')
        return wechat_provider

    def pending_query(token, session, account):
        return select(challenges).where(
            challenges.c.id_hash == hashlib.sha256(token.encode()).hexdigest(),
            challenges.c.provider == 'wechat', challenges.c.purpose == 'bind_wechat',
            challenges.c.account_id == account['id'],
            challenges.c.session_token_hash == session['token_hash'],
            challenges.c.expires_at > int(time.time()))

    @router.post('/account/wechat/binding/challenge')
    def prepare(body: PasswordBody, request: Request, authorization: str | None = Header(default=None)):
        provider()
        limits.check('security_ip', request_source(request))
        session, account = session_service.authenticate(authorization)
        snapshot = checked_password(database, limits, account['id'], body.password)
        token, nonce, expires = secrets.token_urlsafe(32), secrets.token_hex(32), int(time.time()) + 300
        with database.begin() as conn:
            lock_credential(conn, account['id'], snapshot)
            session, account = session_service.authenticate(authorization, conn, lock=True)
            conn.execute(delete(challenges).where(challenges.c.account_id == account['id'],
                challenges.c.purpose == 'bind_wechat', challenges.c.session_token_hash == session['token_hash']))
            conn.execute(insert(challenges).values(id_hash=hashlib.sha256(token.encode()).hexdigest(),
                provider='wechat', purpose='bind_wechat', account_id=account['id'],
                session_token_hash=session['token_hash'], nonce=nonce, expires_at=expires))
        limits.success('login', snapshot['username'])
        return {'challenge': token, 'nonce': nonce, 'expires_at': expires}

    @router.post('/account/wechat/binding')
    def bind(body: BindBody, request: Request, authorization: str | None = Header(default=None)):
        source = provider()
        limits.check('security_ip', request_source(request))
        session, account = session_service.authenticate(authorization)
        query = pending_query(body.challenge, session, account)
        with database.connect() as conn:
            if conn.execute(query).first() is None:
                raise auth_failure(401, 'binding_expired', '绑定请求已失效，请重新操作')
        try:
            subject, encrypted = source.exchange(body.code)
        except (InvalidIdentity, ProviderUnavailable) as error:
            with database.begin() as conn:
                conn.execute(delete(challenges).where(challenges.c.id_hash == hashlib.sha256(body.challenge.encode()).hexdigest(),
                    challenges.c.account_id == account['id'], challenges.c.purpose == 'bind_wechat'))
            if isinstance(error, InvalidIdentity):
                raise auth_failure(401, 'invalid_wechat', '微信授权无效，请重新尝试') from None
            raise HTTPException(503, '微信登录暂不可用，请稍后重试') from None
        try:
            with database.begin() as conn:
                session, account = session_service.authenticate(authorization, conn, lock=True)
                pending = conn.execute(pending_query(body.challenge, session, account).with_for_update()).mappings().first()
                if not pending:
                    raise auth_failure(401, 'binding_expired', '绑定请求已失效，请重新操作')
                occupied = conn.execute(select(accounts.c.id).where(accounts.c.wechat_subject == subject)).scalar_one_or_none()
                if occupied is not None and occupied != account['id']:
                    raise auth_failure(409, 'wechat_in_use', '此微信已关联其他粥记账户，暂不支持合并')
                if account['wechat_subject'] is not None and account['wechat_subject'] != subject:
                    raise auth_failure(409, 'wechat_already_bound', '请先解绑当前微信，再绑定其他微信')
                conn.execute(update(accounts).where(accounts.c.id == account['id']).values(
                    wechat_subject=subject, wechat_refresh_encrypted=encrypted, verified_at=int(time.time())))
                conn.execute(delete(challenges).where(challenges.c.id_hash == pending['id_hash']))
                updated = conn.execute(select(accounts).where(accounts.c.id == account['id'])).mappings().one()
                result = session_service.public_account(conn, updated, session['auth_method'])
        except IntegrityError:
            raise auth_failure(409, 'wechat_in_use', '此微信已关联其他粥记账户，暂不支持合并') from None
        return {'account': result}

    @router.delete('/account/wechat/binding')
    def unbind(body: PasswordBody, request: Request, authorization: str | None = Header(default=None)):
        limits.check('security_ip', request_source(request))
        session, account = session_service.authenticate(authorization)
        snapshot = checked_password(database, limits, account['id'], body.password)
        with database.begin() as conn:
            lock_credential(conn, account['id'], snapshot)
            session, account = session_service.authenticate(authorization, conn, lock=True)
            conn.execute(update(accounts).where(accounts.c.id == account['id']).values(
                wechat_subject=None, wechat_refresh_encrypted=None))
            conn.execute(delete(challenges).where(challenges.c.account_id == account['id'],
                                                   challenges.c.purpose == 'bind_wechat'))
            conn.execute(delete(sessions).where(sessions.c.account_id == account['id'], sessions.c.auth_method.in_(('wechat', 'legacy'))))
            updated = conn.execute(select(accounts).where(accounts.c.id == account['id'])).mappings().one()
            result = {'account': session_service.public_account(conn, updated, 'password')}
            if session['auth_method'] == 'wechat':
                result['session'] = session_service.issue_locked(conn, account['id'], 'password')
        limits.success('login', snapshot['username'])
        return result

    return router
