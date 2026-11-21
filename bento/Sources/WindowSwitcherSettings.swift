import SwiftUI

struct WindowSwitcherSettingsView: View {
    @AppStorage("windowSwitcher.theme") var theme = 0
    @AppStorage("windowSwitcher.cardSize") var cardSize = 0
    @AppStorage("windowSwitcher.showMinimized") var minimized = true
    @AppStorage("windowSwitcher.showWindowless") var windowless = true
    @AppStorage("windowSwitcher.showHidden") var hidden = true
    @AppStorage("windowSwitcher.excludedApps") var excludedApps = ""
    @AppStorage("windowSwitcher.ignoredApps") var ignoredApps = "com.apple.ScreenSharing\ncom.microsoft.rdc.macos\ncom.teamviewer.TeamViewer\ncom.parallels.*"
    @ObservedObject var owner: WindowSwitcherController
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading) {
                    Text("Bento 窗口切换").font(.system(size: 26, weight: .bold))
                    Text("Bento 设置 · 外观、控制、权限与应用例外").foregroundColor(.secondary)
                }
                Spacer()
                Text("⌘ ⇥").font(.system(size: 24, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
            }
            TabView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("窗口缩略图").font(.title2).bold()
                    Text("按窗口比例排列缩略图，蓝色边框标记当前选择。").foregroundColor(.secondary)
                    Picker("大小", selection: $cardSize) {
                        Text("自动").tag(0); Text("小").tag(1); Text("中").tag(2); Text("大").tag(3)
                    }.pickerStyle(SegmentedPickerStyle())
                    Picker("主题", selection: $theme) {
                        Text("跟随 Bento").tag(0); Text("浅色").tag(1); Text("深色").tag(2)
                    }.pickerStyle(SegmentedPickerStyle())
                    Button("预览切换界面") { owner.preview() }
                    Text("显示在鼠标所在屏幕；窗口多时自动分页。预览模式使用示例卡片。").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }.padding(24).tabItem { Label("外观", systemImage: "paintpalette") }
                VStack(alignment: .leading, spacing: 20) {
                    Text("按住 ⌘，按 Tab 切换窗口").font(.title2).bold()
                    Text("Shift + Tab 反向切换 · 方向键选择\n松开 ⌘ 确认 · Return 确认 · Esc 取消")
                    Divider()
                    Toggle("显示最小化窗口", isOn: $minimized)
                    Toggle("显示隐藏应用的窗口", isOn: $hidden)
                    Toggle("没有窗口的应用在末尾显示", isOn: $windowless)
                    Text("列出辅助功能可访问的窗口，包括同一应用的多个窗口。跨桌面和全屏表现取决于应用及 macOS。").foregroundColor(.secondary)
                    Spacer()
                }.padding(24).tabItem { Label("控制", systemImage: "command") }
                VStack(alignment: .leading, spacing: 12) {
                    Text("权限与运行检查").font(.title2).bold()
                    Text(owner.permissionSummary).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Text(owner.shortcutSummary).font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(owner.checkingPermissions ? "正在检查…" : "重新检查") { owner.checkPermissions() }.disabled(owner.checkingPermissions)
                        Button("启用窗口切换") { owner.enable(); owner.checkPermissions() }
                    }
                    Divider()
                    HStack {
                        Button("辅助功能设置") { owner.accessibilitySettings() }
                        Button("屏幕录制设置") { owner.screenSettings() }
                    }
                    Text("请授权 /Applications/Bento.app。列表中没有 Bento 时用「＋」添加，授权后重启 Bento。独立 WinTab 的权限不能转移。")
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("请退出独立 WinTab / AltTab，避免抢占 Cmd+Tab。缩略图不保存、不上传。")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }.padding(24).tabItem { Label("通用", systemImage: "gearshape") }
                VStack(alignment: .leading, spacing: 10) {
                    Text("隐藏这些应用的窗口").bold()
                    TextEditor(text: $excludedApps).font(.system(.body, design: .monospaced)).frame(height: 70).border(Color.gray.opacity(0.25))
                    Text("这些应用在前台时，保留原有 Cmd+Tab").bold()
                    TextEditor(text: $ignoredApps).font(.system(.body, design: .monospaced)).frame(height: 90).border(Color.gray.opacity(0.25))
                    Text("每行一个 Bundle ID；以 .* 结尾可匹配整个应用系列。").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }.padding(24).tabItem { Label("例外", systemImage: "hand.raised") }
            }
        }.padding(28).frame(width: 650, height: 475)
    }
}
