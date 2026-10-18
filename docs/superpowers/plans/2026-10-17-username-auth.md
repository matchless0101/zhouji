# 用户名登录与微信可选绑定 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 交付用户名密码注册登录、恢复码找回密码和可选微信绑定，保留原账户及本机记录。

**Architecture:** 扩展现有 FastAPI 账户、会话与微信身份列，新增密码认证模块及持久限流。会话认证方式与账户创建类型分离，绑定不改变账户 ID。iOS 复用 AccountStore、钥匙串和本机分库，新增沿用现有纸张风格的认证、安全设置与恢复码页面。

**Tech Stack:** Swift 6、SwiftUI、SwiftData、iOS 17+；Python 3.12、FastAPI、SQLAlchemy、MySQL 8；现有微信 OpenSDK 与 AuthenticationServices；不新增依赖。

**Spec:** [用户名密码与恢复码完整设计](../specs/2026-10-17-username-auth-design.md)，含本轮用户确认的可选微信绑定增量。

## Global Constraints

- 用户名 4–32 位，只允许英文字母、数字、下划线；去除首尾空白并转小写作为唯一登录键。
- 密码 15–128 个 Unicode 标量，不裁剪、不静默截断；`scrypt N=2^17,r=8,p=1`，盐至少 16 字节、输出 32 字节。
- 恢复码 20 个随机字节、32 位大写 Base32、8 组各 4 位；数据库仅保存带用途前缀的 SHA-256 摘要。
- 恢复码一次重置后轮换；重置密码撤销全部会话，改密撤销旧会话并给当前设备替换会话。
- 用户名账户支持可选绑定／解绑微信；已有独立账户不合并、不迁移任务，不增加 Apple 绑定。
- 账号、Apple、微信和游客入口均非强制；未安装微信提示“当前设备未安装微信，可使用账号或 Apple 登录。”。
- 不启用云同步，不修改 App 版本号、签名和发布配置，不添加邮件、短信或其他第三方依赖。
- 密码、恢复码、私钥和会话不进入日志、文档、Git 或 UI 截图；测试只使用隔离数据。
- 保留工作区已有改动；按 AGENTS.md，仅完成并验证后提交、推送当前跟踪分支，不在任务中间额外提交文档或失败功能。

## Review Focus

- 注册／重置已经在服务器成功，但客户端响应丢失：可用新密码登录、重新生成恢复码，不恢复旧码；任务 3、6、8 验证。
- 微信绑定的用户名账户通过微信登录，解绑或平台授权失效：用户名方式仍可用，同一账户库保持不变；任务 4、6、9 验证。
- 微信回调在退出、改密、解绑或注销后迟到：专用 challenge 和会话失效，不能把微信重新绑回；任务 4、5 验证。
- 同一微信并发绑定两个账户、旧密码登录与改密并发：数据库唯一键、行锁及二次核对保证身份唯一，旧凭据不能生成有效会话；任务 3、4、5 验证。
- 旧钥匙串缺少新增字段、UI 键盘弹出和返回：旧缓存可读，输入不缩小、插画不被上顶、不会登录到错误记录库；任务 6、8、9 验证。

## 文件职责与实施顺序

1. 数据层：`server/migrations/006_password_auth.sql`、`server/src/zhouji_api/models.py`。
2. 认证原语：新增 `passwords.py`、`auth_limits.py`；分别负责校验／摘要与数据库限流。
3. 会话共用边界：新增 `account_sessions.py`，集中认证、事务内签发和账户响应；原 `auth.py` 接入，不重写同步模块。
4. 密码路由：新增 `password_auth.py`，负责注册、登录、找回、改密与恢复码轮换；`app.py` 注册路由。
5. 微信绑定：新增 `wechat_binding.py`；`auth.py` 普通微信登录复用同一身份映射，区分登录与绑定用途。
6. iOS 协议／状态：`AccountAPI.swift`、新增 `PasswordCredentials.swift`、`AccountStore.swift` 及同模块扩展；更新全部测试／预览适配器。
7. iOS 页面：新增 `Features/Profile/Authentication/{PasswordLoginView,PasswordRegistrationView,PasswordRecoveryView,RecoveryCodeView,AccountSecurityView}.swift`；复用现有主题。
8. 测试、产品说明与交付记录：逐任务维护；最后统一构建、提交，不夹带原工作区未跟踪素材。

## 执行前准备

- [x] 审阅本计划并确定执行方式；执行时读取对应技能，检查 `git status`、跟踪分支和现有工作树附件，再按隔离工作要求选择工作目录，避免覆盖原工作区内容。
- [x] 在执行目录读取 AGENTS.md、完整设计和相关文件；确认 `server/.venv/bin/python`、XcodeGen、Xcode 与微信 SDK 可用。缺少工具先报告环境事实，不调整项目依赖或发布配置。
- [x] 记录后端现有测试基线及 iOS 模拟器可用目标。命令均从执行目录运行；测试数据库使用独立 `zhouji_verify_*`，绝不对生产账户运行自动化测试。

### Task 1: 数据模型和旧会话迁移

**Files:** 新建 `server/migrations/006_password_auth.sql`、`server/tests/test_password_schema.py`；修改 `models.py` 和 `app.py` 就绪检查。

**Interfaces:** `password_credentials` 表包括 `account_id,username,password_hash,recovery_hash,updated_at`；`auth_attempts` 表包括 `key_hash,window_start,count,blocked_until,expires_at`；`sessions.auth_method` 为非空字符串；challenge 增加 `purpose,account_id,session_token_hash`，默认用途 `login`，关联账户／会话可为空。

- [x] 写失败测试 `test_existing_accounts_and_sessions_survive_migration`：原 Apple／微信 ID、token 摘要、资料不变，旧会话 `auth_method` 与原 provider 一致。
- [x] 写 `test_password_account_with_optional_wechat_constraint`：允许密码账户微信两列同时为空或非空，拒绝半份凭据、Apple 身份及重复微信 subject；注销级联删除密码凭据。
- [x] 运行 `server/.venv/bin/python -m pytest server/tests/test_password_schema.py -q`，确认缺少新表／列导致失败。
- [x] 实现 SQLAlchemy 表和 006。迁移先回填旧会话再设非空，替换旧 provider CHECK，保留历史列和唯一键。普通 challenge 的默认值保证旧调用兼容。
- [x] 重跑结构测试并跑 `server/.venv/bin/python -m pytest server/tests/test_auth.py server/tests/test_wechat.py server/tests/test_service.py -q`。SQLite 验证模型；真实 ALTER 在任务 5 验证。

### Task 2: 密码、恢复码和限流原语

**Files:** 新建 `server/src/zhouji_api/{passwords,auth_limits}.py`、`server/tests/test_password_primitives.py`。

**Interfaces:** `normalize_username(value: str) -> str`、`validate_password(value: str) -> str`、`hash_password(value: str) -> str`、`verify_password(value: str, encoded: str) -> bool`、`new_recovery_code() -> str`、`recovery_digest(value: str) -> str`。`AuthLimits(database, clock=time.time)` 提供 `check(scope: str, key: str) -> None`、`failure(scope: str, key: str) -> None`、`success(scope: str, key: str) -> None`，错误为 429 并含 Retry-After。

- [x] 写校验断言：`normalize_username(' Alice_1 ') == 'alice_1'`；3／33 位、中文用户名拒绝；15／128 标量密码接受，14／129 拒绝；密码空格不被裁剪。
- [x] 写摘要测试：相同密码摘要因盐不同而不同、正确密码成功、错误密码失败；恢复码去掉短横线后长 32、小写可验证、无效字符拒绝，数据库摘要不含原始码。
- [x] 写持久限流测试：第 5 次错误后同用户名验证被限制 15 分钟，重新创建服务对象不解除，到期可用；密码和恢复码使用不同 scope。来源登录／恢复最多 20 次／分钟；注册每来源 5 次／小时、20 次／天；成功只清除对应用户名错误窗口，不清除来源额度。
- [x] 运行 `server/.venv/bin/python -m pytest server/tests/test_password_primitives.py -q`，确认失败后实现。哈希工作并发上限 2，满额返回可重试错误；固定参数解析不允许数据库摘要随意指定超大工作量。限流计数必须在独立提交事务内保存，不能随认证失败异常回滚。
- [x] 重跑测试并记录单次真实参数哈希耗时与内存；以测试可注入哈希器提高组合测试速度，但至少保留真实 scrypt 正确性测试，生产不可启用低成本测试参数。

### Task 3: 会话边界和用户名认证接口

**Files:** 新建 `server/src/zhouji_api/{account_sessions,password_auth}.py`、`server/tests/test_password_auth.py`；修改 `auth.py`、`app.py`。

**Interfaces:** `AccountSessions(database)`：`authenticate(authorization: str | None) -> tuple[Mapping, Mapping]`、`issue_locked(conn, account_id: str, auth_method: str) -> dict`、`public_account(conn, account, auth_method: str) -> dict`。密码路由工厂 `password_router(database, session_service: AccountSessions, limits: AuthLimits) -> APIRouter`。新失败响应用 `detail={code,message}`；保留原接口的字符串 detail 兼容。

线格式固定：注册请求 `{username,password}`，返回 `{session:{token,expires_at,account},recovery_code}`；登录请求 `{username,password}`，返回原会话格式 `{token,expires_at,account}`；恢复请求 `{username,recovery_code,new_password}`，返回 `{username,recovery_code}`；改密请求 `{password,new_password}`，返回原会话格式；轮换请求 `{password}`，返回 `{session:{token,expires_at,account},recovery_code}`。确认密码仅在客户端比较，不发送冗余字段。所有用户名、密码及恢复码输入在服务端仍完整校验。

- [x] 写 `test_register_login_profile_logout_delete`：注册返回 session 内的原格式 token、账户及外层恢复码；用户名大小写归一，默认资料正确；再次登录同 ID，重复注册 409；密码资料不进入普通账户响应。
- [x] 写 `test_recovery_consumes_code_and_revokes_all_sessions`、`test_change_and_rotate_issue_replacement_session`：重置后旧密码／旧码／所有旧会话失败；新密码／新码可用；改密保留恢复码、轮换保留密码；现用新会话保持同 ID。
- [x] 写 `test_lost_response_does_not_reactivate_old_recovery` 和 `test_errors_never_echo_secrets`：丢弃成功响应后，使用新密码登录再轮换；错误 body、校验异常与 SQL 错误不含提交的密码／恢复码。
- [x] 运行 `server/.venv/bin/python -m pytest server/tests/test_password_auth.py -q`，确认失败后实现设计中的五个密码端点和公共会话边界。输入模型 `extra='forbid'`，密码字段不在 repr 显示；无效凭据 401/code=`invalid_credentials`，恢复失败 `invalid_recovery`，重名 409/`username_taken`，输入错误 422/`invalid_input`。
- [x] 昂贵哈希在事务外执行，取得账户锁后重查密码摘要／恢复摘要是否仍为已验证版本，再修改或发会话；已注销账户不能被旧请求重建。注册唯一冲突仅转换成重名，其他数据库异常沿用 503。密码方法不调用外部授权验证。
- [x] 重跑任务 1–3 及原 auth／wechat 测试。旧会话读取、资料更新、退出、注销与同步认证改用共用服务；不改变同步事实协议。

### Task 4: 微信绑定、解绑与平台会话隔离

**Files:** 新建 `server/src/zhouji_api/wechat_binding.py`、`server/tests/test_wechat_binding.py`；修改 `auth.py`、`account_sessions.py`、`app.py`。

**Interfaces:** `wechat_binding_router(database, session_service, wechat_provider, limits) -> APIRouter`。challenge 请求 `{password}`；绑定请求 `{challenge,code}`；解绑请求 `{password}`。返回 `{account}`，当前微信会话解绑时另返回 `{session}`，其中 session 遵循原 token 格式。密码账户能力来自凭据表，不由当前 provider 推断。

- [x] 写 `test_bind_then_wechat_login_same_account`：绑定不创建第二账户；之后微信登录的 account.id 与原用户名账户一致，provider=`wechat`、has_password=true；密码登录 provider=`password`。
- [x] 写 `test_binding_rejects_foreign_session_login_challenge_and_used_identity`：另一会话／另一账户／普通登录 challenge 均拒绝；微信已在其他账户时 409/`wechat_in_use`，两个账户、资料和原 subject 不变；重复绑定当前 subject 幂等。
- [x] 写 `test_late_binding_after_logout_password_change_or_delete_fails`：换码阻塞时退出／改密／注销，释放换码后绑定失败，不能复活关联或账户。不同微信替换已有绑定返回 409/`wechat_already_bound`。
- [x] 写 `test_unbind_and_revocation_preserve_password_sessions`：微信会话撤销，密码会话仍有效；当前微信会话解绑取得密码替换会话；授权失效不清除用户名账户、凭据和记录，密码恢复后绑定仍在。
- [x] 运行对应失败测试后实现。绑定前校验当前密码；换码后在短事务内按账户锁重新认证会话、消费专用 challenge、检查 subject 唯一性；失败不新建账户。注销清理关联 challenge，改密／恢复／退出后旧会话绑定请求不可用。
- [x] 微信日常刷新按 session.auth_method 和当前 credential 快照验证，提交时核对凭据仍相同；失效只删微信会话。绑定／解绑不调用微信不存在的 revoke。运行 `server/.venv/bin/python -m pytest server/tests/test_wechat_binding.py server/tests/test_wechat.py server/tests/test_auth.py -q`。

### Task 5: MySQL 迁移、竞争与全后端验证

**Files:** 新建 `server/tests/test_mysql_auth.py`；提取现有 `test_mysql_sync.py` 的隔离数据库 fixture 到 `server/tests/conftest.py`，两个测试模块共享；不更改生产配置。

**Interfaces:** `isolated_mysql` 继续从显式 `ZHOUJI_TEST_MYSQL_CONFIG` 读受限配置，创建随机命名测试库、执行 001–006，结束只删除自身库。未配置时明确 skip，不将 skip 报告为通过。

- [x] 写 `test_mysql_migration_preserves_legacy_sessions`：执行 001–005、写入隔离旧账号会话、再执行 006，验证字段回填与旧接口可用；独立检查整套迁移新装成功。
- [x] 写并发断言：两请求使用同恢复码恰好一次成功；同微信绑两账户恰好一次成功；改密与旧密码签发竞争后不存在有效旧凭据会话；注销与绑定竞争后不存在悬空关联。
- [x] 在隔离 MySQL 运行 `server/.venv/bin/python -m pytest server/tests/test_mysql_auth.py server/tests/test_mysql_sync.py -q`；记录真实 PASS 或缺配置的 SKIP。锁等待或唯一冲突需成为可预测业务错误，不返回原始 SQL。
- [x] 运行 `server/.venv/bin/python -m pytest server/tests -q`，修复失败；检查真实参数并发哈希不会耗尽服务器预算。生产尚未部署时明确记录。

### Task 6: iOS API、校验与 AccountStore 状态

**Files:** 修改 `AccountAPI.swift`、`AccountStore.swift`、`WeChatLogin.swift`；新建 `Core/Authentication/{PasswordCredentials,AccountStore+Password,AccountStore+WeChatBinding}.swift`、`ZhouJiTests/PasswordAuthenticationTests.swift`；更新现有 AccountServing 适配器，包括 `App/ZhouJiApp.swift` DEBUG 预览适配器和 `AccountStoreTests.swift`。

**Interfaces:** `AppAccount` 增加可兼容旧 JSON 的 `hasPassword: Bool`、`weChatBound: Bool`、`username: String?`；用显式解码对旧数据回退 false／nil。`PasswordCredentials` 提供与后端一致的用户名、密码及恢复码校验。`RecoveryMaterial` 是内存中的 Sendable 结构，含 username/code；不加入 Codable 持久会话。

`AccountServing` 新增 `registerPassword(username:password:) -> PasswordRegistration`、`loginPassword(username:password:) -> AccountSession`、`recoverPassword(username:recoveryCode:newPassword:) -> RecoveryMaterial`、`changePassword(token:password:newPassword:) -> AccountSession`、`rotateRecoveryCode(token:password:) -> RecoveryRotation`、`weChatBindingChallenge(token:password:) -> LoginChallenge`、`bindWeChat(token:challenge:code:) -> AppAccount`、`unbindWeChat(token:password:) -> BindingResult`，全部 async throws。`PasswordRegistration`／`RecoveryRotation` 携带 session 和 recoveryCode；`BindingResult` 携带 account 和可选替换 session。

- [x] 写 `test_old_keychain_decodes_new_capabilities`，旧 JSON 无新增字段仍恢复；provider 未知不显示 Apple 名称／图标。写前后端用户名、Unicode 密码边界共享样例测试。
- [x] 写 `test_register_login_and_recovery_lost_response`：注册写钥匙串失败撤销新会话并保留“账户可能已创建”提示；恢复接口错误凭据不清掉其他已登录会话；恢复码不进入钥匙串。
- [x] 写 `test_same_account_binding_and_replacement_without_library_switch`：绑定前后库实例／账户 ID 相同；微信当前会话解绑后保存替换会话，保存失败停止旧会话、不删除库。
- [x] 写 `test_stale_login_binding_or_refresh_cannot_restore_old_session`，沿用可控 continuation 重现后台刷新、退出、取消与迟到响应；Apple 撤销不误伤 password／wechat 当前会话。
- [x] 运行目标测试确认失败；实现 API 类型及状态扩展。对新增端点先解析稳定 code，再区分 401 登录失败与现有会话失效；不把所有 401 都当作退出。状态修订和 persistLogin／替换会话共用能力只调整必要访问级别，不对 UI 暴露凭据。
- [x] 新增源码后运行 `cd ios && xcodegen generate`；在已确认模拟器目标运行 `xcodebuild -project ios/ZhouJi.xcodeproj -scheme ZhouJi -destination '<已记录的模拟器目标>' -only-testing:ZhouJiTests/PasswordAuthenticationTests -only-testing:ZhouJiTests/AccountStoreTests CODE_SIGNING_ALLOWED=NO test`。参数占位符在执行前准备中用实际设备 ID 替换并记录，不猜测机型。

### Task 7: 微信入口可用性与独立提示

**Files:** 修改 `WeChatLogin.swift`、`AccountStore.swift`、`Features/Profile/AccountControls.swift`；修改 `ZhouJiTests/WeChatLoginTests.swift`、新增相应 API／状态测试。

**Interfaces:** `WeChatAvailability: Equatable { case available, notInstalled, unsupported, notConfigured }`；`WeChatAuthorizing.availability`、`AccountStore.weChatAvailability`；前台激活时刷新。可用性查询不注册或拉起微信，真正授权仍沿用现有 SDK 边界。

- [x] 用 SDK 替身写测试：未安装不发授权／绑定请求、无下载跳转；已安装且版本支持显示微信入口；返回前台从 available 变 notInstalled 后 UI 状态刷新。
- [x] 修改入口与两段文案：登录“当前设备未安装微信，可使用账号或 Apple 登录。”；绑定“当前设备未安装微信，暂时无法绑定；账号密码登录不受影响。”。未配置／不支持不得误称未安装，分别提示暂不可用并保留其他入口。
- [x] 删除“请先安装或更新微信”的要求性反馈；发起瞬间变化、超时和取消仍有准确重试提示。保留既有 state、五分钟时限、回前台等待与后台切换行为。
- [x] 运行 WeChatLoginTests 与认证状态测试，确保未安装路径、已安装授权回调、取消／超时均覆盖。

### Task 8: 登录、注册、恢复和恢复码页面

**Files:** 新建 `Features/Profile/Authentication/{PasswordLoginView,PasswordRegistrationView,PasswordRecoveryView,RecoveryCodeView}.swift`；修改 `AccountControls.swift`、`ZhouJiUITests/ZhouJiV2UITests.swift` 及 DEBUG 测试适配器。

**Interfaces:** 登录入口 `PasswordLoginView()` 从 AccountStore environment 获取服务；`RecoveryCodeView(material: RecoveryMaterial, onDone: () -> Void)` 不访问服务器。标识符前缀 `account.password.*` 与 `account.recovery.*`。

- [x] 先用 XCTest 增加完整注册／保存恢复资料／退出／登录／恢复流程断言。测试替身仅在既有 `#if DEBUG` 且显式 in-memory flag 下启用，不接触真实钥匙串或生产接口，Release 不包含模拟注册路径。
- [x] 实现四页及导航：用户名 .username、密码 .password／.newPassword，关闭自动纠错及自动大写；使用共享校验禁用无效提交，注册成功后先展示恢复码，取消恢复不修改账户。
- [x] 实现恢复码逐组朗读、明确复制按钮、`UIPasteboard` 本机内容与两分钟有效期；不自动复制，不提供日志输出。scene 非 active 时用隐私遮罩替换恢复资料预览。
- [x] 使用现有设计规范，表单可滚动避让键盘；插画在独立背景层，不跟随 keyboard safe area 缩小或上顶。支持大字体及 VoiceOver，避免把整个表单强制缩放。
- [x] 运行新增认证 UI 流程与原资料／游客页相关测试；按实际范围保存截图，测试截图不包含真实密码或恢复码。

### Task 9: 账户安全、改密、微信绑定和注销

**Files:** 新建 `Features/Profile/Authentication/AccountSecurityView.swift`；修改 `ProfileView.swift`、`AccountControls.swift`，扩展状态与 UI 测试。

**Interfaces:** `AccountSecurityView()` 用 account.hasPassword 决定改密／恢复码／绑定能力，当前登录方式只用于标识与必要的会话替换；所有敏感操作用 SecureField 接收当前密码，完成或离开清空。

- [x] 写状态／UI 用例：密码验证后改密与轮换、绑定失败或取消保留未绑定状态；微信占用另一账户显示冲突、原资料和库均不变；已绑定微信方式登录仍显示密码安全操作。
- [x] 实现安全设置入口，复用任务 6 的方法；绑定发起阶段不锁住本机记录库，等待微信时可取消。解绑确认明确不会删任务；未安装时保持已绑定状态可见并允许密码验证解绑。
- [x] 为三种独立／绑定情形生成正确注销说明。按账户实际关联决定说明内容，不能仅凭本次 provider 把密码账户误描述为撤销 Apple 授权。
- [x] 回归资料编辑、后台刷新、记录库切换、退出、注销副本保护与失败重试；绑定与解绑全程不切库、不清空数据。
- [x] 运行相关单元／UI 测试；iPhone 模拟器与 iPad 兼容模式认证验证通过，结果见交付记录。
- [ ] iPhone 真机验证密码登录、软键盘和真实微信授权：配对真机当前 unavailable，不计入自动化通过。需要用户系统身份验证时才请用户接管，不索取密码／恢复码到聊天。

### Task 10: 文档、全量检查、部署交付和 Git

**Files:** 更新 `docs/02-产品需求文档-PRD.md` 账户增量、`docs/07-本机账户数据隔离.md`、`server/README.md`、`website/dist/privacy/index.html`；新增 `docs/releases/2026-10-17/username-auth-validation.md`；按 XcodeGen 更新工程文件。

- [x] 同步真实产品规则与隐私说明；用 `node --test website/tests/site.test.mjs website/tests/universal-links.test.mjs` 验证现有站点链接和隐私基础约束。审核资料只写已完成能力，测试账号秘密不入库。
- [x] 全量后端测试、ZhouJiTests、关键认证和原有任务／目标／计时／日历 UI 测试；执行 AGENTS.md 要求的 generic iOS Simulator build。记录命令、测试数、退出码、环境阻塞和未验证项，不把 focused PASS 写成全回归。
- [x] 核对 diff、迁移和密钥扫描，确认无无关素材、发布配置或原用户改动混入。新增 UI 文件后工程重新生成并验证。
- [x] 准备可回退后端发布及生产迁移步骤：先备份、隔离 MySQL 验证、记录表结构、执行 006、部署匹配代码、健康检查、外部临时测试账户验证并按测试授权清理。涉及实际生产部署须依现有用户授权范围执行；没有部署就明确保留待部署状态，不称线上已可用。
- [x] 代码完成且验证通过后，精确暂存本轮文件，创建一次描述最终功能的提交，推送当前跟踪分支；只提交已交付部分，不以完成名义提交已知失败。原工作区其他未跟踪文件保持原状。
- [x] 汇报已实现功能、关键文件、验证范围、提交／推送结果和部署事实。App 新构建上传、隐私问卷提交与 Apple 重新送审另按用户指令，不擅自操作。

## 自检结果与执行边界

设计各节均分配到任务：身份／数据兼容 1、3、6；密码与恢复 2、3、6、8、9；微信绑定及会话隔离 4、5、6、9；入口提示 7；布局 8、9；隐私／发布 10。审阅重点五项均有具体测试归属。

用户已确认按当前对话实施，并另行明确授权生产部署和临时账户验证。代码 `7f6e1fd` 已推送；生产 006、API 与隐私页已发布，服务器隔离测试 102 项和正式 HTTPS 检查 35 项通过，临时账户已注销。新版 App 真机第三方授权及 App Store 上传／送审尚未执行。最终结果见 docs/releases/2026-10-17/username-auth-validation.md。
