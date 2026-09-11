# 粥记后端

用户于 2026-09-11 确认使用 Python + FastAPI + MySQL。复用 `yj` 的 MySQL 8.0 实例，为粥记配置独立数据库和受限账号，iOS 本地继续使用 SwiftData。

## 当前交付范围

- FastAPI 服务入口、MySQL 连接池、配置校验、服务存活与数据库就绪检查。
- 不包含账户注册、微信或 Apple 授权、令牌签发、云端任务数据和同步接口。
- 服务尚未部署；线上 MySQL 凭据尚未提供，因此当前测试不代表已通过服务器 MySQL 联调。
- 微信 AppID 已由用户提供，仅在未跟踪的配置文件中保存；AppSecret 及微信登录权限状态待补充。
- Apple Key ID 与 `.p8` 私钥按用户要求暂缓。

验证记录：Python 3.12 下 7 项测试通过，依赖一致性检查通过。覆盖 MySQL 方言和特殊字符密码配置、缺失配置、非法端口、HTTP 健康检查、数据库故障响应与错误信息脱敏。HTTP 成功路径使用 SQLite 测试连接；没有用它代替生产 MySQL，也未将其作为 MySQL 联调通过的证据。

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

## 部署准备（尚未执行）

1. 使用数据库管理员为粥记建立 `zhouji` 库，字符集 `utf8mb4`。创建独立 `zhouji_app` 账号并限制到本机，只授予本项目实际需要的权限；数据库迁移通过单独管理凭据执行。
2. 创建无登录权限的 `zhouji-api` 系统用户，将服务安装到 `/opt/zhouji-api/releases/版本号`，虚拟环境随版本建立。用 `current` 软链接指向经过验证的版本。
3. 将配置放在 `/etc/zhouji/api.env`（root 所有、权限 600），由 systemd 读取；安装 `deploy/zhouji-api.service`。数据库端口与 API 端口均只监听本机。
4. 先检查 API 本机存活和真实 MySQL 就绪响应，再为现有粥记 Nginx 站点增加 `/api/` 代理到 `127.0.0.1:8011`，保留 `/api/` 前缀，禁用该路径访问日志，设置合理的请求大小和超时限制。
5. 备份本站 Nginx 配置，执行 `nginx -t` 后再 reload；验证官网、HTTPS、AASA 与 `/wechat/` 仍正常。失败时恢复本站配置和上一个 API 发布版本。

本阶段没有修改生产数据库、Nginx 或 systemd。不得因为健康检查成功就将登录、云同步标为完成。
