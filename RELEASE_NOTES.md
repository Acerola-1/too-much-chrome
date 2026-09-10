## 更新内容

### 新功能

- 新增三类检测：厂商自研的 Chromium 派生内核（微信 XWeb 一类）、Flutter WebView（要求 FlutterMacOS 与 webview 插件同时在架）、系统 WebView（链接 WebKit 且带自有前端入口 HTML，排除 Safari 扩展宿主与帮助文档目录）——类型分段、环形图与悬停说明同步扩展

### 修复

- 重命名引擎此前完全漏检：框架名与 Bundle ID 双双被换成自有标识的构建（ChatGPT 的 Codex Framework、微信的 WeChatAppEx Framework）现由框架二进制内的家族标记与内嵌 Chrome UA 串兜底
- 微信被误标为 Electron：纠正「带 Node 即 Electron」的推理错误——腾讯 XWeb 同样内嵌 Node.js，现单列为「自研内核」
- 引擎藏在子应用里看不到：微信的 XWeb 在 Contents/MacOS/WeChatAppEx.app 内、WPS 的 CEF 在 Contents/SharedSupport/browserserver.app 内，框架枚举现下钻子应用一层
- CEF 版本号取信：框架 plist 被写成厂商应用版本时（网易云 3.1.11）此前显示「未知」，现从框架二进制的 Chrome UA 串取真实内核 116 并正确判为老旧
- 老版本 Electron 被漏判：aTrust 的 11.5.0 是真实的 Electron 11（Chromium 87），此前显示「未知」，现正确判为老旧
- 框架主二进制体积未解析符号链接：量到的是链接自身的 32 字节，导致「体积 ≥20MB 才做 UA 兜底」这条判据从未生效
- 扫描枚举放宽到两层：/Applications/Utilities/ 与「<浏览器> Apps.localized/」内的应用此前不被枚举
- 离线时 Tauri / Wails 恒显示「未知」：内置锚点补齐并校准为 Electron 44 · Chromium 152 · Tauri 2.11.5 · Wails 2.14.0
- dev 构建无法启动：adhoc 签名叠加 hardened runtime 后内嵌 Sparkle 过不了 library validation，应用起不来并连弹错误对话框

### 优化与体验

- 文案口径修正：面板与空状态的「基于 WebView / Chromium 的应用」改为「内嵌 Chromium / WebView 引擎的应用」
- 自研内核在详情弹层补一句说明：应用本体不是网页应用，只是内嵌了一份 Chromium 运行时
- 详情弹层的版本徽章不再重复类型名，四段式 UA 版本号不再被截断
- 无头扫描 CLI 的版本与体积列加宽，四段式版本号不再挤压后续列

### 代码质量

- 新增 15 个回归测试（重命名引擎、家族标记、子应用下钻、版本取信口径、系统 WebView 误报排除、枚举深度），共 33 个全绿
- 真机核对：本机检出由 18 个增至 22 个应用（新增 ChatGPT、微信、Typora、WPS Office），误报 0，全盘扫描约 15 秒
- detection-strategy.md 与三语 README / 官网分层卡片同步更新

