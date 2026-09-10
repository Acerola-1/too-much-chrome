# Too Much Chrome

> [English](README.en.md) · [日本語](README.ja.md) · [官网](https://acerola-1.github.io/too-much-chrome/)

<p align="center">
  <img src="docs/images/icon.png" width="132" alt="Too Much Chrome icon">
</p>

<p align="center">
  <strong>看看你的 Mac 里藏了多少网页引擎应用。</strong>
</p>

<p align="center">
  Too Much Chrome 扫描 macOS 上所有基于 Chromium / WebView 的应用——Electron、CEF、NW.js、
  Tauri、Wails、Flutter WebView、系统 WebView，以及 Chrome、Edge、Brave 这类完整浏览器——
  并统计它们占用的存储空间与版本健康度。名字是个梗，扫描是认真的。
</p>

<p align="center">
  <a href="https://github.com/Acerola-1/too-much-chrome/releases/latest"><strong>下载最新版</strong></a> ·
  <a href="https://acerola-1.github.io/too-much-chrome/"><strong>官网</strong></a> ·
  <a href="#功能亮点">功能亮点</a> ·
  <a href="#安装">安装</a> ·
  <a href="#系统要求">系统要求</a> ·
  <a href="#构建">构建</a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-M%20series-2ECC71?style=flat-square&logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-blue?style=flat-square">
  <img alt="SwiftPM" src="https://img.shields.io/badge/SwiftPM-5.9-orange?style=flat-square&logo=swift">
</p>

## 截图

### 扫描结果主界面

浮动玻璃工具栏与右侧报告面板同处一条主线：左侧网格按发现顺序逐个显现应用，扫描线光条即真实扫描进度；右侧一屏汇总总数、存储占用、类型分布环形图、Top 5 排行与版本健康度。

<p align="center">
  <img src="docs/images/app-hero-light.png" width="720" alt="Too Much Chrome 扫描结果主界面">
</p>

## 功能亮点

### 真实扫描

枚举 `/Applications` 与 `~/Applications` 下**两层** `.app`（含 `Utilities/` 与
`<浏览器> Apps.localized/` 里的 PWA 快捷方式），但不进入 `.app` 内部——那里是 helper 子应用。

Electron / CEF / NW.js 按框架目录名与 plist Bundle ID 双特征识别，接近 100% 准确率——
改名构建（如 QQNT.framework）仍保留 `com.github.Electron.framework`，是目录名之外的第二特征。
连 Bundle ID 一起换掉的（如 ChatGPT 的 `Codex Framework`）按框架二进制里的家族标记定家族
（`electron_browser` / `ELECTRON_` / `libcef` / `CefBrowser`）、内嵌 `Chrome/x.y.z.w` UA 串定内核版本。
引擎框架也不限于 `Contents/Frameworks`——微信的 XWeb 就在
`Contents/MacOS/WeChatAppEx.app/` 内，框架枚举会下钻到子应用一层。

两者都不是的 Chromium 派生内核单列为**「自研内核」**类型：微信 macOS 4.x 是 Qt 原生应用
（`Contents/Resources/wechat.dylib`，327MB），Chrome 来自它内嵌的小程序运行时（XWeb，内核 144、
387MB）。它不出现在"基于 WebView 的应用"里，但那份 Chromium 是硬盘上的真实占用，因此计入统计、
单列一类、并在详情弹层说明——这是本工具"你硬盘上有多少 Chromium"的口径。

Tauri / Wails 走 Bundle ID / 资源目录关键词与主二进制构建路径特征；Flutter WebView 要求
`FlutterMacOS.framework` 与 webview 插件同时在架（纯 Flutter 是自绘渲染，不算 Web 技术应用）；
系统 WebView 要求"链接 WebKit + 带独立前端入口 HTML"，并排除 Safari 扩展宿主与帮助文档目录。
后三类均为推断，实验性标注如实呈现。

### 体积统计

应用本体递归计算分配大小，加上 `~/Library` 用户数据（Application Support / Caches /
Containers / WebKit / Saved Application State / Logs），按 bundle id 与应用名双重匹配并去重。

### 版本健康度

按在线版本基准动态分档五档状态（绿 → 红）：Electron 走 npm registry、Chromium 走 Google
VersionHistory、Tauri 走 crates.io、Wails 走 Go module proxy；缓存 24 小时，单项失败沿用缓存值，
全部失败退内置锚点，离线照常可用。

框架 plist 里写的可能是厂商的应用版本而非内核版本，因此版本取信有口径：CEF 的大版本低于 20
一律拒收，改从框架二进制里的 `Chrome/` UA 串取真实内核（实测网易云 plist 写 3.1.11、真实内核
116）；Electron 则相反，大版本 1 起即合法，Electron 11 这类老版本要照实判"老旧"。

### 扫描线开场

复印机扫描线绑定真实扫描进度——光条位置即扫描进度，图标按发现顺序逐个去模糊显现。
「减少动态效果」开启时自动跳过动画。

### 报告面板与详情弹层

点击任意应用查看存储分解与安装路径，一键在 Finder 中显示；排行行与网格图标联动高亮，`⌘R` 随时重扫。

### Swift 原生，一次任务

Swift / SwiftUI 原生开发，macOS 26+ 自动启用液态玻璃（低版本回退毛玻璃材质）。
扫描在后台线程进行，主线程只做结果呈现，扫完即走，无常驻进程。

## 安装

1. 从 [Releases](https://github.com/Acerola-1/too-much-chrome/releases/latest) 下载最新版 `.dmg`
2. 打开 DMG，将 Too Much Chrome 拖入 Applications 文件夹
3. 从 Launchpad 或 Applications 启动，首次扫描自动开始

应用已通过 Apple 公证，下载后可直接打开。

## 系统要求

- macOS 14 及以上（macOS 26+ 自动启用液态玻璃）
- Apple Silicon（M 系列芯片，仅支持 arm64，不提供 Intel 版）

## 构建

SwiftPM 工程，Xcode 可直接打开 `Package.swift` 开发：

```bash
./launch.sh            # 一键构建 .app 并启动（内部走 scripts/build-app.sh dev）
./launch.sh cli        # 构建并运行无头扫描 CLI（tmc-scan）
swift build            # 编译全部 target
swift test             # 单元测试
swift run tmc-scan --online   # 无头扫描（在线版本基准分档）
```

对外分发（Developer ID 签名 + Apple 公证 + DMG）走 `scripts/build-app.sh`：

```bash
./scripts/build-app.sh release    # 组装 .app + Developer ID 签名（硬运行时 + 时间戳）
./scripts/build-app.sh notarize   # 提交 Apple 公证并 staple 票据
./scripts/build-app.sh dmg        # 生成并公证 DMG（对外分发物）
```

发布版本由 `scripts/release.sh` 驱动：更新版本号 → 生成发布说明 → 合入 main → 打 tag →
GitHub Actions 自动构建、签名、公证并发布 Release（详见 `.github/workflows/release.yml`）。

## Star History

<p align="center">
  <a href="https://star-history.com/#Acerola-1/too-much-chrome&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Acerola-1/too-much-chrome&type=Date&theme=dark" />
      <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Acerola-1/too-much-chrome&type=Date" />
      <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Acerola-1/too-much-chrome&type=Date" width="720" />
    </picture>
  </a>
</p>

<p align="center">
  如果这个项目对你有帮助，欢迎点一个 ⭐ 支持持续维护。
</p>

## 许可证

本项目采用 **GNU AGPL-3.0** 双许可模式：

- **开源使用**：源码公开，任何人可在 [AGPL-3.0](LICENSE) 条款下自由查看、修改、分发。
  按 AGPL 要求，任何基于本项目的衍生作品（含通过网络提供服务的情形）也必须以
  AGPL-3.0 开源其完整源码。
- **商业使用**：如果你希望在**不遵守 AGPL 开源义务**的前提下将本项目用于商业产品
  （例如闭源分发、上架收费而不公开源码），**必须获取商业授权**。
  请通过 [GitHub](https://github.com/Acerola-1/too-much-chrome) 提 Issue 或私信作者洽谈。

版权所有 © 2026 Acerola。保留所有权利。

### 第三方组件

本项目唯一的第三方依赖是 **Sparkle**（自更新框架）—— MIT 类许可；
其余全部使用系统框架（SwiftUI / AppKit / Foundation）。
