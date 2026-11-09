import Foundation
import WebKit
import SwiftUI
import UIKit
import SafariServices
import UniformTypeIdentifiers

/// 持有 WKWebView 的唯一实例，负责：
///   · 首次用带 token 的 URL 换 cookie（dsh 0.1.5+ 根路径无 cookie 会 401）
///   · 401 → 自动切登录 URL → 成功后再回首页
///   · 注入 mobile.css / inject.js / 原生桥 shim
///   · 外链、文件上传、JS 弹窗的原生兜底
///   · 失败时给出可读原因（不发「未知错误」）
final class WebController: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case needsLogin
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var hostLabel = ""

    let webView: WKWebView

    private var progressObs: NSKeyValueObservation?
    private var loginAttempted = false
    private var awaitingLoginResult = false
    private var started = false

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.defaultWebpagePreferences.preferredContentMode = .mobile
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.applicationNameForUserAgent = "DSHMobile-iOS/1.0"
        cfg.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        configure()
    }

    deinit {
        progressObs?.invalidate()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "dshNative")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    // MARK: - 初始化

    private func configure() {
        let ucc = webView.configuration.userContentController
        for s in ScriptInjector.makeUserScripts() { ucc.addUserScript(s) }
        ucc.add(self, name: "dshNative")

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.alwaysBounceVertical = true
        webView.isOpaque = false
        let bg = UIColor(red: 0.045, green: 0.055, blue: 0.078, alpha: 1)
        webView.backgroundColor = bg
        webView.scrollView.backgroundColor = bg
        webView.underPageBackgroundColor = bg
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            let p = wv.estimatedProgress
            DispatchQueue.main.async { self?.progress = p }
        }
    }

    // MARK: - 加载控制

    func startIfNeeded() {
        guard !started else { return }
        started = true
        loadHome()
    }

    func loadHome() {
        guard let base = AppSettings.shared.normalizedServerURL else {
            phase = .failed("还没有填写 DSH 服务地址。点右上角齿轮去设置。")
            return
        }
        hostLabel = AppSettings.shared.hostLabel
        loginAttempted = false
        awaitingLoginResult = false
        phase = .loading
        var req = URLRequest(url: base, timeoutInterval: 25)
        req.cachePolicy = .useProtocolCachePolicy
        webView.load(req)
    }

    func retry() {
        started = true
        loadHome()
    }

    func reload() {
        if webView.url == nil { retry() } else { webView.reload() }
    }

    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }

    private func loadLogin(url: URL) {
        awaitingLoginResult = true
        phase = .loading
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(req)
    }

    // MARK: - 401 处理

    private func handleUnauthorized() {
        if !loginAttempted, let lu = AppSettings.shared.normalizedLoginURL {
            loginAttempted = true
            loadLogin(url: lu)
            return
        }
        phase = .needsLogin
    }

    // MARK: - 失败描述

    private static func describe(_ e: NSError) -> String {
        switch e.code {
        case NSURLErrorCannotFindHost:
            return "找不到这个服务器，检查地址是否写错"
        case NSURLErrorCannotConnectToHost:
            return "连不上服务器。确认 dsh web 已启动、端口没写错、防火墙放行"
        case NSURLErrorTimedOut:
            return "连接超时。服务器可能没开，或者当前网络到不了它"
        case NSURLErrorNotConnectedToInternet:
            return "手机现在没有网络"
        case NSURLErrorNetworkConnectionLost:
            return "网络中断了，重试一次"
        case NSURLErrorDNSLookupFailed:
            return "域名解析失败，试试直接用 IP 地址"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "被 iOS 的传输安全策略拦了（http 未放行）"
        case NSURLErrorServerCertificateUntrusted:
            return "https 证书不受信任。自签证书要先在系统里装好并信任"
        case NSURLErrorSecureConnectionFailed:
            return "TLS 握手失败，检查证书或改用 http"
        default:
            return "加载失败（\(e.code)）：\(e.localizedDescription)"
        }
    }

    private func failIfNeeded(_ error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }
        DispatchQueue.main.async {
            if case .needsLogin = self.phase { return }
            self.phase = .failed(WebController.describe(ns))
        }
    }

    // MARK: - 原生弹层

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        let keyWindow = windows.first(where: { $0.isKeyWindow })
        var root: UIViewController? = keyWindow?.rootViewController
        while let p = root?.presentedViewController { root = p }
        return root
    }

    private func openExternally(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            let vc = SFSafariViewController(url: url)
            topViewController()?.present(vc, animated: true)
        } else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func presentInfo(_ title: String, _ message: String) {
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "知道了", style: .default))
        topViewController()?.present(ac, animated: true)
    }
}

// MARK: - WKNavigationDelegate

extension WebController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        // target=_blank / window.open
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            DispatchQueue.main.async { self.openExternally(url) }
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        let internalSchemes = ["http", "https", "about", "blob", "data", "file", "javascript", "ws", "wss"]
        if !internalSchemes.contains(scheme) {
            decisionHandler(.cancel)
            DispatchQueue.main.async { self.openExternally(url) }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard navigationResponse.isForMainFrame,
              let http = navigationResponse.response as? HTTPURLResponse else {
            decisionHandler(.allow)
            return
        }
        if http.statusCode == 401 {
            decisionHandler(.cancel)
            DispatchQueue.main.async { self.handleUnauthorized() }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
        }

        // 刚才加载的是带 token 的登录地址 → cookie 应已落地，回首页
        if awaitingLoginResult {
            awaitingLoginResult = false
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { _ in
                DispatchQueue.main.async {
                    guard let base = AppSettings.shared.normalizedServerURL else {
                        self.phase = .ready
                        return
                    }
                    // 换 cookie 成功后回首页，中间保持 loading，避免闪一下登录页
                    self.phase = .loading
                    webView.load(URLRequest(url: base))
                }
            }
            return
        }

        ScriptInjector.reinject(into: webView)
        DispatchQueue.main.async { self.phase = .ready }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failIfNeeded(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failIfNeeded(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // WebContent 进程被系统回收（iOS 常见）：直接重载，不给用户看白屏
        DispatchQueue.main.async {
            self.phase = .loading
            webView.reload()
        }
    }
}

// MARK: - WKUIDelegate

extension WebController: WKUIDelegate {

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
        picker.allowsMultipleSelection = parameters.allowsMultipleSelection
        picker.delegate = FilePickerProxy.shared
        FilePickerProxy.shared.store(completionHandler)
        DispatchQueue.main.async {
            self.topViewController()?.present(picker, animated: true)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        DispatchQueue.main.async {
            // present 不出去时必须立刻放行，否则网页会永久卡在弹窗回调上
            guard let vc = self.topViewController() else {
                completionHandler()
                return
            }
            vc.present(ac, animated: true)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        ac.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        DispatchQueue.main.async {
            guard let vc = self.topViewController() else {
                completionHandler(false)
                return
            }
            vc.present(ac, animated: true)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let ac = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        ac.addTextField { tf in tf.text = defaultText }
        ac.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        ac.addAction(UIAlertAction(title: "确定", style: .default) { [weak ac] _ in
            completionHandler(ac?.textFields?.first?.text)
        })
        DispatchQueue.main.async {
            guard let vc = self.topViewController() else {
                completionHandler(nil)
                return
            }
            vc.present(ac, animated: true)
        }
    }
}

// MARK: - WKScriptMessageHandler

extension WebController: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "dshNative",
              let body = message.body as? [String: Any],
              let method = body["method"] as? String else { return }

        DispatchQueue.main.async {
            switch method {
            case "openConfig":
                NotificationCenter.default.post(name: .dshOpenSettings, object: nil)
            case "installPlugin":
                let arg = (body["arg"] as? String) ?? ""
                let target = arg.isEmpty ? "<插件名或本地 tgz 路径>" : arg
                self.presentInfo(
                    "远程模式说明",
                    "iOS 版是通过网络连到已经跑起来的 DSH，插件装在服务器那一侧：\n\n"
                    + "dsh plugin --profile web add \(target)"
                )
            default:
                break
            }
        }
    }
}

// MARK: - 文件选择代理

final class FilePickerProxy: NSObject, UIDocumentPickerDelegate {

    static let shared = FilePickerProxy()

    private var completion: (([URL]?) -> Void)?

    func store(_ c: @escaping ([URL]?) -> Void) {
        completion = c
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion?(urls)
        completion = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion?(nil)
        completion = nil
    }
}
