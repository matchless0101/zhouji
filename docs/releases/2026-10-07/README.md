# App Store 1.0（构建 3）

2026-10-07 将最新版上传到 App Store Connect，并关联到 iOS 版本 1.0。用户确认后，于北京时间 22:39 正式提交 `1.0 (3)`，后台已显示「已提交 1 个项目」及版本状态「正在等待审核」。

审核提交：[App Store Connect 审核详情](https://appstoreconnect.apple.com/apps/6814795775/distribution/reviewsubmissions/details/5b1ca6a5-f3d3-4336-91a8-2a2aeb0fef51)。

## 安装包

- 应用：`com.matchless.ZhouJi`，版本 `1.0`，构建号 `3`。
- 应用代码基线：`78186e4`；本轮仅将 XcodeGen 构建号从 2 更新为 3 并重新生成工程。
- 包含构建 2 后的任务完成动效及布局修复、账户授权撤销与后台刷新修复，以及仅首次启动展示的「翻开今天」动画。
- 微信配置沿用本机忽略的 `Local.xcconfig`，未将配置内容或签名凭据写入仓库。

## 审核配置

- 构建 3 已完成 Apple 处理和出口合规问卷，声明与构建 2 相同；缺少出口合规证明提示已消除。
- 版本关联已替换为构建 3，刷新页面后再次确认保存成功。
- 审核备注中的注销入口已更新为「我的 → 偏好设置 → 底部『注销账户』（登录后可见）」。
- 原有今天、目标、日历、我的四张商店截图仍在素材视图中；此次沿用既有截图。
- 发布方式保持「审核通过后自动发布」。
- 未修改价格、销售地区和隐私收集声明。

移除旧版本关联不会删除账户中的已上传构建，操作依据：[Apple 选择审核构建说明](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit)。

## 验证

- 正式设备 Release 归档成功，签名完成；归档中的应用 ID、版本、构建号均已核对。
- 上传成功，`xcodebuild -exportArchive` 返回 0；后台已处理为可选构建。
- 构建号更新后的模拟器构建成功，返回 0。
- 本轮未修改应用行为，未重复运行单元或界面测试。应用代码基线在本日已通过 111 项单元测试及 3 条相关界面测试，这不代表完整界面回归或实机联网登录验证。

本机归档：`/private/tmp/ZhouJi-1.0-3-20261007.xcarchive`。

日志：

- `/private/tmp/zhouji-release-archive-20261007.log`
- `/private/tmp/zhouji-release-upload-20261007.log`
- `/private/tmp/zhouji-release-simulator-20261007.log`
