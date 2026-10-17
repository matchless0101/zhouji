"""Database-backed, fixed windows. Failure counters commit independently of auth transactions."""
import hashlib
import time

from fastapi import HTTPException
from sqlalchemy import delete, insert, select, update
from sqlalchemy.exc import IntegrityError

from .models import auth_attempts


class AuthLimits:
    QUOTAS = {'login_ip': (20, 60), 'recovery_ip': (20, 60),
              'register_hour': (5, 3600), 'register_day': (20, 86400),
              'security_ip': (20, 60)}

    def __init__(self, database, clock=time.time):
        self.database, self.clock = database, clock

    @staticmethod
    def _key(scope, key):
        return hashlib.sha256((scope + ':' + key).encode()).hexdigest()

    def _change(self, scope, key, increment):
        now = int(self.clock())
        maximum, window = self.QUOTAS.get(scope, (5, 900))
        digest = self._key(scope, key)
        for attempt in range(3):
            try:
                with self.database.begin() as conn:
                    # Expiry is indexed; no account data or input appears in these buckets.
                    expired = select(auth_attempts.c.key_hash).where(auth_attempts.c.expires_at <= now).limit(100)
                    stale = list(conn.execute(expired).scalars())
                    if stale:
                        conn.execute(delete(auth_attempts).where(auth_attempts.c.key_hash.in_(stale)))
                    row = conn.execute(select(auth_attempts).where(
                        auth_attempts.c.key_hash == digest).with_for_update()).mappings().first()
                    quota = scope in self.QUOTAS
                    if row and row['blocked_until'] > now:
                        return row['blocked_until'] - now
                    if row and row['window_start'] + window > now:
                        count = row['count'] + (1 if increment else 0)
                        start = row['window_start']
                    else:
                        count, start = (1 if increment else 0), now
                    if quota and count > maximum:
                        return start + window - now
                    blocked = now + window if not quota and count >= maximum else 0
                    values = dict(window_start=start, count=count, blocked_until=blocked,
                                  expires_at=max(start + window, blocked))
                    if row:
                        conn.execute(update(auth_attempts).where(auth_attempts.c.key_hash == digest).values(**values))
                    elif increment:
                        conn.execute(insert(auth_attempts).values(key_hash=digest, **values))
                return 0
            except IntegrityError:
                if attempt == 2:
                    raise HTTPException(429, '请求过于频繁，请稍后重试') from None

    def check(self, scope: str, key: str) -> None:
        remaining = self._change(scope, key, scope in self.QUOTAS)
        if remaining:
            raise HTTPException(429, detail={'code': 'rate_limited', 'message': '尝试过于频繁，请稍后重试'},
                                headers={'Retry-After': str(remaining)})

    def failure(self, scope: str, key: str) -> None:
        self._change(scope, key, True)

    def success(self, scope: str, key: str) -> None:
        if scope in self.QUOTAS:
            return
        with self.database.begin() as conn:
            conn.execute(delete(auth_attempts).where(auth_attempts.c.key_hash == self._key(scope, key)))
