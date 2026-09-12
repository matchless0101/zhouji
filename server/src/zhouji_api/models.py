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
    CheckConstraint("(provider = 'apple' AND apple_subject IS NOT NULL AND apple_refresh_encrypted IS NOT NULL AND wechat_subject IS NULL AND wechat_refresh_encrypted IS NULL) OR (provider = 'wechat' AND wechat_subject IS NOT NULL AND wechat_refresh_encrypted IS NOT NULL AND apple_subject IS NULL AND apple_refresh_encrypted IS NULL)", name='auth_account_one_provider'),
)
sessions = Table('auth_sessions', metadata,
    Column('token_hash', identifier(64), primary_key=True),
    Column('account_id', identifier(36), ForeignKey('auth_accounts.id', ondelete='CASCADE'), nullable=False, index=True),
    Column('created_at', BigInteger, nullable=False),
    Column('expires_at', BigInteger, nullable=False, index=True),
)
challenges = Table('auth_challenges', metadata,
    Column('id_hash', identifier(64), primary_key=True),
    Column('nonce', identifier(64), nullable=False),
    Column('provider', String(16), nullable=False, server_default='apple'),
    Column('expires_at', BigInteger, nullable=False, index=True),
)
