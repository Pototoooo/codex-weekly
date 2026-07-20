import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let client = CodexQuotaClient()
    private var timer: Timer?
    private var isRefreshing = false

    private let remainingItem = NSMenuItem(title: "本周剩余：读取中…", action: nil, keyEquivalent: "")
    private let usedItem = NSMenuItem(title: "已使用：—", action: nil, keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "重置时间：—", action: nil, keyEquivalent: "")
    private let statusItemText = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var launchAtLoginItem = NSMenuItem(
        title: "登录时启动",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureMenu()
        configureAppearanceMonitoring()
        updateLaunchAtLoginState()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = templateSymbol(
            named: "gauge.with.dots.needle.33percent",
            fallback: "gauge",
            description: "Codex 周额度"
        )
        button.imagePosition = .imageLeading
        button.title = " --%"
        button.toolTip = "Codex 本周剩余额度"
        button.contentTintColor = nil
    }

    private func configureAppearanceMonitoring() {
        // A menu bar can switch between light and dark independently of the app
        // (wallpaper, fullscreen spaces, accessibility settings). Template
        // images let macOS choose a contrasting foreground automatically. The
        // notifications below force an immediate redraw for those transitions.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarAppearanceDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(menuBarAppearanceDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(menuBarAppearanceDidChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func menuBarAppearanceDidChange() {
        guard let button = statusItem.button else { return }
        button.image?.isTemplate = true
        button.contentTintColor = nil
        button.needsDisplay = true
    }

    private func configureMenu() {
        let menu = NSMenu()
        remainingItem.isEnabled = false
        usedItem.isEnabled = false
        resetItem.isEnabled = false
        statusItemText.isEnabled = false

        menu.addItem(remainingItem)
        menu.addItem(usedItem)
        menu.addItem(resetItem)
        menu.addItem(statusItemText)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "立即刷新", action: #selector(refreshFromMenu), keyEquivalent: "r"))
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        menu.addItem(NSMenuItem(title: "打开 Codex", action: #selector(openCodex), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Codex Weekly", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusItemText.title = "正在读取 Codex 本地额度…"

        Task.detached(priority: .utility) { [client] in
            let result = Result { try client.fetch() }
            await MainActor.run { [weak self] in
                self?.isRefreshing = false
                switch result {
                case .success(let snapshot): self?.render(snapshot)
                case .failure(let error): self?.render(error)
                }
            }
        }
    }

    private func render(_ snapshot: QuotaSnapshot) {
        let remaining = Int(snapshot.remainingPercent.rounded())
        let used = Int(snapshot.usedPercent.rounded())
        statusItem.button?.title = " \(remaining)%"
        statusItem.button?.image = quotaSymbol(for: remaining)
        statusItem.button?.contentTintColor = nil
        statusItem.button?.toolTip = "Codex 本周剩余 \(remaining)%"

        remainingItem.title = "本周剩余：\(remaining)%"
        usedItem.title = "已使用：\(used)%"
        resetItem.title = "重置时间：\(formatReset(snapshot.resetsAt))"
        statusItemText.title = "每分钟自动刷新 · 刚刚更新"
    }

    private func render(_ error: Error) {
        statusItem.button?.title = " --%"
        statusItem.button?.image = templateSymbol(
            named: "exclamationmark.triangle.fill",
            fallback: "exclamationmark.circle",
            description: "Codex 额度读取失败"
        )
        statusItem.button?.contentTintColor = nil
        statusItem.button?.toolTip = error.localizedDescription
        remainingItem.title = "本周剩余：读取失败"
        usedItem.title = "已使用：—"
        resetItem.title = "重置时间：—"
        statusItemText.title = error.localizedDescription
    }

    private func quotaSymbol(for remaining: Int) -> NSImage? {
        switch remaining {
        case 20...:
            templateSymbol(
                named: "gauge.with.dots.needle.33percent",
                fallback: "gauge",
                description: "Codex 周额度"
            )
        default:
            templateSymbol(
                named: "exclamationmark.triangle.fill",
                fallback: "exclamationmark.circle",
                description: "Codex 周额度不足"
            )
        }
    }

    private func templateSymbol(named: String, fallback: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: named, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    private func formatReset(_ date: Date?) -> String {
        guard let date else { return "未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"

        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: "zh_CN")
        relative.unitsStyle = .full
        return "\(formatter.string(from: date))（\(relative.localizedString(for: date, relativeTo: Date()))）"
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改登录启动项"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        updateLaunchAtLoginState()
    }

    private func updateLaunchAtLoginState() {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openCodex() {
        let appPaths = ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
        if let path = appPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex")!)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
