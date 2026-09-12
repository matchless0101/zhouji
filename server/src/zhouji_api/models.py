from sqlalchemy import BigInteger, Column, ForeignKey, MetaData, String, Table, Text

metadata = MetaData()
# Binary collation: Apple subjects and token hashes are case-sensitive identifiers.
def identifier(size):
    return String(size).with_variant(String(size, collation='utf8mb4_bin'), 'mysql')

accounts = Table('auth_accounts', metadata,
    Column('id', identifier(36), primary_key=True),
    Column('apple_subject', identifier(255), nullable=False, unique=True),
    Column('apple_refresh_encrypted', Text, nullable=False),
    Column('created_at', BigInteger, nullable=False),
    Column('verified_at', BigInteger, nullable=False),
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
    Column('expires_at', BigInteger, nullable=False, index=True),
)
