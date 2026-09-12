-- Administrator only. Apply to the dedicated zhouji database, never xdd.
CREATE TABLE IF NOT EXISTS auth_accounts (
    id VARCHAR(36) COLLATE utf8mb4_bin NOT NULL PRIMARY KEY,
    apple_subject VARCHAR(255) COLLATE utf8mb4_bin NOT NULL UNIQUE,
    apple_refresh_encrypted TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    verified_at BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS auth_challenges (
    id_hash VARCHAR(64) COLLATE utf8mb4_bin NOT NULL PRIMARY KEY,
    nonce VARCHAR(64) COLLATE utf8mb4_bin NOT NULL,
    expires_at BIGINT NOT NULL,
    INDEX ix_auth_challenges_expires_at (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS auth_sessions (
    token_hash VARCHAR(64) COLLATE utf8mb4_bin NOT NULL PRIMARY KEY,
    account_id VARCHAR(36) COLLATE utf8mb4_bin NOT NULL,
    created_at BIGINT NOT NULL,
    expires_at BIGINT NOT NULL,
    INDEX ix_auth_sessions_expires_at (expires_at),
    INDEX ix_auth_sessions_account_id (account_id),
    FOREIGN KEY (account_id) REFERENCES auth_accounts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
