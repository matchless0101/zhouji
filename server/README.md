# 粥记后端

用户于 2026-09-11 确认使用 Python + FastAPI + MySQL。复用 `yj` 的 MySQL 8.0 实例，为粥记配置独立数据库和受限账号，iOS 本地继续使用 SwiftData。

## 2026-09-20 可靠性修复（已部署）

当前生产版本 `sync-reliability-20260920-01`，迁移 005 已执行，服务器侧 72 项测试通过；三个定时任务与一次完整隔离恢复演练已通过。外部通知、异地副本与正式保留期仍待配置。

同版本并发修改只有内容/操作/时间一致时去重，否则返回冲突。迁移 `005_sync_tombstones.sql` 保存不含正文的最小删除凭据；七天清理正文后，旧 ID 不能被离线设备复活，同步序号不回退，注销一并删除凭据。push、purge 与注销通过账户行锁协调，空账户库也可安全并发推送。

iOS 按已确认内容检测增量，处理改名、图标、取消完成及撤销删除；接收已清理内容的删除冲突时保留本地历史事实。同步仍默认关闭，用户自行真机验收。

运维脚本和三组 systemd 单元见 `deploy/BACKUP-DRILL.md`。最新部署与演练结果统一记录在 `docs/08-云同步部署与真机联调.md`，历史记录不代表本次变更已经部署。

## 当前交付范围

- FastAPI 与独立 MySQL 已部署，提供健康检查、Apple / 微信登录准备与换码、授权验证、账户读取、昵称头像编辑、退出及注销接口。
- iOS 使用系统 Apple 登录按钮与微信 OpenSDK 登录入口，登录状态保存在设备钥匙串，支持恢复、退出和注销。登录不上传本机任务、目标或计时记录。
- 微信 AppID 与 AppSecret 已由用户提供并私下保存；服务端微信 OAuth、账户多 provider 模型与迁移 `003_wechat_login.sql` 已完成，**003 已在生产执行**。用户已确认真机微信登录成功；退出、重新登录、注销与异常路径仍应分别验收并记录。
- Apple 平台 App ID、专用密钥与服务器配置已完成。用户已在真机确认 Apple 登录与退出正常；真机注销尚未人工验收，其成功、失败与重试路径已由自动化测试覆盖。
- 云同步：服务端协议已部署生产（`content-sync-20260914-01`，迁移 `004` 已执行）；**iOS 功能开关仍默认关闭**，待真机联调后再对用户开放。规则见 `docs/05-云同步产品需求增量.md` 与 `docs/08-云同步部署与真机联调.md`。

验证记录（2026-09-12）：后端 22 项测试本地和服务器均通过；iOS 原 29 项单元测试及新增钥匙串读取异常测试、2 项游客界面测试、模拟器构建和真机签名构建通过，已安装到配对 iPhone。真实 MySQL 的账户与会话生命周期验证通过，其中 Apple 返回使用隔离测试适配器。生产服务未安装任何模拟登录入口。Apple 官方令牌端点对故意无效的授权码返回预期错误，该检查只证明连通；随后用户已在真机确认真实登录与退出成功。

### 独立数据库交付（2026-09-11）

- `zhouji` 库已创建，字符集 `utf8mb4`、排序规则 `utf8mb4_0900_ai_ci`。
- `zhouji_app` 账号仅允许从 `127.0.0.1` 连接，只获授 `zhouji.*` 的 `SELECT / INSERT / UPDATE / DELETE` 权限；不具备建库、建表、管理账号或授权权限。后续数据库迁移需由管理员单独执行。
- 新密码仅在服务器保存；`/etc/zhouji-db-password` 和 `/etc/zhouji/api.env` 均为 `root:root`、权限 `600`。不得复制配置内容至仓库。
- 已验证业务账号登录、中文与 emoji 数据的增删改查，以及访问响当档 `xdd` 被拒绝。验证表已删除，响当档的库、账号和配置未修改。
- 最初数据库验证使用 MySQL 客户端；本次增量已完成 FastAPI 的真实 MySQL 联调，云同步仍未上线。

## 开发与验证

真实 AppID、AppSecret、私钥及数据库密码不得写入示例、文档、测试或提交记录。AppID 与密钥统一使用未跟踪的本地或服务器配置。克隆仓库后执行 `git config core.hooksPath .githooks`，启用暂存区的微信 AppID / 私钥拦截检查；它是额外防线，不替代提交前检查。

使用 Python 3.12，创建虚拟环境后安装固定版本依赖与本地包：

```sh
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements.lock
.venv/bin/python -m pip install --no-deps -e .
.venv/bin/python -m pytest
```

`requirements.lock` 包含服务和测试依赖；不包含 editable 本地路径。数据库配置参考 `.env.example`，由调用环境或服务管理器加载。应用不自动读取 `.env`，配置缺失时启动失败，不能退回 SQLite 或无密码数据库。

```sh
.venv/bin/uvicorn zhouji_api.app:create_app --factory --host 127.0.0.1 --port 8011
```

| 接口 | 行为 |
| --- | --- |
| `GET /api/v1/health/live` | 服务存活返回 200，不检查数据库 |
| `GET /api/v1/health/ready` | MySQL 连接与已启用登录所需表结构正常返回 200，否则 503 |
| `POST /api/v1/auth/apple/challenge` | 返回 5 分钟有效的一次性 challenge 和 nonce |
| `POST /api/v1/auth/apple` | 接收 challenge、code、identity_token，向 Apple 换码并验证后返回账户与 30 天会话 |
| `POST /api/v1/auth/wechat/challenge` | 返回绑定微信 provider 的一次性 challenge 和 nonce |
| `POST /api/v1/auth/wechat` | 接收 challenge、code，向微信换码并验证后返回账户与 30 天会话 |
| `GET /api/v1/account` | Bearer 会话查询当前账户，每 24 小时向对应登录提供方再验证授权 |
| `POST /api/v1/auth/logout` | 撤销当前会话，重复退出返回 204 |
| `DELETE /api/v1/account` | 需最近 10 分钟的登录；先撤销 Apple 授权（微信无对等撤销端点），再删除账户及所有会话与同步内容 |
| `POST /api/v1/sync/push` | 账户内容上行：按实体版本写入；旧版本返回冲突与服务端状态；同版本幂等 |
| `GET /api/v1/sync/pull` | 按 `server_seq` 游标拉取本账户变更 |
| `GET /api/v1/sync/status` | 最新游标与软删除计数（阶段 B 基础，客户端同步 UI 尚未接通） |

## 内容同步（阶段 B–D 服务端已部署，iOS 默认关闭）

- 表：`sync_entities`（迁移 `004_content_sync.sql`，2026-09-14 已在生产执行）。
- 发布：`/opt/zhouji-api/releases/content-sync-20260914-01`，`current` 已切换；回退可指回 `wechat-20260912-03`。
- R1：客户端 `version` 小于服务端 → `conflicts` 返回服务端版本与 payload，不静默覆盖。
- R2：软删除写入 `deleted_at`；`purge_soft_deleted(..., older_than_seconds=7*86400)` 按 7 天清理正文并保留最小删除凭据（定时任务状态见 `docs/08-云同步部署与真机联调.md`）。
- R3：应用层约定仅推送已结束计时会话。
- 健康探针：`/usr/local/sbin/zhouji-health-probe`；原“每 5 分钟 cron”记录未通过核验，2026-09-20 已由 `zhouji-ops-check.timer` 每五分钟调用并验证。
- 生产部署前备份：`/var/backups/zhouji/zhouji-20260914-160830.sql.gz`（zhouji_app 权限限制下含 3 张 auth 表结构；正式灾备建议用 debian-sys-maint 全量 dump）。
- 服务器侧 pytest：50 项通过。公网 `GET /api/v1/health/ready`=200，未登录 `/sync/pull`=401。

健康响应均禁止缓存，不返回数据库地址、账号、SQL 错误或密钥。登录启用时，就绪检查同时检查账户、会话和一次性请求表的列。公网不提供 Swagger/OpenAPI 文档。

## 账户昵称与头像

新增 `PATCH /api/v1/account/profile`，请求仅包含 `nickname` 与 `avatar`。身份来自 Bearer 会话，不接受客户端指定账户 ID。登录与账户读取响应增加昵称和头像字段，原客户端可忽略新字段，新客户端可读取缺失字段的旧钥匙串缓存。

首次安装先执行 `001_apple_auth.sql`，再执行一次 `002_account_profile.sql`；已有登录服务只执行 `002`，为已有账户补充默认资料。微信登录需在 `002` 之后执行一次 `003_wechat_login.sql`，为已有 Apple 账户补默认 `provider`，并增加微信身份列与单 provider 约束。生产迁移先检查目标列/约束：均不存在才执行，均存在则跳过，部分存在时停止检查，不自动猜测修复。

头像仅支持固定枚举，不涉及上传文件。昵称按 NFC 规范化后校验长度及不可见字符。自动化验证覆盖默认资料、修改保存、再次登录保留、账号隔离、非法昵称、非法头像地址和已撤销授权。

本增量已部署至 `/opt/zhouji-api/releases/profile-20260912-02`，`current` 已切换。31 项后端测试、34 项 iOS 单元测试、游客资料页回归测试与真机签名构建通过，新版已安装到配对 iPhone。使用隔离测试账户完成真实 MySQL 的默认资料、Unicode 昵称修改、再次登录保留和账户隔离验证；测试账户已清理，未改动用户资料。此次资料编辑尚无用户人工验收记录。

若需回退本增量，将 `current` 恢复指向 `/opt/zhouji-api/releases/apple-login-20260912-01` 并重启专用服务。保留新增列和已保存资料，旧版登录代码可忽略这些字段；无需回退 Nginx 或删除数据库列。

## 微信登录

- 依赖 `ZHOUJI_WECHAT_APP_ID`、`ZHOUJI_WECHAT_APP_SECRET_PATH` 与共用的 `ZHOUJI_TOKEN_ENCRYPTION_KEY_PATH`；缺任一项时微信登录返回 530/503，不影响 Apple 登录与健康检查。
- AppSecret 仅保存为服务器权限 600 的文件；systemd 通过 `LoadCredential=wechat-app-secret` 映射到 `/run/credentials/zhouji-api.service/`。真实 AppID 不写入仓库示例或文档。
- challenge 与会话按 provider 隔离；微信 refresh token 与 Apple 一样使用 Fernet 加密保存。httpx/httpcore 日志调高阈值，避免官方 OAuth 把 secret 写进查询串时落入日志。
- 注销：删除粥记账户与加密凭据；微信无官方 revoke 端点，客户端确认文案引导用户在微信设置中管理授权。

## Apple 登录部署

- 当前运行目录：`/opt/zhouji-api/current`，专用系统用户 `zhouji-api`，systemd 单进程监听 `127.0.0.1:8011`。
- 表结构：管理员对 `zhouji` 执行 `migrations/001_apple_auth.sql`；业务用户继续只有增删改查权限。不要对其他项目执行迁移。
- 真实配置只在 `/etc/zhouji/api.env`；Apple 私钥在 `/etc/zhouji/apple-login.p8`，微信 AppSecret 在 `/etc/zhouji/wechat-app-secret`，刷新令牌加密密钥在 `/etc/zhouji/token-encryption-key`，均 `root:root 600`。
- systemd 使用 `LoadCredential` 提供上述文件，应用中的路径分别是 `/run/credentials/zhouji-api.service/apple-private-key`、`wechat-app-secret` 和 `token-encryption-key`。不要将加密密钥重新生成，否则已保存的刷新令牌将无法解密。需将它与数据库一同私下备份。
- Apple / 微信的刷新令牌加密保存，粥记会话只保存 SHA-256 摘要。授权码与 identity token 不落库、不写日志；接口校验失败也不回显提交值。
- 粥记 Nginx `/api/` 保留路径代理到 8011，覆盖真实客户端地址，禁用访问日志，限制 32KB 请求体和请求速率。应用授权接口额外按来源限制每分钟 20 次，当前实现限定单进程；增加 worker 或副本前须改用共享限流存储。
- 配置备份：`/etc/zhouji/api.env.before-apple`、`/etc/nginx/sites-available/zhouji-site.before-apple`。官网、两个 AASA 地址及 `/wechat/` 应在每次部署后验证。
- 账号功能不删除本机 SwiftData 数据；云端事实存于 `sync_entities`，本机使用独立账户库。同步默认关闭。

## 备份与故障探针（阶段 A）

- 数据库备份脚本：`deploy/backup-zhouji-db.sh`；演练步骤与验收见 `deploy/BACKUP-DRILL.md`。令牌加密密钥必须与库同批备份。
- 就绪探针：`deploy/health-probe.sh`，对 `GET /api/v1/health/ready` 非 200 返回非零退出码，可接入 cron / systemd timer / 外部拨测。示例：

```sh
# crontab -e
*/5 * * * * /opt/zhouji-api/current/deploy/health-probe.sh http://127.0.0.1:8011 || logger -t zhouji-api 'ready check failed'
```

告警通道（邮件、IM webhook）由服务器侧已有通知设施承接；本仓库只保证探针可脚本化调用。

回退首次部署：先恢复粥记站点配置备份，移除本次专用限流配置 `/etc/nginx/conf.d/zhouji-api-limit.conf`，`nginx -t` 成功后 reload，再停止 `zhouji-api`。保留数据库与密钥备份，不因服务回退删除账户数据。

接口实现依据：[Apple 用户验证](https://developer.apple.com/documentation/signinwithapple/verifying-a-user)、[Apple 账户注销与令牌撤销](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)、[PyJWT](https://pyjwt.readthedocs.io/en/stable/)。
