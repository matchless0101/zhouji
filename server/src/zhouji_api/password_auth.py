import hmac
import time
import uuid

from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import delete, insert, select, update
from sqlalchemy.exc import IntegrityError

from . import passwords
from .models import accounts, password_credentials, sessions


def auth_failure(status, code, message):
    return HTTPException(status, detail={'code': code, 'message': message})


class LoginBody(BaseModel):
    model_config = ConfigDict(extra='forbid')
    username: str = Field(max_length=100, repr=False)
    password: str = Field(max_length=128, repr=False)

    @field_validator('username')
    @classmethod
    def username_value(cls, value):
        return passwords.normalize_username(value)

    @field_validator('password')
    @classmethod
    def password_value(cls, value):
        return passwords.validate_password(value)


class PasswordBody(BaseModel):
    model_config = ConfigDict(extra='forbid')
    password: str = Field(max_length=128, repr=False)

    @field_validator('password')
    @classmethod
    def password_value(cls, value):
        return passwords.validate_password(value)


class ChangeBody(PasswordBody):
    new_password: str = Field(max_length=128, repr=False)

    @field_validator('new_password')
    @classmethod
    def new_password_value(cls, value):
        return passwords.validate_password(value)


class RecoverBody(BaseModel):
    model_config = ConfigDict(extra='forbid')
    username: str = Field(max_length=100, repr=False)
    recovery_code: str = Field(max_length=100, repr=False)
    new_password: str = Field(max_length=128, repr=False)

    @field_validator('username')
    @classmethod
    def username_value(cls, value):
        return passwords.normalize_username(value)

    @field_validator('new_password')
    @classmethod
    def new_password_value(cls, value):
        return passwords.validate_password(value)


def request_source(request):
    return request.client.host if request.client else 'unknown'


def read_password(database, *, username=None, account_id=None):
    clause = (password_credentials.c.username == username if username is not None
              else password_credentials.c.account_id == account_id)
    with database.connect() as conn:
        return conn.execute(select(password_credentials).where(clause)).mappings().first()


def checked_password(database, limits, account_id, value):
    snapshot = read_password(database, account_id=account_id)
    if snapshot is None:
        raise auth_failure(409, 'password_unavailable', '此账户未设置用户名密码')
    limits.check('login', snapshot['username'])
    if not passwords.verify_password(value, snapshot['password_hash']):
        limits.failure('login', snapshot['username'])
        raise auth_failure(401, 'invalid_credentials', '当前密码不正确')
    return snapshot


def lock_credential(conn, account_id, snapshot, *, field='password_hash'):
    account = conn.execute(select(accounts).where(accounts.c.id == account_id).with_for_update()).mappings().first()
    current = conn.execute(select(password_credentials).where(
        password_credentials.c.account_id == account_id).with_for_update()).mappings().first()
    if not account or not current or not hmac.compare_digest(current[field], snapshot[field]):
        raise auth_failure(401, 'credentials_changed', '账户凭据已更新，请重新尝试')
    return account, current


def password_router(database, session_service, limits):
    router = APIRouter()

    def require_recent_wechat(session, account):
        if account['provider'] != 'wechat' or session['auth_method'] != 'wechat' or account['wechat_subject'] is None:
            raise auth_failure(409, 'wechat_setup_unavailable', '请使用原微信账户登录后设置用户名密码')
        if session['created_at'] < int(time.time()) - 600:
            raise auth_failure(403, 'recent_wechat_login_required', '为保护账户，请退出后重新微信登录，再设置用户名密码')

    @router.post('/account/password/setup')
    def setup(body: LoginBody, request: Request, authorization: str | None = Header(default=None)):
        limits.check('security_ip', request_source(request))
        session, account = session_service.authenticate(authorization)
        require_recent_wechat(session, account)
        if read_password(database, account_id=account['id']):
            raise auth_failure(409, 'password_already_set', '此账户已设置用户名密码，请使用修改密码')
        hashed, code = passwords.hash_password(body.password), passwords.new_recovery_code()
        try:
            with database.begin() as conn:
                session, account = session_service.authenticate(authorization, conn, lock=True)
                require_recent_wechat(session, account)
                if conn.execute(select(password_credentials.c.account_id).where(
                        password_credentials.c.account_id == account['id'])).first():
                    raise auth_failure(409, 'password_already_set', '此账户已设置用户名密码，请使用修改密码')
                conn.execute(insert(password_credentials).values(account_id=account['id'], username=body.username,
                    password_hash=hashed, recovery_hash=passwords.recovery_digest(code), updated_at=int(time.time())))
                conn.execute(delete(sessions).where(sessions.c.account_id == account['id']))
                result = session_service.issue_locked(conn, account['id'], 'wechat')
        except IntegrityError:
            if read_password(database, username=body.username):
                raise auth_failure(409, 'username_taken', '此用户名已被使用') from None
            raise
        return {'session': result, 'recovery_code': code}

    @router.post('/auth/password/register')
    def register(body: LoginBody, request: Request):
        source = request_source(request)
        limits.check('register_hour', source)
        limits.check('register_day', source)
        hashed = passwords.hash_password(body.password)
        code = passwords.new_recovery_code()
        account_id, now = str(uuid.uuid4()), int(time.time())
        try:
            with database.begin() as conn:
                conn.execute(insert(accounts).values(id=account_id, provider='password', created_at=now, verified_at=now))
                conn.execute(insert(password_credentials).values(account_id=account_id, username=body.username,
                    password_hash=hashed, recovery_hash=passwords.recovery_digest(code), updated_at=now))
                session = session_service.issue_locked(conn, account_id, 'password')
        except IntegrityError:
            if read_password(database, username=body.username):
                raise auth_failure(409, 'username_taken', '此用户名已被使用') from None
            raise
        return {'session': session, 'recovery_code': code}

    @router.post('/auth/password/login')
    def login(body: LoginBody, request: Request):
        limits.check('login_ip', request_source(request))
        limits.check('login', body.username)
        snapshot = read_password(database, username=body.username)
        valid = passwords.verify_password(body.password, snapshot['password_hash'] if snapshot else passwords.DUMMY_PASSWORD_HASH)
        if not valid or not snapshot:
            limits.failure('login', body.username)
            raise auth_failure(401, 'invalid_credentials', '用户名或密码不正确')
        with database.begin() as conn:
            lock_credential(conn, snapshot['account_id'], snapshot)
            result = session_service.issue_locked(conn, snapshot['account_id'], 'password')
        limits.success('login', body.username)
        return result

    @router.post('/auth/password/recover')
    def recover(body: RecoverBody, request: Request):
        limits.check('recovery_ip', request_source(request))
        limits.check('recovery', body.username)
        snapshot = read_password(database, username=body.username)
        try:
            submitted = passwords.recovery_digest(body.recovery_code)
        except ValueError:
            submitted = ''
        if not snapshot or not hmac.compare_digest(submitted, snapshot['recovery_hash']):
            limits.failure('recovery', body.username)
            raise auth_failure(401, 'invalid_recovery', '用户名或恢复码不正确')
        new_hash, new_code = passwords.hash_password(body.new_password), passwords.new_recovery_code()
        with database.begin() as conn:
            lock_credential(conn, snapshot['account_id'], snapshot, field='recovery_hash')
            conn.execute(update(password_credentials).where(password_credentials.c.account_id == snapshot['account_id']).values(
                password_hash=new_hash, recovery_hash=passwords.recovery_digest(new_code), updated_at=int(time.time())))
            conn.execute(delete(sessions).where(sessions.c.account_id == snapshot['account_id']))
        limits.success('recovery', body.username)
        return {'username': body.username, 'recovery_code': new_code}

    def change_or_rotate(body, authorization, request, *, rotate):
        limits.check('security_ip', request_source(request))
        _, account = session_service.authenticate(authorization)
        snapshot = checked_password(database, limits, account['id'], body.password)
        new_code = passwords.new_recovery_code() if rotate else None
        new_hash = None if rotate else passwords.hash_password(body.new_password)
        with database.begin() as conn:
            lock_credential(conn, account['id'], snapshot)
            session_service.authenticate(authorization, conn, lock=True)
            changes = {'updated_at': int(time.time())}
            changes.update(recovery_hash=passwords.recovery_digest(new_code)) if rotate else changes.update(password_hash=new_hash)
            conn.execute(update(password_credentials).where(password_credentials.c.account_id == account['id']).values(**changes))
            conn.execute(delete(sessions).where(sessions.c.account_id == account['id']))
            result = session_service.issue_locked(conn, account['id'], 'password')
        limits.success('login', snapshot['username'])
        return {'session': result, 'recovery_code': new_code} if rotate else result

    @router.post('/account/password/change')
    def change(body: ChangeBody, request: Request, authorization: str | None = Header(default=None)):
        return change_or_rotate(body, authorization, request, rotate=False)

    @router.post('/account/password/recovery-code')
    def rotate(body: PasswordBody, request: Request, authorization: str | None = Header(default=None)):
        return change_or_rotate(body, authorization, request, rotate=True)

    return router
