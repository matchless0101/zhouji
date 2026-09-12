# 粥记服务端备份与恢复演练

_阶段 A 数据保护：在开放云同步前完成账户库备份策略与一次可复现的恢复演练。_

## 备份范围

| 项 | 说明 |
| --- | --- |
| MySQL `zhouji` 库 | 账户、会话、challenge；云同步上线后含用户内容表 |
| `/etc/zhouji/api.env` | 配置（root 600） |
| Apple 私钥 / 微信 AppSecret | 路径见 `server/README.md` |
| **令牌加密密钥** | `/etc/zhouji/token-encryption-key`，与库必须同批备份；丢失则已存 refresh 无法解密 |

密钥与数据库备份放在同一受控目录，权限 `600`，不进入 Git。

## 自动备份

脚本：`deploy/backup-zhouji-db.sh`

```sh
# 一次性
sudo install -m 750 deploy/backup-zhouji-db.sh /usr/local/sbin/zhouji-backup-db
sudo mkdir -p /var/backups/zhouji
sudo chown root:root /var/backups/zhouji
sudo chmod 700 /var/backups/zhouji

# 建议每日 cron（root）
# 17 3 * * * /usr/local/sbin/zhouji-backup-db /var/backups/zhouji >>/var/log/zhouji-backup.log 2>&1
```

保留策略建议：本地 14 天；至少再有一份异地拷贝（私有对象存储或另一台主机）。

## 恢复演练步骤（每次开放同步前或季度至少一次）

1. **准备空库**（隔离实例或临时库名，**不要**直接覆盖生产）  
   `CREATE DATABASE zhouji_restore CHARACTER SET utf8mb4;`
2. **导入最近备份**  
   `gunzip -c /var/backups/zhouji/zhouji-YYYYmmdd-HHMMSS.sql.gz | mysql -u root zhouji_restore`
3. **校验**  
   - 表存在：`auth_accounts` / `auth_sessions` / `auth_challenges`  
   - `SELECT COUNT(*)` 与备份前记录的行数一致  
   - `SHOW CREATE TABLE auth_accounts` 含 provider 约束（003 之后）
4. **密钥可用性**  
   确认 `token-encryption-key` 与备份同期；用隔离测试账户验证能完成一次 `GET /account` 刷新（勿用生产用户做破坏性操作）。
5. **记录**  
   在运维笔记写明：备份文件名、时间、导入耗时、行数、演练人、是否成功。

失败时：停止演练，保留现场，不删除原备份。

## 回滚与数据保留

- 应用版本回退 **不** 自动删库。  
- 恢复生产库仅在确认备份完整且业务窗口允许时由管理员执行。  
- 云同步上线后，用户内容表纳入同一 mysqldump；注销删除路径的备份窗口策略在同步 PRD 阶段 E 再补。

## 验收

- [ ] 脚本在服务器可执行且产出 `600` 权限 `.sql.gz`
- [ ] 完成一次向隔离库的恢复演练并有行数记录
- [ ] 加密密钥与数据库备份同批存放且可读
- [ ] 告警探针 `health-probe.sh` 可被 cron/systemd timer 调用
