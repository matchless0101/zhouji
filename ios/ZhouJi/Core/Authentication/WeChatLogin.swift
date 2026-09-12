import Foundation
@preconcurrency import WechatOpenSDK

enum WeChatLoginError: LocalizedError, Equatable {
    case notConfigured, notInstalled, unavailable, cancelled, denied, expired, callbackMissing, notOpened, invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "此版本尚未配置微信登录。"
        case .notInstalled: "请先安装或更新微信，再使用微信登录。"
        case .unavailable: "暂时无法发起微信授权，请稍后重试。"
        case .cancelled: "已取消微信登录。"
        case .denied: "微信授权未获允许，请重试。"
        case .expired: "微信授权已超时，请重新登录。"
        case .callbackMissing: "未收到微信授权结果，请在微信中完成授权后重试。"
        case .notOpened: "微信未能打开，请重试。若仍失败，请确认微信已更新。"
        case .invalidResponse: "微信授权结果不完整，请重新登录。"
        }
    }
}

@MainActor
protocol WeChatAuthorizing: AnyObject {
    func authorize(state: String) async throws -> String
    func cancel()
    func handle(url: URL)
    func handle(activity: NSUserActivity)
    func applicationDidEnterBackground()
    func applicationDidBecomeActive()
}

extension WeChatAuthorizing {
    func applicationDidEnterBackground() {}
    func applicationDidBecomeActive() {}
}

/// Small boundary around the official SDK so real callback handling can be regression tested.
@MainActor
protocol WeChatSDKDriving: AnyObject {
    var onResponse: (@MainActor (Int32, String?, String?) -> Void)? { get set }
    func register(appID: String, universalLink: String) -> Bool
    var isInstalledAndSupported: Bool { get }
    func send(state: String, completion: @escaping @MainActor (Bool) -> Void)
    func handle(url: URL)
    func handle(activity: NSUserActivity)
}

@MainActor
private final class OfficialWeChatSDK: NSObject, WeChatSDKDriving, WXApiDelegate {
    var onResponse: (@MainActor (Int32, String?, String?) -> Void)?
    func register(appID: String, universalLink: String) -> Bool {
        WXApi.registerApp(appID, universalLink: universalLink)
    }
    var isInstalledAndSupported: Bool { WXApi.isWXAppInstalled() && WXApi.isWXAppSupport() }
    func send(state: String, completion: @escaping @MainActor (Bool) -> Void) {
        let request = SendAuthReq()
        request.scope = "snsapi_userinfo"
        request.state = state
        WXApi.send(request) { sent in Task { @MainActor in completion(sent) } }
    }
    func handle(url: URL) { WXApi.handleOpen(url, delegate: self) }
    func handle(activity: NSUserActivity) { WXApi.handleOpenUniversalLink(activity, delegate: self) }
    nonisolated func onResp(_ resp: BaseResp) {
        guard let auth = resp as? SendAuthResp else { return }
        let state = auth.state, code = auth.code, errorCode = auth.errCode
        Task { @MainActor [weak self] in self?.onResponse?(errorCode, state, code) }
    }
}

/// Only initializes the official SDK when the user requests WeChat login.
@MainActor
final class WeChatLogin: WeChatAuthorizing {
    private var continuation: CheckedContinuation<String, Error>?
    private var pendingState: String?
    private var timeout: Task<Void, Never>?
    private var handoffTimeout: Task<Void, Never>?
    private var registered = false
    private var leftApplication = false
    private let sdk: any WeChatSDKDriving
    private let appID: String
    private let launchWait: Duration
    private let returnWait: Duration
    private let universalLink = "https://zhouji.xiangdangdang.top/wechat/"

    init(sdk: (any WeChatSDKDriving)? = nil, appID: String? = nil,
         launchWait: Duration = .seconds(30), returnWait: Duration = .seconds(10)) {
        self.sdk = sdk ?? OfficialWeChatSDK()
        self.appID = appID ?? Bundle.main.object(forInfoDictionaryKey: "ZhouJiWeChatAppID") as? String ?? ""
        self.launchWait = launchWait
        self.returnWait = returnWait
        self.sdk.onResponse = { [weak self] errorCode, state, code in
            self?.receive(errorCode: errorCode, state: state, code: code)
        }
    }

    func authorize(state: String) async throws -> String {
        guard continuation == nil else { throw WeChatLoginError.unavailable }
        guard appID.range(of: "^wx[0-9a-fA-F]{16}$", options: .regularExpression) != nil else {
            throw WeChatLoginError.notConfigured
        }
        if !registered { registered = sdk.register(appID: appID, universalLink: universalLink) }
        guard registered else { throw WeChatLoginError.unavailable }
        guard sdk.isInstalledAndSupported else { throw WeChatLoginError.notInstalled }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            pendingState = state
            leftApplication = false
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                self?.finish(.failure(WeChatLoginError.expired), state: state)
            }
            scheduleHandoffTimeout(after: launchWait, error: .notOpened, state: state)
            sdk.send(state: state) { [weak self] sent in
                if !sent { self?.finish(.failure(WeChatLoginError.unavailable), state: state) }
            }
        }
    }

    func cancel() {
        guard let pendingState else { return }
        finish(.failure(WeChatLoginError.cancelled), state: pendingState)
    }

    func applicationDidEnterBackground() {
        guard pendingState != nil else { return }
        leftApplication = true
        handoffTimeout?.cancel()
    }

    func applicationDidBecomeActive() {
        guard leftApplication, let pendingState else { return }
        leftApplication = false
        // Scene activation may arrive before the URL/SDK callback; allow it time to finish.
        scheduleHandoffTimeout(after: returnWait, error: .callbackMissing, state: pendingState)
    }

    func handle(url: URL) {
        guard registered, pendingState != nil else { return }
        if url.scheme == appID {
            sdk.handle(url: url)
        } else if isUniversalLink(url) {
            // SwiftUI can deliver universal links through onOpenURL as well as user activity.
            let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            activity.webpageURL = url
            sdk.handle(activity: activity)
        }
    }

    func handle(activity: NSUserActivity) {
        guard registered, pendingState != nil,
              activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL, isUniversalLink(url) else { return }
        sdk.handle(activity: activity)
    }

    private func isUniversalLink(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "zhouji.xiangdangdang.top"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && url.path.hasPrefix("/wechat/")
    }

    private func receive(errorCode: Int32, state: String?, code: String?) {
        guard let pendingState else { return }
        // Never accept a foreign state's success or use it to end the active request.
        if let state, !state.isEmpty, state != pendingState { return }
        if errorCode != 0 {
            // Cancellation/SDK failures may omit state. They may end a request, never authenticate it.
            let error: WeChatLoginError = errorCode == -2 ? .cancelled : (errorCode == -4 ? .denied : .unavailable)
            finish(.failure(error), state: pendingState)
        } else if state == pendingState, let code, !code.isEmpty {
            finish(.success(code), state: pendingState)
        } else {
            finish(.failure(WeChatLoginError.invalidResponse), state: pendingState)
        }
    }

    private func scheduleHandoffTimeout(after delay: Duration, error: WeChatLoginError, state: String) {
        handoffTimeout?.cancel()
        handoffTimeout = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            self?.finish(.failure(error), state: state)
        }
    }

    private func finish(_ result: Result<String, Error>, state: String) {
        guard state == pendingState, let continuation else { return }
        self.continuation = nil
        pendingState = nil
        timeout?.cancel()
        timeout = nil
        handoffTimeout?.cancel()
        handoffTimeout = nil
        continuation.resume(with: result)
    }
}
