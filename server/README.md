# 粥记后端

用户于 2026-09-11 确认使用 Python + FastAPI + MySQL。复用 `yj` 的 MySQL 8.0 实例，为粥记配置独立数据库和受限账号，iOS 本地继续使用 SwiftData。

## 当前交付范围

- FastAPI 服务入口、MySQL 连接池、配置校验、服务存活与数据库就绪检查。
- 不包含账户注册、微信或 Apple 授权、令牌签发、云端任务数据和同步接口。
- 独立 MySQL 数据库和账号已创建并完成数据库层验证；FastAPI 服务尚未部署，应用接口与 MySQL 的联调尚未完成。
- 微信 AppID 已由用户提供，仅在未跟踪的配置文件中保存；AppSecret 及微信登录权限状态待补充。
- Apple Key ID 与 `.p8` 私钥按用户要求暂缓。

验证记录：Python 3.12 下 7 项测试通过，依赖一致性检查通过。覆盖 MySQL 方言和特殊字符密码配置、缺失配置、非法端口、HTTP 健康检查、数据库故障响应与错误信息脱敏。HTTP 成功路径使用 SQLite 测试连接；没有用它代替生产 MySQL，也未将其作为 MySQL 联调通过的证据。

### 独立数据库交付（2026-09-11）

- `zhouji` 库已创建，字符集 `utf8mb4`、排序规则 `utf8mb4_0900_ai_ci`。
- `zhouji_app` 账号仅允许从 `127.0.0.1` 连接，只获授 `zhouji.*` 的 `SELECT / INSERT / UPDATE / DELETE` 权限；不具备建库、建表、管理账号或授权权限。后续数据库迁移需由管理员单独执行。
- 新密码仅在服务器保存；`/etc/zhouji-db-password` 和 `/etc/zhouji/api.env` 均为 `root:root`、权限 `600`。不得复制配置内容至仓库。
- 已验证业务账号登录、中文与 emoji 数据的增删改查，以及访问响当档 `xdd` 被拒绝。验证表已删除，响当档的库、账号和配置未修改。
- 上述验证使用 MySQL 客户端，不代表 FastAPI、登录或云同步已经上线。

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
| `GET /api/v1/health/ready` | MySQL 执行 `SELECT 1` 成功返回 200；连接或查询异常返回 503 |

健康响应均禁止缓存，不返回数据库地址、账号、SQL 错误或密钥。数据库就绪仅表示可连接，后续增加业务表时应扩展为包含数据库迁移状态的检查。公网不提供 Swagger/OpenAPI 文档。

## 部署进度与后续步骤

1. 已完成：建立独立 `zhouji` 数据库、`zhouji_app` 账号和服务器凭据配置。数据库迁移通过单独管理凭据执行。
2. 待执行：创建无登录权限的 `zhouji-api` 系统用户，将服务安装到 `/opt/zhouji-api/releases/版本号`，虚拟环境随版本建立。用 `current` 软链接指向经过验证的版本。
3. 待执行：由 systemd 读取已准备的 `/etc/zhouji/api.env`，安装 `deploy/zhouji-api.service`。数据库端口与 API 端口均只监听本机。
4. 先检查 API 本机存活和真实 MySQL 就绪响应，再为现有粥记 Nginx 站点增加 `/api/` 代理到 `127.0.0.1:8011`，保留 `/api/` 前缀，禁用该路径访问日志，设置合理的请求大小和超时限制。
5. 备份本站 Nginx 配置，执行 `nginx -t` 后再 reload；验证官网、HTTPS、AASA 与 `/wechat/` 仍正常。失败时恢复本站配置和上一个 API 发布版本。

本阶段只新增粥记独立数据库、专用账号和凭据配置，没有修改 Nginx 或 systemd。不得因为数据库验证或健康检查成功就将登录、云同步标为完成。
