"""Credential primitives. Password work is bounded; recovery secrets have 160 random bits."""
import base64
import binascii
import hashlib
import hmac
import re
import secrets
from threading import BoundedSemaphore

from fastapi import HTTPException

_work_slots = BoundedSemaphore(2)


def normalize_username(value: str) -> str:
    value = value.strip()
    if not value.isascii():
        raise ValueError('invalid username')
    value = value.lower()
    if not re.fullmatch(r'[a-z0-9_]{4,32}', value, flags=re.ASCII):
        raise ValueError('invalid username')
    return value


def validate_password(value: str) -> str:
    if not 15 <= len(value) <= 128 or any(0xD800 <= ord(c) <= 0xDFFF for c in value):
        raise ValueError('invalid password')
    return value


def _derive(value: str, salt: bytes) -> bytes:
    if not _work_slots.acquire(blocking=False):
        raise HTTPException(503, '登录服务繁忙，请稍后重试', headers={'Retry-After': '2'})
    try:
        return hashlib.scrypt(value.encode('utf-8'), salt=salt, n=2**17, r=8, p=1,
                              maxmem=256*1024*1024, dklen=32)
    finally:
        _work_slots.release()


def hash_password(value: str) -> str:
    validate_password(value)
    salt = secrets.token_bytes(16)
    result = _derive(value, salt)
    return 'scrypt$131072$8$1$' + base64.b64encode(salt).decode() + '$' + base64.b64encode(result).decode()


def verify_password(value: str, encoded: str) -> bool:
    try:
        validate_password(value)
        name, n, r, p, salt, expected = encoded.split('$')
        if (name, n, r, p) != ('scrypt', '131072', '8', '1'):
            return False
        salt = base64.b64decode(salt, validate=True)
        expected = base64.b64decode(expected, validate=True)
        if len(salt) != 16 or len(expected) != 32:
            return False
        return hmac.compare_digest(_derive(value, salt), expected)
    except (ValueError, UnicodeError, binascii.Error):
        return False


# Unknown users still perform equivalent expensive work, without creating a credential.
DUMMY_PASSWORD_HASH = 'scrypt$131072$8$1$' + base64.b64encode(b'\0'*16).decode() + '$' + base64.b64encode(b'\0'*32).decode()


def new_recovery_code() -> str:
    value = base64.b32encode(secrets.token_bytes(20)).decode()
    return '-'.join(value[i:i+4] for i in range(0, 32, 4))


def recovery_digest(value: str) -> str:
    if not value.isascii():
        raise ValueError('invalid recovery code')
    normalized = re.sub(r'[- \t\r\n\f\v]', '', value).upper()
    if not re.fullmatch(r'[A-Z2-7]{32}', normalized, flags=re.ASCII):
        raise ValueError('invalid recovery code')
    return hashlib.sha256(('zhouji:recovery:v1:' + normalized).encode('ascii')).hexdigest()
