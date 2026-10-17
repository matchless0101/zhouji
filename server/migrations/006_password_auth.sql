-- Apply once after 005 to the dedicated ZhouJi database. Preserve legacy identities.
ALTER TABLE auth_accounts DROP CHECK auth_account_one_provider;
ALTER TABLE auth_accounts ADD CONSTRAINT auth_account_one_provider CHECK (
    (provider = 'apple' AND apple_subject IS NOT NULL AND apple_refresh_encrypted IS NOT NULL AND wechat_subject IS NULL AND wechat_refresh_encrypted IS NULL)
    OR (provider = 'wechat' AND wechat_subject IS NOT NULL AND wechat_refresh_encrypted IS NOT NULL AND apple_subject IS NULL AND apple_refresh_encrypted IS NULL)
    OR (provider = 'password' AND apple_subject IS NULL AND apple_refresh_encrypted IS NULL AND ((wechat_subject IS NULL AND wechat_refresh_encrypted IS NULL) OR (wechat_subject IS NOT NULL AND wechat_refresh_encrypted IS NOT NULL)))
);
-- Legacy is a rolling-back compatibility default. New code always supplies auth_method.
ALTER TABLE auth_sessions ADD COLUMN auth_method VARCHAR(16) NOT NULL DEFAULT 'legacy';
UPDATE auth_sessions s JOIN auth_accounts a ON s.account_id = a.id SET s.auth_method = a.provider;
ALTER TABLE auth_challenges
    ADD COLUMN purpose VARCHAR(32) NOT NULL DEFAULT 'login',
    ADD COLUMN account_id VARCHAR(36) COLLATE utf8mb4_bin NULL,
    ADD COLUMN session_token_hash VARCHAR(64) COLLATE utf8mb4_bin NULL,
    ADD CONSTRAINT challenge_account FOREIGN KEY (account_id) REFERENCES auth_accounts(id) ON DELETE CASCADE,
    ADD CONSTRAINT challenge_session FOREIGN KEY (session_token_hash) REFERENCES auth_sessions(token_hash) ON DELETE CASCADE;
CREATE TABLE auth_password_credentials (
    account_id VARCHAR(36) COLLATE utf8mb4_bin PRIMARY KEY,
    username VARCHAR(32) COLLATE utf8mb4_bin NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    recovery_hash VARCHAR(64) COLLATE utf8mb4_bin NOT NULL,
    updated_at BIGINT NOT NULL,
    CONSTRAINT password_account FOREIGN KEY (account_id) REFERENCES auth_accounts(id) ON DELETE CASCADE
);
CREATE TABLE auth_attempts (
    key_hash VARCHAR(64) COLLATE utf8mb4_bin PRIMARY KEY,
    window_start BIGINT NOT NULL,
    count BIGINT NOT NULL,
    blocked_until BIGINT NOT NULL DEFAULT 0,
    expires_at BIGINT NOT NULL,
    INDEX attempts_expiry (expires_at)
);
