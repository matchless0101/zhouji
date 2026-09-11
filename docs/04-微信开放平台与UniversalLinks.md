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

微信 AppID 已提供，AppSecret 和微信登录权限状态待确认，项目尚未接入微信 OpenSDK。这里只完成官网与 iOS 的域名关联准备，不表示微信登录已经实现。后端已确定使用 Python + FastAPI + MySQL，基础服务见 `server/`；Apple 私钥配置按用户要求暂缓。

## iOS 工程

- `ios/project.yml` 设置 `DEVELOPMENT_TEAM` 与应用的 `CODE_SIGN_ENTITLEMENTS`，Xcode 工程已通过 XcodeGen 同步。
- `ios/ZhouJi/ZhouJi.entitlements` 声明 `applinks:zhouji.xiangdangdang.top`。
- App 的 Bundle ID 未改变，不影响既有本地数据标识。
- 没有新增 SDK、账户入口、授权请求或登录后端，也没有变更现有任务与计时行为。

真机签名时，需要在对应 Apple 开发团队下注册/使用此 Bundle ID，并启用 Associated Domains，签名描述文件必须包含该权限。最终应核对真机签名 App 的 `application-identifier` 与上述 AASA 标识一致；历史 App 的 App ID Prefix 可能与 Team ID 不同。本次未访问 Apple 开发者后台、未修改其 App ID 或签名描述文件。

## 官网关联

源文件：`website/dist/.well-known/apple-app-site-association`。

公开访问地址均返回相同 JSON，不重定向：

- <https://zhouji.xiangdangdang.top/.well-known/apple-app-site-association>
- <https://zhouji.xiangdangdang.top/apple-app-site-association>

仅将 `/wechat/*` 交给 App；官网首页与其他页面不在关联路径范围内。`website/dist/wechat/index.html` 为未唤起 App 时的网页落地页，不模拟微信授权成功，也不读取或保存回调参数。

Nginx 为两个 AASA 地址设置精确匹配和 `application/json` 类型，其余隐藏路径继续禁止访问。后续发布必须包含 `dist/.well-known/`，不能只上传非隐藏文件。

## 验证与后续接入

已完成：8 项静态/交互/关联配置检查；iOS 通用模拟器无签名构建；线上两个 AASA 地址返回匹配本地的 JSON、无跳转；`/wechat/` 返回 200；Apple 的 AASA CDN 返回 200，内容与部署文件一致。

尚未完成：真机签名、安装后由系统唤起 App，以及微信授权回调。模拟器无签名构建不能代替上述验证。

拿到微信 AppID 后，再按微信官方 SDK 指南接入注册和回调处理；SDK 注册时的 Universal Link 必须与平台填写值一致。真机验收应使用正确签名的新安装版本，从备忘录等外部入口点击上述链接，并检查微信发起与返回流程。

参考：[Apple Universal Links](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/UniversalLinks.html)、[微信 iOS 接入指南](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Access_Guide/iOS.html)。
