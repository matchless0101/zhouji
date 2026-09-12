import Foundation
import Testing
@testable import ZhouJi

@MainActor private final class SDKStub: WeChatSDKDriving {
    var onResponse: (@MainActor (Int32, String?, String?) -> Void)?
    var isInstalledAndSupported = true
    var state: String?
    var sent: (@MainActor (Bool) -> Void)?
    var universalCallbacks: [URL] = []
    var schemeCallbacks: [URL] = []
    func register(appID: String, universalLink: String) -> Bool { true }
    func send(state: String, completion: @escaping @MainActor (Bool) -> Void) {
        self.state = state
        sent = completion
    }
    func handle(url: URL) { schemeCallbacks.append(url) }
    func handle(activity: NSUserActivity) {
        if let url = activity.webpageURL { universalCallbacks.append(url) }
    }
}

@MainActor struct WeChatLoginTests {
    private let fakeAppID = "wx" + String(repeating: "0", count: 16)

    private func start(_ login: WeChatLogin, sdk: SDKStub, state: String = "request-one") async -> Task<Result<String, Error>, Never> {
        sdk.state = nil
        let task = Task { () -> Result<String, Error> in
            do { return .success(try await login.authorize(state: state)) }
            catch { return .failure(error) }
        }
        while sdk.state == nil { await Task.yield() }
        return task
    }

    private func failure(_ task: Task<Result<String, Error>, Never>) async -> WeChatLoginError? {
        if case .failure(let error) = await task.value { return error as? WeChatLoginError }
        return nil
    }

    @Test func bothSwiftUIEntrypointsForwardOnlyTrustedLinksToSDK() async {
        let sdk = SDKStub()
        let bridge = WeChatLogin(sdk: sdk, appID: fakeAppID)
        let pending = await start(bridge, sdk: sdk)
        let url = URL(string: "https://zhouji.xiangdangdang.top/wechat/callback?test=1")!
        bridge.handle(url: url)
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url
        bridge.handle(activity: activity)
        #expect(sdk.universalCallbacks == [url, url])
        let scheme = URL(string: fakeAppID + "://oauth?test=1")!
        bridge.handle(url: scheme)
        #expect(sdk.schemeCallbacks == [scheme])
        for value in ["https://example.com/wechat/callback", "http://zhouji.xiangdangdang.top/wechat/callback",
                      "https://zhouji.xiangdangdang.top/other", "https://zhouji.xiangdangdang.top:8443/wechat/callback",
                      "https://someone@zhouji.xiangdangdang.top/wechat/callback"] {
            bridge.handle(url: URL(string: value)!)
        }
        #expect(sdk.universalCallbacks.count == 2)
        bridge.cancel()
        #expect(await failure(pending) == .cancelled)
    }

    @Test(arguments: [Int32(-2), -4, -1])
    func errorWithoutStateEndsWaitingAndAllowsRetry(code: Int32) async {
        let sdk = SDKStub()
        let login = WeChatLogin(sdk: sdk, appID: fakeAppID)
        let first = await start(login, sdk: sdk)
        sdk.onResponse?(code, nil, nil)
        #expect(await failure(first) == (code == -2 ? .cancelled : (code == -4 ? .denied : .unavailable)))
        let retry = await start(login, sdk: sdk, state: "request-two")
        sdk.onResponse?(0, "request-two", "authorized-code")
        if case .success(let value) = await retry.value { #expect(value == "authorized-code") }
        else { Issue.record("Retry did not complete") }
    }

    @Test func missingStateNeverAuthenticatesAndForeignStateIsIgnored() async {
        let sdk = SDKStub()
        let bridge = WeChatLogin(sdk: sdk, appID: fakeAppID)
        let first = await start(bridge, sdk: sdk)
        sdk.onResponse?(0, nil, "untrusted-code")
        #expect(await failure(first) == .invalidResponse)
        let second = await start(bridge, sdk: sdk, state: "request-two")
        sdk.onResponse?(0, "request-one", "stale-code")
        sdk.onResponse?(-2, "foreign-state", nil)
        sdk.onResponse?(0, "request-two", "valid-code")
        sdk.onResponse?(0, "request-two", "duplicate-code")
        if case .success(let code) = await second.value { #expect(code == "valid-code") }
        else { Issue.record("Foreign state interrupted active request") }
    }

    @Test func failedHandoffEndsPromptlyWithoutWaitingFiveMinutes() async {
        let sdk = SDKStub()
        let login = WeChatLogin(sdk: sdk, appID: fakeAppID, launchWait: .milliseconds(20))
        let pending = await start(login, sdk: sdk)
        sdk.sent?(true) // SDK accepted the request, but the app never left the foreground.
        #expect(await failure(pending) == .notOpened)
    }

    @Test func returnWithoutCallbackTimesOutButValidCallbackWins() async {
        let sdk = SDKStub()
        let login = WeChatLogin(sdk: sdk, appID: fakeAppID, returnWait: .milliseconds(20))
        let pending = await start(login, sdk: sdk)
        login.applicationDidEnterBackground()
        login.applicationDidBecomeActive()
        #expect(await failure(pending) == .callbackMissing)
        let retry = await start(login, sdk: sdk, state: "retry")
        login.applicationDidEnterBackground()
        login.applicationDidBecomeActive()
        sdk.onResponse?(0, "retry", "code")
        if case .success = await retry.value {} else { Issue.record("Valid return was rejected") }
    }

    @Test func leavingAgainCancelsReturnTimeout() async throws {
        let sdk = SDKStub()
        let login = WeChatLogin(sdk: sdk, appID: fakeAppID, returnWait: .milliseconds(20))
        let pending = await start(login, sdk: sdk)
        login.applicationDidEnterBackground()
        login.applicationDidBecomeActive()
        login.applicationDidEnterBackground() // SDK verification can bounce through the app before authorization.
        try await Task.sleep(for: .milliseconds(50))
        sdk.onResponse?(0, "request-one", "code")
        if case .success = await pending.value {} else { Issue.record("Return timeout survived a new handoff") }
    }
}
