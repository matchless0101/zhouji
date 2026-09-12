# 粥记后端

用户于 2026-09-11 确认使用 Python + FastAPI + MySQL。复用 `yj` 的 MySQL 8.0 实例，为粥记配置独立数据库和受限账号，iOS 本地继续使用 SwiftData。

## 当前交付范围

- FastAPI 与独立 MySQL 已部署，提供健康检查、Apple 登录准备、授权验证、账户读取、退出及注销接口。
- iOS 使用系统 Apple 登录按钮，登录状态保存在设备钥匙串，支持恢复、退出和注销。登录不上传本机任务、目标或计时记录。
- 微信 AppID 与 AppSecret 已由用户提供并私下保存，微信登录权限仍待确认，微信 SDK 与登录接口尚未实现。
- Apple 平台 App ID、专用密钥与服务器配置已完成。用户已在真机确认 Apple 登录与退出正常；真机注销尚未人工验收，其成功、失败与重试路径已由自动化测试覆盖。
- 云同步尚未实现，登录界面与游客界面均明确说明数据仍在本机。

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
| `GET /api/v1/account` | Bearer 会话查询当前账户，每 24 小时向 Apple 再验证授权 |
| `POST /api/v1/auth/logout` | 撤销当前会话，重复退出返回 204 |
| `DELETE /api/v1/account` | 需最近 10 分钟的登录；先撤销 Apple 授权，再删除账户及所有会话 |

健康响应均禁止缓存，不返回数据库地址、账号、SQL 错误或密钥。登录启用时，就绪检查同时检查账户、会话和一次性请求表的列。公网不提供 Swagger/OpenAPI 文档。

## Apple 登录部署

- 当前运行目录：`/opt/zhouji-api/current`，专用系统用户 `zhouji-api`，systemd 单进程监听 `127.0.0.1:8011`。
- 表结构：管理员对 `zhouji` 执行 `migrations/001_apple_auth.sql`；业务用户继续只有增删改查权限。不要对其他项目执行迁移。
- 真实配置只在 `/etc/zhouji/api.env`；Apple 私钥在 `/etc/zhouji/apple-login.p8`，刷新令牌加密密钥在 `/etc/zhouji/token-encryption-key`，均 `root:root 600`。
- systemd 使用 `LoadCredential` 提供两个文件，应用中的路径分别是 `/run/credentials/zhouji-api.service/apple-private-key` 和 `/run/credentials/zhouji-api.service/token-encryption-key`。不要将加密密钥重新生成，否则已保存的 Apple 刷新令牌将无法解密。需将它与数据库一同私下备份。
- Apple 的刷新令牌加密保存，粥记会话只保存 SHA-256 摘要。授权码与 identity token 不落库、不写日志；接口校验失败也不回显提交值。
- 粥记 Nginx `/api/` 保留路径代理到 8011，覆盖真实客户端地址，禁用访问日志，限制 32KB 请求体和请求速率。应用授权接口额外按来源限制每分钟 20 次，当前实现限定单进程；增加 worker 或副本前须改用共享限流存储。
- 配置备份：`/etc/zhouji/api.env.before-apple`、`/etc/nginx/sites-available/zhouji-site.before-apple`。官网、两个 AASA 地址及 `/wechat/` 应在每次部署后验证。
- 本次账号功能不删除本机 SwiftData 数据；尚无云端任务表。后续同步必须增加游客数据归属和账号隔离，再接通自动同步。

回退首次部署：先恢复粥记站点配置备份，移除本次专用限流配置 `/etc/nginx/conf.d/zhouji-api-limit.conf`，`nginx -t` 成功后 reload，再停止 `zhouji-api`。保留数据库与密钥备份，不因服务回退删除账户数据。

接口实现依据：[Apple 用户验证](https://developer.apple.com/documentation/signinwithapple/verifying-a-user)、[Apple 账户注销与令牌撤销](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)、[PyJWT](https://pyjwt.readthedocs.io/en/stable/)。
