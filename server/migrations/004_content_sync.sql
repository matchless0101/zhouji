-- Stage B content sync foundation. Apply once after 003, to zhouji only.
-- Does not open sync to clients; feature still requires explicit product release.

CREATE TABLE IF NOT EXISTS sync_entities (
    account_id VARCHAR(36) COLLATE utf8mb4_bin NOT NULL,
    entity_type VARCHAR(32) NOT NULL,
    entity_id VARCHAR(36) COLLATE utf8mb4_bin NOT NULL,
    version BIGINT NOT NULL,
    server_seq BIGINT NOT NULL,
    updated_at BIGINT NOT NULL,
    deleted_at BIGINT NULL,
    payload TEXT NOT NULL DEFAULT '{}',
    client_op_id VARCHAR(64) COLLATE utf8mb4_bin NULL,
    PRIMARY KEY (account_id, entity_type, entity_id),
    KEY sync_entities_seq_idx (account_id, server_seq),
    CONSTRAINT sync_entities_account_fk
        FOREIGN KEY (account_id) REFERENCES auth_accounts (id) ON DELETE CASCADE,
    CONSTRAINT sync_entities_type_chk
        CHECK (entity_type IN ('goal', 'task', 'timing_session'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
