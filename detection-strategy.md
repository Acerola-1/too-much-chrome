# Too-Much-Chrome 检测策略

## 目标

扫描 macOS 上所有基于 Chromium / WebView 技术的应用，帮助用户了解"自己的电脑上有多少 Chrome"。

## 检测分层

按准确率和实现难度分为四层，**判定顺序即下表顺序**（高置信特征先判，避免被低置信特征抢先）：

### Tier 1: 高准确率（自带 Chromium 内核）

这些框架自带 Chromium 内核，有明确的文件特征，检测准确率接近 100%。

| 框架 | 检测特征 | 文件路径示例 |
|------|---------|-------------|
| **Electron** | `Electron Framework.framework` | `Foo.app/Contents/Frameworks/Electron Framework.framework` |
| **CEF** | `Chromium Embedded Framework.framework` | `Foo.app/Contents/Frameworks/Chromium Embedded Framework.framework` |
| **NW.js** | `nwjs Framework.framework` 或 `nwjs` 相关 | `Foo.app/Contents/Frameworks/nwjs Framework.framework` |
| **自研内核** | 名字与 Bundle ID 均为厂商自有，靠二进制家族标记 + Chrome UA 串辨认 | 微信 `Contents/MacOS/WeChatAppEx.app/…/WeChatAppEx Framework.framework` |

**双特征匹配（2026-08 实测）**：部分厂商会重命名框架目录躲过名称匹配（如 QQ NT 的
`QQNT.framework`），但框架 Info.plist 的 `CFBundleIdentifier` 仍为
`com.github.Electron.framework`——目录名与 plist Bundle ID 双特征匹配。版本号此时读框架
plist 的 `CFBundleVersion`（QQ 为 40.0.0）。

**框架根不限于 `Contents/Frameworks`（2026-09 实测）**：部分厂商把引擎放在子应用里，
`Contents/Frameworks` 顶层根本看不到：

| 应用 | 引擎实际位置 |
|------|-------------|
| 微信 | `Contents/MacOS/WeChatAppEx.app/Contents/Frameworks/` |
| WPS Office | `Contents/SharedSupport/browserserver.app/Contents/Frameworks/` |
| WPS Office | `Contents/Frameworks/office6/addons/cef/` |

因此框架枚举覆盖 `Contents/Frameworks` **以及** `Contents/<任意子目录>/<子应用>.app/Contents/Frameworks`。
只看顶层会漏掉微信（其顶层 Frameworks 里最大的只是 51MB 的业务动态库，真正的内核 387MB 在子应用内）。

#### 重命名引擎兜底（2026-09 实测）

部分厂商不只改目录名，连框架 plist 的 Bundle ID 一起换成自有标识，两条身份特征同时失效。
此时只剩框架二进制自身可辨，两步走：**先用家族标记定家族，再用内嵌 UA 串定内核版本**。

**第一步：家族标记。** 只对**主二进制 ≥20MB 的框架**做检查（真实引擎是 100MB 量级，
实测最小 128MB），在二进制里找各组框架的内嵌符号名：

| 框架 | `electron_browser` | `ELECTRON_` | `libcef` | `CefBrowser` | 判定 |
|------|-------------------|-------------|----------|--------------|------|
| Obsidian（Electron） | 8 | 16 | 0 | 0 | Electron |
| QQNT（Electron 改名） | 10 | 16 | 0 | 0 | Electron |
| Codex Framework（ChatGPT） | 3 | 6 | 0 | 0 | Electron |
| Qoder（Electron） | 42 | 27 | 0 | 0 | Electron |
| 网易云 CEF | 0 | 0 | 12 | 2 | CEF |
| 企业微信 CEF | 0 | 0 | 8 | 4 | CEF |
| **微信 XWeb** | **0** | **0** | **0** | **0** | **自研内核** |

全机普查 11 个真 Electron 框架与 2 个真 CEF 框架，两组标记互不误报。
三组全为 0 时判为**厂商自研的 Chromium 派生内核**。

**第二步：内核版本。** 框架二进制里带 `Chrome/x.y.z.w` UA 串，即证明它在分发 Chromium，
该串就是它实际携带的内核版本。全盘普查（所有嵌套位置、≥10MB 的框架）中，
含 `Chrome/` UA 串的框架无一例外都是真实引擎，误报面为零。

> **实测微信 XWeb（`com.tencent.flue.framework`）**：框架内嵌
> `Chrome/144.0.7559.236`、`blink::` 55 次、`content::` 10 次、`node::` 192 次，
> 但 `electron_browser` / `ELECTRON_` / `libcef` / `CefBrowser` **全部为 0**。
>
> ⚠️ 这里踩过一个坑：早期用「Electron = Chromium + Node.js」的推理，只看 `node::`
> 是否存在来分家族，于是把微信误标成了 Electron。**带 Node 不等于 Electron**——
> 腾讯的 XWeb 同样内嵌 Node.js。家族必须由框架自己的标记认定，不能由"含有哪些组件"反推。

#### 微信：原生 Qt 应用 + 内嵌的小程序内核（2026-09 实测）

微信是本层最需要注意口径的一个：**它不是网页应用，但确实在分发一份完整 Chromium**。

| 组件 | 体积 | 技术栈 |
|------|------|--------|
| `Contents/MacOS/WeChat` + `libwxld.dylib` | 184 KB | 薄启动器 |
| `Contents/Resources/wechat.dylib` | 327 MB | **Qt Widgets 原生界面**（`QWidget` 92 次、`QApplication` 18 次、`QMetaObject` 4 次；无 `QtWebEngine` / `QWebEngineView`） |
| `Contents/MacOS/WeChatAppEx.app/…/WeChatAppEx Framework.framework` | 387 MB | **自研 Chromium 内核**（XWeb，内核 144：`blink::` 55 次、`content::` 10 次、`node::` 192 次） |
| `Contents/Frameworks/mmcronet.framework` | 14 MB | Cronet（Chromium 网络栈） |
| 系统 WebKit 链接 | — | 普通内置网页走系统 WebView |

所以微信 macOS 4.x 是 **Qt 原生应用 + 内嵌 Chromium 小程序运行时**，
与"基于 Electron 构建"完全是两回事。它出现在列表里的理由只有一个：
本工具的承诺是"你硬盘上有多少 Chromium 代码、它有多旧"，
而这 387MB 的 Chromium 内核是真实占用（实测内核 144，占比微信本体 1.43GB 的四分之一）。

> **口径**：计入，但**不叫"基于 WebView 的应用"**。UI 里用独立类型「自研内核」单列，
> 与 Electron/CEF 在分段过滤、环形图、配色上都分开，详情弹层另有一句说明，
> 避免用户误以为微信是 Electron 应用。同类还有支付宝、钉钉等自研内核应用。

**`app.asar` 兜底**：`Contents/Resources/app.asar` 是 Electron 打包应用代码的档案。
只有在家族标记与 UA 串都读不到时才用它，并默认按 Electron 记录——此时无从查证家族，
asar 属 Electron 生态是默认假设（本机唯一命中者 ChatGPT 已由标记独立佐证为 Electron）。

**版本号获取：**
- Electron: 框架 Info.plist 的 `CFBundleShortVersionString`，为空时退 `CFBundleVersion`
- CEF: 框架 Info.plist 版本；不可信时退框架二进制内的 `Chrome/` UA 串（见下节）
- NW.js: 应用自身 `Info.plist`

### Tier 2: 中等准确率（实验性功能）

这些框架使用系统原生 WebView，没有独立 Chromium 内核，需要通过间接特征推断。

| 框架 | macOS WebView | 检测策略 | 准确率 |
|------|--------------|---------|--------|
| **Tauri** | WKWebView | 二进制内 cargo 构建路径 | 高（见下） |
| **Wails** | WKWebView | 二进制内 Go 模块路径 | 高（见下） |
| **Flutter WebView** | WKWebView（经 webview 插件） | `FlutterMacOS.framework` + webview 插件框架 | 中 |

**Tauri / Wails 具体检测逻辑：**

Tauri release 构建**不随包携带** `tauri.conf.json`（配置在构建期编译进二进制），
按资源目录找配置文件对正式发布的应用基本无效。实测可靠的二进制标记（mmap 扫描主程序，≤256MB）：

- Tauri：`src-tauri` / `tauri-`（cargo 构建路径）出现 ≥2 次；
  或裸词 `tauri` ≥5 次且伴随 `.cargo`（Rust 上下文，排除 centauri 之类误报）
- Wails：`wailsapp`（模块路径 `github.com/wailsapp/wails`）出现即命中
- 已知局限：`wails build -obfuscated`（garble）会抹掉模块路径字符串，无法检测

> 本机实测命中：Clash Verge、DBX、GameHub、CC Switch（Bundle ID 与资源目录均无 "tauri" 字样）。

**Flutter WebView**：Flutter 本身是自绘渲染，**不承载网页**——只有引入 webview 插件才算
Web 技术应用。判据为 `Contents/Frameworks` 同时存在 `FlutterMacOS.framework` 与下列之一：
`inappwebview`、`webview_flutter`、`desktop_webview_window`、`flutter_webview`。

> 本机 3 个 Flutter 应用（Reqable、DartShell Pro、企业微信）均无 webview 插件，
> 因此本机该类型检出为 0——这是正确结果，不是检测失效。

### Tier 3: 完整浏览器（仅列出）

| 浏览器 | 检测方式 |
|--------|---------|
| Google Chrome | 应用名 / Bundle ID |
| Microsoft Edge | 应用名 / Bundle ID |
| Chromium | 应用名 / Bundle ID |
| Brave | 应用名 / Bundle ID |
| Arc | 应用名 / Bundle ID |
| Vivaldi | 应用名 / Bundle ID |
| Opera / Opera GX | 应用名 / Bundle ID |

> **浏览器必须排在重命名引擎兜底之前**：Edge 的框架里嵌着**过期的** `Chrome/70.0.3538.102`
> UA 串（实际内核 152），先走 UA 兜底会把浏览器误判成 Electron。
>
> **内核版本判定**：Chromium 系浏览器的应用主版本与内核主版本严格对齐
> （Edge 79+ / Chrome / Opera / Vivaldi 均如此），直接读应用 Info.plist 版本即可；
> 版本方案不对齐的（如 Arc 的 1.x）由主二进制中的 `Chrome/x.y.z.w` UA 串兜底提取，
> 提不到则诚实显示"未知"。

**注意：** 浏览器本身不是"嵌了 Chrome 的应用"，但用户可能想知道。UI 中单独分组，避免混淆。

**已知局限**：Tier 3 是一份**白名单**。白名单外的 Chromium 系浏览器（Thunderbird 之类的
小众派生、厂商自研浏览器）会落到重命名引擎兜底，被报成 Electron/CEF。这类应用确实在分发
Chromium，归类偏差仅影响类型标签，不影响计数与体积。

### Tier 4: 系统 WebView（实验性）

**仅"链接了 `WebKit.framework`"判不出来**：本机 80 个应用里 23 个链接 WebKit，绝大多数
只是拿它做局部功能（邮件预览、内嵌帮助）。叠加条件后可收敛到真正的 WebView 承载型：

```
链接 WebKit.framework
  AND Contents/Resources 或其一级子目录内存在前端入口 HTML
      （index.html / main.html / app.html）
  AND 不是 Safari 扩展宿主（Contents/PlugIns/*.appex）
```

- **链接判定**：Mach-O 的 `LC_LOAD_DYLIB` 原样保存安装路径，因此主二进制内搜
  `WebKit.framework/Versions` 与 `otool -L` 结果逐应用核对一致，无需起子进程
- **排除文档目录**：帮助文档也常以 `index.html` 分发（实测 LibreOffice 的
  `Resources/help/`），故跳过 `help` / `docs` / `manual` / `guide` / `samples` 等目录名
- **排除扩展宿主**：Safari 扩展的网页由 Safari 加载，不在宿主的 WebView 里。
  实测 `Microsoft Rewards for Safari` 与 `Doubao Extension` 都带
  `Resources/Main.html` + `Script.js` + `Style.css`，看着像前端资源，实际是扩展弹窗；
  两者都有 `Contents/PlugIns/<名> Extension.appex`，据此排除

> 本机实测：23 个链接 WebKit 的应用中只有 **Typora** 命中
> （`Contents/Resources/TypeMark/index.html`，主程序仅 3.3MB、无任何 Chromium 框架）。
> 加上上述两条排除后，两个扩展宿主不再误报，误报数为 0。

## 扫描路径

```
/Applications                          ← 系统级应用（顶层）
/Applications/Utilities/*.app         ← 直接子目录内的应用
~/Applications/*.app                   ← 用户级应用（顶层）
~/Applications/*/*.app                 ← PWA 快捷方式等（<浏览器> Apps.localized/）
~/Library/Application Support/<名>/<名>.AppBundle/   ← 引导壳应用的真实客户端（Steam，按需下钻）
```

枚举**两层但绝不进入 `.app` 内部**——`Contents/Frameworks/*.app` 是 Electron helper
子应用，不是独立安装的应用。

> 实测：本机 75 个顶层 + 3 个用户级 + 1 个 `Utilities/` + 2 个 `/Applications/Python 3.12/`
> = 80 个候选，全程约 15 秒。
>
> `/Applications/Safari.app` 是**隐藏**的符号链接（指向 Cryptexes 内的系统应用），
> 被 `skipsHiddenFiles` 跳过；其 `detect` 结果本就为 nil（无 Chromium 框架、
> 也无 WebView 承载特征），无影响。

**引导壳应用（2026-08 实测，Steam）**：`/Applications/Steam.app` 只是微型引导器
（Frameworks 仅 Breakpad），真实客户端自更新到
`~/Library/Application Support/Steam/Steam.AppBundle/Steam/`——包根**不带 .app 后缀**，
其 Frameworks 内才是真正的 `Chromium Embedded Framework.framework`（实测 CEF 126）。
处理：顶层应用所有特征落空时，回退下钻 `<AppSupport>/<名>/<名>.AppBundle/` 下带
`Contents/Info.plist` 的直接子目录再检一次；报告路径指向真实客户端。
体积口径：数据目录扣除客户端本体（避免与本体重复计）与 `steamapps` 游戏安装内容
（非 Chrome 内核，本机实测 29GB）；Steam 本体约 1.2GB。

**App Store 限制：** 沙箱应用无法访问 `/Applications` 和 `/Library`，需要用户手动授权"完整磁盘访问权限"。

## 版本号与老旧判定

> **2026-09 重新校准**：内置锚 **Electron 44**（npm registry 实查 44.3.0）、
> **Chromium 152**（本机 Edge 152.0.41912.89，Edge 主版本与内核对齐）。
> 现行分档（实现见 `VersionBands`，锚点由 `VersionCatalog` 在线刷新，内置值为离线兜底）：
>
> | 类型 | 当前 | 正常 | 建议更新 | 老旧 |
> |---|---|---|---|---|
> | Electron（锚 44） | ≥ 42 | ≥ 37 | ≥ 32 | < 32 |
> | CEF / Chromium（锚 152） | ≥ 149 | ≥ 140 | ≥ 129 | < 129 |
> | Tauri（锚 2.11.5） | 次版本差 ≤2 | 差 ≤6 | 更远 | 主版本落后 ≥2 |
> | Wails（锚 2.14.0） | 同上 | 同上 | 同上 | 同上 |
>
> 离线时用内置锚，照常分档（内置锚**必须**包含 Tauri/Wails——否则这两个类型的运行时版本
> 明明从二进制里提出来了，却恒判"未知"）。

### 框架 plist 里的版本号可能是假的

厂商常把**应用自身版本**写进框架 plist，两个类型的可信口径不同：

**Electron —— 小大版本要采信**。Electron 的大版本从 1 开始就合法，Electron 11（Chromium 87）
这类老版本真实存在。实测 aTrust 的框架 plist 写 `11.5.0`，框架二进制 UA 为
`Chrome/87.0.4280.141`——11.5.0 **就是**真实的 Electron 11，应判"老旧"。
早期实现用"大版本 ≥20"当合理性防线，把它误判成"未知"，等于放过了明显该更新的引擎。
现在的采信区间是 `1 … 锚+20`。

**CEF —— 低于 20 一律拒收，用 UA 兜底**。实测网易云 CEF 框架 plist 写的是应用版本
`3.1.11`，而框架二进制里的 UA 是 `Chrome/116.0.5845.190`——真实内核是 **116**（应判老旧）。
若直接采信 3.1.11 会按 Chromium 3 分档（结论碰巧也是"老旧"，但版本号是错的）。
现在的口径：plist 大版本 ≥20 采信（企业微信 138.0.57.0、Steam 126.0.0.0 均正确），
否则用框架二进制内的 `Chrome/` UA 串；两者都拿不到才判"未知"。

**框架 plist 写成 Chromium 方案时按 Chromium 分档**：ChatGPT 的框架版本为
`152.0.7977.83`，152 不是 Electron 大版本。分档函数发现大版本超过 `锚+20` 即改走
Chromium 阈值，而不是拿 152 去比 Electron 锚点。

### 在线版本基准（`VersionCatalog`）

启动后从官方源拉取最新版，缓存 24h（`~/Library/Caches/`），单项失败沿用缓存值，
全部失败退内置常数：

| 来源 | 用途 |
|---|---|
| npm registry | Electron |
| Google VersionHistory API | Chromium |
| crates.io | Tauri |
| Go module proxy | Wails |

Tauri/Wails 的运行时版本从主二进制提取（cargo 路径 `tauri-2.10.3/…` /
Go module info `wails/v2 v2.11.0`），与在线锚做主/次版本距离分档。

## 已知局限

1. **Tauri/Wails 依赖二进制特征**，garble 等混淆构建会抹掉标记；开发者刻意隐藏时无法检测
2. **无 webview 插件的纯 Flutter 应用不检出**——这是有意的，它们不承载网页
3. **Tier 3 浏览器是白名单**，名单外的 Chromium 系浏览器会被归到 Electron/CEF（见 Tier 3 注）
4. **无法区分"用了 WebView"和"基于 WebView 构建"** — 很多原生应用内嵌了网页视图，但不是 WebView 应用
5. **动态加载的 WebView 无法检测** — 应用运行时下载的组件，静态扫描扫不到
6. **App Store 沙箱限制** — 需要用户授权完整磁盘访问权限
7. **重命名引擎兜底依赖框架二进制 ≥20MB** — 极小的裁剪版引擎会漏掉；且 UA 串被抹掉的
   加固构建同样无法识别（`Chrome/` 串是兜底的关键，不是可选信息）
8. **Cronet 不算命中**：`mmcronet.framework` / `libreqable_cronet.dylib` 是 Chromium 的
   **网络栈**而非渲染内核（微信、Reqable 都有）。它确实是一份 Chromium 代码，但不代表
   应用在用 WebView 渲染页面，故不作为命中依据
9. **用户数据匹配按 bundle id / 应用名**，使用自定义存储路径（如直接写 `~/Documents`）的应用会漏计；
   现覆盖 Application Support / Caches / Containers / WebKit / Saved Application State / Logs 六处
10. **扫描器永不报告自身** — 本工具的二进制内嵌检测关键词字面量（"wailsapp"/"src-tauri" 等），
    扫描自己必然误报 Wails，故按 bundle id（`com.acerola.too-much-chrome`）无条件跳过任意副本

## 参考项目

- [SafariYYDS](https://github.com/Lakr233/SafariYYDS) — macOS Electron/Rosetta/VSCode 扫描器（SwiftUI）
- [CEF Detector](https://github.com/ShirasawaSama/CefDetector) — Windows 版 CEF 检测器
