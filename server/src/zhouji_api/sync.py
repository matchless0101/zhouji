"""Account-scoped content sync (stage B protocol foundation).

Rules encoded here (product-confirmed):
- R1: equal-or-older client version returns conflict with server state; never silent overwrite.
- R2: soft deletes are stored with deleted_at; physical purge is a separate 7-day job.
- R3: only finished sessions should be pushed by clients; server stores what is sent.
- Server always derives account_id from the Bearer session.
"""
from __future__ import annotations

import json
import time
import uuid

from fastapi import APIRouter, Header, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import func, select

from .models import accounts, sync_entities, sync_tombstones

ENTITY_TYPES = frozenset({'goal', 'task', 'timing_session'})
MAX_BATCH = 200
MAX_PAYLOAD_BYTES = 64 * 1024


class SyncChange(BaseModel):
    model_config = ConfigDict(extra='forbid')
    client_op_id: str = Field(min_length=8, max_length=64)
    entity_type: str
    entity_id: str = Field(min_length=8, max_length=36)
    op: str
    version: int = Field(ge=1)
    updated_at: int = Field(gt=0)
    payload: dict = Field(default_factory=dict)

    @field_validator('entity_type')
    @classmethod
    def valid_type(cls, value):
        if value not in ENTITY_TYPES:
            raise ValueError('entity_type')
        return value

    @field_validator('op')
    @classmethod
    def valid_op(cls, value):
        if value not in ('upsert', 'delete'):
            raise ValueError('op')
        return value

    @field_validator('entity_id', 'client_op_id')
    @classmethod
    def printable_id(cls, value):
        if not value or any(c.isspace() for c in value):
            raise ValueError('id')
        return value


class SyncPush(BaseModel):
    model_config = ConfigDict(extra='forbid')
    changes: list[SyncChange] = Field(min_length=1, max_length=MAX_BATCH)


def purge_soft_deleted(database, *, older_than_seconds: int = 7 * 86400, now: int | None = None) -> int:
    """Remove expired content, retaining only terminal deletion receipts."""
    cutoff = (now if now is not None else int(time.time())) - older_than_seconds
    removed = 0
    with database.connect() as conn:
        account_ids = conn.execute(select(sync_entities.c.account_id).where(
            sync_entities.c.deleted_at <= cutoff,
        ).distinct().order_by(sync_entities.c.account_id)).scalars().all()
    for account_id in account_ids:
        with database.begin() as conn:
            # Same lock order as push/account deletion, including empty libraries.
            if conn.execute(select(accounts.c.id).where(
                accounts.c.id == account_id,
            ).with_for_update()).scalar_one_or_none() is None:
                continue
            rows = conn.execute(select(sync_entities).where(
                sync_entities.c.account_id == account_id,
                sync_entities.c.deleted_at <= cutoff,
            ).with_for_update()).mappings().all()
            for row in rows:
                conn.execute(sync_tombstones.insert().values(**{
                    key: row[key] for key in (
                        'account_id', 'entity_type', 'entity_id', 'version', 'server_seq', 'deleted_at'
                    )
                }))
                conn.execute(sync_entities.delete().where(
                    sync_entities.c.account_id == account_id,
                    sync_entities.c.entity_type == row['entity_type'],
                    sync_entities.c.entity_id == row['entity_id'],
                ))
                removed += 1
    return removed


def latest_sequence(conn, account_id):
    return max(int(conn.execute(select(func.max(table.c.server_seq)).where(
        table.c.account_id == account_id,
    )).scalar() or 0) for table in (sync_entities, sync_tombstones))


def _conflict(change, row, *, purged=False):
    return {
        'client_op_id': change.client_op_id,
        'entity_type': change.entity_type,
        'entity_id': change.entity_id,
        'server_version': int(row['version']),
        'server_updated_at': row['deleted_at'] if purged else row['updated_at'],
        'server_deleted_at': row['deleted_at'],
        'server_payload': {} if purged else json.loads(row['payload']),
    }


def sync_router(database, authenticate):
    # Mounted under auth_router which already prefixes /api/v1.
    router = APIRouter()

    def _encode_payload(change: SyncChange) -> str:
        raw = json.dumps(change.payload, ensure_ascii=False, separators=(',', ':'), sort_keys=True)
        if len(raw.encode()) > MAX_PAYLOAD_BYTES:
            raise HTTPException(413, '单条内容过大，请分批同步')
        return raw

    def _row_payload(row) -> dict:
        try:
            value = json.loads(row['payload'] or '{}')
        except ValueError:
            value = {}
        return value if isinstance(value, dict) else {}

    def _public_entity(row) -> dict:
        return {
            'entity_type': row['entity_type'],
            'entity_id': row['entity_id'],
            'version': row['version'],
            'server_seq': row['server_seq'],
            'updated_at': row['updated_at'],
            'deleted_at': row['deleted_at'],
            'payload': _row_payload(row),
        }

    @router.post('/sync/push')
    def push(body: SyncPush, authorization: str | None = Header(default=None)):
        _, account = authenticate(authorization)
        account_id = account['id']
        applied = []
        conflicts = []
        now = int(time.time())

        with database.begin() as conn:
            # Serialize writers per account so server_seq is monotonic.
            if conn.execute(select(accounts.c.id).where(
                accounts.c.id == account_id,
            ).with_for_update()).scalar_one_or_none() is None:
                raise HTTPException(401, '账户已注销，请重新登录')
            next_seq = latest_sequence(conn, account_id)

            for change in body.changes:
                if change.updated_at > now + 300:
                    raise HTTPException(422, '同步时间异常，请检查设备时间后重试')
                encoded = _encode_payload(change)
                tombstone = conn.execute(select(sync_tombstones).where(
                    sync_tombstones.c.account_id == account_id,
                    sync_tombstones.c.entity_type == change.entity_type,
                    sync_tombstones.c.entity_id == change.entity_id,
                )).mappings().first()
                if tombstone is not None:
                    conflicts.append(_conflict(change, tombstone, purged=True))
                    continue
                existing = conn.execute(
                    select(sync_entities).where(
                        sync_entities.c.account_id == account_id,
                        sync_entities.c.entity_type == change.entity_type,
                        sync_entities.c.entity_id == change.entity_id,
                    ).with_for_update()
                ).mappings().first()

                deleted_at = change.updated_at if change.op == 'delete' else None
                same_facts = existing is not None and (
                    change.version == int(existing['version'])
                    and change.updated_at == existing['updated_at']
                    and deleted_at == existing['deleted_at']
                    and encoded == json.dumps(_row_payload(existing), ensure_ascii=False,
                                              separators=(',', ':'), sort_keys=True)
                )
                if existing is not None and change.version <= int(existing['version']) and not same_facts:
                    conflicts.append(_conflict(change, existing))
                    continue

                # Retries may have a fresh operation ID, but must carry identical facts.
                if same_facts:
                    applied.append({
                        'client_op_id': change.client_op_id,
                        'entity_type': change.entity_type,
                        'entity_id': change.entity_id,
                        'version': int(existing['version']),
                        'server_seq': int(existing['server_seq']),
                        'deduped': True,
                    })
                    continue

                next_seq += 1
                values = {
                    'account_id': account_id,
                    'entity_type': change.entity_type,
                    'entity_id': change.entity_id,
                    'version': change.version,
                    'server_seq': next_seq,
                    'updated_at': change.updated_at,
                    'deleted_at': deleted_at,
                    'payload': encoded,
                    'client_op_id': change.client_op_id,
                }
                if existing is None:
                    conn.execute(sync_entities.insert().values(**values))
                else:
                    conn.execute(
                        sync_entities.update().where(
                            sync_entities.c.account_id == account_id,
                            sync_entities.c.entity_type == change.entity_type,
                            sync_entities.c.entity_id == change.entity_id,
                        ).values(**values)
                    )
                applied.append({
                    'client_op_id': change.client_op_id,
                    'entity_type': change.entity_type,
                    'entity_id': change.entity_id,
                    'version': change.version,
                    'server_seq': next_seq,
                    'deduped': False,
                })

        return {'applied': applied, 'conflicts': conflicts, 'server_time': now}

    @router.get('/sync/pull')
    def pull(
        authorization: str | None = Header(default=None),
        cursor: int = Query(default=0, ge=0),
        limit: int = Query(default=100, ge=1, le=MAX_BATCH),
    ):
        _, account = authenticate(authorization)
        account_id = account['id']
        with database.connect() as conn:
            rows = conn.execute(
                select(sync_entities)
                .where(
                    sync_entities.c.account_id == account_id,
                    sync_entities.c.server_seq > cursor,
                )
                .order_by(sync_entities.c.server_seq.asc())
                .limit(limit)
            ).mappings().all()

        entities = [_public_entity(row) for row in rows]
        next_cursor = int(entities[-1]['server_seq']) if entities else cursor
        return {
            'entities': entities,
            'cursor': next_cursor,
            'has_more': len(entities) == limit,
        }

    @router.get('/sync/status')
    def status(authorization: str | None = Header(default=None)):
        _, account = authenticate(authorization)
        account_id = account['id']
        with database.connect() as conn:
            row = latest_sequence(conn, account_id)
            soft_deleted = conn.execute(
                select(func.count()).select_from(sync_entities).where(
                    sync_entities.c.account_id == account_id,
                    sync_entities.c.deleted_at.is_not(None),
                )
            ).scalar_one()
        return {
            'account_id': account_id,
            'latest_seq': int(row or 0),
            'soft_deleted_count': int(soft_deleted or 0),
            'sync_enabled': True,
        }

    return router


def new_op_id() -> str:
    return uuid.uuid4().hex
