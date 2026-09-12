-- Apply once after 001_apple_auth.sql, to the dedicated zhouji database only.
-- Existing accounts receive the same defaults as newly created accounts.
ALTER TABLE auth_accounts
    ADD COLUMN nickname VARCHAR(20) NOT NULL DEFAULT '粥记用户',
    ADD COLUMN avatar VARCHAR(16) NOT NULL DEFAULT 'sunrise';
