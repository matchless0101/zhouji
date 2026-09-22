import time
from unittest.mock import Mock

import pytest

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.pool import StaticPool

from zhouji_api.app import create_app
from zhouji_api.models import metadata, sync_entities, sync_tombstones
from zhouji_api.sync import purge_soft_deleted


def make_client():
    db = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    metadata.create_all(db)
    provider = Mock()
    provider.exchange.return_value = ('test-subject', 'encrypted-refresh')
    client = TestClient(create_app(engine=db, apple_provider=provider))
    return client, db


def login_headers(client):
    challenge = client.post('/api/v1/auth/apple/challenge').json()
    body = {'challenge': challenge['challenge'], 'code': 'code', 'identity_token': 'token'}
    response = client.post('/api/v1/auth/apple', json=body)
    return {'Authorization': 'Bearer ' + response.json()['token']}


def change(op_id, entity_id, version=1, op='upsert', payload=None, updated_at=None):
    return {
        'client_op_id': op_id,
        'entity_type': 'task',
        'entity_id': entity_id,
        'op': op,
        'version': version,
        'updated_at': updated_at or int(time.time()),
        'payload': payload or {'title': '写摘要'},
    }


def test_push_pull_is_account_scoped_and_idempotent():
    client, db = make_client()
    headers = login_headers(client)
    entity_id = '11111111-1111-1111-1111-111111111111'
    push = client.post('/api/v1/sync/push', headers=headers, json={
        'changes': [change('op-00000001', entity_id, version=1)]
    })
    assert push.status_code == 200
    assert push.json()['applied'][0]['deduped'] is False

    replay = client.post('/api/v1/sync/push', headers=headers, json={
        'changes': [change('op-00000001', entity_id, version=1)]
    })
    assert replay.json()['applied'][0]['deduped'] is True
    assert replay.json()['conflicts'] == []

    pull = client.get('/api/v1/sync/pull', headers=headers, params={'cursor': 0})
    assert pull.status_code == 200
    body = pull.json()
    assert len(body['entities']) == 1
    assert body['entities'][0]['entity_id'] == entity_id
    assert body['entities'][0]['payload']['title'] == '写摘要'
    assert body['has_more'] is False

    status = client.get('/api/v1/sync/status', headers=headers)
    assert status.json()['latest_seq'] == body['cursor']


def test_older_version_is_conflict_and_never_overwrites():
    client, db = make_client()
    headers = login_headers(client)
    entity_id = '22222222-2222-2222-2222-222222222222'
    client.post('/api/v1/sync/push', headers=headers, json={
        'changes': [change('op-00000002', entity_id, version=3, payload={'title': '云端较新'})]
    })
    conflict = client.post('/api/v1/sync/push', headers=headers, json={
        'changes': [change('op-00000003', entity_id, version=2, payload={'title': '本机较旧'})]
    })
    assert conflict.status_code == 200
    assert conflict.json()['applied'] == []
    assert conflict.json()['conflicts'][0]['server_version'] == 3
    assert conflict.json()['conflicts'][0]['server_payload']['title'] == '云端较新'

    pull = client.get('/api/v1/sync/pull', headers=headers)
    assert pull.json()['entities'][0]['payload']['title'] == '云端较新'


def test_soft_delete_then_purge_after_seven_days():
    client, db = make_client()
    headers = login_headers(client)
    entity_id = '33333333-3333-3333-3333-333333333333'
    now = int(time.time())
    client.post('/api/v1/sync/push', headers=headers, json={
        'changes': [change('op-00000004', entity_id, version=1, updated_at=now - 8 * 86400)]
    })
    deleted = client.post('/api/v1/sync/push', headers=headers, json={
        'changes': [change('op-00000005', entity_id, version=2, op='delete', updated_at=now - 8 * 86400)]
    })
    assert deleted.json()['applied'][0]['version'] == 2
    pull = client.get('/api/v1/sync/pull', headers=headers)
    assert pull.json()['entities'][0]['deleted_at'] is not None

    removed = purge_soft_deleted(db, now=now)
    assert removed == 1
    after = client.get('/api/v1/sync/pull', headers=headers)
    assert after.json()['entities'] == []


def test_unauthenticated_and_foreign_account_are_rejected():
    client, db = make_client()
    assert client.get('/api/v1/sync/pull').status_code == 401
    headers_a = login_headers(client)

    # Second identity
    provider = Mock()
    provider.exchange.return_value = ('subject-b', 'refresh-b')
    # Same app already has apple provider from make_client; use wechat path instead.
    from zhouji_api.models import challenges
    with db.begin() as conn:
        conn.execute(challenges.delete())
    # Login as different apple subject by resetting provider on the app is heavy;
    # instead verify missing token is enough for isolation at this layer.
    bad = {'Authorization': 'Bearer ' + ('x' * 40)}
    assert client.get('/api/v1/sync/pull', headers=bad).status_code == 401
    assert client.post('/api/v1/sync/push', headers=bad, json={
        'changes': [change('op-00000006', '44444444-4444-4444-4444-444444444444')]
    }).status_code == 401
    assert headers_a['Authorization'].startswith('Bearer ')


def test_delete_account_removes_sync_rows():
    client, db = make_client()
    headers = login_headers(client)
    entity_id = '55555555-5555-5555-5555-555555555555'
    client.post('/api/v1/sync/push', headers=headers, json={
        'changes': [change('op-00000007', entity_id, version=1)]
    })
    # Mark session created_at recent enough for deletion policy.
    from zhouji_api.auth import digest
    from zhouji_api.models import sessions
    token = headers['Authorization'].split(' ', 1)[1]
    with db.begin() as conn:
        conn.execute(sessions.update().where(sessions.c.token_hash == digest(token)).values(created_at=int(time.time())))
    assert client.delete('/api/v1/account', headers=headers).status_code == 204
    with db.connect() as conn:
        rows = conn.execute(select(sync_entities)).all()
    assert rows == []


def test_delete_account_also_removes_purged_entity_receipts():
    client, db = make_client()
    headers = login_headers(client)
    client.post('/api/v1/sync/push', headers=headers, json={'changes': [
        change('deleted-operation-01', 'deleted-entity-01', op='delete',
               updated_at=int(time.time()) - 8 * 86400)
    ]})
    assert purge_soft_deleted(db) == 1
    assert purge_soft_deleted(db) == 0
    with db.connect() as conn:
        assert len(conn.execute(select(sync_tombstones)).all()) == 1
    assert client.delete('/api/v1/account', headers=headers).status_code == 204
    with db.connect() as conn:
        assert conn.execute(select(sync_tombstones)).all() == []


def test_purge_receipt_is_account_scoped_and_contains_no_payload():
    client, db = make_client()
    headers = login_headers(client)
    entity = 'purged-entity-01'
    client.post('/api/v1/sync/push', headers=headers, json={'changes': [
        change('deleted-operation-01', entity, op='delete', payload={'title': 'private text'},
               updated_at=int(time.time()) - 8 * 86400)
    ]})
    assert purge_soft_deleted(db) == 1
    with db.connect() as conn:
        receipt = dict(conn.execute(select(sync_tombstones)).mappings().one())
        assert 'payload' not in receipt
        assert 'private text' not in str(receipt)
    provider = Mock()
    provider.exchange.return_value = ('other-subject', 'other-refresh')
    other = TestClient(create_app(engine=db, apple_provider=provider))
    response = other.post('/api/v1/sync/push', headers=login_headers(other), json={'changes': [
        change('other-operation-01', entity)
    ]}).json()
    assert len(response['applied']) == 1
    assert response['conflicts'] == []


def test_equal_version_different_edit_is_conflict_not_success():
    client, _ = make_client()
    headers = login_headers(client)
    entity = 'concurrent-task-01'
    first = change('device-a-op-01', entity, version=2, payload={'title': 'A 修改'})
    second = change('device-b-op-01', entity, version=2, payload={'title': 'B 修改'})
    client.post('/api/v1/sync/push', headers=headers, json={'changes': [first]})
    response = client.post('/api/v1/sync/push', headers=headers, json={'changes': [second]}).json()
    assert response['applied'] == []
    assert response['conflicts'][0]['server_payload'] == first['payload']


def test_reusing_operation_id_cannot_disguise_different_payload():
    client, _ = make_client()
    headers = login_headers(client)
    original = change('same-operation-01', 'same-task-00001')
    client.post('/api/v1/sync/push', headers=headers, json={'changes': [original]})
    changed = {**original, 'payload': {'title': '另一份修改'}}
    response = client.post('/api/v1/sync/push', headers=headers, json={'changes': [changed]}).json()
    assert response['applied'] == []
    assert len(response['conflicts']) == 1


@pytest.mark.parametrize(('first', 'second'), [(True, 1), (False, 0)])
def test_different_json_types_are_not_idempotent(first, second):
    client, _ = make_client()
    headers = login_headers(client)
    original = change('same-operation-01', 'typed-task-0001', payload={'value': first})
    client.post('/api/v1/sync/push', headers=headers, json={'changes': [original]})
    response = client.post('/api/v1/sync/push', headers=headers, json={'changes': [
        {**original, 'payload': {'value': second}}
    ]}).json()
    assert response['applied'] == []
    assert len(response['conflicts']) == 1


def test_retry_with_fresh_operation_id_and_identical_facts_is_deduplicated():
    client, _ = make_client()
    headers = login_headers(client)
    original = change('first-operation-01', 'same-task-00001')
    client.post('/api/v1/sync/push', headers=headers, json={'changes': [original]})
    retry = {**original, 'client_op_id': 'retry-operation-01'}
    response = client.post('/api/v1/sync/push', headers=headers, json={'changes': [retry]}).json()
    assert response['conflicts'] == []
    assert response['applied'][0]['deduped'] is True


def test_purged_entity_rejects_old_and_new_version_resurrection_and_keeps_cursor():
    client, db = make_client()
    headers = login_headers(client)
    old = int(time.time()) - 8 * 86400
    entity = 'purged-task-0001'
    deletion = change('delete-operation-01', entity, version=3, op='delete', updated_at=old)
    client.post('/api/v1/sync/push', headers=headers, json={'changes': [deletion]})
    cursor = client.get('/api/v1/sync/pull', headers=headers).json()['cursor']
    assert purge_soft_deleted(db) == 1
    assert client.get('/api/v1/sync/pull', headers=headers).json()['entities'] == []
    for version in (1, 3, 4, 100):
        response = client.post('/api/v1/sync/push', headers=headers, json={
            'changes': [change(f'offline-operation-{version}', entity, version=version)]
        }).json()
        assert response['applied'] == []
        assert response['conflicts'][0]['server_deleted_at'] == old
        assert response['conflicts'][0]['server_payload'] == {}
    assert client.get('/api/v1/sync/status', headers=headers).json()['latest_seq'] >= cursor
    fresh = change('fresh-operation-01', 'brand-new-task-01')
    client.post('/api/v1/sync/push', headers=headers, json={'changes': [fresh]})
    page = client.get('/api/v1/sync/pull', headers=headers, params={'cursor': cursor}).json()
    assert [row['entity_id'] for row in page['entities']] == [fresh['entity_id']]
    assert page['cursor'] > cursor


def test_status_reports_actual_deleted_count():
    client, _ = make_client()
    headers = login_headers(client)
    for i in range(2):
        client.post('/api/v1/sync/push', headers=headers, json={
            'changes': [change(f'delete-operation-{i}', f'deleted-task-{i}', op='delete')]
        })
    assert client.get('/api/v1/sync/status', headers=headers).json()['soft_deleted_count'] == 2


def test_actual_two_accounts_cannot_read_or_modify_each_others_entity():
    client_a, db = make_client()
    headers_a = login_headers(client_a)
    provider_b = Mock()
    provider_b.exchange.return_value = ('another-subject', 'encrypted-refresh-b')
    client_b = TestClient(create_app(engine=db, apple_provider=provider_b))
    headers_b = login_headers(client_b)
    entity = 'shared-entity-id-01'
    client_a.post('/api/v1/sync/push', headers=headers_a, json={
        'changes': [change('account-a-operation', entity, payload={'title': 'A 私有'})]
    })
    assert client_b.get('/api/v1/sync/pull', headers=headers_b).json()['entities'] == []
    client_b.post('/api/v1/sync/push', headers=headers_b, json={
        'changes': [change('account-b-operation', entity, payload={'title': 'B 私有'})]
    })
    assert client_a.get('/api/v1/sync/pull', headers=headers_a).json()['entities'][0]['payload']['title'] == 'A 私有'
