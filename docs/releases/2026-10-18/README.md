# 原微信账户补设密码部署及 App Store 1.0（5）上传

用户在功能完成后授权继续。2026-10-18 已发布后端与隐私页，上传构建 5 并完成出口合规；未关联审核版本、修改审核备注、分配测试群组或重新送审。

## 生产部署

- 代码 `f9cf3af2d2565089560d8bad7cf8d7c58918319e`；发布包 SHA-256：`e302b856693ee184122c2db5080dd2be071c1b7e13fdf16d954d38c216bbee72`。发布源码与服务器隔离测试所用 src、tests、migrations 逐文件一致；此前完整后端测试 112 项通过。
- 完整备份：`/var/backups/zhouji/zhouji-20261019-000728.sql.gz` 及同名前缀 `.bundle.tar.gz`。备份名为服务器 UTC+8 时间；两个文件非空、权限 600、gzip 完整性通过，包含匹配配置和密钥，不复制到公开仓库。
- 2026-10-18 16:07:30 UTC 激活。停止专用 API 后只执行一次 007；七张表数量、原账户 ID／创建来源及会话旧字段摘要前后一致。新检查约束、原外键、唯一索引核对通过。实测服务中断约 1.41 秒，不作为未来时长保证。
- API 当前 `/opt/zhouji-api/releases/wechat-password-20261018-01`；原 `username-auth-20261017-01` 保留。复用原虚拟环境，没有改变依赖、密钥、Nginx 或云同步开关。
- 网站当前 `/var/www/zhouji-site/releases/20261018-wechat-password`。从上一线上版本复制，仅替换隐私页；其余 8 文件摘要保持一致。政策公网 SHA-256：`e063f88cf4bd7903feca60ad25a0e1a592372642b6c9d7f068c97453f1521190`。
- 正式 HTTPS 20 项检查通过：鉴权、近期登录限制、首次设置、旧会话撤销、原账户密码登录、资料保持、重复设置拒绝、恢复码重置、旧恢复码拒绝、解绑、退出、解绑后密码登录及注销。使用运行时随机生成的临时合成微信身份，没有请求真实微信授权；验证结束核对六张账户关联表无残留，原真实账户身份摘要一致。
- 首轮验证脚本误以为密码会话解绑也会返回替换 token，在清理临时账户后修正脚本，完整重跑 20 项通过；应用接口无需修改。
- live/ready、官网、微信落地页和两个 AASA 路径正常；API 与备份、清理、运维检查三个 timer 均 active。私有审计目录：`/var/backups/zhouji/deploy-wechat-password-f9cf3af`，最终 activation.json 为 verified。
- 回退仅将 API current 指回上一 release 并重启，网站可独立指回 `20261017-username-auth`；保留 007 及用户新设凭据。不要恢复旧数据库覆盖上线后的用户数据，不删除所复用的旧虚拟环境。

## 构建 5

- 仅把 `ios/project.yml` 构建号从 4 更新为 5，并重新生成工程；应用版本仍为 1.0，签名、团队和应用标识沿用现有配置。
- 构建号更新后的 Release 通用模拟器构建通过。本轮应用行为无新增修改，未重复前一轮 129 项单元和 3 项认证界面测试；实际部署另经上述正式 HTTPS 检查验证。
- 正式签名归档成功，严格签名校验通过。受限环境的信任校验不可用，正常钥匙串环境重试成功。核对 `com.matchless.ZhouJi`、1.0（5）、浅色外观、Apple 登录及本站关联域名权限；二进制不含新增认证测试启动参数、替身类型或预置会话。
- `xcodebuild -exportArchive` 返回 0，日志显示 `Upload succeeded`、`Uploaded ZhouJi`、`EXPORT SUCCEEDED`。Safari 的 TestFlight 构建列表确认构建 5 已完成处理。
- 出口合规按当前应用实际使用及前次申报选择「不属于上述的任意一种算法」，保存刷新后构建 5 显示「准备提交」，缺项提示消失。客户端沿用系统 HTTPS、钥匙串及 SHA-256；微信 NoPay 框架未发现所检查的独立加密实现符号；新增 scrypt 摘要和恢复码摘要在后端，不在 App 二进制。依据：[Apple 加密出口说明](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)。
- 归档 `/private/tmp/ZhouJi-1.0-5-20261018.xcarchive`；归档、上传和模拟器日志分别为 `/private/tmp/zhouji-release5-archive.log`、`/private/tmp/zhouji-release5-upload.log`、`/private/tmp/zhouji-release5-simulator.log`。

本次自动化和线上接口验证不代表新版真机微信授权或软键盘验收。审核版本此前仍关联旧构建，旧备注描述无用户名密码，需要在再次送审前更新；构建上传和 TestFlight「准备提交」不等于 App 已进入审核。
