import Cocoa
import CoreImage
import CryptoKit
import Darwin

private struct FolderIconBackup: Codable {
    let hadCustomIcon: Bool
    let originalTIFF: Data?
}

final class FolderColorController: NSObject {
    static var palette: [(String, NSColor)] { [(L("红色"), .systemRed), (L("橙色"), .systemOrange), (L("黄色"), .systemYellow), (L("绿色"), .systemGreen), (L("青色"), .systemTeal), (L("蓝色"), .systemBlue), (L("紫色"), .systemPurple), (L("粉色"), .systemPink)] }
    private let backupDirectory: URL
    private let context = CIContext()
    init(backupDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bento/FolderIcons", isDirectory: true)) {
        self.backupDirectory = backupDirectory
        super.init()
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "Bento.FolderColor", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func backupURL(for folder: URL) throws -> URL {
        var info = stat()
        guard folder.isFileURL, lstat(folder.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw failure(L("请选择普通文件夹，不支持文件或符号链接。")) }
        let values = try folder.resourceValues(forKeys: [.isPackageKey, .volumeUUIDStringKey])
        guard values.isPackage != true, let volume = values.volumeUUIDString else { throw failure(L("此位置不支持安全备份图标，或选择的是应用程序包。")) }
        // Volume + inode + birth time survives folder renames without confusing reused inodes.
        let identity = "\(volume):\(info.st_ino):\(info.st_birthtimespec.tv_sec):\(info.st_birthtimespec.tv_nsec)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return backupDirectory.appendingPathComponent(key + ".plist")
    }
    private func hasCustomIcon(_ folder: URL) throws -> Bool {
        var bytes = [UInt8](repeating: 0, count: 32)
        let count = getxattr(folder.path, "com.apple.FinderInfo", &bytes, bytes.count, 0, 0)
        if count < 0 && errno == ENOATTR { return false }
        guard count == 32 else { throw failure(L("无法读取原图标信息，未修改文件夹。")) }
        return bytes[8] & 0x04 != 0
    }
    func icon(colorIndex: Int) throws -> NSImage {
        guard Self.palette.indices.contains(colorIndex) else { throw failure(L("无效的颜色。")) }
        let folder = NSWorkspace.shared.icon(forFileType: "public.folder").copy() as! NSImage
        folder.size = NSSize(width: 512, height: 512)
        var rect = NSRect(x: 0, y: 0, width: 512, height: 512)
        guard let source = folder.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let tint = Self.palette[colorIndex].1.usingColorSpace(.sRGB),
              let filter = CIFilter(name: "CIColorMonochrome") else { throw failure(L("无法生成文件夹图标。")) }
        filter.setValue(CIImage(cgImage: source), forKey: kCIInputImageKey)
        filter.setValue(CIColor(red: tint.redComponent, green: tint.greenComponent, blue: tint.blueComponent), forKey: kCIInputColorKey)
        filter.setValue(1, forKey: kCIInputIntensityKey)
        guard let output = filter.outputImage, let cg = context.createCGImage(output, from: output.extent) else { throw failure(L("无法生成文件夹图标。")) }
        return NSImage(cgImage: cg, size: NSSize(width: 512, height: 512))
    }
    func apply(to folder: URL, colorIndex: Int?) throws {
        let backup = try backupURL(for: folder)
        if let index = colorIndex {
            let image = try icon(colorIndex: index)
            if !FileManager.default.fileExists(atPath: backup.path) {
                let custom = try hasCustomIcon(folder)
                var original: Data?
                if custom {
                    let image = NSWorkspace.shared.icon(forFile: folder.path).copy() as! NSImage
                    image.size = NSSize(width: 512, height: 512)
                    guard let tiff = image.tiffRepresentation else { throw failure(L("原图标备份失败，未修改文件夹。")) }
                    original = tiff
                }
                try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let data = try PropertyListEncoder().encode(FolderIconBackup(hadCustomIcon: custom, originalTIFF: original))
                try data.write(to: backup, options: .atomic)
            }
            guard NSWorkspace.shared.setIcon(image, forFile: folder.path, options: []) else { throw failure(L("无法设置图标，请检查文件夹的写入权限。原图标备份已保留。")) }
        } else {
            guard FileManager.default.fileExists(atPath: backup.path) else { throw failure(L("没有此文件夹的 Bento 图标备份，已保留现有图标。")) }
            let saved = try PropertyListDecoder().decode(FolderIconBackup.self, from: Data(contentsOf: backup))
            var original: NSImage?
            if saved.hadCustomIcon {
                guard let data = saved.originalTIFF, let image = NSImage(data: data) else { throw failure(L("图标备份无法读取，已保留现有图标。")) }
                original = image
            }
            guard NSWorkspace.shared.setIcon(original, forFile: folder.path, options: []) else { throw failure(L("无法恢复图标，备份已保留。")) }
            try FileManager.default.removeItem(at: backup)
        }
    }
    @objc func chooseFolders() {
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSOpenPanel()
        picker.title = L("文件夹着色"); picker.message = L("选择需要着色或恢复原图标的文件夹，可多选。")
        picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = true
        picker.canCreateDirectories = false; picker.prompt = L("下一步")
        guard picker.runModal() == .OK else { return }
        let folders = picker.urls
        let alert = NSAlert()
        alert.messageText = L("设置 %@ 个文件夹的颜色", String(describing: folders.count))
        alert.informativeText = folders.prefix(4).map { $0.lastPathComponent }.joined(separator: "、") + (folders.count > 4 ? "…" : "")
        let colors = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
        for (index, color) in Self.palette.enumerated() {
            colors.addItem(withTitle: color.0)
            colors.lastItem?.tag = index
            if let image = try? icon(colorIndex: index) { image.size = NSSize(width: 18, height: 18); colors.lastItem?.image = image }
        }
        colors.menu?.addItem(.separator())
        colors.addItem(withTitle: L("恢复 Bento 着色前的图标")); colors.lastItem?.tag = -1
        alert.accessoryView = colors; alert.addButton(withTitle: L("应用")); alert.addButton(withTitle: L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn, let choice = colors.selectedItem?.tag else { return }
        var failures: [String] = []
        for folder in folders {
            do { try apply(to: folder, colorIndex: choice < 0 ? nil : choice) }
            catch { failures.append(folder.lastPathComponent + "：" + error.localizedDescription) }
        }
        let result = NSAlert()
        result.messageText = L("已更新 %@ / %@ 个文件夹", String(describing: folders.count - failures.count), String(describing: folders.count))
        result.informativeText = failures.isEmpty ? (choice < 0 ? L("原图标已恢复。") : L("再次打开「文件夹着色…」可恢复原图标。")) : failures.joined(separator: "\n")
        if !failures.isEmpty { result.alertStyle = .warning }
        result.runModal()
    }
}
