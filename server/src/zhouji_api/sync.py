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
from sqlalchemy import select

from .models import sync_entities

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
    """Physical-delete soft-deleted rows older than retention (R2 = 7 days)."""
    cutoff = (now if now is not None else int(time.time())) - older_than_seconds
    with database.begin() as conn:
        result = conn.execute(
            sync_entities.delete().where(
                sync_entities.c.deleted_at.is_not(None),
                sync_entities.c.deleted_at <= cutoff,
            )
        )
        return int(result.rowcount or 0)


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
            conn.execute(select(sync_entities).where(sync_entities.c.account_id == account_id).with_for_update())
            current_max = conn.execute(
                select(sync_entities.c.server_seq)
                .where(sync_entities.c.account_id == account_id)
                .order_by(sync_entities.c.server_seq.desc())
                .limit(1)
            ).scalar()
            next_seq = int(current_max or 0)

            for change in body.changes:
                if change.updated_at > now + 300:
                    raise HTTPException(422, '同步时间异常，请检查设备时间后重试')
                encoded = _encode_payload(change)
                existing = conn.execute(
                    select(sync_entities).where(
                        sync_entities.c.account_id == account_id,
                        sync_entities.c.entity_type == change.entity_type,
                        sync_entities.c.entity_id == change.entity_id,
                    ).with_for_update()
                ).mappings().first()

                if existing is not None and change.version < int(existing['version']):
                    conflicts.append({
                        'client_op_id': change.client_op_id,
                        'entity_type': change.entity_type,
                        'entity_id': change.entity_id,
                        'server_version': int(existing['version']),
                        'server_updated_at': int(existing['updated_at']),
                        'server_deleted_at': existing['deleted_at'],
                        'server_payload': _row_payload(existing),
                    })
                    continue

                # Idempotent replay of the same version is a success, not a conflict.
                if existing is not None and change.version == int(existing['version']):
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
                deleted_at = change.updated_at if change.op == 'delete' else None
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
            row = conn.execute(
                select(sync_entities.c.server_seq)
                .where(sync_entities.c.account_id == account_id)
                .order_by(sync_entities.c.server_seq.desc())
                .limit(1)
            ).scalar()
            soft_deleted = conn.execute(
                select(sync_entities).where(
                    sync_entities.c.account_id == account_id,
                    sync_entities.c.deleted_at.is_not(None),
                )
            ).rowcount
        return {
            'account_id': account_id,
            'latest_seq': int(row or 0),
            'soft_deleted_count': int(soft_deleted or 0),
            'sync_enabled': True,
        }

    return router


def new_op_id() -> str:
    return uuid.uuid4().hex
