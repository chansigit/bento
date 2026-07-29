# Bento 🍱

macOS 菜单栏多合一小工具,一格一格装着:世界时钟 + 鼠标/触控板滚动方向 +
Dock 固定 + 显示器亮度。

> 前身叫 GTime;现已扩展成多功能菜单栏工具,故更名 Bento。为保留已授予的
> 辅助功能权限与设置,内部 bundle id 仍是 `com.sijie.gtime`。

## 世界时钟

在顶栏常驻显示其他时区的当前时间,样式如
`🇬🇧 7:11 AM⁺¹  🇨🇳 2:11 PM⁺¹`(⁺¹/⁻¹ 表示相对本地日期的跨天)。

- 按城市名搜索添加时区,支持**中文 / 英文 / 拼音**(如 `北京`、`Tokyo`、`xianggang`),
  内置 200+ 主要城市,也可直接搜任意 IANA 时区标识符
- 内置库找不到的中小城市/任意地名(如 `达姆施塔特`、`Darmstadt`、大学、地标),
  可点搜索框里的「🔍 在线搜索」用系统地图数据联网解析出所在时区(无需任何权限)
- 时间随本地时钟自动换算,自动处理夏令时;睡眠唤醒、修改系统时间/时区后立即校正

## 滚动方向

macOS 只有一个全局「自然滚动」开关同时管鼠标和触控板。本功能通过事件拦截
把两者解耦,可**分别**把鼠标、触控板设为「自然」或「反转」。

- 下拉菜单里直接有**鼠标**和**触控板**两个左右切换按钮(分段控件):**左=自然,右=反转**
- 默认**鼠标反转、触控板自然**;你的选择存本地,重启后自动恢复
- 会读取系统「自然滚动」作为基准自动换算,改了系统设置也保持正确
- 两个设备都无需翻转时不启用拦截,零开销
- 首次启用需授予**辅助功能**权限(事件拦截必需);菜单会引导到系统设置
- 局限:Magic Mouse 上报连续事件,会被当作触控板处理;普通滚轮鼠标正常

> 灵感与技术源自同仓库外的 [fanguolai](https://github.com/chansigit/fanguolai)(CLI 版)。

## Dock 固定

多显示器下 macOS 会让 Dock 跟着鼠标乱跑。本功能把 Dock 固定在你选的那块屏。

- 菜单「Dock 固定」子菜单里选显示器,✓ 标出当前固定在哪块屏;选「关闭」取消固定
- **选中后弹提示**:macOS 没有"直接设定 Dock 在哪块屏"的 API,只能靠指针压向该屏
  Dock 边缘触发。为避免软件替你乱动鼠标,选中目标后会弹一个提示,请你**自己**把
  鼠标移到该屏底部,Dock 就会迁过去;之后固定不再乱跑。目标屏未连接时选中自动跳过
- 原理(移植自 [dockpin](https://github.com/chansigit/dockpin)):鼠标移动事件的
  `CGEventTap` 把光标挡在非目标屏的 Dock 触发边之外,Dock 只能出现在目标屏
- 选择存本地,重启自动恢复
- 用**监听式**全局鼠标监视器(不拦截、不进输入路径)+ 光标回弹实现,不给鼠标加延迟、
  也不需要辅助功能权限;只在接了多块屏且固定了目标时才运行,单屏时完全不跑
- 只拦截**真正的外沿**(边缘外没有其它屏的地方),用 `CGWarpMouseCursorPosition`
  强制把光标挡在 Dock 触发区外;显示器之间的内部边界不拦,不影响跨屏移动
- 插拔显示器会自动重新解析目标屏并调整
- 「Dock 当前在」这行需要屏幕录制权限才能显示,取不到就自动隐藏

## 显示器亮度

菜单「显示器亮度」子菜单里,每块显示器一个亮度滑块,拖动即时调硬件亮度。

- 内建屏:私有 `DisplayServices` 框架读写亮度
- 外接屏:DDC/CI(VCP `0x10`),走 Apple Silicon 的 `IOAVService` I²C 写(与
  m1ddc / MonitorControl 同法);不支持 DDC 的显示器标为「不支持 DDC」
- 每块屏的亮度记忆存本地;无需辅助功能权限
- 插拔显示器会自动刷新菜单里的显示器列表
- 局限:DDC 并非所有显示器/转接线都支持;**显示器开 HDR 或护眼/B.I.+ 等图像模式时,
  厂商会锁掉亮度控制**(OSD 里手动亮度也是灰的),此时 DDC 写入无效——需在显示器
  OSD 关掉 HDR / 切到 Standard 图像模式,并确保 DDC/CI 为开

## Wi-Fi 信号

菜单「📶 Wi-Fi 信号」子菜单:打开时扫描附近网络,按信号强弱排序显示
每个网络的信号条(▂▄▆█)和 RSSI(dBm),当前连接的网络打 ✓ 并排最前。

- 只在打开该子菜单时才扫描(扫描要占用无线电几秒钟,不会常驻后台扫)
- 同名网络(多个 AP)自动去重,取最强信号
- macOS 要求**定位服务**权限才能显示网络名称;首次打开会请求,拒绝则会提示

## 皮肤

菜单「🎨 皮肤」:默认(跟随系统)/ 浅色 / 深色 三种菜单外观,以及
🍵 抹茶、🌊 海盐、🍊 蜜柑、🌸 樱花四种强调色(应用于顶栏文字和菜单里的
时间)。选择存本地,重启保持。

## 防止休眠

菜单里的「☕️ 防止休眠」开关:开启后阻止系统休眠和屏幕熄灭(跑长任务、
演示时用),顶栏出现 ☕️ 提示。用 `IOPMAssertion` 实现,无需任何权限。
**不会**跨重启记忆——防休眠是临时状态,重启后自动恢复正常休眠。

## 其它

- 默认开机自动启动(菜单内可关)
- 纯 AppKit 原生实现,零依赖,无 Dock 图标,内存占用极小

## 安装(普通用户)

从 [Releases](https://github.com/chansigit/bento/releases) 下载最新的
`Bento-x.x.dmg`,打开后把 Bento 拖进 Applications 即可。

> 应用是自签名的(没有 Apple 开发者账号公证),首次打开 macOS 会拦截:
> 在「应用程序」里**右键 Bento → 打开 → 打开**即可(只需一次);或执行
> `xattr -cr /Applications/Bento.app`。滚动方向/Dock 固定功能需要在
> 系统设置里授予「辅助功能」权限。

## 构建与安装(从源码)

```sh
./build.sh        # 构建 + 安装 + 启动
./make-dist.sh    # 另外打一个可分发的 DMG(build/Bento-x.x.dmg)
```

脚本会依次:跑测试 → 编译 → 打包 `Bento.app` → 签名 → 安装到
`/Applications`(不可写时装到 `~/Applications`)→ 启动。

## 使用

点击菜单栏的时间(或 🌐)打开菜单:

| 菜单项 | 说明 |
|---|---|
| 城市条目 | 显示该地当前时间与日期;子菜单可 **移除 / 上移 / 下移** |
| 添加城市… | 打开搜索窗口,回车或双击添加,Esc 关闭;本地无结果时回车走在线搜索;同一时区不重复添加 |
| 24 小时制 | 切换 12/24 小时显示 |
| 滚动方向 ▸ | 鼠标 / 触控板 各自「自然 / 反转」;含系统基准显示与授权入口 |
| Dock 固定 ▸ | 选择把 Dock 固定在哪块显示器;✓ 标出当前;「关闭」取消 |
| 显示器亮度 ▸ | 每块显示器一个亮度滑块(内建走 DisplayServices,外接走 DDC/CI) |
| 📶 Wi-Fi 信号 ▸ | 扫描附近网络,显示信号条与 dBm;当前网络打 ✓(需定位权限显示名称) |
| ☕️ 防止休眠 | 开关:阻止系统休眠与屏幕熄灭;开启时顶栏显示 ☕️;不跨重启记忆 |
| 🎨 皮肤 ▸ | 菜单浅色/深色外观 + 抹茶/海盐/蜜柑/樱花强调色;选择跨重启记忆 |
| 登录时自动启动 | 开关 `~/Library/LaunchAgents/com.sijie.gtime.plist` |

## 卸载

```sh
pkill -x Bento
rm -rf /Applications/Bento.app ~/Library/LaunchAgents/com.sijie.gtime.plist
defaults delete com.sijie.gtime
```

## 开发

- `Sources/GTimeCore.swift` — 纯逻辑:时区数学、格式化、城市库与搜索(全部有测试)
- `Sources/ScrollCore.swift` — 纯逻辑:滚动翻转计算、delta 取负、设置持久化(全部有测试)
- `Sources/ScrollFlip.swift` — CGEventTap 控制器、辅助功能检查、系统基准读取
- `Sources/DockCore.swift` — 纯逻辑:Dock 边缘、光标钳制数学(有测试)
- `Sources/DockPin.swift` — 显示器枚举、Dock 固定的鼠标事件 tap 控制器
- `Sources/BrightnessCore.swift` — 纯逻辑:DDC 报文构造、百分比钳制(有测试)
- `Sources/Brightness.swift` — DisplayServices / IOAVService 亮度读写控制器
- `Sources/WifiCore.swift` — 纯逻辑:信号等级/百分比换算、去重排序(有测试)
- `Sources/Wifi.swift` — CoreWLAN 扫描控制器(含定位权限请求)
- `Sources/Theme.swift` — 皮肤定义(菜单外观 + 强调色)
- `Sources/Caffeine.swift` — IOPMAssertion 防休眠控制器
- `Sources/main.swift` — AppKit 壳:状态栏、菜单、搜索窗口、LaunchAgent
- `Tests/main.swift` — 独立测试二进制:
  `swiftc Sources/GTimeCore.swift Sources/ScrollCore.swift Tests/main.swift -o build/tests && ./build/tests`

兼容旧工具链(Swift 5.4 / macOS 11.3 SDK)编译,运行于 macOS 11+。
