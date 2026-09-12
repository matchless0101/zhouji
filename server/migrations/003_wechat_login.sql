-- Apply once after 002_account_profile.sql, to zhouji only. Preserve all Apple accounts.
ALTER TABLE auth_accounts
    ADD COLUMN provider VARCHAR(16) NOT NULL DEFAULT 'apple',
    MODIFY COLUMN apple_subject VARCHAR(255) COLLATE utf8mb4_bin NULL,
    MODIFY COLUMN apple_refresh_encrypted TEXT NULL,
    ADD COLUMN wechat_subject VARCHAR(255) COLLATE utf8mb4_bin NULL UNIQUE,
    ADD COLUMN wechat_refresh_encrypted TEXT NULL,
    ADD CONSTRAINT auth_account_one_provider CHECK (
        (provider = 'apple' AND apple_subject IS NOT NULL AND apple_refresh_encrypted IS NOT NULL AND wechat_subject IS NULL AND wechat_refresh_encrypted IS NULL)
        OR (provider = 'wechat' AND wechat_subject IS NOT NULL AND wechat_refresh_encrypted IS NOT NULL AND apple_subject IS NULL AND apple_refresh_encrypted IS NULL)
    );
ALTER TABLE auth_challenges ADD COLUMN provider VARCHAR(16) NOT NULL DEFAULT 'apple';
