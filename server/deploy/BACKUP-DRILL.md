# 粥记服务端备份与恢复演练

正式开放同步前，必须完成备份恢复演练及异地存储、外部通知配置。实际执行结果见 `docs/08-云同步部署与真机联调.md`；本文件说明脚本行为，不代表已在生产执行。

## 同批备份范围

`backup-zhouji-db.sh /var/backups/zhouji` 成功时产出：

- `zhouji-时间.sql.gz`：完整 `zhouji` 数据库，包括账户、会话、登录挑战、同步正文和删除凭据。
- `zhouji-时间.bundle.tar.gz`：同份 SQL，加 `configuration/api.env`、`secrets/token-encryption-key`、`secrets/apple-login.p8`、`secrets/wechat-app-secret`。

数据库与密钥必须同批保存。输出目录权限 700、文件 600；包内含私密配置，仅 root 可读，不提交 Git 或上传公开位置。备份包目前依赖文件权限保护，异地副本应使用加密存储及独立访问权限，位置待用户确认。

脚本优先使用 `/etc/mysql/debian.cnf`，也支持 `ZHOUJI_MYSQL_DEFAULTS_FILE`、环境密码或 `ZHOUJI_DB_PASSWORD_FILE`。`mysqldump` 使用单事务和 `--no-tablespaces`；配置或密钥缺失、dump/压缩失败均返回非零，不发布完整备份包。压缩包最后原子改名，作为完成标志。原始 dump 错误留在私有临时文件并随临时目录清理，不打印凭据。

导出的 SQL 不包含 `CREATE DATABASE` / `USE`，恢复时必须明确选择预先创建的目标库；不得直接将包导入生产库。

## 定时任务

| 单元 | 频率 | 行为 |
| --- | --- | --- |
| `zhouji-backup.timer` | 每日 03:17，最多随机延后 10 分钟 | 生成数据库与密钥完整包 |
| `zhouji-purge.timer` | 每日 04:05，最多随机延后 10 分钟 | 清理七天前删除正文，保留无正文凭据 |
| `zhouji-ops-check.timer` | 每 5 分钟 | 检查本地/公网 ready，以及最近完整备份非空、gzip 完整且不超过 36 小时 |

运行时区沿用服务器。失败通过 systemd failed 状态和 journal 记录；这不是已接通外部消息通知。目前不自动删除旧备份，正式保留期、异地副本、RPO/RTO 和通知接收渠道待确认后配置。

安装位置：`backup-zhouji-db.sh` → `/usr/local/sbin/zhouji-backup`，`health-probe.sh` → `/usr/local/sbin/zhouji-health-probe`，`check-zhouji-ops.sh` → `/usr/local/sbin/zhouji-ops-check`。三个 service/timer 复制至 `/etc/systemd/system/` 后先运行 `systemd-analyze verify`，再 reload、手动执行与启用 timer。清理服务要求 API 与 005 迁移已部署。

## 隔离恢复演练

1. 在服务器私有临时目录解包指定 bundle；不要将密钥复制到工作区或日志。
2. 创建随机命名的 `zhouji_restore_...` 空库，确认与 `zhouji` 不同。
3. 对 SQL 先做 `gzip -t`，再解压至私有临时文件，使用 `mysql ... 隔离库名 < 文件`；分别检查解压与导入的退出码，不能用无 pipefail 的管道吞错。
4. 核对所有表结构和数量；同步正文及 `sync_tombstones` 均应纳入。记录备份生成与验证时刻，避免把备份后的合法新写入误当恢复丢失。
5. 用备份中对应 `token-encryption-key` 验证备份内加密令牌可解密，只记录成功/失败，不输出令牌。没有令牌时，用该密钥进行隔离加解密回环并记录验证范围。
6. 隔离库运行适当查询后仅删除本次创建的隔离库和临时解包目录；不覆盖生产，不删除原备份。
7. 归档包名、权限、表数量、耗时、密钥验证范围与结果。

恢复生产是独立操作：旧备份可能包含后来注销的账户，恢复前必须处理注销/删除记录与旧游标重新对账；本轮正常清理凭据不能代替完整灾备回滚协议。在完成该专项验收前，不能声称任意旧备份均可直接恢复上线。

## 验收

- [x] 服务器成功产出完整 600 权限备份包（2026-09-20）
- [x] 向隔离库恢复并记录所有表的数量（2026-09-20；见 08 联调记录）
- [x] 同批密钥可用性验证（2 个既有令牌解密成功）
- [x] 三个定时任务已安装、启用并手动运行成功（2026-09-20）
- [ ] 外部故障通知和异地副本配置并演练
