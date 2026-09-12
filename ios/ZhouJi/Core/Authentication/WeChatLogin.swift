import Foundation
@preconcurrency import WechatOpenSDK

enum WeChatLoginError: LocalizedError {
    case notConfigured, notInstalled, unavailable, cancelled, denied, expired

    var errorDescription: String? {
        switch self {
        case .notConfigured: "此版本尚未配置微信登录。"
        case .notInstalled: "请先安装或更新微信，再使用微信登录。"
        case .unavailable: "暂时无法发起微信授权，请稍后重试。"
        case .cancelled: "已取消微信登录。"
        case .denied: "微信授权未获允许，请重试。"
        case .expired: "微信授权已超时，请重新登录。"
        }
    }
}

@MainActor
protocol WeChatAuthorizing: AnyObject {
    func authorize(state: String) async throws -> String
    func cancel()
    func handle(url: URL)
    func handle(activity: NSUserActivity)
}

/// Only initializes the official SDK when the user requests WeChat login.
@MainActor
final class WeChatLogin: NSObject, WeChatAuthorizing, WXApiDelegate {
    private var continuation: CheckedContinuation<String, Error>?
    private var pendingState: String?
    private var timeout: Task<Void, Never>?
    private var registered = false
    private var appID: String { Bundle.main.object(forInfoDictionaryKey: "ZhouJiWeChatAppID") as? String ?? "" }
    private let universalLink = "https://zhouji.xiangdangdang.top/wechat/"

    func authorize(state: String) async throws -> String {
        guard continuation == nil else { throw WeChatLoginError.unavailable }
        guard appID.range(of: "^wx[0-9a-fA-F]{16}$", options: .regularExpression) != nil else {
            throw WeChatLoginError.notConfigured
        }
        if !registered { registered = WXApi.registerApp(appID, universalLink: universalLink) }
        guard registered else { throw WeChatLoginError.unavailable }
        guard WXApi.isWXAppInstalled(), WXApi.isWXAppSupport() else { throw WeChatLoginError.notInstalled }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            pendingState = state
            let request = SendAuthReq()
            request.scope = "snsapi_userinfo"
            request.state = state
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                self?.finish(.failure(WeChatLoginError.expired), state: state)
            }
            WXApi.send(request) { [weak self] sent in
                if !sent {
                    Task { @MainActor in self?.finish(.failure(WeChatLoginError.unavailable), state: state) }
                }
            }
        }
    }

    func cancel() {
        guard let pendingState else { return }
        finish(.failure(WeChatLoginError.cancelled), state: pendingState)
    }

    func handle(url: URL) {
        guard registered, pendingState != nil, url.scheme == appID else { return }
        WXApi.handleOpen(url, delegate: self)
    }

    func handle(activity: NSUserActivity) {
        guard registered, pendingState != nil, let url = activity.webpageURL,
              url.scheme == "https", url.host == "zhouji.xiangdangdang.top",
              url.path.hasPrefix("/wechat/") else { return }
        WXApi.handleOpenUniversalLink(activity, delegate: self)
    }

    nonisolated func onResp(_ resp: BaseResp) {
        guard let auth = resp as? SendAuthResp else { return }
        let state = auth.state
        let code = auth.code
        let errorCode = auth.errCode
        Task { @MainActor [weak self] in
            guard let state else { return }
            if errorCode == 0, let code, !code.isEmpty {
                self?.finish(.success(code), state: state)
            } else {
                let error: WeChatLoginError = errorCode == -2 ? .cancelled : (errorCode == -4 ? .denied : .unavailable)
                self?.finish(.failure(error), state: state)
            }
        }
    }

    private func finish(_ result: Result<String, Error>, state: String) {
        // Reject foreign, stale and repeated callbacks without ending the active request.
        guard state == pendingState, let continuation else { return }
        self.continuation = nil
        pendingState = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(with: result)
    }
}
