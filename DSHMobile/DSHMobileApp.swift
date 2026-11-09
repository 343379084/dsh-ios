import SwiftUI

@main
struct DSHMobileApp: App {
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: .dshOpenSettings)) { _ in
                    settings.requestOpenSettings += 1
                }
        }
    }
}

extension Notification.Name {
    /// 网页内的 DshNative.openConfig() 通过原生桥触发，用来打开 App 设置页
    static let dshOpenSettings = Notification.Name("dsh.open.settings")
    /// 网页请求重新加载（例如鉴权失败后用户重试）
    static let dshRequestReload = Notification.Name("dsh.request.reload")
}
