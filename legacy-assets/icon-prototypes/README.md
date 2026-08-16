# 图标原型（概念 E · 已选定）

CoreGraphics 程序化绘制，符合 macOS 图标规范：超级椭圆（squircle, n≈4.8）、
824/1024 内容幅面、透明圆角、无文字、小尺寸可辨。产物含
1024 母版（`master.png`）、全尺寸 `AppIcon.iconset/`、`AppIcon.icns`
（传统格式，macOS 25 及以下兼容）与 macOS 26 分层 `AppIcon.icon`。

| 目录 | 概念 | 叙事 |
|---|---|---|
| `E-brand-lens/` | 放大镜 + 四方格品牌图标 | 镜内 2×2 整齐排列 Chrome / Electron / Tauri / VS Code，细扫描线沿行间隙横贯——"检视经典 WebView 框架"；**已按 macOS 26 分层标准输出 Icon Composer 源**（见下） |

早期概念 A-D（扫描发现/原子/堆积/早期放大镜）已归档至
`legacy-assets/icon-concepts/`，对应绘制代码可从 git 历史找回。

## 概念 E · macOS 26 分层图标（Icon Composer 工作流）

新 `.icon` 格式是分层 bundle：系统对 Front 层施加 Liquid Glass 光学、
明暗五外观与倾斜视差。概念 E 天然适配两层结构——
**Background = 底渐变 + 四方格品牌网格 + 扫描线；Front = 放大镜（透明底）**，
视差时放大镜真的"浮"在网格上检视。

### 直接可用的 `AppIcon.icon`（Icon Composer 双击即开）

`E-brand-lens/AppIcon.icon/` 是已组装好的分层 bundle（macOS 26 格式：
`icon.json` + `Assets/`，与 Icon Composer 导出结构一致，已过
`xcrun actool` 编译验证）：

| 层 | 图像 | 属性 |
|---|---|---|
| Lens（Front） | `Assets/front.png` | glass 开启，系统接管镜片高光 |
| Background | `Assets/background-dark.png` | 只填默认槽 = **深色优先**（明暗外观均为深底） |

配色决策：浅色底曾显得泛白（中心白光晕 + 低饱和渐变），四枚彩色 logo
不突出；故默认外观改为**深靛青渐变 + 镜心蓝色晕光**，logo 在深底上最跳。
另备提饱和浅色版（去掉白光晕，两端各加深一档），需要时在 Icon Composer
里给 Background 层导入 `icon-src/background-light.png` 作为 Light 外观即可。

```bash
# 打开编辑（也可直接双击 AppIcon.icon）
open -a "Icon Composer" icon-prototypes/E-brand-lens/AppIcon.icon

# 编译进 app（无需 Xcode 工程）
xcrun actool icon-prototypes/E-brand-lens/AppIcon.icon --compile ./out \
  --output-partial-info-plist ./out/icon.plist --app-icon AppIcon \
  --include-all-app-icons --target-device mac \
  --minimum-deployment-target 26.0 --platform macosx
# out/Assets.car + Info.plist 配 CFBundleIconName=AppIcon
```

分层源 PNG（重新生成/手工组装时用，均 1024×1024）：

| 文件 | 层 | 说明 |
|---|---|---|
| `background-light.png` | Background · 浅色备选 | 提饱和浅青→蓝（默认未启用） |
| `background-dark.png` | Background · 默认 | 深靛青渐变 + 镜心蓝晕光 + 品牌网格 |
| `front.png` | Front | 放大镜（精工银框/手柄/贴框内缘弧反光），背景全透明，镜片透出下层 |
| `preview-dark.png` / `preview-light.png` | 合成预览 | 明/暗两版 squircle 叠加效果对照 |

组装（如需手工重建而非用已生成的 `AppIcon.icon`；Icon Composer 位于
`/Applications/Xcode.app/Contents/Applications/`）：

1. 打开 Icon Composer → macOS 模板新建
2. Background 层：导入 `background-dark.png`（Default）；如需浅色外观，
   Light 槽导入 `background-light.png`
3. Front 层：导入 `front.png`（明暗同图即可，银色中性）
4. 保持 Specular 开启（高光弧是近白元素，系统玻璃会接管镜片质感——
   源图刻意克制避免叠加过曝）
5. 导出 `AppIcon.icon`

`.icon` 编译进 app（无需 Xcode 工程，macOS 26 SDK 的 actool）：

```bash
xcrun actool AppIcon.icon --compile ./out --output-format human-readable-text \
  --output-partial-info-plist ./out/icon.plist \
  --app-icon AppIcon --include-all-app-icons --target-device mac \
  --minimum-deployment-target 26.0 --platform macosx
# out/Assets.car + Info.plist 配 CFBundleIconName=AppIcon
```

macOS 25 及以下回退传统 `AppIcon.icns`（已同时生成，`CFBundleIconFile`）。

> **品牌图形说明**：四枚贴片均为**官方图标资源原样引用**（`official/` 目录，
> 不加白底贴片、不做统一 inset）：
> Chrome ← npm `@browser-logos/chrome`（Google 官方分发集，512px 圆形透明 PNG）·
> Electron ← 官网仓库 `electron/website` 的 `electron-logo.svg` 原子轨道 mark
> （官方色 #47848F，qlmanage 转 1024px PNG 后抠白底）·
> Tauri ← tauri.app 官网 logo 的 mark 部分（黄/青双色环，同上转制）·
> VS Code ← 官网 apple-touch-icon（256px 蓝底白丝带版）；
> 源 SVG 一并留存（`electron-mark.svg` / `tauri-mark.svg` 等）供溯源。
> `MakeIcons.swift` 缺图时回退手绘近似。商标权利归各所有方；本项目为个人
> 扫描工具的风格引用，若对外分发/商用请复核各商标方政策。

## 候选配色（挑选用）

`E-brand-lens/palettes/` 下每套含 `background-<name>.png`（分层源）与
`preview-<name>.png`（squircle 合成预览）；当前默认（`preview-dark.png`）
为深靛青。选定后把 `MakeIcons.swift` 里 `paletteDefaultDark` 换成对应
一套（`paletteCandidates` 里直接拷参数），重跑生成器即可全套重出。

| 名称 | 文件后缀 | 调性 |
|---|---|---|
| 深空紫 | `abyss-purple` | logo 全系无紫，对比最干净 |
| 碳黑 | `carbon` | 近纯黑 + 冷蓝晕光，最克制高级 |
| 深海青 | `abyss-teal` | 呼应 Tauri/Electron 的青，同色系 |
| 酒红 | `burgundy` | 暖色反差，冷色 logo 被衬得最亮 |
| 石墨蓝灰 | `graphite` | 中性不抢戏，纯工具感 |

## 用法

```bash
# 预览：Finder 打开 E-brand-lens/master.png 或 palettes/preview-*.png

# 用 Icon Composer 打开编辑（可继续调 Liquid Glass/高光/变体）：
open -a "Icon Composer" icon-prototypes/E-brand-lens/AppIcon.icon

# 重新生成（改 MakeIcons.swift 里的配色/布局后）：
swift icon-prototypes/MakeIcons.swift
iconutil -c icns icon-prototypes/E-brand-lens/AppIcon.iconset \
  -o icon-prototypes/E-brand-lens/AppIcon.icns
```

## 选定后接入应用

在 `scripts/build-app.sh` 组装 .app 时加入两步即可生效：

```zsh
cp icon-prototypes/<选中>/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Info.plist 模板中加： <key>CFBundleIconFile</key><string>AppIcon</string>
```

## 调参入口

背景配色全部集中在 `MakeIcons.swift` 的 `BgPalette` 结构（`paletteDefaultDark`
/ `paletteLight` / `paletteCandidates`）；放大镜与网格几何也是具名常量，
改完重跑生成命令即可，无需图像工具。
