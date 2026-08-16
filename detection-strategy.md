# Too-Much-Chrome 检测策略

## 目标

扫描 macOS 上所有基于 Chromium / WebView 技术的应用，帮助用户了解"自己的电脑上有多少 Chrome"。

## 检测分层

按准确率和实现难度分为三层：

### Tier 1: 高准确率（优先实现）

这些框架自带 Chromium 内核，有明确的文件特征，检测准确率接近 100%。

| 框架 | 检测特征 | 文件路径示例 |
|------|---------|-------------|
| **Electron** | `Electron Framework.framework` | `Foo.app/Contents/Frameworks/Electron Framework.framework` |
| **CEF** | `Chromium Embedded Framework.framework` | `Foo.app/Contents/Frameworks/Chromium Embedded Framework.framework` |
| **NW.js** | `nwjs Framework.framework` 或 `nwjs` 相关 | `Foo.app/Contents/Frameworks/nwjs Framework.framework` |

> **改名构建的补充特征（2026-08 实测）**：部分厂商会重命名框架目录躲过名称匹配
> （如 QQ NT 的 `QQNT.framework`），但框架 Info.plist 的 `CFBundleIdentifier`
> 仍为 `com.github.Electron.framework`——目录名与 plist Bundle ID 应双特征匹配。
> 版本号此时读框架 plist 的 `CFBundleVersion`（QQ 为 40.0.0）。

**版本号获取：**
- Electron: 读取 `Electron Framework.framework/Versions/A/Resources/Info.plist` 中的 `CFBundleVersion`
- CEF: 读取 `Chromium Embedded Framework.framework/Versions/A/Resources/Info.plist`
- NW.js: 读取应用自身 `Info.plist` 或框架内版本信息

### Tier 2: 中等准确率（实验性功能）

这些框架使用系统原生 WebView，没有独立 Chromium 内核，需要通过间接特征推断。

| 框架 | macOS WebView | 检测策略 | 准确率 |
|------|--------------|---------|--------|
| **Tauri** | WKWebView | Bundle ID 含 `tauri` / 资源目录含 `tauri.conf.json` | ~70% |
| **Wails** | WKWebView | Bundle ID 含 `wails` / 资源目录含 `wails` 相关文件 | ~60% |
| **Flutter WebView** | WKWebView (via webview_flutter) | 检测到 Flutter 框架 + WebView 插件 | ~50% |

**Tauri 具体检测逻辑：**

```
1. 读取 Info.plist 的 CFBundleIdentifier，检查是否包含 "tauri"
2. 扫描 Contents/Resources 目录，查找以下文件：
   - tauri.conf.json
   - .tauri 目录
   - 任何文件名包含 "tauri" 的文件
3. 扫描 Contents/MacOS 下的二进制文件，搜索字符串 "tauri"（性能差，仅对可疑应用使用）
```

**Wails 类似，替换关键词为 "wails"。**

> **2026-08 校准**：Tauri release 构建**不随包携带** `tauri.conf.json`（配置在构建期编译进二进制），
> 第 2 步对正式发布的应用基本无效。实测可靠的二进制标记（mmap 扫描主程序，≤256MB）：
> - Tauri：`src-tauri` / `tauri-`（cargo 构建路径）出现 ≥2 次；
>   或裸词 `tauri` ≥5 次且伴随 `.cargo`（Rust 上下文，排除 centauri 之类误报）
> - Wails：`wailsapp`（模块路径 `github.com/wailsapp/wails`）出现即命中
> - 已知局限：`wails build -obfuscated`（garble）会抹掉模块路径字符串，无法检测
>
> 本机实测命中：Clash Verge、DBX、GameHub（三者 Bundle ID 与资源目录均无 "tauri" 字样）。

### Tier 3: 完整浏览器（可选检测）

用户通常知道自己在用浏览器，但为完整性可列出。

| 浏览器 | 检测方式 |
|--------|---------|
| Google Chrome | 应用名匹配 |
| Microsoft Edge | 应用名匹配 |
| Chromium | 应用名匹配 |
| Brave | 应用名匹配 |
| Arc | 应用名匹配 |
| Vivaldi | 应用名匹配 |
| Opera | 应用名匹配 |

> **浏览器内核版本判定（2026-08 实现）**：Chromium 系浏览器的**应用主版本与内核主版本
> 严格对齐**（Edge 79+ / Chrome / Opera / Vivaldi 均如此），因此直接读应用 Info.plist 版本
> 对 Chromium 基准分档即可（Edge 151 = Chromium 151）。版本方案不对齐的（如 Arc 自有 1.x）
> 由主二进制中的 `Chrome/x.y.z.w` UA 串兜底提取；提取不到则诚实显示"未知"。

**注意：** 浏览器本身不是"嵌了 Chrome 的应用"，但用户可能想知道。UI 中应分组显示，避免混淆。

### Tier 4: 未知 WebView（低准确率，可选）

对无法归类但链接了 `WebKit.framework` 的应用，标记为"可能使用 WebView"。

**误报风险高：** 大量原生应用都链接了 WebKit（如邮件客户端、RSS 阅读器），不建议默认开启。

## 扫描路径

```
/Applications                    ← 系统级应用
~/Applications                   ← 用户级应用
/Library/Application Support     ← 部分企业软件（如 aTrust）
~/Library/Application Support  ← 部分用户安装的应用
```

**App Store 限制：** 沙箱应用无法访问 `/Applications` 和 `/Library`，需要用户手动授权"完整磁盘访问权限"。

## 版本号与老旧判定

### Electron 版本对照表（建议标红阈值）

> **2026-08 重新校准**：下表为文档初版（Electron 33 时代）的历史值，已过时约 10 个大版本。
> 当前稳定版 **43.4.0**（Chromium ~149），官方支持窗口 = 最新 3 个主版本。现行分档
> （实现见 `VersionBands`，锚定常数需定期重估）：
>
> | Electron | 状态 | 建议 |
> |---|---|---|
> | ≥ 41 | ✅ 当前 | 官方支持窗口内 |
> | 36–40 | ✅ 正常 | 一年内版本 |
> | 31–35 | ⚠️ 建议更新 | 1–2 年前版本 |
> | ≤ 30 | 🔴 老旧 | 两年以上 |
>
> CEF 按 Chromium 对齐（当前稳定 151）：≥148 当前 · 139–147 正常 · 128–138 偏旧 · ≤127 老旧。
> 另注意：部分厂商会把**应用自身版本**塞进框架 plist（实测 NeteaseMusic CEF 的 "3.1.10"、
> aTrust 的 "11.5.0"）——大版本早于引擎存在年代时应判"未知"而非"老旧"。

> **在线版本基准（2026-08 已实现，`VersionCatalog`）**：锚点不再依赖人工更新——
> 启动后从官方源拉取最新版（Electron→npm registry · Chromium→Google VersionHistory API ·
> Tauri→crates.io · Wails→Go module proxy），缓存 24h（~/Library/Caches/），
> 单项失败沿用缓存值，全部失败退内置常数。Tauri/Wails 的运行时版本从主二进制提取
> （cargo 路径 `tauri-2.10.3/…` / Go module info `wails/v2 v2.11.0`），
> 与在线锚做主/次版本距离分档。上表仅供离线兜底参考。

| Electron 版本 | Chromium 版本 | 状态 | 建议 |
|--------------|--------------|------|------|
| 33+ | 130+ | ✅ 当前 | 无需关注 |
| 30-32 | 124-129 | ⚠️ 较新 | 正常 |
| 28-29 | 120-123 | ⚠️ 一般 | 可接受 |
| 25-27 | 114-119 | ⚠️ 偏旧 | 建议更新 |
| 22-24 | 108-113 | 🔴 老旧 | 建议更新 |
| < 22 | < 108 | 🔴 很老 | 强烈建议更新 |

### CEF 版本对照表

CEF 版本号通常和 Chromium 版本对齐（如 CEF 120 = Chromium 120），可直接用 Chromium 版本判断。

## 检测实现伪代码

```swift
enum AppType {
    case electron(version: String?)
    case cef(version: String?)
    case nwjs(version: String?)
    case tauri          // 实验性
    case wails          // 实验性
    case browser        // 完整浏览器
    case unknownWebView // 低准确率
}

struct DetectedApp {
    let name: String
    let path: String
    let type: AppType
    let isOutdated: Bool
    let icon: NSImage
}

func detectApp(at path: String) -> DetectedApp? {
    // Tier 1: 自带 Chromium 内核的框架
    if let version = detectElectron(at: path) {
        return DetectedApp(name: name, path: path, type: .electron(version: version),
                          isOutdated: isElectronOutdated(version), icon: icon)
    }
    if let version = detectCEF(at: path) {
        return DetectedApp(name: name, path: path, type: .cef(version: version),
                          isOutdated: isCEFOutdated(version), icon: icon)
    }
    if let version = detectNWJS(at: path) {
        return DetectedApp(name: name, path: path, type: .nwjs(version: version),
                          isOutdated: false, icon: icon)
    }
    
    // Tier 3: 浏览器
    if isBrowser(at: path) {
        return DetectedApp(name: name, path: path, type: .browser,
                          isOutdated: false, icon: icon)
    }
    
    // Tier 2: 系统 WebView 框架（实验性）
    if isTauriApp(at: path) {
        return DetectedApp(name: name, path: path, type: .tauri,
                          isOutdated: false, icon: icon)
    }
    if isWailsApp(at: path) {
        return DetectedApp(name: name, path: path, type: .wails,
                          isOutdated: false, icon: icon)
    }
    
    // Tier 4: 未知 WebView（可选，默认关闭）
    if scanUnknownWebView && linksWebKit(at: path) {
        return DetectedApp(name: name, path: path, type: .unknownWebView,
                          isOutdated: false, icon: icon)
    }
    
    return nil
}
```

## UI 展示建议

### 分组显示

```
📦 自带 Chromium 内核（高准确率）
   ├── Electron 应用 (7)
   │   ├── Trae CN        v39.2.7   🔴
   │   ├── Qoder          v42.2.0   ✅
   │   └── ...
   ├── CEF 应用 (2)
   └── NW.js 应用 (1)

🌐 系统 WebView 应用（实验性检测）
   ├── Tauri 应用 (?)    [可能不准确]
   └── Wails 应用 (?)    [可能不准确]

🌍 浏览器（完整浏览器）
   ├── Google Chrome
   └── Microsoft Edge
```

### 版本状态标识

| 标识 | 含义 |
|------|------|
| ✅ | 版本较新，无需关注 |
| ⚠️ | 版本一般，可更新 |
| 🔴 | 版本老旧，建议更新 |
| ❓ | 无法获取版本号 |

## 已知局限

1. **Tauri/Wails 检测依赖二进制特征**，garble 等混淆构建会抹掉标记；开发者刻意隐藏时无法检测
2. **无法区分"用了 WebView"和"基于 WebView 构建"** — 很多原生应用内嵌了网页视图，但不是 WebView 应用
3. **动态加载的 WebView 无法检测** — 应用运行时下载的组件，静态扫描扫不到
4. **App Store 沙箱限制** — 需要用户授权完整磁盘访问权限
5. **改名/自研内核不在 Tier 1 特征内** — 微信的 XWeb（Chromium 派生，框架名 WCDY 等自研命名）
   目前不检出，如需支持要单列专门签名（2026-08 实测确认）
6. **用户数据匹配按 bundle id / 应用名**，使用自定义存储路径（如直接写 `~/Documents`）的应用会漏计；
   现覆盖 Application Support / Caches / Containers / WebKit / Saved Application State / Logs 六处
7. **扫描器永不报告自身** — 本工具的二进制内嵌检测关键词字面量（"wailsapp"/"src-tauri" 等），
   扫描自己必然误报 Wails，故按 bundle id（`com.acerola.too-much-chrome`）无条件跳过任意副本

## 参考项目

- [SafariYYDS](https://github.com/Lakr233/SafariYYDS) — macOS Electron/Rosetta/VSCode 扫描器（SwiftUI）
- [CEF Detector](https://github.com/ShirasawaSama/CefDetector) — Windows 版 CEF 检测器
