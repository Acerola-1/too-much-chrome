## 更新内容

### 新功能

- 支持引导壳应用检测：Steam 的真实客户端（CEF）自更新到 Application Support 内，此前漏检，现已正确检出并计入体积
- 新增两类检测：**系统 WebView**（WKWebView 承载 + 自有前端入口 HTML，排除 Safari 扩展宿主与帮助文档目录）与 **Flutter WebView**（要求 FlutterMacOS 与 webview 插件同时在架，纯 Flutter 应用不算）——类型分布、分段过滤与悬停说明同步扩展

### 检测修复

- **重命名引擎兜底**：框架名与 Bundle ID 双双被换成自有标识的应用此前完全漏检（实测 ChatGPT 的 `Codex Framework` / `com.openai.codex.framework`、微信的 `WeChatAppEx Framework` / `com.tencent.flue.framework`），现由框架二进制里的家族标记（`electron_browser` / `ELECTRON_` / `libcef` / `CefBrowser`）定家族、内嵌 `Chrome/x.y.z.w` UA 串定内核版本；家族标记读不到时退回 `Contents/Resources/app.asar` 判定
- **新增「自研内核」类型**：既无 Electron 也无 CEF 家族标记的 Chromium 派生内核单列一类（实测微信 XWeb，内核 144）。此前用「Electron = Chromium + Node.js」的推理只看 `node::`，把微信误标成了 Electron——**带 Node 不等于 Electron**，腾讯 XWeb 同样内嵌 Node.js
- **引擎枚举下钻到子应用**：微信的 XWeb 在 `Contents/MacOS/WeChatAppEx.app/` 内、WPS 的 CEF 在 `Contents/SharedSupport/browserserver.app/` 内，只看 `Contents/Frameworks` 顶层整片看不到
- **口径澄清**：微信是 Qt 原生应用（`Contents/Resources/wechat.dylib`，327MB，`QWidget` 92 次）内嵌 Chromium 小程序运行时，不是基于 WebView 构建的应用。因本工具衡量的是"硬盘上有多少 Chromium 代码"，387MB 的内核仍计入，但 UI 文案由"基于 WebView / Chromium 的应用"改为"内嵌 Chromium / WebView 引擎的应用"，并在详情弹层为自研内核补一句说明
- 修复框架主二进制体积统计未解析符号链接的缺陷：量到的是链接自身的 32 字节，导致「体积 ≥20MB 才做 UA 兜底」这条判据从未生效
- **CEF 版本号取信口径**：框架 plist 大版本低于 20 视为厂商塞入的应用版本，改从框架二进制的 `Chrome/` UA 串取真实内核——网易云 plist 写 3.1.11，真实内核 116，此前显示「未知」，现正确判为老旧
- **Electron 版本号取信口径**：大版本 1 起即合法，不再把真实的老版本误判为「未知」——aTrust 的 11.5.0 就是 Electron 11（Chromium 87），现正确判为老旧
- Electron 框架 plist 写成 Chromium 方案时（ChatGPT 的 152.0.7977.83）改按 Chromium 阈值分档
- 扫描枚举放宽到两层：`/Applications/Utilities/` 与 `<浏览器> Apps.localized/` 内的应用此前不被枚举；仍不进入 `.app` 内部（那里是 helper 子应用）
- 内置离线锚点补齐 Tauri / Wails 并同步校准（Electron 44 · Chromium 152 · Tauri 2.11.5 · Wails 2.14.0）——此前离线运行时这两个类型恒显示「未知」

### 代码质量

- 体积口径修正：引导壳应用的数据目录扣除客户端本体与游戏安装内容，避免重复计入
- 同步 detection-strategy.md 扫描路径说明，新增引导壳布局回归测试
- 新增 14 个回归测试覆盖重命名引擎、子应用下钻、版本取信口径、系统 WebView 误报排除与枚举深度，测试总数 32 个全绿
- 真机核对：本机检出由 18 个增至 22 个应用（新增 ChatGPT、微信、Typora、WPS Office），误报为 0；全盘扫描耗时约 15 秒不变

