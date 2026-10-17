import importlib
import importlib.util

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, select

from zhouji_api.models import metadata, auth_attempts


def primitives():
    assert importlib.util.find_spec('zhouji_api.passwords') is not None
    return importlib.import_module('zhouji_api.passwords')


def test_username_and_password_boundaries():
    p = primitives()
    assert p.normalize_username(' Alice_1 ') == 'alice_1'
    assert p.normalize_username('\u001cAlice_1\u001f') == 'alice_1'
    for bad in ('abc', 'a'*33, '你好用户', 'a-bc', 'a\nbc', 'a\u200bbc', 'Kate', '\u200balice\u200b'):
        with pytest.raises(ValueError):
            p.normalize_username(bad)
    for value in ('x'*15, '中'*128, ' ' + 'x'*14):
        assert p.validate_password(value) == value
    for value in ('x'*14, '中'*129, '\ud800'*15):
        with pytest.raises(ValueError):
            p.validate_password(value)


def test_real_password_hashes_are_salted_and_not_fast_digests():
    p = primitives()
    value = 'a long test password'
    first, second = p.hash_password(value), p.hash_password(value)
    assert first != second
    assert value not in first
    assert p.verify_password(value, first)
    assert not p.verify_password('wrong long password', first)
    assert not p.verify_password(value, 'scrypt$999999999$8$1$bad$bad')


def test_recovery_code_normalization_and_digest():
    p = primitives()
    code = p.new_recovery_code()
    assert len(code.split('-')) == 8
    assert len(code.replace('-', '')) == 32
    assert p.recovery_digest(code) == p.recovery_digest(code.lower().replace('-', ' '))
    assert code not in p.recovery_digest(code)
    for bad in ('bad', '0'*32, 'A'*31, 'A'*32+'!', 'ß'*16):
        with pytest.raises(ValueError):
            p.recovery_digest(bad)


def test_failure_window_persists_and_does_not_extend_while_blocked():
    assert importlib.util.find_spec('zhouji_api.auth_limits') is not None
    from zhouji_api.auth_limits import AuthLimits
    db = create_engine('sqlite://')
    metadata.create_all(db)
    now = [1000]
    limits = AuthLimits(db, clock=lambda: now[0])
    for _ in range(5):
        limits.check('login', 'alice')
        limits.failure('login', 'alice')
    limits = AuthLimits(db, clock=lambda: now[0])
    with pytest.raises(HTTPException) as error:
        limits.check('login', 'alice')
    assert error.value.status_code == 429
    limits.check('recovery', 'alice')
    now[0] += 500
    limits.failure('login', 'alice')
    now[0] += 401
    limits.check('login', 'alice')
    limits.success('login', 'alice')
    with db.connect() as conn:
        assert conn.execute(select(auth_attempts)).first() is None
    db.dispose()


def test_source_quota_is_not_cleared_by_success():
    from zhouji_api.auth_limits import AuthLimits
    db = create_engine('sqlite://')
    metadata.create_all(db)
    limits = AuthLimits(db, clock=lambda: 1000)
    for _ in range(20):
        limits.check('login_ip', '127.0.0.1')
    limits.success('login', 'alice')
    with pytest.raises(HTTPException):
        limits.check('login_ip', '127.0.0.1')
    db.dispose()
