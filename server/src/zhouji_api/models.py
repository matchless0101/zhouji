from sqlalchemy import BigInteger, CheckConstraint, Column, ForeignKey, MetaData, String, Table, Text

metadata = MetaData()
# Binary collation: Apple subjects and token hashes are case-sensitive identifiers.
def identifier(size):
    return String(size).with_variant(String(size, collation='utf8mb4_bin'), 'mysql')

accounts = Table('auth_accounts', metadata,
    Column('id', identifier(36), primary_key=True),
    Column('provider', String(16), nullable=False, server_default='apple'),
    Column('apple_subject', identifier(255), nullable=True, unique=True),
    Column('apple_refresh_encrypted', Text, nullable=True),
    Column('wechat_subject', identifier(255), nullable=True, unique=True),
    Column('wechat_refresh_encrypted', Text, nullable=True),
    Column('created_at', BigInteger, nullable=False),
    Column('verified_at', BigInteger, nullable=False),
    Column('nickname', String(20), nullable=False, server_default='粥记用户'),
    Column('avatar', String(16), nullable=False, server_default='sunrise'),
    CheckConstraint("(provider = 'apple' AND apple_subject IS NOT NULL AND apple_refresh_encrypted IS NOT NULL AND wechat_subject IS NULL AND wechat_refresh_encrypted IS NULL) OR (provider IN ('wechat', 'password') AND apple_subject IS NULL AND apple_refresh_encrypted IS NULL AND ((wechat_subject IS NULL AND wechat_refresh_encrypted IS NULL) OR (wechat_subject IS NOT NULL AND wechat_refresh_encrypted IS NOT NULL)))", name='auth_account_one_provider'),
)
sessions = Table('auth_sessions', metadata,
    Column('token_hash', identifier(64), primary_key=True),
    Column('account_id', identifier(36), ForeignKey('auth_accounts.id', ondelete='CASCADE'), nullable=False, index=True),
    Column('auth_method', String(16), nullable=False, server_default='legacy'),
    Column('created_at', BigInteger, nullable=False),
    Column('expires_at', BigInteger, nullable=False, index=True),
)
challenges = Table('auth_challenges', metadata,
    Column('id_hash', identifier(64), primary_key=True),
    Column('nonce', identifier(64), nullable=False),
    Column('provider', String(16), nullable=False, server_default='apple'),
    Column('purpose', String(32), nullable=False, server_default='login'),
    Column('account_id', identifier(36), ForeignKey('auth_accounts.id', ondelete='CASCADE'), nullable=True),
    Column('session_token_hash', identifier(64), ForeignKey('auth_sessions.token_hash', ondelete='CASCADE'), nullable=True),
    Column('expires_at', BigInteger, nullable=False, index=True),
)

password_credentials = Table('auth_password_credentials', metadata,
    Column('account_id', identifier(36), ForeignKey('auth_accounts.id', ondelete='CASCADE'), primary_key=True),
    Column('username', identifier(32), nullable=False, unique=True),
    Column('password_hash', String(255), nullable=False),
    Column('recovery_hash', identifier(64), nullable=False),
    Column('updated_at', BigInteger, nullable=False),
)

auth_attempts = Table('auth_attempts', metadata,
    Column('key_hash', identifier(64), primary_key=True),
    Column('window_start', BigInteger, nullable=False),
    Column('count', BigInteger, nullable=False),
    Column('blocked_until', BigInteger, nullable=False, server_default='0'),
    Column('expires_at', BigInteger, nullable=False, index=True),
)

# Content sync facts. Account-scoped only; server never trusts client account_id.
# version is the client's monotonic entity version (R1 conflict gate).
# server_seq is the per-account pull cursor (assigned under account lock).
sync_entities = Table('sync_entities', metadata,
    Column('account_id', identifier(36), ForeignKey('auth_accounts.id', ondelete='CASCADE'), primary_key=True),
    Column('entity_type', String(32), primary_key=True),
    Column('entity_id', identifier(36), primary_key=True),
    Column('version', BigInteger, nullable=False),
    Column('server_seq', BigInteger, nullable=False, index=True),
    Column('updated_at', BigInteger, nullable=False),
    Column('deleted_at', BigInteger, nullable=True),
    Column('payload', Text, nullable=False),
    Column('client_op_id', identifier(64), nullable=True),
)

# No content: keeps purged IDs terminal and cursors monotonic until account deletion.
sync_tombstones = Table('sync_tombstones', metadata,
    Column('account_id', identifier(36), ForeignKey('auth_accounts.id', ondelete='CASCADE'), primary_key=True),
    Column('entity_type', String(32), primary_key=True),
    Column('entity_id', identifier(36), primary_key=True),
    Column('version', BigInteger, nullable=False),
    Column('server_seq', BigInteger, nullable=False),
    Column('deleted_at', BigInteger, nullable=False),
)
