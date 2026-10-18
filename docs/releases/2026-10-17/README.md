# App Store 1.0（构建 4）上传记录

用户在用户名认证服务部署完成后明确要求上传新构建。本次已上传 `com.matchless.ZhouJi` 版本 `1.0`、构建号 `4`，App Store Connect 的 TestFlight 构建上传列表显示 `1.0 (4)`「正在处理」，创建时间为 2026-10-17 23:41（本机 America/New_York）。没有提交 App 审核。

## 内容与范围

- 应用功能基线 `7f6e1fd`，包含用户名／密码注册登录、恢复码找回、密码修改、恢复码轮换和可选微信绑定；原 Apple、微信快捷登录及游客本机记录保留。
- 发布前代码提交为 `f4f1c69`，已记录正式后端与隐私页部署验证。本次应用仅把 XcodeGen 的构建号从 3 更新为 4，并重新生成工程；版本号仍为 1.0。
- 微信配置沿用忽略的本机 `Local.xcconfig`。签名、团队、应用 ID 与权限沿用既有配置；未提交配置凭据或密钥。
- 本次只上传构建，没有替换审核版本关联、更新审核备注、完成新构建出口合规问卷、分配测试群组或重新送审。Apple 处理完成和真机验收需分别确认，不能将成功上传等同于审核通过。

## 实际验证

- 正式 iOS Release 签名归档成功，`xcodebuild archive` 返回 0。
- 核对归档中的应用 ID、1.0（4）、浅色外观、微信配置，以及实际签名中的 Apple 登录和本站关联域名权限。描述文件给关联域名通配授权；应用实际权限仅包含 `applinks:zhouji.xiangdangdang.top`，两者不能直接按相同数组比较。
- 严格签名验证通过；Release 可执行文件不含本轮 Debug 认证替身启动参数。
- `xcodebuild -exportArchive` 返回 0，日志包含 `Upload succeeded`、`Uploaded ZhouJi` 和 `EXPORT SUCCEEDED`；随后通过 Safari 核实 TestFlight 的新构建行及「正在处理」状态。
- 构建号更新后的 Release 通用模拟器构建成功。本次未修改应用行为，未重复运行单元或界面测试；前一功能迭代的验证范围见 [用户名账户交付与验证](username-auth-validation.md)。未将模拟器或归档验证称作新包的真机联网验证。

## 本机产物

- 归档：`/private/tmp/ZhouJi-1.0-4-20261017.xcarchive`。
- 归档日志：`/private/tmp/zhouji-release4-archive.log`。
- 上传日志：`/private/tmp/zhouji-release4-upload.log`。
- 模拟器构建日志：`/private/tmp/zhouji-release4-simulator.log`。
- 上传选项：`/private/tmp/zhouji-release4-ExportOptions.plist`；使用 App Store Connect、自动签名，禁止上传工具自动改写构建号。

后台入口：[TestFlight](https://appstoreconnect.apple.com/teams/b1cc1463-2b72-4472-bdaa-c3e5d476d80e/apps/6814795775/testflight/ios)。
