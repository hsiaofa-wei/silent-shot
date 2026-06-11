// SilentShot for macOS —— 静默后台热键截图（菜单栏 App，可隐藏图标）。
//
// 热键（默认 ⌃⌥S）：进程内静默截全屏（含多显示器），存到 ~/Pictures/Screenshots/shot_*.png。
// 无快门声 / 无闪屏 / 无遮罩 —— 投屏 / 会议中不被发现。
//
// 设计要点（与 Windows 版对应）：
//   - 全局热键用 Carbon RegisterEventHotKey，不需要「辅助功能」权限（唯一需要的是「屏幕录制」）。
//   - 截图在进程内用 CGDisplayCreateImage，本 App 成为屏幕录制的 TCC 责任进程（按名字出现在
//     系统设置里，授权可持久）。CGDisplayCreateImage 在 macOS 14+ 标记为弃用但仍可用；
//     未来迁移路径是 ScreenCaptureKit。
//   - 受 DRM/安全保护的画面可能截成黑块；macOS 15+ 会周期性提醒「正在录制你的屏幕」，第三方无法关闭。
import AppKit
import Carbon
import CoreGraphics
import ScreenCaptureKit
import ServiceManagement

// MARK: - 配置

struct Config: Codable {
    var hotkey: String
    var saveDirectory: String
    var filenamePrefix: String
    var imageFormat: String        // "png" | "jpg"
    var captureAllDisplays: Bool
    var playShutterSound: Bool
    var showMenuBarIcon: Bool
    var launchAtLogin: Bool

    static let `default` = Config(
        hotkey: "ctrl+option+s",
        saveDirectory: "~/Pictures/Screenshots",
        filenamePrefix: "shot",
        imageFormat: "png",
        captureAllDisplays: false,
        playShutterSound: false,
        showMenuBarIcon: true,
        launchAtLogin: false
    )

    var isJPEG: Bool { imageFormat.lowercased().hasPrefix("j") }
    var fileExtension: String { isJPEG ? "jpg" : "png" }
}

enum ConfigStore {
    static var dir: String { (NSHomeDirectory() as NSString).appendingPathComponent(".config/silentshot") }
    static var path: String { (dir as NSString).appendingPathComponent("config.json") }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            let fresh = Config.default
            save(fresh)
            return fresh
        }
        return (try? JSONDecoder().decode(Config.self, from: data)) ?? Config.default
    }

    static func save(_ config: Config) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - 热键解析

struct Hotkey {
    var keyCode: UInt32
    var carbonModifiers: UInt32
}

enum HotkeyParser {
    // (token, ANSI 虚拟键码)。键码来自 HIToolbox Events.h。
    static let keys: [(String, UInt32)] = [
        ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8),
        ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17),
        ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("=", 24), ("9", 25),
        ("7", 26), ("-", 27), ("8", 28), ("0", 29), ("]", 30), ("o", 31), ("u", 32), ("[", 33),
        ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("'", 39), ("k", 40), (";", 41), ("\\", 42),
        (",", 43), ("/", 44), ("n", 45), ("m", 46), (".", 47), ("`", 50),
        ("return", 36), ("tab", 48), ("space", 49), ("delete", 51), ("escape", 53),
        ("f1", 122), ("f2", 120), ("f3", 99), ("f4", 118), ("f5", 96), ("f6", 97), ("f7", 98),
        ("f8", 100), ("f9", 101), ("f10", 109), ("f11", 103), ("f12", 111),
    ]

    static func keyCode(for token: String) -> UInt32? {
        let t = token.lowercased()
        return keys.first { $0.0 == t }?.1
    }

    static func token(for keyCode: UInt32) -> String? {
        keys.first { $0.1 == keyCode }?.0
    }

    static func parse(_ string: String) -> Hotkey? {
        let parts = string.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var mods: UInt32 = 0
        var key: UInt32?
        for part in parts {
            switch part {
            case "control", "ctrl", "\u{2303}": mods |= UInt32(controlKey)
            case "option", "opt", "alt", "\u{2325}": mods |= UInt32(optionKey)
            case "shift", "\u{21E7}": mods |= UInt32(shiftKey)
            case "command", "cmd", "\u{2318}", "meta", "super", "win": mods |= UInt32(cmdKey)
            default: if let code = keyCode(for: part) { key = code }
            }
        }
        guard let code = key else { return nil }
        return Hotkey(keyCode: code, carbonModifiers: mods)
    }

    /// 把热键串变成符号显示，例如 "ctrl+option+s" -> "⌃⌥S"。
    static func display(_ string: String) -> String {
        guard let hk = parse(string) else { return string }
        var out = ""
        if hk.carbonModifiers & UInt32(controlKey) != 0 { out += "\u{2303}" }
        if hk.carbonModifiers & UInt32(optionKey) != 0 { out += "\u{2325}" }
        if hk.carbonModifiers & UInt32(shiftKey) != 0 { out += "\u{21E7}" }
        if hk.carbonModifiers & UInt32(cmdKey) != 0 { out += "\u{2318}" }
        out += label(for: hk.keyCode)
        return out
    }

    static func label(for keyCode: UInt32) -> String {
        guard let token = token(for: keyCode) else { return "?" }
        if token.count == 1 { return token.uppercased() }
        return token.prefix(1).uppercased() + token.dropFirst()
    }

    /// 录制时把一次按键事件转成热键串；要求至少一个修饰键，避免劫持普通按键。
    static func string(from event: NSEvent) -> String? {
        var tokens: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { tokens.append("ctrl") }
        if flags.contains(.option) { tokens.append("option") }
        if flags.contains(.shift) { tokens.append("shift") }
        if flags.contains(.command) { tokens.append("cmd") }
        guard !tokens.isEmpty, let key = token(for: UInt32(event.keyCode)) else { return nil }
        tokens.append(key)
        return tokens.joined(separator: "+")
    }
}

// MARK: - Carbon 全局热键

// C 回调不能捕获 Swift 上下文，必须通过 userData 指针拿回 self，再跳回主线程处理。
private func hotKeyEventHandlerProc(_ next: EventHandlerCallRef?,
                                    _ event: EventRef?,
                                    _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData = userData else { return noErr }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { manager.fire() }
    return noErr
}

final class HotKeyManager {
    var onFire: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x5353_4854  // 'SSHT'

    func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(),
                            hotKeyEventHandlerProc,
                            1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(),
                            &handlerRef)
    }

    func fire() { onFire?() }

    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id,
                                         GetEventDispatcherTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}

// MARK: - 时间戳 / 工具

private func timeStamp() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd_HHmmss"
    return f.string(from: Date())
}

private func shortTime() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm:ss"
    return f.string(from: Date())
}

// MARK: - App 主体

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var config = Config.default
    private let hotKeys = HotKeyManager()
    private var statusItem: NSStatusItem?
    private var prefsController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = ConfigStore.load()
        hotKeys.onFire = { [weak self] in self?.capture() }
        hotKeys.installHandler()
        applyConfig()

        // 隐藏图标时，再次启动 App 会通过分布式通知让本实例打开偏好设置（见单实例守卫）。
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(menuPreferences),
            name: NSNotification.Name("com.silentshot.mac.showPreferences"), object: nil)

        // 首次启动引导屏幕录制授权。
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        log("SilentShot 启动，热键 \(HotkeyParser.display(config.hotkey))")
    }

    // 把当前 config 应用到热键 / 菜单栏图标 / 登录项。
    func applyConfig() {
        if let hk = HotkeyParser.parse(config.hotkey) {
            if !hotKeys.register(hk) { log("热键注册失败：\(config.hotkey)（可能被占用）") }
        } else {
            log("热键无法解析：\(config.hotkey)")
        }
        updateStatusItem()
        syncLoginItem()
    }

    /// 偏好窗口改动入口：修改、落盘、实时生效。
    func updateConfig(_ mutate: (inout Config) -> Void) {
        mutate(&config)
        ConfigStore.save(config)
        applyConfig()
    }

    // MARK: 截图

    func capture() {
        guard CGPreflightScreenCaptureAccess() else {
            log("尚未授予屏幕录制权限，已发起系统授权请求")
            _ = CGRequestScreenCaptureAccess()
            return
        }
        Task { await captureScreens() }
    }

    // 用 ScreenCaptureKit 在进程内截图：本 App 成为屏幕录制的 TCC 责任进程，
    // 截图无声无闪。CGDisplayCreateImage 在 macOS 15 已被移除，这是当下正确路径。
    private func captureScreens() async {
        let dir = (config.saveDirectory as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        do {
            let content = try await SCShareableContent.current
            let all = content.displays
            guard !all.isEmpty else { log("SHOT-ERROR 没有可截取的显示器"); return }
            let mainID = CGMainDisplayID()
            let targets = config.captureAllDisplays ? all : all.filter { $0.displayID == mainID }
            let displays = targets.isEmpty ? [all[0]] : targets

            let stamp = timeStamp()
            var saved = 0
            for (index, display) in displays.enumerated() {
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let cfg = SCStreamConfiguration()
                if let mode = CGDisplayCopyDisplayMode(display.displayID) {
                    cfg.width = mode.pixelWidth      // 原生像素，高分屏不糊
                    cfg.height = mode.pixelHeight
                } else {
                    cfg.width = display.width
                    cfg.height = display.height
                }
                cfg.showsCursor = false
                do {
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
                    let suffix = displays.count > 1 ? "_\(index + 1)" : ""
                    let file = "\(dir)/\(config.filenamePrefix)_\(stamp)\(suffix).\(config.fileExtension)"
                    if write(image, to: file) {
                        saved += 1
                        log("SHOT saved \((file as NSString).lastPathComponent)")
                    } else {
                        log("SHOT-ERROR 写文件失败 \(file)")
                    }
                } catch {
                    log("SHOT-ERROR 截图失败 display=\(display.displayID): \(error.localizedDescription)")
                }
            }
            if saved > 0, config.playShutterSound {
                NSSound(named: "Tink")?.play()
            }
        } catch {
            log("SHOT-ERROR 获取可共享内容失败：\(error.localizedDescription)")
        }
    }

    private func write(_ cgImage: CGImage, to path: String) -> Bool {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let type: NSBitmapImageRep.FileType = config.isJPEG ? .jpeg : .png
        let props: [NSBitmapImageRep.PropertyKey: Any] = config.isJPEG ? [.compressionFactor: 0.9] : [:]
        guard let data = rep.representation(using: type, properties: props) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    // MARK: 菜单栏

    private func updateStatusItem() {
        if config.showMenuBarIcon {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SilentShot") {
                    image.isTemplate = true
                    item.button?.image = image
                } else {
                    item.button?.title = "SS"
                }
                statusItem = item
            }
            statusItem?.menu = buildMenu()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        add("立即截图 (\(HotkeyParser.display(config.hotkey)))", #selector(menuCapture))
        add("打开截图文件夹", #selector(menuOpenFolder))
        menu.addItem(.separator())
        add("偏好设置…", #selector(menuPreferences), ",")
        add("重新载入配置", #selector(menuReload))
        add("打开设置网页…", #selector(menuSettingsPage))
        menu.addItem(.separator())
        add("退出 SilentShot", #selector(menuQuit), "q")
        return menu
    }

    // MARK: 登录项（SMAppService）

    private func syncLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            if config.launchAtLogin, service.status != .enabled {
                try service.register()
            } else if !config.launchAtLogin, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            log("登录项设置出错：\(error.localizedDescription)")
        }
    }

    func loginItemEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return config.launchAtLogin }
        return SMAppService.mainApp.status == .enabled
    }

    // MARK: 菜单动作

    @objc private func menuCapture() { capture() }

    @objc private func menuOpenFolder() {
        let dir = (config.saveDirectory as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    @objc func menuPreferences() {
        if prefsController == nil {
            prefsController = PreferencesWindowController(appDelegate: self)
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsController?.refreshFromConfig()
        prefsController?.showWindow(nil)
        prefsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func menuReload() {
        config = ConfigStore.load()
        applyConfig()
        prefsController?.refreshFromConfig()
        log("已重新载入配置")
    }

    @objc private func menuSettingsPage() {
        if let url = Bundle.main.url(forResource: "settings", withExtension: "html") {
            NSWorkspace.shared.open(url)
        } else {
            log("未在 App 包内找到 settings.html")
        }
    }

    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: 日志

    func log(_ message: String) {
        let dir = (config.saveDirectory as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let file = dir + "/_listener.log"
        let line = shortTime() + " " + message + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: URL(fileURLWithPath: file))
        }
    }
}

// MARK: - 热键录制按钮

final class HotkeyRecorderButton: NSButton {
    var onCapture: ((String) -> Void)?
    private var recording = false
    private var monitor: Any?
    private var current = ""

    func setHotkey(_ hotkey: String) {
        current = hotkey
        if !recording { title = HotkeyParser.display(hotkey) }
    }

    override func mouseDown(with event: NSEvent) {
        recording ? stop(restore: true) : start()
    }

    private func start() {
        recording = true
        title = "按下新热键…（Esc 取消）"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {  // Esc
                self.stop(restore: true)
                return nil
            }
            if let string = HotkeyParser.string(from: event) {
                self.current = string
                self.onCapture?(string)
                self.stop(restore: false)
            }
            return nil  // 录制期间吞掉按键，避免触发其它快捷键
        }
    }

    private func stop(restore: Bool) {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        title = HotkeyParser.display(current)
    }
}

// MARK: - 偏好窗口

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private unowned let appDelegate: AppDelegate

    private let hotkeyButton = HotkeyRecorderButton(frame: .zero)
    private let saveDirField = NSTextField(frame: .zero)
    private let prefixField = NSTextField(frame: .zero)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let soundCheck = NSButton(checkboxWithTitle: "截图时播放提示音", target: nil, action: nil)
    private let allDisplaysCheck = NSButton(checkboxWithTitle: "截取所有显示器", target: nil, action: nil)
    private let menuBarCheck = NSButton(checkboxWithTitle: "在菜单栏显示图标", target: nil, action: nil)
    private let loginCheck = NSButton(checkboxWithTitle: "开机自启", target: nil, action: nil)

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "SilentShot 偏好设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    private func buildUI() {
        hotkeyButton.bezelStyle = .rounded
        hotkeyButton.setButtonType(.momentaryPushIn)
        hotkeyButton.onCapture = { [weak self] string in
            self?.appDelegate.updateConfig { $0.hotkey = string }
        }

        saveDirField.isEditable = true
        saveDirField.lineBreakMode = .byTruncatingMiddle
        saveDirField.target = self
        saveDirField.action = #selector(saveDirChanged)

        let chooseButton = NSButton(title: "选择…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded

        prefixField.target = self
        prefixField.action = #selector(prefixChanged)

        formatPopup.addItems(withTitles: ["PNG", "JPG"])
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)

        for check in [soundCheck, allDisplaysCheck, menuBarCheck, loginCheck] {
            check.target = self
            check.action = #selector(checkChanged)
        }

        let dirStack = NSStackView(views: [saveDirField, chooseButton])
        dirStack.orientation = .horizontal
        dirStack.spacing = 6
        saveDirField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        hotkeyButton.widthAnchor.constraint(equalToConstant: 180).isActive = true
        prefixField.widthAnchor.constraint(equalToConstant: 150).isActive = true

        func label(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.alignment = .right
            return l
        }

        let grid = NSGridView(views: [
            [label("热键"), hotkeyButton],
            [label("保存到"), dirStack],
            [label("文件名前缀"), prefixField],
            [label("图片格式"), formatPopup],
            [NSGridCell.emptyContentView, soundCheck],
            [NSGridCell.emptyContentView, allDisplaysCheck],
            [NSGridCell.emptyContentView, menuBarCheck],
            [NSGridCell.emptyContentView, loginCheck],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
        window?.contentView = content
    }

    func refreshFromConfig() {
        let config = appDelegate.config
        hotkeyButton.setHotkey(config.hotkey)
        saveDirField.stringValue = config.saveDirectory
        prefixField.stringValue = config.filenamePrefix
        formatPopup.selectItem(withTitle: config.isJPEG ? "JPG" : "PNG")
        soundCheck.state = config.playShutterSound ? .on : .off
        allDisplaysCheck.state = config.captureAllDisplays ? .on : .off
        menuBarCheck.state = config.showMenuBarIcon ? .on : .off
        loginCheck.state = appDelegate.loginItemEnabled() ? .on : .off
    }

    @objc private func saveDirChanged() {
        appDelegate.updateConfig { $0.saveDirectory = saveDirField.stringValue }
    }

    @objc private func prefixChanged() {
        let value = prefixField.stringValue.isEmpty ? "shot" : prefixField.stringValue
        appDelegate.updateConfig { $0.filenamePrefix = value }
    }

    @objc private func formatChanged() {
        let value = formatPopup.titleOfSelectedItem == "JPG" ? "jpg" : "png"
        appDelegate.updateConfig { $0.imageFormat = value }
    }

    @objc private func checkChanged() {
        appDelegate.updateConfig {
            $0.playShutterSound = soundCheck.state == .on
            $0.captureAllDisplays = allDisplaysCheck.state == .on
            $0.showMenuBarIcon = menuBarCheck.state == .on
            $0.launchAtLogin = loginCheck.state == .on
        }
        // 登录项实际状态以系统为准，回读刷新。
        loginCheck.state = appDelegate.loginItemEnabled() ? .on : .off
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (saveDirField.stringValue as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            saveDirField.stringValue = url.path
            appDelegate.updateConfig { $0.saveDirectory = url.path }
        }
    }
}

// MARK: - 入口（单实例守卫 + 启动）

// 已有同 bundle 实例在跑：通知它打开偏好设置，然后本进程退出。
if let bundleID = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !others.isEmpty {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.silentshot.mac.showPreferences"),
            object: nil, userInfo: nil, deliverImmediately: true)
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // 无 Dock 图标（等价 LSUIElement）
app.run()
