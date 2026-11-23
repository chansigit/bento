import SwiftUI

struct WindowSwitcherSettingsView: View {
    @AppStorage("languageID") var language = "system"
    @AppStorage("skinID") var skinID = "system"
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
                    Text(L("Bento 窗口切换")).font(.system(size: 26, weight: .bold))
                    Text(L("Bento 设置 · 外观、控制、权限与应用例外")).foregroundColor(.secondary)
                }
                Spacer()
                Text("⌘ ⇥").font(.system(size: 24, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
            }
            TabView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(L("Bento 皮肤"), selection: $skinID) {
                        ForEach(allSkins, id: \.id) { skin in Text(skin.name).tag(skin.id) }
                    }
                    Picker(L("语言"), selection: $language) {
                        ForEach(BentoLanguage.choices, id: \.0) { choice in Text(choice.0 == "system" ? L("跟随系统") : choice.1).tag(choice.0) }
                    }
                    Text(L("窗口缩略图")).font(.title2).bold()
                    Text(L("按窗口比例排列缩略图，皮肤强调色标记当前选择。")).foregroundColor(.secondary)
                    Picker(L("大小"), selection: $cardSize) {
                        Text(L("自动")).tag(0); Text(L("小")).tag(1); Text(L("中")).tag(2); Text(L("大")).tag(3)
                    }.pickerStyle(SegmentedPickerStyle())
                    Picker(L("主题"), selection: $theme) {
                        Text(L("跟随 Bento")).tag(0); Text(L("浅色")).tag(1); Text(L("深色")).tag(2)
                    }.pickerStyle(SegmentedPickerStyle())
                    Button(L("预览切换界面")) { owner.preview() }
                    Text(L("显示在鼠标所在屏幕；窗口多时自动分页。预览模式使用示例卡片。")).font(.caption).foregroundColor(.secondary)
                    Spacer()
                }.padding(24).tabItem { Label(L("外观"), systemImage: "paintpalette") }
                VStack(alignment: .leading, spacing: 20) {
                    Text(L("按住 ⌘，按 Tab 切换窗口")).font(.title2).bold()
                    Text(L("Shift + Tab 反向切换 · 方向键 / 鼠标移动选择\n点击 / 松开 ⌘ / Return 确认 · Esc 取消\n拖着文件时，悬停约 0.65 秒唤出目标窗口，再松开鼠标放置。"))
                    Divider()
                    Toggle(L("显示最小化窗口"), isOn: $minimized)
                    Toggle(L("显示隐藏应用的窗口"), isOn: $hidden)
                    Toggle(L("没有窗口的应用在末尾显示"), isOn: $windowless)
                    Text(L("列出辅助功能可访问的窗口，包括同一应用的多个窗口。跨桌面和全屏表现取决于应用及 macOS。")).foregroundColor(.secondary)
                    Spacer()
                }.padding(24).tabItem { Label(L("控制"), systemImage: "command") }
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("权限与运行检查")).font(.title2).bold()
                    Text(owner.permissionSummary).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Text(owner.shortcutSummary).font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(owner.checkingPermissions ? L("正在检查…") : L("重新检查")) { owner.checkPermissions() }.disabled(owner.checkingPermissions)
                        Button(L("启用窗口切换")) { owner.enable(); owner.checkPermissions() }
                    }
                    Divider()
                    HStack {
                        Button(L("辅助功能设置")) { owner.accessibilitySettings() }
                        Button(L("屏幕录制设置")) { owner.screenSettings() }
                    }
                    Text(L("请授权 /Applications/Bento.app。列表中没有 Bento 时用「＋」添加，授权后重启 Bento。独立 WinTab 的权限不能转移。"))
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(L("请退出独立 WinTab / AltTab，避免抢占 Cmd+Tab。缩略图不保存、不上传。"))
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }.padding(24).tabItem { Label(L("通用"), systemImage: "gearshape") }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("隐藏这些应用的窗口")).bold()
                    TextEditor(text: $excludedApps).font(.system(.body, design: .monospaced)).frame(height: 70).border(Color.gray.opacity(0.25))
                    Text(L("这些应用在前台时，保留原有 Cmd+Tab")).bold()
                    TextEditor(text: $ignoredApps).font(.system(.body, design: .monospaced)).frame(height: 90).border(Color.gray.opacity(0.25))
                    Text(L("每行一个 Bundle ID；以 .* 结尾可匹配整个应用系列。")).font(.caption).foregroundColor(.secondary)
                    Spacer()
                }.padding(24).tabItem { Label(L("例外"), systemImage: "hand.raised") }
            }
        }.padding(28).frame(width: 760, height: 555)
            .onChange(of: language) { _ in
                NotificationCenter.default.post(name: BentoLanguage.changed, object: nil)
                owner.checkPermissions()
            }
            .onChange(of: skinID) { _ in NotificationCenter.default.post(name: .bentoSkinChanged, object: nil) }
            .accentColor(Color(skin(withID: skinID).accent ?? .controlAccentColor))
    }
}
