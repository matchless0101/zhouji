-- Apply once after 006. Creation provider and account IDs stay unchanged.
-- A WeChat-created account may remove WeChat only after password setup;
-- the API requires an existing password credential before unbinding.
ALTER TABLE auth_accounts DROP CHECK auth_account_one_provider,
    ADD CONSTRAINT auth_account_one_provider CHECK (
        (provider = 'apple' AND apple_subject IS NOT NULL AND apple_refresh_encrypted IS NOT NULL
            AND wechat_subject IS NULL AND wechat_refresh_encrypted IS NULL)
        OR (provider IN ('wechat', 'password') AND apple_subject IS NULL AND apple_refresh_encrypted IS NULL
            AND ((wechat_subject IS NULL AND wechat_refresh_encrypted IS NULL)
                OR (wechat_subject IS NOT NULL AND wechat_refresh_encrypted IS NOT NULL)))
    );
