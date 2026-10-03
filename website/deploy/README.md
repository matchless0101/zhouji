# 阿里云部署

正式官网：<https://zhouji.xiangdangdang.top/>

## 当前部署

| 项目 | 配置 |
| --- | --- |
| 服务器 | `8.130.135.112`，本机 SSH 别名 `yj` |
| DNS | `zhouji` A 记录指向 `8.130.135.112` |
| 服务 | Ubuntu 24.04 / 系统 Nginx，纯静态文件 |
| 发布根目录 | `/var/www/zhouji-site` |
| 当前目录 | `/var/www/zhouji-site/current`，软链接到发布版本 |
| 首次发布版本 | `/var/www/zhouji-site/releases/7cc1dcc` |
| Universal Links 发布版本 | `/var/www/zhouji-site/releases/20260910-universal-links` |
| Nginx 配置 | `/etc/nginx/sites-available/zhouji-site`，软链接启用于 `sites-enabled` |
| HTTPS 证书 | Let's Encrypt，独立域名证书，首次有效期至 2026-12-09 |
| 证书校验目录 | `/var/www/zhouji-site/acme` |
| 续期后加载脚本 | `/etc/letsencrypt/renewal-hooks/deploy/zhouji-reload-nginx` |
| 日志 | `/var/log/nginx/zhouji-site.access.log`、`zhouji-site.error.log` |

`nginx.conf`、`reload-nginx.sh` 与服务器安装内容一致。只新增粥记站点，复用已有 Nginx 和 Certbot，不需要应用进程、数据库或容器。HTTP 跳转到 HTTPS；ACME 校验路径保持可访问。静态内容要求浏览器重新验证缓存，避免更新后仍显示旧布局。

## 后续更新

1. 在本地完成相关测试。网页内容仍以 `website/dist/` 为准。
2. 将 `dist/` 内的静态文件上传到服务器一个新的 `releases/版本号/` 目录，权限为目录 755、文件 644。
3. 校验上传后的文件摘要，在服务器上以临时软链接加原子重命名的方式切换 `current`。只更新静态文件时不需要重启 Nginx。
4. 检查首页、样式、脚本与图片通过正式域名返回 200。保留前一版本目录，必要时将 `current` 指回前一版本。

修改 Nginx 配置时先备份本站配置，再执行 `nginx -t`，成功后才执行 `systemctl reload nginx`。初次 HTTP 配置备份位于 `/var/backups/zhouji-site/initial-http.conf`，仅用于初次部署排错，不是 HTTPS 的日常回滚配置。

## 验证记录（2026-09-10）

- 公网 DNS A 记录解析为 `8.130.135.112`。
- 正式 HTTPS 首页返回 200，TLS 证书验证通过；HTTP 返回 301 并跳转 HTTPS。
- 样式、两个脚本、SVG 标识与手机展示图片全部返回 200。
- 服务器六个静态文件的 SHA-256 与本地一致；公网获取的首页 SHA-256 也一致。
- Nginx 配置测试通过。
- `certbot renew --cert-name zhouji.xiangdangdang.top --dry-run --run-deploy-hooks --non-interactive` 续期演练成功，且执行了本站的 Nginx 加载钩子。复用服务器原有续期定时任务。

官网的 App Store 链接仍未提供，下载状态保持“即将上架”。正式下载、政策和邮箱仍在 `dist/config.js` 配置。

## 隐私政策更新（2026-10-03）

- 正式政策：`https://zhouji.xiangdangdang.top/privacy/`，适用于 iOS 1.0（构建 2）。明确可选联网登录及保存的账户数据、正式版本云同步尚未开放、没有通用备份恢复入口、默认榴莲头像、账户记录隔离和注销前本机副本。
- 政策内联系邮箱已经用户明确授权公开；官网的隐私入口改为打开正式政策。
- 发布目录：`/var/www/zhouji-site/releases/20261003-privacy-build2`。从原线上目录复制完整站点，只更新 `privacy/index.html` 和 `config.js`，随后原子切换 `current`；未修改 Nginx 或登录服务。
- 上一版本保留在 `/var/www/zhouji-site/releases/20260922-privacy`，可通过切换 `current` 回退。
- 验证：官网交互与资源测试 6 项通过；政策结构、链接、联系方式及版本说明检查通过。公网政策与配置逐字节匹配本地文件，首页返回 HTTP 200。
- 本次仅更新网页，不修改安装包，也未提交 App 审核。

## Universal Links 更新

已发布 `/.well-known/apple-app-site-association`，并兼容根目录 `/apple-app-site-association` 地址。两个地址直接返回 `application/json`，关联标识为 `7V46ZF4WY4.com.matchless.ZhouJi`，仅匹配 `/wechat/*`。更新前的 HTTPS 配置保存在 `/var/backups/zhouji-site/before-universal-links.conf`，原静态版本保留在 `releases/7cc1dcc`。

后续打包需包含隐藏目录 `.well-known`。平台填写信息、签名要求和验收边界见 [微信与 Universal Links 说明](../../docs/04-微信开放平台与UniversalLinks.md)。
