# DSH iPhone 版（iOS 远程客户端）

把 Android 版 `dsh-mobile` 的**界面层**搬到 iPhone，在线编译出 **unsigned IPA**，你自己签名安装。

---

## 一、先说结论

**APK → IPA 不能"直接转换"，但功能可以搬过去。** 原因是硬性的，不是工具问题：

| Android 版靠什么跑 | iOS 能不能给 |
|---|---|
| 内置 `proot` 跑 Ubuntu 22.04 aarch64 rootfs | ❌ iOS 内核只认 Mach-O，`execve` 遇 ELF 直接 ENOEXEC |
| `proot` 依赖 `ptrace(PTRACE_TRACEME/SYSCALL)` | ❌ App 沙箱禁止 ptrace（只有越狱/TrollStore 才可能） |
| Node.js 的 `child_process`（fork/exec） | ❌ iOS App 禁止 fork/exec 任意二进制 |
| V8 的 JIT | ❌ 侧载 IPA 拿不到 `allow-jit` entitlement |
| `targetSdk=28` 才能 exec 私有目录二进制 | — |

> 原文出处（`dsh-mobile/app/build.gradle.kts`）：
> 「targetSdk 必须 ≤28：Android 10+ 对 targetSdk 29+ 的应用启用 SELinux 域限制，
> 禁止 exec 私有目录里的二进制（proot/node 都跑不了），Termux 同理。」

连 Android 系统版本稍新一点都不让 exec，iOS 是**根本不允许**。所以"在 iPhone 里跑一个真 Linux 容器"这条路走不通。

**但可以搬的是**：`mobile.css`（29 KB）、`inject.js`（31 KB）、`early-polyfill.js`（3.3 KB）
这三份纯前端适配资源 —— Android 版全部的"手机版界面"逻辑都在这里，iOS 原样复用。

所以本工程 = **iPhone 上只跑界面（WKWebView），DSH 本体跑在服务器/电脑上**。
看起来、用起来跟 Android 版一样，区别只是算力在哪。

---

## 二、最快拿到 IPA（3 步）

### 1. 推到你的 GitHub 仓库

双击 `一键推送到GitHub.bat`（在上一级目录），按提示填仓库地址。

### 2. 等 Actions 跑完

推上去自动触发 `build-ipa`，macOS 机器上跑 **2~4 分钟**。
也可以手动触发：仓库 → Actions → `build-ipa` → Run workflow。

### 3. 下产物

Actions 那次运行页面底部 → **Artifacts** → `DSHMobile-unsigned-ipa` → 解压得
`DSHMobile-unsigned.ipa`。

---

## 三、后端从哪来

App 只是客户端，必须有台机器在跑 `dsh` 的 web 服务。

> ⚠️ **`--host 0.0.0.0` 会被拒绝**。dsh 源码里写死了：
> 「unbinding every interface would expose remote code execution to the network;
> bind one concrete IPv4 or IPv6 address instead」。
> 所以必须给**本机某块网卡的具体 IP**，不能用通配地址。

### A. 就用你现在这台电脑（最快）

先查本机局域网 IP：

```powershell
# Windows
ipconfig | findstr /i "IPv4"
```

```bash
# Linux
hostname -I | awk '{print $1}'
```

然后（`192.168.x.x` 换成你查到那个）：

```bash
dsh --profile web --host 192.168.x.x --port 3080 --no-open
```

手机要和电脑**同一个 WiFi**，App 里填：

```
http://192.168.x.x:3080
```

启动后终端会打印一行 `dsh web:`，后面那条 URL 带着 `?token=...` —— **把它整条粘进 App 设置页的「登录凭证」**（见第四节）。

> 注意：桌面版 DSH（Electron 那个，端口是随机的 63663 之类）只监听 `127.0.0.1`，
> 手机连不上。要手机访问就按上面单独起一个 CLI 的 web 实例，两者可以同时跑、互不干扰。

**不想重开实例的话**，可以把局域网端口转发到桌面版那个 63663：

```cmd
netsh interface portproxy add v4tov4 listenaddress=192.168.x.x listenport=3080 connectaddress=127.0.0.1 connectport=63663
```

删掉用 `netsh interface portproxy delete v4tov4 listenaddress=192.168.x.x listenport=3080`。

### B. 放到 124 服务器

```bash
npm i -g @deepseek-ai/dsh
dsh --profile web --host <服务器网卡IP> --port 3080 --no-open \
    --public-url http://124.220.61.238:3080 \
    --trusted-host 124.220.61.238:3080
```

- `--host` 填**服务器网卡上的 IP**（云主机一般是私网 IP，如 `10.x.x.x`；公网 IP 是 NAT 映射，绑不上）
- `--public-url` 是"公告"出去的地址，App 和打印的 URL 都按它来
- `--trusted-host` 是给 `/api` 的浏览器信任栅栏放行的 authority；**页面能开但功能报 403 时就是缺这个**
- 安全组 / 防火墙放行 3080

124 上长期跑记得注册进脚本管理器，别留孤儿进程。

### C. 用 frp 把家里电脑的 DSH 穿透出去

你已经有 frps（`123.56.85.39`），按现有隧道规则加一条 `3080`；
再配 `--public-url http://<frp域名>:<端口> --trusted-host <frp域名>:<端口>`。

---

## 四、登录凭证（dsh 0.1.5 起必看）

dsh 0.1.5 起 Web 入口带一次性 token：**根路径没有 token / 没有有效 cookie 直接 401**。

Android 版是读容器里 `/home/dsh/.dsh/.credentials.yaml` 的签名密钥、自己 HMAC 签一枚 cookie 解决的。
iOS 拿不到服务器上的密钥，所以用另一条路：

1. 启动 `dsh --profile web …` 时，终端会打印一行 `dsh web:`，后面那条 URL 带 `?token=...`
2. 把**整条 URL** 粘进 App 的设置页「登录凭证」
3. App 用它加载一次 → 服务器 `Set-Cookie` → cookie 落到 WKWebView → 之后正常访问
4. 之后再启动就不需要了（cookie 持久化在 App 沙箱里）

App 里做了自动处理：**第一次访问首页吃到 401 → 自动切到登录 URL → 成功后再回首页**。
如果两条都失败，会显示「需要登录凭证」并给按钮直接跳设置。

---

## 五、装到 iPhone

unsigned IPA 必须自己签名才能装。

| 工具 | 说明 |
|---|---|
| **Sideloadly**（Win/Mac，推荐） | 拖入 ipa + Apple ID，7 天有效（免费账号） |
| **AltStore / SideStore** | 自签 + 自动续期，需要 AltServer |
| **TrollStore** | iOS 14.0–16.6.1 / 17.0 特定版本，永久签名、免续期、**不受 7 天限制** |
| **企业签 / 超级签** | 淘宝买证书 |

签名后首次打开如果闪退，多半是证书问题，不是 App 问题：

```bash
# 在 Mac 上可以先验证产物结构
unzip -l DSHMobile-unsigned.ipa | head -20
```

---

## 六、这个 App 做了什么

```
DSHMobile/
├─ DSHMobileApp.swift      @main，注入 AppSettings
├─ AppSettings.swift       服务器地址 / 登录 URL 持久化
├─ WebController.swift     WKWebView 唯一实例：401 自愈、注入、外链、文件上传、JS 弹窗
├─ ScriptInjector.swift    组装 WKUserScript（polyfill → CSS/viewport → inject.js）
├─ RootView.swift          WebView + 顶部进度 + 底部工具条 + 失败/登录提示卡
├─ SettingsView.swift      地址 / 登录凭证 / 连接测试 / 清除缓存 / 诊断
├─ Info.plist              ATS 放行 http、文件/相机/麦克风说明
├─ Assets.xcassets/        AppIcon（1024，程序生成）
└─ Resources/
   ├─ mobile.css           ← 原样来自 Android 版
   ├─ inject.js            ← 原样来自 Android 版
   ├─ early-polyfill.js    ← 原样来自 Android 版
   └─ ios-tweaks.css       ← iOS 独有兜底
```

### 注入顺序与 Android 对齐

Android `MobileUiInjector` 的顺序是：`onPageStarted` 注 polyfill → 插 `<style>` + 改 viewport → 注 `inject.js`。
iOS 用 `WKUserScript` 复刻同一顺序，且不靠 `evaluateJavaScript` 的时序竞争：

| 时机 | 内容 |
|---|---|
| `atDocumentStart` | `early-polyfill.js` |
| `atDocumentStart` | `DshNative` 桥 shim（`window.webkit.messageHandlers`） |
| `atDocumentStart` | `mobile.css` + `ios-tweaks.css` + viewport meta 修正 |
| `atDocumentEnd` | `inject.js`（只主框架） |
| 每次 `didFinish` | 再跑一次 `inject.js`（它本身幂等，应对 SPA 首屏晚挂载） |

### iOS 专门修的坑（`ios-tweaks.css`）

- **输入框聚焦整页放大** —— `mobile.css` 原本只兜了 `textarea / input[type=text|search] / div[class*="_input"]`，
  这里把 `select`、`contenteditable`、`email/url/tel/number/password/date` 全补成 `16px !important`
- `-webkit-text-size-adjust: 100%` 钉死，横竖屏切换不顶字号
- 长按选择：给 `pre / code / _markdown / _message` 显式开 `user-select: text`（否则复制不了）
- 弹窗/设置面板 `max-height: calc(100vh - 28px)` + 自身可滚，不压 Home Indicator
- 隐藏 overlay 滚动条（iOS 那个又粗又挡字）
- 代码块强制横向滚动，不被裁

### 与 Android 版的差异（诚实清单）

| 项 | Android | iOS |
|---|---|---|
| DSH 本体 | 手机里跑（proot+Ubuntu+Node） | 服务器上跑 |
| 手机终端（`ssh` 进容器） | 自带 TerminalActivity | 无（用 Termius / Blink 连服务器） |
| 装插件 | 可装本地 tgz | 只能在服务器 `dsh plugin add` |
| 保活/前台服务 | 有 | 不需要 |
| SD 卡映射 | 有 | 无（服务器侧挂载） |
| 界面/交互 | — | **完全一致**（同一份 CSS/JS） |

点「设置 → DSH 配置」时，iOS 会打开 App 设置页而不是容器配置编辑器（没有容器可编）。

---

## 七、本地构建（手上有 Mac 时）

```bash
brew install xcodegen
cd ios-dsh
chmod +x build-ipa.sh
./build-ipa.sh
# 产出：DSHMobile-unsigned.ipa
```

---

## 八、CI 里都验了什么

`.github/workflows/ios-build.yml` 不是"编过就算"，还带产物自检：

1. `plutil -lint` 校验 Info.plist
2. 四份前端资源逐个检查非空
3. AppIcon 存在
4. `xcodegen generate`
5. `xcodebuild`（`CODE_SIGNING_ALLOWED=NO`）
6. 打完包后**回查**：`mobile.css / inject.js / early-polyfill.js / ios-tweaks.css` 是否真的进了 `.app` 根目录
7. `file` + `lipo -info` 确认二进制是 arm64
8. 失败时把 `build.log` 一起传上来

任何一步不过直接 fail，不会给出一个装不上的空壳 IPA。

---

## 九、不想用 GitHub / 不想装 App 的话

- **Safari 直接开**：`http://<服务器>:3080`，Safari → 分享 → 添加到主屏幕。
  能用，但没有 mobile.css 的手机适配（会看到桌面布局）。
- **加 Userscripts 扩展**（App Store 免费）：装 `mobile.css` + `inject.js` 注入到该站点，
  这样 Safari 里的效果和这个 App 几乎一样，**零编译**。
- **iOS 上跑真 Linux**：`iSH` / `a-Shell` 只能跑 x86 模拟的 Alpine，Node 跑得动但慢到不可用，
  并且装不了 dsh 的原生依赖。不推荐。
