# 微信开放平台与 Universal Links

## 平台填写信息

| 字段 | 当前值 |
| --- | --- |
| 开发 iPhone 应用 | 是 |
| Bundle ID | `com.matchless.ZhouJi`，保持大小写 |
| 测试版本 Bundle ID | 当前 Debug 与 Release 使用同一个 App Bundle ID；未定义独立测试 App。测试组件 `com.matchless.ZhouJiTests` 和 `com.matchless.ZhouJiUITests` 不用于该字段 |
| Universal Links | `https://zhouji.xiangdangdang.top/wechat/`，保留末尾 `/` |
| Apple Team ID | `7V46ZF4WY4`，由用户提供 |
| 微信 AppID | `仅在未跟踪的配置文件中保存`，用户于 2026-09-11 提供 |
| AASA application identifier | `7V46ZF4WY4.com.matchless.ZhouJi`，这不是微信 AppID |

微信 AppID 与 AppSecret 已私下保存；微信开放平台登录权限状态以平台侧为准。iOS 已接入官方 OpenSDK（Vendor 目录本地安装，不入库），服务端提供 challenge 与换码接口。真机微信授权、Universal Link 唤起与开放平台权限仍待人工验收，完成前不将微信登录表述为已上线能力。后端见 `server/`；Apple 专用密钥已在开发者平台创建并部署到服务器，内容及实际 Key ID 不进入 Git。

## iOS 工程

- `ios/project.yml` 设置 `DEVELOPMENT_TEAM` 与应用的 `CODE_SIGN_ENTITLEMENTS`，Xcode 工程已通过 XcodeGen 同步。
- `ios/ZhouJi/ZhouJi.entitlements` 声明 `applinks:zhouji.xiangdangdang.top`。
- App 的 Bundle ID 未改变，不影响既有本地数据标识。
- Apple 登录已接入原生 AuthenticationServices 与专用后端。
- 微信登录已接入官方 OpenSDK：`ios/scripts/setup-wechat-sdk.sh` 安装 `Vendor/WechatOpenSDK-NoPay.xcframework`（已 gitignore）；AppID 写入 `ios/Config/Local.xcconfig`（已 gitignore）；URL Scheme 与 Universal Link 回调见 `ZhouJiApp` 与 `WeChatLogin`。
- 任务与计时仍在本机，登录成功不等于云同步完成。

真机签名时，需要在对应 Apple 开发团队下注册/使用此 Bundle ID，并启用 Associated Domains，签名描述文件必须包含该权限。最终应核对真机签名 App 的 `application-identifier` 与上述 AASA 标识一致；历史 App 的 App ID Prefix 可能与 Team ID 不同。2026-09-12 已在开发者平台为粥记注册 App ID，启用 Associated Domains 与 Sign in with Apple，并完成带权限的真机签名构建与安装。

## 官网关联

源文件：`website/dist/.well-known/apple-app-site-association`。

公开访问地址均返回相同 JSON，不重定向：

- <https://zhouji.xiangdangdang.top/.well-known/apple-app-site-association>
- <https://zhouji.xiangdangdang.top/apple-app-site-association>

仅将 `/wechat/*` 交给 App；官网首页与其他页面不在关联路径范围内。`website/dist/wechat/index.html` 为未唤起 App 时的网页落地页，不模拟微信授权成功，也不读取或保存回调参数。

Nginx 为两个 AASA 地址设置精确匹配和 `application/json` 类型，其余隐藏路径继续禁止访问。后续发布必须包含 `dist/.well-known/`，不能只上传非隐藏文件。

## 验证与后续接入

已完成：8 项静态/交互/关联配置检查；iOS 通用模拟器无签名构建；线上两个 AASA 地址返回匹配本地的 JSON、无跳转；`/wechat/` 返回 200；Apple 的 AASA CDN 返回 200，内容与部署文件一致。

尚未完成：安装后通过 Universal Link 由系统唤起 App，以及微信授权回调。模拟器无签名构建不能代替上述验证。

微信 OpenSDK 注册与回调已在代码中实现；SDK 注册时的 Universal Link 必须与平台填写值一致。真机验收应使用正确签名的新安装版本，从备忘录等外部入口点击上述链接，并检查微信发起与返回流程；同时确认开放平台登录权限已开通。

参考：[Apple Universal Links](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/UniversalLinks.html)、[微信 iOS 接入指南](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Access_Guide/iOS.html)。
