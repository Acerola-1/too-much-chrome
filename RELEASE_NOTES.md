## 更新内容

### 修复

- 安装体验修复：DMG 改为标准安装布局（应用 + Applications 文件夹链接），打开即可拖入安装
- 从安装镜像直接运行时弹窗引导先安装到 Applications（只读卷上自动更新无法工作）

### 代码质量

- CI 用 GITHUB_RUN_NUMBER 作为 CFBundleVersion，修复浅克隆下 build 号恒为 1、Sparkle 无法判断更新的问题

