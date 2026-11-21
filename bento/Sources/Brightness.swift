import AppKit
import CoreGraphics
import Foundation
import IOKit

// MARK: - Private framework bindings (resolved at runtime via dlsym)

private typealias DSGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias DSSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
private typealias AVServiceCreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
private typealias AVI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32

private struct PrivateAPI {
    let dsGet: DSGetBrightnessFn?
    let dsSet: DSSetBrightnessFn?
    let avCreate: AVServiceCreateFn?
    let avWrite: AVI2CFn?
    let avRead: AVI2CFn?

    init() {
        let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        dsGet = PrivateAPI.sym(ds, "DisplayServicesGetBrightness")
        dsSet = PrivateAPI.sym(ds, "DisplayServicesSetBrightness")
        let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        avCreate = PrivateAPI.sym(iokit, "IOAVServiceCreateWithService")
        avWrite = PrivateAPI.sym(iokit, "IOAVServiceWriteI2C")
        avRead = PrivateAPI.sym(iokit, "IOAVServiceReadI2C")
    }

    static func sym<T>(_ handle: UnsafeMutableRawPointer?, _ name: String) -> T? {
        guard let handle = handle, let s = dlsym(handle, name) else { return nil }
        return unsafeBitCast(s, to: T.self)
    }
}

// MARK: - Brightness targets

enum DisplayKind { case builtin, external }

final class BrightnessTarget {
    let id: CGDirectDisplayID
    let name: String
    let kind: DisplayKind
    let avService: CFTypeRef?
    var supported: Bool
    var reading: DDCValue?
    var status = ""

    init(id: CGDirectDisplayID, name: String, kind: DisplayKind, avService: CFTypeRef?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.avService = avService
        self.supported = (kind == .builtin)   // external support decided in refresh()
    }
}

// MARK: - Controller

final class BrightnessController {
    private let api = PrivateAPI()
    private(set) var targets: [BrightnessTarget] = []

    func refresh() {
        let displays = listDockDisplays()
        let externalServices = collectExternalAVServices()
        let externalCount = displays.filter { CGDisplayIsBuiltin($0.id) == 0 }.count
        targets = displays.map { d in
            if CGDisplayIsBuiltin(d.id) != 0 {
                let t = BrightnessTarget(id: d.id, name: d.name, kind: .builtin, avService: nil)
                t.supported = api.dsGet != nil && api.dsSet != nil
                return t
            }
            // shortcut: only pair an unambiguous external display; add EDID matching for multiple monitors.
            let svc = externalCount == 1 && externalServices.count == 1 ? externalServices.first : nil
            let t = BrightnessTarget(id: d.id, name: d.name, kind: .external, avService: svc)
            if let svc = svc { t.reading = readBrightness(svc) }
            t.supported = t.reading != nil
            if !t.supported {
                t.status = externalCount > 1 ? "多显示器尚无法安全匹配 DDC" : "无法读取亮度 · 检查 DDC/CI 与连接线"
            }
            return t
        }
    }

    func currentPercent(_ t: BrightnessTarget) -> Int {
        if t.kind == .builtin, let get = api.dsGet {
            var value: Float = 0
            if get(t.id, &value) == 0 { return clampBrightnessPercent(Int((value * 100).rounded())) }
        }
        return t.reading?.percent ?? 50
    }

    @discardableResult
    func setPercent(_ t: BrightnessTarget, _ percent: Int) -> Bool {
        t.status = ""
        switch t.kind {
        case .builtin:
            guard let set = api.dsSet, set(t.id, Float(clampBrightnessPercent(percent)) / 100) == 0 else {
                t.status = "系统未接受亮度调节"
                return false
            }
            return true
        case .external:
            guard let svc = t.avService, let before = readBrightness(svc) else {
                t.status = "无法读取亮度 · 检查 DDC/CI 与连接线"
                return false
            }
            t.reading = before
            let raw = before.rawValue(percent: percent)
            if raw == before.current { return true }
            guard send(ddcSetVCPPayload(vcp: 0x10, value: raw), to: svc) else {
                t.status = "亮度指令发送失败 · 检查连接线"
                return false
            }
            // Give the monitor time to apply the command before verifying it.
            usleep(100_000)
            guard let after = readBrightness(svc) else {
                t.status = "无法确认调节结果 · 请重新打开菜单"
                return false
            }
            t.reading = after
            guard after.current == raw else {
                t.status = "屏幕未接受调节 · 请关闭 HDR / B.I.+"
                return false
            }
            return true
        }
    }

    private func send(_ bytes: [UInt8], to service: CFTypeRef) -> Bool {
        guard let write = api.avWrite else { return false }
        var payload = bytes
        // Some DDC bridges require the command twice, with a quiet interval.
        for _ in 0..<2 {
            usleep(10_000)
            let rc = payload.withUnsafeMutableBytes {
                write(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count))
            }
            if rc != 0 { return false }
        }
        return true
    }

    private func readBrightness(_ service: CFTypeRef) -> DDCValue? {
        guard let read = api.avRead else { return nil }
        for _ in 0..<2 {
            guard send(ddcGetVCPPayload(vcp: 0x10), to: service) else { return nil }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 12)
            let rc = reply.withUnsafeMutableBytes {
                read(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count))
            }
            if rc == 0, let value = parseDDCValue(reply, vcp: 0x10) { return value }
        }
        return nil
    }

    /// External DCPAVServiceProxy nodes (Location == External), in IORegistry order.
    private func collectExternalAVServices() -> [CFTypeRef] {
        guard let create = api.avCreate else { return [] }
        var result: [CFTypeRef] = []
        var iterator = io_iterator_t()
        let match = IOServiceMatching("DCPAVServiceProxy")
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, match, &iterator) == KERN_SUCCESS else {
            return []
        }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let loc = IORegistryEntryCreateCFProperty(service, "Location" as CFString,
                                                      kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            if loc == "External", let av = create(kCFAllocatorDefault, service)?.takeRetainedValue() {
                result.append(av)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return result
    }
}
