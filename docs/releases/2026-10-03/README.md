# App Store 1.0（构建 2）素材与出口合规

2026-10-03 完成 App Store Connect 配置，未提交苹果审核。

## 出口合规

构建 2 已保存加密问卷，选择“不属于上述的任意一种算法”。版本页刷新后，加密状态显示“否”，缺少出口合规信息提示已消除。

核对范围：系统 URLSession HTTPS、Security 钥匙串、CryptoKit SHA256 和登录随机数；微信 NoPay 静态框架未发现所检查的独立加密实现符号。服务器端加密不属于应用二进制。此次未修改应用源码、发布配置或重新上传构建。

参考：[Apple 加密出口规范](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)。

## 商店截图

四张截图已上传到简体中文、iPhone 6.5 英寸截图栏，后台显示 4/10。使用当前应用实际界面和独立模拟器示例数据，未使用用户个人数据；原始 PNG 未裁剪或缩放。

| 顺序 | 页面 | 文件 |
| --- | --- | --- |
| 1 | 今天 | [01-today.png](screenshots/01-today.png) |
| 2 | 目标 | [02-goals.png](screenshots/02-goals.png) |
| 3 | 日历 | [03-calendar.png](screenshots/03-calendar.png) |
| 4 | 我的（游客模式） | [04-profile.png](screenshots/04-profile.png) |

尺寸均为 1284 × 2778，来自 iPhone 14 Plus / iOS 26.5 模拟器。截图源码基线为 eb1637f，最新应用代码与已上传构建 2 一致。

## 验证

既有界面测试 `testReferenceAppearanceAndNavigation` 通过：1 项测试、0 失败。覆盖四个主页面导航和相关任务操作，未进行完整回归或联网登录验证。

本机测试结果：`/private/tmp/zhouji-store-screenshots-20261003.xcresult`；日志：`/private/tmp/zhouji-store-screenshots-20261003.log`。

中国大陆备案事项仍需另外确定；此次未填写备案号、未修改销售地区。审核版本保持“准备提交”。
