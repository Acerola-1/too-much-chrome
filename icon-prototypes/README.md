# 图标原型（5 概念）

CoreGraphics 程序化绘制，符合 macOS 图标规范：超级椭圆（squircle, n≈4.8）、
824/1024 内容幅面、透明圆角、无文字、小尺寸可辨。每个概念含
1024 母版（`master.png`）、全尺寸 `AppIcon.iconset/`、以及 Icon Composer
可直接打开的 `AppIcon.icns`。

| 目录 | 概念 | 叙事 |
|---|---|---|
| `A-scanline/` | 扫描发现 | 品牌色应用网格 + 青色扫描线（呼应开场动画） |
| `B-atom/` | Chromium 原子 | 原子核 + 三条电子轨道（Electron 本源） |
| `C-pile/` | 堆积超载 | 彩色应用芯片堆山外溢（"too much" 直译） |
| `D-lens/` | 放大镜检视 | 镜下小网格 + 扫描线（温和的扫描工具感） |
| `E-brand-lens/` | 放大镜 + 品牌图标 | 镜外散布品牌贴片，镜内 Chrome 三色圆为主角、Electron/Tauri 露边，扫描线横过——"在一堆应用里揪出那个 Chrome" |

`overview.png` 为全概念对比总览。

> **E 的品牌图形说明**：Chrome 三色圆 / Electron 轨道原子 / Tauri 渐变环 /
> VS Code 角括号 / Slack 四色井字均为程序化**风格化近似**（非官方资源文件），
> 个人项目使用无碍；若对外分发/商用，建议复核各商标方针对 logo 使用的具体政策。

## 用法

```bash
# 预览：Finder 打开 overview.png 或直接看各 master.png

# 用 Icon Composer 打开编辑（可继续做 Liquid Glass 分层/高光/暗色变体）：
open -a "Icon Composer" icon-prototypes/D-lens/AppIcon.icns

# 重新生成（改 MakeIcons.swift 里的配色/布局后）：
swift icon-prototypes/MakeIcons.swift
for d in A-scanline B-atom C-pile D-lens; do
  iconutil -c icns "icon-prototypes/$d/AppIcon.iconset" -o "icon-prototypes/$d/AppIcon.icns"
done
```

## 选定后接入应用

在 `scripts/build-app.sh` 组装 .app 时加入两步即可生效：

```zsh
cp icon-prototypes/<选中>/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Info.plist 模板中加： <key>CFBundleIconFile</key><string>AppIcon</string>
```

## 调参入口

所有几何与配色都是 `MakeIcons.swift` 里的具名常量/数组（调色板、贴片尺寸、
扫描线强度、轨道相位、堆叠布局），改完重跑生成命令即可，无需图像工具。
