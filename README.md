<p align="center">
  <img src="bento/Resources/BentoIcon.png" width="112" alt="Bento">
</p>

<h1 align="center">Bento</h1>
<p align="center"><strong>一个菜单栏，搞定窗口、截图和桌面工具。</strong></p>
<p align="center">按窗口切换 · 拖文件跨窗口 · 截图置顶与标注 · 外接屏亮度 · 独立滚动方向</p>
<p align="center">
  <a href="https://github.com/chansigit/bento/releases/latest"><strong>下载 Bento ↗</strong></a>
  &nbsp; · &nbsp;
  <a href="bento/README.md">使用指南</a>
  &nbsp; · &nbsp;
  <a href="https://github.com/chansigit/bento/releases/tag/v1.2.2">看看这次更新</a>
</p>
<p align="center"><sub>原生 macOS 应用 · Apple Silicon · 无第三方运行时依赖</sub></p>

---

写东西时来回找参考，截图后还要另开图片，鼠标和触控板总有一个滚反了……

Bento 把这些每天遇到的小事，收进一个菜单栏入口。按一下快捷键，处理好，继续手上的事。

## ⌘Tab，直接切到那一个窗口

一个应用开了好几个窗口？按住 <kbd>⌘</kbd>，轻点 <kbd>Tab</kbd>，直接在窗口缩略图之间选择。找到那份文档、那页参考，或藏在后面的终端，不用先切应用再翻窗口。

![Bento 窗口切换：按比例排列缩略图，突出当前选择](docs/images/window-switcher.png)

- **键盘和鼠标都顺手。** Tab 向前、Shift+Tab 向后；也可以直接移动鼠标选择。点击或松开 ⌘，切过去。
- **拖文件，顺便切窗口。** 抓住文件不放，打开切换器，悬停目标缩略图唤出窗口，再把文件放进去。
- **重新打开，接着看。** 复用内存中的缩略图，后台更新，让反复切换更连贯。

## ⌘1，截图直接变成桌面参考

<kbd>⌘</kbd> + <kbd>1</kbd> 框选截图，选区立即成为桌面贴图。原位置、原大小，像把一张便签放在手边。

![Bento 桌面贴图：在参考图上圈出重点、添加箭头](docs/images/desktop-sticker.png)

对照设计写代码、照着资料填表、把一段说明留在眼前。**拖着走，滚轮缩放**，用完就关掉。

需要讲清重点时，展开下边缘的编辑栏：画箭头、加文字、圈出细节，或者用马赛克和遮挡处理信息。编辑栏随时收起，标注继续保留；复制、保存 PNG 也都在手边。

![展开后的 Bento 贴图编辑栏](docs/images/sticker-tools.png)

剪贴板里的图片也能直接贴出来：<kbd>⌃</kbd> + <kbd>⌥</kbd> + <kbd>P</kbd>。想临时清爽一下桌面，再加 <kbd>⇧</kbd> 隐藏／显示全部贴图。

<sub>以上为 Bento 真实组件渲染，窗口及图片内容均为演示素材。贴图在退出应用后关闭；需要留存时请先保存。</sub>

## 把桌面调到顺手的状态

| 你想做的事 | Bento 随手帮一下 |
|---|---|
| 看一眼异地现在几点 | **世界时钟** · 多时区紧凑显示，中文、英文、拼音都能搜城市。 |
| 鼠标反着滚，触控板自然滚 | **独立滚动方向** · 两个设备分别设置。 |
| 外接屏太亮，Dock 又跑了 | **亮度与 Dock** · 调节支持 DDC/CI 的外接屏，固定 Dock 所在屏幕。 |
| 下载到底有没有在跑 | **实时网速** · 顶栏两行显示下载与上传，另可按需扫描 Wi-Fi 信号。 |
| 一堆文件夹，看着都一样 | **文件夹着色** · 八种颜色，在 Finder 里区分项目，也能恢复原图标。 |
| 不确定是不是开了大写 | **Caps Lock 提示** · 浮层、顶栏标记和可关闭的提示音。 |
| 跑任务时别让电脑睡着 | **防止休眠** · 一键临时保持唤醒。 |

菜单按功能分组，常用操作直接可见。Bento 用 AppKit + SwiftUI 构建，无第三方运行时依赖；截图与缩略图在本机内存处理，不上传。

## 下载，开始用

1. **[下载最新 DMG](https://github.com/chansigit/bento/releases/latest)**，把 Bento 拖入 Applications 并打开。
2. 按需为 `/Applications/Bento.app` 开启**辅助功能**与**屏幕录制**权限。菜单「Bento 设置 → 通用」可检查状态。
3. 按 **⌘Tab** 切一次窗口，再按 **⌘1** 贴一张参考图。

当前安装包面向 **Apple Silicon Mac**，最低声明系统版本为 macOS 11。应用使用自签名证书，未经过 Apple 公证；首次打开可能需要在「系统设置 → 隐私与安全性」中允许。

[权限与故障排查](bento/README.md) · [版本记录](https://github.com/chansigit/bento/releases) · [提建议或报告问题](https://github.com/chansigit/bento/issues)

<details>
<summary>外观与语言</summary>

支持 15 款皮肤与 17 种语言，可在「Bento 设置 → 外观」切换。菜单、设置、窗口切换器及贴图编辑栏统一跟随皮肤；截图保持原色。

语言包括简体中文、繁體中文、English、日本語、한국어、Français、Español、Tiếng Việt、Svenska、Русский、Norsk bokmål、Suomi、Deutsch、Italiano、Українська、Kiswahili、Português (Brasil)。译文尚未经过全部语种的母语校对。

</details>

<details>
<summary>想自己编译？</summary>

准备好 Xcode Command Line Tools，然后：

```sh
git clone https://github.com/chansigit/bento.git
cd bento/bento
BUILD_ONLY=1 ./build.sh  # 测试、构建、签名
./build.sh              # 构建、安装并重启
./make-dist.sh          # 打包 DMG
```

源码、资源与构建脚本在 [`bento/`](bento/)。构建会检查核心逻辑、窗口切换、截图标注、菜单交互、皮肤和语言资源；安装前备份旧应用，并检查签名身份。

Bento 前身为 GTime，内部 bundle ID 保持 `com.sijie.gtime`，以延续设置与权限。窗口切换已集成，无需另装 WinTab。

</details>
