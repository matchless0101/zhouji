-- Preserve only deletion identity/version after the seven-day content purge.
-- Apply to zhouji before deploying the corresponding API; no client gate change.
CREATE TABLE IF NOT EXISTS sync_tombstones (
    account_id VARCHAR(36) COLLATE utf8mb4_bin NOT NULL,
    entity_type VARCHAR(32) NOT NULL,
    entity_id VARCHAR(36) COLLATE utf8mb4_bin NOT NULL,
    version BIGINT NOT NULL,
    server_seq BIGINT NOT NULL,
    deleted_at BIGINT NOT NULL,
    PRIMARY KEY (account_id, entity_type, entity_id),
    KEY sync_tombstones_seq_idx (account_id, server_seq),
    CONSTRAINT sync_tombstones_account_fk
        FOREIGN KEY (account_id) REFERENCES auth_accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
