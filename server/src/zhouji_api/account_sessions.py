"""Shared session boundary. Account identity is stable; authentication method belongs to a session."""
from contextlib import nullcontext
import hashlib
import secrets
import time

from fastapi import HTTPException
from sqlalchemy import insert, select

from .models import accounts, password_credentials, sessions


class AccountSessions:
    def __init__(self, database):
        self.database = database

    def authenticate(self, authorization: str | None, conn=None, *, lock=False):
        if not authorization or not authorization.startswith('Bearer ') or len(authorization) > 256:
            raise HTTPException(401, '请重新登录')
        token_hash = hashlib.sha256(authorization[7:].encode()).hexdigest()
        with (nullcontext(conn) if conn is not None else self.database.connect()) as connection:
            query = select(sessions).where(sessions.c.token_hash == token_hash,
                                            sessions.c.expires_at > int(time.time()))
            session = connection.execute(query).mappings().first()
            if not session:
                raise HTTPException(401, '请重新登录')
            account_query = select(accounts).where(accounts.c.id == session['account_id'])
            account = connection.execute(account_query.with_for_update() if lock else account_query).mappings().first()
            if lock:
                session = connection.execute(query.with_for_update()).mappings().first()
            if not account or not session:
                raise HTTPException(401, '请重新登录')
            result = dict(session)
            if result['auth_method'] == 'legacy':
                # Old writers only supported Apple/WeChat. A password-created account
                # can have an old-writer session only through its bound WeChat identity.
                result['auth_method'] = 'wechat' if account['provider'] == 'password' else account['provider']
                if result['auth_method'] == 'wechat' and account['wechat_subject'] is None:
                    raise HTTPException(401, '请重新登录')
            return result, account

    def public_account(self, conn, account, auth_method: str) -> dict:
        credential = conn.execute(select(password_credentials.c.username).where(
            password_credentials.c.account_id == account['id'])).scalar_one_or_none()
        return {'id': account['id'], 'provider': auth_method, 'nickname': account['nickname'],
                'avatar': account['avatar'], 'has_password': credential is not None,
                'wechat_bound': account['wechat_subject'] is not None, 'username': credential}

    def issue_locked(self, conn, account_id: str, auth_method: str) -> dict:
        account = conn.execute(select(accounts).where(accounts.c.id == account_id)).mappings().one()
        token, now = secrets.token_urlsafe(32), int(time.time())
        expires = now + 30 * 86400
        conn.execute(insert(sessions).values(token_hash=hashlib.sha256(token.encode()).hexdigest(),
            account_id=account_id, auth_method=auth_method, created_at=now, expires_at=expires))
        return {'token': token, 'expires_at': expires,
                'account': self.public_account(conn, account, auth_method)}
