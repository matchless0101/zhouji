#!/bin/sh
# Certbot deploy hook. Reload only after this site's certificate is renewed.
set -eu
if [ "${RENEWED_LINEAGE:-}" = /etc/letsencrypt/live/zhouji.xiangdangdang.top ]; then
    /usr/sbin/nginx -t
    /usr/bin/systemctl reload nginx
fi
