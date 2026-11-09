import SwiftUI
import WebKit

struct SettingsView: View {

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let isFirstRun: Bool
    let onSave: () -> Void

    @State private var probe: ProbeResult = .idle
    @State private var cacheCleared = false
    @State private var showAdvanced = false

    enum ProbeResult: Equatable {
        case idle
        case running
        case ok(Int)
        case needLogin(Int)
        case failed(String)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {

                    if isFirstRun {
                        OnboardingCard()
                    }

                    serverCard
                    loginCard
                    if showAdvanced { advancedCard }
                    aboutCard

                    Button {
                        onSave()
                    } label: {
                        Text(isFirstRun ? "保存并连接" : "保存并重新连接")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.accent))
                    }
                    .padding(.top, 4)

                    Text("iOS 版是「远程连接」形态：iPhone 上只跑界面，DSH 本体在服务器上跑。")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.subtext.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Theme.text)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(showAdvanced ? "简化" : "高级") {
                        withAnimation(.easeInOut(duration: 0.18)) { showAdvanced.toggle() }
                    }
                    .foregroundColor(Theme.accent)
                }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }

    // MARK: - 服务地址

    private var serverCard: some View {
        Card(title: "服务地址", icon: "server.rack") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("http://124.220.61.238:3080", text: $settings.serverURL)
                    .font(.system(size: 16))   // 必须 ≥16pt，否则 iOS 聚焦会整页放大
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke, lineWidth: 0.5))

                HStack(spacing: 8) {
                    Button {
                        runProbe()
                    } label: {
                        HStack(spacing: 6) {
                            if case .running = probe {
                                ProgressView().scaleEffect(0.6).tint(Theme.text)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text("测试连接")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Theme.text)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.glass))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke, lineWidth: 0.5))
                    }

                    Button {
                        settings.serverURL = "http://127.0.0.1:3080"
                    } label: {
                        Text("本机默认")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.subtext)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.glass))
                    }
                    Spacer()
                }

                probeHint
            }
        }
    }

    @ViewBuilder
    private var probeHint: some View {
        switch probe {
        case .idle:
            EmptyView()
        case .running:
            HintLine(text: "正在探测…", color: Theme.subtext)
        case .ok(let code):
            HintLine(text: "通了（HTTP \(code)），可以连接", color: Color(red: 0.36, green: 0.82, blue: 0.55))
        case .needLogin(let code):
            HintLine(text: "服务器通了（HTTP \(code)），但需要登录凭证 → 填下面的登录地址", color: Color(red: 0.98, green: 0.75, blue: 0.32))
        case .failed(let msg):
            HintLine(text: msg, color: Theme.danger)
        }
    }

    // MARK: - 登录凭证

    private var loginCard: some View {
        Card(title: "登录凭证（可选）", icon: "key.horizontal") {
            VStack(alignment: .leading, spacing: 10) {
                Text("dsh 0.1.5 起，根路径没有 token 会返回 401。在服务器上启动时终端会打印一条带 `?token=…` 的地址，把它整条粘进来，App 只用它换一次 cookie。")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $settings.loginTokenURL)
                    .font(.system(size: 16, design: .monospaced))   // 同样 ≥16pt
                    .foregroundColor(Theme.text)
                    .scrollContentBackgroundHiddenCompat()
                    .frame(height: 74)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke, lineWidth: 0.5))
                    .overlay(alignment: .topLeading) {
                        if settings.loginTokenURL.isEmpty {
                            Text("http://host:3080/?token=xxxxx")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(Theme.subtext.opacity(0.5))
                                .padding(.horizontal, 12)
                                .padding(.top, 14)
                                .allowsHitTesting(false)
                        }
                    }

                Button {
                    settings.loginTokenURL = ""
                } label: {
                    Text("清空")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.subtext)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.glass))
                }
            }
        }
    }

    // MARK: - 高级

    private var advancedCard: some View {
        Card(title: "诊断", icon: "stethoscope") {
            VStack(alignment: .leading, spacing: 12) {

                Text(ScriptInjector.diagnostics())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel))

                HStack(spacing: 8) {
                    Button {
                        clearWebCache()
                    } label: {
                        Text(cacheCleared ? "已清除" : "清除网页缓存")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(cacheCleared ? Color(red: 0.36, green: 0.82, blue: 0.55) : Theme.text)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.glass))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke, lineWidth: 0.5))
                    }
                    Spacer()
                }

                Text("调试：把 iPhone 用数据线连 Mac，Safari → 开发 → 你的 iPhone → 页面，可直接看 WebView 控制台。")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.subtext.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 关于

    private var aboutCard: some View {
        Card(title: "关于这个版本", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 9) {
                KeyValue("版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                KeyValue("形态", "远程 WebView 客户端")
                KeyValue("适配资源", "mobile.css / inject.js 原样复用自 Android 版")
                Text("Android 版能在手机里跑，是因为它带 proot + Ubuntu + Node；iOS 内核不允许执行 ELF、不允许 fork/exec、App 也拿不到 JIT，所以那套后端无法搬到 iPhone。界面层 100% 复用，服务跑在服务器上。")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.subtext.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - 动作

    private func runProbe() {
        guard let url = settings.normalizedServerURL else {
            probe = .failed("地址不合法")
            return
        }
        probe = .running
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { _, resp, err in
            DispatchQueue.main.async {
                if let e = err as NSError? {
                    if e.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
                        probe = .failed("被 ATS 拦了")
                    } else if e.code == NSURLErrorCannotConnectToHost {
                        probe = .failed("端口不通：服务没起或被防火墙挡了")
                    } else if e.code == NSURLErrorTimedOut {
                        probe = .failed("超时：网络到不了这个地址")
                    } else {
                        probe = .failed("失败（\(e.code)）\(e.localizedDescription)")
                    }
                    return
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 401 {
                    probe = .needLogin(code)
                } else if code > 0 {
                    probe = .ok(code)
                } else {
                    probe = .failed("没有拿到 HTTP 响应")
                }
            }
        }.resume()
    }

    private func clearWebCache() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
            DispatchQueue.main.async { cacheCleared = true }
        }
    }
}

// MARK: - 小组件

struct Card<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(Theme.text)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.5)
        )
    }
}

struct HintLine: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5).padding(.top, 5)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct KeyValue: View {
    let k: String
    let v: String

    init(_ k: String, _ v: String) {
        self.k = k
        self.v = v
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(k)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.subtext)
                .frame(width: 66, alignment: .leading)
            Text(v)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("先填一个 DSH 地址")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.text)
            Text("iPhone 上不会跑 DSH 本体（iOS 不允许跑 Linux 容器），所以 App 连的是一台已经跑着 dsh web 的机器：自己的服务器、VPS、或者电脑都行。")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)
            Text("dsh --profile web --host <本机IP> --port 3080 --no-open")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(Theme.accent)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
            Text("注意：--host 不能写 0.0.0.0，dsh 会直接拒绝通配地址，要填本机某块网卡的具体 IP。")
                .font(.system(size: 11))
                .foregroundColor(Theme.subtext.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.accent.opacity(0.35), lineWidth: 0.5)
        )
    }
}

// MARK: - iOS 15 兼容

private extension View {
    /// iOS 16 才有 scrollContentBackground，iOS 15 上 TextEditor 自带白底
    @ViewBuilder
    func scrollContentBackgroundHiddenCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
