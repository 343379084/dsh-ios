import Foundation
import Combine

/// 持久化配置。远程连接模式下只有两个必填项：
/// 1) serverURL    — dsh web 的服务地址（例如 http://124.220.61.238:3080）
/// 2) loginTokenURL — dsh 0.1.5+ 的带 token 一次性登录地址（首启用它换 cookie）
///
/// dsh 的 Web 入口在根路径无 token / 无有效 cookie 时直接 401。
/// Android 版是通过读容器里的 .credentials.yaml 自签 cookie 解决的；
/// iOS 侧拿不到服务器密钥，所以用「粘贴一条带 token 的 URL，让服务器自己 Set-Cookie」。
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum K {
        static let serverURL = "dsh.serverURL"
        static let loginTokenURL = "dsh.loginTokenURL"
        static let lastVersion = "dsh.lastVersion"
    }

    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: K.serverURL) }
    }

    @Published var loginTokenURL: String {
        didSet { defaults.set(loginTokenURL, forKey: K.loginTokenURL) }
    }

    /// 由网页桥或错误页发起的「打开设置」请求计数
    @Published var requestOpenSettings: Int = 0

    private init() {
        serverURL = defaults.string(forKey: K.serverURL) ?? "http://127.0.0.1:3080"
        loginTokenURL = defaults.string(forKey: K.loginTokenURL) ?? ""
        let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        if defaults.string(forKey: K.lastVersion) != current {
            defaults.set(current, forKey: K.lastVersion)
        }
    }

    /// 归一化后的服务根地址（补 http://、去掉尾部斜杠）
    var normalizedServerURL: URL? {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    /// 归一化后的登录地址
    var normalizedLoginURL: URL? {
        var s = loginTokenURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            s = "http://" + s
        }
        return URL(string: s)
    }

    /// 宿主名，用于加载提示文案
    var hostLabel: String {
        guard let u = normalizedServerURL else { return "未配置" }
        let port = u.port.map { ":\($0)" } ?? ""
        return (u.host ?? u.absoluteString) + port
    }
}
