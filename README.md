# Bento 🍱

<img src="bento/Resources/BentoIcon.png" width="112" alt="Bento 图标">

把常用的 macOS 小工具放进一个菜单栏应用：窗口切换、截图贴图、世界时钟、显示器亮度、实时网速，以及独立的鼠标与触控板滚动方向。

[下载安装包](https://github.com/chansigit/bento/releases/latest) · [完整使用说明](bento/README.md) · [反馈问题](https://github.com/chansigit/bento/issues)

## 功能

| 功能 | 使用方式 |
|---|---|
| 窗口切换 | **⌘Tab** 查看窗口缩略图；键盘或鼠标选择，点击或松开 ⌘ 切换。拖着文件时也可唤出目标窗口，继续拖放。 |
| 截图与桌面贴图 | **⌘1** 框选截图，原位置、原大小贴在桌面；拖动移动、滚轮缩放。展开下边缘编辑栏即可画箭头、写字、遮挡、打马赛克或撤销。 |
| 剪贴板贴图 | **⌃⌥P** 贴出剪贴板图片，**⌃⌥⇧P** 隐藏／显示全部贴图；支持复制和保存 PNG。 |
| 世界时钟 | 紧凑显示多个时区；支持中文、英文、拼音搜索城市，以及在线解析地名。 |
| 鼠标与触控板 | 分别选择自然或反向滚动。 |
| 显示器与 Dock | 内建／外接显示器亮度、Dock 固定到指定屏幕；外接亮度需要显示器和连接链路支持 DDC/CI。 |
| 网络 | 两行紧凑显示下载／上传速率；按需扫描附近 Wi-Fi 信号。 |
| 文件夹着色 | 为 Finder 文件夹设置颜色，并可恢复着色前的图标。 |
| Caps Lock 提示 | 大写锁定浮层、顶栏标记和可关闭的提示音。 |
| 防止休眠 | 一键临时保持系统及屏幕唤醒。 |

下拉菜单按「世界时钟」「窗口与输入」「截图与贴图」「文件与文件夹」「显示与连接」「Bento」分组。常用操作直接可见，详细选项放在子菜单中。

## 皮肤与语言

**15 款皮肤**：系统、浅色、深色、抹茶、海盐、蜜柑、樱花、薰衣草、玫瑰、沙丘、薄荷、午夜、极光、余烬、葡萄。

皮肤统一设置页、窗口切换面板、贴图编辑器以及下拉主菜单和子菜单的背景、卡片、边框、圆角与选中效果。截图和窗口缩略图本身保持原色。菜单可用鼠标悬停、点击及方向键操作，保留亮度滑块等原生控件。

**17 种语言**：简体中文、繁體中文、English、日本語、한국어、Français、Español、Tiếng Việt、Svenska、Русский、Norsk bokmål、Suomi、Deutsch、Italiano、Українська、Kiswahili、Português (Brasil)。

在「Bento 设置 → 外观」或菜单中的「外观」「语言」切换，即时生效并保存，也可跟随系统。翻译尚未经过全部语种的母语校对。

这里介绍的是当前源码功能；主题下拉菜单已加入源码，发行包包含的功能请查看对应 [Release 说明](https://github.com/chansigit/bento/releases)。

## 安装与权限

从 [Releases](https://github.com/chansigit/bento/releases/latest) 下载 DMG，将 **Bento.app** 拖入 **Applications**，然后打开。当前发行包面向 Apple Silicon Mac；应用使用自签名证书，尚未经过 Apple 公证，首次打开可能需要在系统设置的「隐私与安全性」中允许。

按需为 **`/Applications/Bento.app`** 授权：

- **辅助功能**：Cmd+Tab 窗口聚焦、快捷键拦截和滚动方向。
- **屏幕与系统音频录制／屏幕录制**：窗口缩略图和截图；未授权时切换器显示应用图标。
- **定位服务**：仅 Wi-Fi 扫描显示网络名称时需要。

在「Bento 设置 → 通用」可重新检查权限和缩略图状态。窗口切换已集成，无需另装 WinTab。截图和缩略图在本机内存处理，不上传；贴图在退出应用后关闭，需要保留的图片请先保存。

外接显示器无法调亮度时，请检查 DDC/CI 是否开启，以及 HDR、B.I.+ 等模式是否锁住硬件亮度。更多限制和排查方法见[详细说明](bento/README.md)。

## 从源码构建

需要 macOS 和 Xcode Command Line Tools，使用 AppKit + SwiftUI，无第三方运行时依赖。

```sh
git clone https://github.com/chansigit/bento.git
cd bento/bento
BUILD_ONLY=1 ./build.sh  # 测试、构建、签名，不替换当前应用
./build.sh              # 测试、构建、安装并重新启动 Bento
./make-dist.sh          # 打包 DMG
```

构建会检查核心逻辑、窗口切换、截图标注、菜单交互、皮肤和全部语言资源。安装前备份旧应用；签名身份不一致时停止覆盖，避免影响现有权限。源码兼容 Swift 5.4 / macOS 11.3 SDK，运行于 macOS 11+。

Bento 前身为 GTime；为延续设置与权限，内部 bundle ID 保持 `com.sijie.gtime`。代码、资源与构建脚本都在 [`bento/`](bento/) 目录。
