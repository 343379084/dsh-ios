import Foundation
import WebKit

/// 把 Android 版的三份前端适配资源原样搬到 iOS：
///   early-polyfill.js → documentStart（老内核 polyfill，iOS 上一般用不到，但注入无害）
///   mobile.css        → documentStart（插 <style id="dsh-mobile-style"> + 修 viewport）
///   inject.js         → documentEnd（侧栏抽屉 / 输入座留白 / 插件面板等交互补丁）
///
/// 注入顺序与 Android 的 MobileUiInjector 对齐：polyfill → CSS/viewport → inject.js。
enum ScriptInjector {

    // MARK: - 资源读取

    /// 读 bundle 里的资源。XcodeGen 会把 Resources/ 下的 js/css 作为 bundle 资源拷进去。
    static func read(_ name: String, ext: String) -> String {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: ext),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources")
        ]
        for case let url? in candidates {
            if let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty {
                return s
            }
        }
        return ""
    }

    // MARK: - JS 字符串字面量

    /// 把任意文本转成安全的 JS 双引号字符串字面量。
    /// 除了常规转义，必须处理 U+2028 / U+2029 —— 它们在 JS 字符串字面量里是行终止符，
    /// 不转义会让整段脚本语法错误（CSS 里偶尔会出现）。
    static func jsLiteral(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"":
                out += "\\\""
            case "\\":
                out += "\\\\"
            case "\n":
                out += "\\n"
            case "\r":
                out += "\\r"
            case "\t":
                out += "\\t"
            case "\u{2028}":
                out += "\\u2028"
            case "\u{2029}":
                out += "\\u2029"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }

    // MARK: - 原生桥 shim

    /// inject.js 里有 `window.DshNative.openConfig()` / `installPlugin(name)` 两处调用
    /// （Android 用 addJavascriptInterface 提供）。iOS 没有那个对象，
    /// 这里补一个同形状的 shim 转成 WKScriptMessageHandler，让 inject.js 的守卫走通。
    static let nativeBridgeShim: String = """
    (function () {
      try {
        if (window.DshNative && window.DshNative.__ios) return;
        var post = function (payload) {
          try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dshNative) {
              window.webkit.messageHandlers.dshNative.postMessage(payload);
            }
          } catch (e) {}
        };
        window.DshNative = {
          __ios: true,
          openConfig: function () { post({ method: 'openConfig' }); },
          installPlugin: function (name) { post({ method: 'installPlugin', arg: String(name == null ? '' : name) }); }
        };
      } catch (e) {}
    })();
    """

    // MARK: - 脚本组装

    static func makeUserScripts() -> [WKUserScript] {
        var scripts: [WKUserScript] = []

        // 1) 老内核 polyfill：必须最先
        let polyfill = read("early-polyfill", ext: "js")
        if !polyfill.isEmpty {
            scripts.append(WKUserScript(source: polyfill,
                                        injectionTime: .atDocumentStart,
                                        forMainFrameOnly: false))
        }

        // 2) 原生桥 shim：必须早于 inject.js
        scripts.append(WKUserScript(source: nativeBridgeShim,
                                    injectionTime: .atDocumentStart,
                                    forMainFrameOnly: false))

        // 3) CSS + viewport：documentStart 就插，避免首屏闪一下桌面布局
        let css = read("mobile", ext: "css")
        let tweaks = read("ios-tweaks", ext: "css")
        let cssPayload = css + "\n\n/* ==== iOS 补充 ==== */\n" + tweaks
        let cssScript = """
        (function () {
          try {
            var css = \(jsLiteral(cssPayload));
            function applyStyle() {
              if (!document.getElementById('dsh-mobile-style')) {
                var st = document.createElement('style');
                st.id = 'dsh-mobile-style';
                st.textContent = css;
                (document.head || document.documentElement).appendChild(st);
                return;
              }
              var old = document.getElementById('dsh-mobile-style');
              if (old && old.textContent !== css) { old.textContent = css; }
            }
            function applyViewport() {
              var content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
              var v = document.querySelector('meta[name=viewport]');
              if (v) { v.setAttribute('content', content); }
              else {
                var m = document.createElement('meta');
                m.name = 'viewport';
                m.setAttribute('content', content);
                (document.head || document.documentElement).appendChild(m);
              }
              if (document.documentElement) {
                document.documentElement.style.webkitTextSizeAdjust = '100%';
              }
            }
            applyStyle();
            applyViewport();
            // head 可能还没解析完，DOMContentLoaded 前再补一次
            document.addEventListener('DOMContentLoaded', function () {
              try { applyStyle(); applyViewport(); } catch (e) {}
            });
          } catch (e) {}
        })();
        """
        scripts.append(WKUserScript(source: cssScript,
                                    injectionTime: .atDocumentStart,
                                    forMainFrameOnly: false))

        // 4) 主注入：DOM 就绪后（只主框架 —— iframe 里重复跑会和页面的抽屉/输入座逻辑打架）
        let inject = read("inject", ext: "js")
        if !inject.isEmpty {
            scripts.append(WKUserScript(source: inject,
                                        injectionTime: .atDocumentEnd,
                                        forMainFrameOnly: true))
        }

        return scripts
    }

    /// 页面每次 didFinish / 从 bfcache 恢复时补一次。
    /// inject.js 自身是幂等的（README 明确说明），重复执行安全。
    static func reinject(into webView: WKWebView) {
        let inject = read("inject", ext: "js")
        guard !inject.isEmpty else { return }
        webView.evaluateJavaScript(inject, completionHandler: nil)
    }

    /// 页面可见性变化时，补一次手机端样式（有些页面会在切前台后重建 DOM）
    static func ensureStyles(into webView: WKWebView) {
        let js = """
        (function () {
          try {
            var st = document.getElementById('dsh-mobile-style');
            if (!st) { window.__dshNeedRestyle = true; }
          } catch (e) {}
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// 启动自检：资源有没有被打进 bundle（缺了就是 XcodeGen 的 sources 配置问题）
    static func diagnostics() -> String {
        let files = [("early-polyfill", "js"), ("mobile", "css"), ("inject", "js"), ("ios-tweaks", "css")]
        var lines: [String] = []
        for (n, e) in files {
            let s = read(n, ext: e)
            lines.append("\(n).\(e): \(s.isEmpty ? "缺失" : "\(s.count) 字符")")
        }
        return lines.joined(separator: "\n")
    }
}
