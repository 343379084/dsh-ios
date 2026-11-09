import SwiftUI
import WebKit

enum Theme {
    static let bg = Color(red: 0.045, green: 0.055, blue: 0.078)
    static let panel = Color(red: 0.075, green: 0.089, blue: 0.118)
    static let glass = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.10)
    static let accent = Color(red: 0.302, green: 0.420, blue: 0.996)   // DeepSeek #4D6BFE
    static let text = Color.white.opacity(0.92)
    static let subtext = Color.white.opacity(0.55)
    static let danger = Color(red: 0.98, green: 0.42, blue: 0.42)
}

struct RootView: View {

    @EnvironmentObject private var settings: AppSettings
    @StateObject private var controller = WebController()

    @State private var showSettings = false
    @State private var keyboardUp = false
    @AppStorage("dsh.hasConfigured") private var hasConfigured = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    WebViewHost(webView: controller.webView)
                    screenOverlay
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !keyboardUp {
                    bottomBar
                }
            }
        }
        .overlay(alignment: .top) {
            if isBusy {
                ProgressStrip(progress: controller.progress)
                    .transition(.opacity)
            }
        }
        .onAppear {
            controller.startIfNeeded()
            if !hasConfigured { showSettings = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.22)) { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.22)) { keyboardUp = false }
        }
        .onReceive(settings.$requestOpenSettings.dropFirst()) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isFirstRun: !hasConfigured) { 
                hasConfigured = true
                showSettings = false
                controller.retry()
            }
            .environmentObject(settings)
        }
    }

    // MARK: - 状态

    private var isBusy: Bool {
        if case .loading = controller.phase { return true }
        if case .idle = controller.phase { return true }
        return false
    }

    @ViewBuilder
    private var screenOverlay: some View {
        switch controller.phase {
        case .idle, .loading:
            VStack {
                Spacer()
                ConnectingPill(host: controller.hostLabel)
                    .padding(.bottom, 24)
            }
            .allowsHitTesting(false)

        case .needsLogin:
            NoticeCard(
                icon: "key.horizontal",
                title: "需要登录凭证",
                text: "这个 DSH 服务要求登录。请在设置里粘贴一条带 token 的地址（服务器启动 dsh web 时会打印），App 用它换一次 cookie 之后就不再需要了。",
                primary: ("去设置", { showSettings = true }),
                secondary: ("重试", { controller.retry() })
            )

        case .failed(let message):
            NoticeCard(
                icon: "exclamationmark.triangle",
                title: "连不上 DSH",
                text: message,
                mono: "目标：\(settings.normalizedServerURL?.absoluteString ?? "未配置")",
                primary: ("重试", { controller.retry() }),
                secondary: ("检查设置", { showSettings = true })
            )

        case .ready:
            EmptyView()
        }
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        HStack(spacing: 4) {
            Button {
                controller.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 38)
            }
            .disabled(!controller.canGoBack)
            .opacity(controller.canGoBack ? 1 : 0.25)

            Text(controller.hostLabel.isEmpty ? "DSH" : controller.hostLabel)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.subtext)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)

            Button {
                controller.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 38)
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 38)
            }
        }
        .foregroundColor(Theme.text)
        .padding(.horizontal, 6)
        .frame(height: 44)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Theme.glass)
            }
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.stroke).frame(height: 0.5)
        }
    }

    // MARK: - 键盘

    // 键盘监听用 onReceive（见 body），SwiftUI 会自动管理订阅生命周期。
}

// MARK: - WebView 宿主

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - 顶部进度

struct ProgressStrip: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.clear
                LinearGradient(
                    colors: [Theme.accent.opacity(0.5), Theme.accent],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: max(6, geo.size.width * (progress <= 0 ? 0.08 : progress)), height: 2)
                .animation(.easeOut(duration: 0.2), value: progress)
            }
        }
        .frame(height: 2)
    }
}

// MARK: - 连接中胶囊

struct ConnectingPill: View {
    let host: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(Theme.text)
            Text(host.isEmpty ? "正在连接…" : "正在连接 \(host)…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.5))
    }
}

// MARK: - 提示卡片

struct NoticeCard: View {
    let icon: String
    let title: String
    let text: String
    let mono: String?
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)?

    init(icon: String, title: String, text: String, mono: String? = nil,
         primary: (String, () -> Void), secondary: (String, () -> Void)?) {
        self.icon = icon
        self.title = title
        self.text = text
        self.mono = mono
        self.primary = primary
        self.secondary = secondary
    }

    var body: some View {
        ZStack {
            Theme.bg.opacity(0.94).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.accent)
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.text)
                }

                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundColor(Theme.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                if let mono = mono {
                    Text(mono)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(Theme.subtext.opacity(0.8))
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
                }

                HStack(spacing: 10) {
                    Button(action: primary.1) {
                        Text(primary.0)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 11).fill(Theme.accent))
                    }
                    if let secondary = secondary {
                        Button(action: secondary.1) {
                            Text(secondary.0)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(RoundedRectangle(cornerRadius: 11).fill(Theme.glass))
                                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.stroke, lineWidth: 0.5))
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 0.5)
            )
            .padding(24)
        }
    }
}
