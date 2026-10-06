import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let client = CodexQuotaClient()
    private var timer: Timer?
    private var isRefreshing = false
    private var generation = 0
    private var lastSub2Attempt = Date.distantPast
    private var sub2Enabled: Bool { UserDefaults.standard.bool(forKey: "sub2Enabled") }
    private var cachedSub2Key: (endpoint: URL, value: String)?
    private let sourceItem = NSMenuItem(title: "数据源：Codex 本地", action: nil, keyEquivalent: "")
    private var lastSub2Success: Date?
    private lazy var sourceSwitchItem = NSMenuItem(
        title: QuotaSource(sub2Enabled: sub2Enabled).switchTitle,
        action: #selector(toggleQuotaSource), keyEquivalent: ""
    )


    private let fiveHourRemainingItem = NSMenuItem(title: "5 小时剩余：读取中…", action: nil, keyEquivalent: "")
    private let fiveHourUsedItem = NSMenuItem(title: "5 小时已使用：—", action: nil, keyEquivalent: "")
    private let fiveHourResetItem = NSMenuItem(title: "5 小时重置：—", action: nil, keyEquivalent: "")
    private let weeklyRemainingItem = NSMenuItem(title: "本周剩余：读取中…", action: nil, keyEquivalent: "")
    private let weeklyUsedItem = NSMenuItem(title: "本周已使用：—", action: nil, keyEquivalent: "")
    private let weeklyResetItem = NSMenuItem(title: "本周重置：—", action: nil, keyEquivalent: "")
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
            Task { @MainActor in
                guard let self else { return }
                if !self.sub2Enabled || Date().timeIntervalSince(self.lastSub2Attempt) >= 300 { self.refresh() }
            }
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = templateSymbol(
            named: "gauge.with.dots.needle.33percent",
            fallback: "gauge",
            description: "Codex 额度"
        )
        button.imagePosition = .imageLeading
        button.title = " 5h --%"
        button.toolTip = "Codex 5 小时与周额度"
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
        let quotaItems = [
            fiveHourRemainingItem, fiveHourUsedItem, fiveHourResetItem,
            weeklyRemainingItem, weeklyUsedItem, weeklyResetItem
        ]
        for item in quotaItems { item.isEnabled = false }
        statusItemText.isEnabled = false

        sourceItem.isEnabled = false
        menu.addItem(sourceItem)
        menu.addItem(fiveHourRemainingItem)
        menu.addItem(fiveHourUsedItem)
        menu.addItem(fiveHourResetItem)
        menu.addItem(.separator())
        menu.addItem(weeklyRemainingItem)
        menu.addItem(weeklyUsedItem)
        menu.addItem(weeklyResetItem)
        menu.addItem(statusItemText)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "立即刷新", action: #selector(refreshFromMenu), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "配置 Sub2API…", action: #selector(configureSub2), keyEquivalent: ""))
        menu.addItem(sourceSwitchItem)
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
        sourceSwitchItem.title = QuotaSource(sub2Enabled: sub2Enabled).switchTitle
        guard !isRefreshing else { return }
        isRefreshing = true
        if sub2Enabled { refreshSub2(); return }
        sourceItem.title = "数据源：Codex 本地"
        let requestGeneration = generation
        statusItemText.title = "正在读取 Codex 本地额度…"

        Task.detached(priority: .utility) { [client] in
            let result = Result { try client.fetch() }
            await MainActor.run { [weak self] in
                guard let self, self.generation == requestGeneration else { return }
                self.isRefreshing = false
                switch result {
                case .success(let snapshot): self.render(snapshot)
                case .failure(let error): self.render(error)
                }
            }
        }
    }

    @objc private func configureSub2() {
        let alert = NSAlert()
        alert.messageText = "配置 Sub2API 分配额度"
        alert.informativeText = "Key 仅保存至本机钥匙串，且仅发送至下方地址。不会读取浏览器 Cookie。保存后切换到 Sub2；留空 Key 可复用该地址已保存的 Key。"
        alert.addButton(withTitle: "保存并查询")
        alert.addButton(withTitle: "取消")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        let base = NSTextField(frame: NSRect(x: 0, y: 65, width: 400, height: 24))
        base.stringValue = UserDefaults.standard.string(forKey: "sub2BaseURL") ?? "https://dodoki.cc"
        base.placeholderString = "HTTPS Base URL"
        let key = NSSecureTextField(frame: NSRect(x: 0, y: 25, width: 400, height: 24))
        key.placeholderString = "API Key（不在聊天或日志中展示）"
        view.addSubview(base)
        view.addSubview(key)
        alert.accessoryView = view
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let endpoint = try Sub2Configuration(baseURL: base.stringValue, key: "placeholder").endpoint
            let secret: String
            if key.stringValue.isEmpty {
                secret = try savedSub2Key(endpoint: endpoint)
            } else {
                secret = key.stringValue
            }
            let config = try Sub2Configuration(baseURL: base.stringValue, key: secret)
            try Sub2Keychain.save(config)
            cachedSub2Key = (config.endpoint, config.key)
            UserDefaults.standard.set(base.stringValue, forKey: "sub2BaseURL")
            UserDefaults.standard.set(true, forKey: "sub2Enabled")
            generation += 1
            isRefreshing = false
            lastSub2Success = nil
            clearSub2("读取中…")
            refresh()
        } catch {
            let failure = NSAlert()
            failure.messageText = "配置未保存"
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    @objc private func toggleQuotaSource() {
        let target = QuotaSource(sub2Enabled: sub2Enabled).other
        if target == .local {
            useLocalCodex()
        } else {
            // Switching sources must not reopen setup or rewrite the saved key.
            UserDefaults.standard.set(true, forKey: "sub2Enabled")
            generation += 1
            isRefreshing = false
            lastSub2Success = nil
            clearSub2("读取中…")
            refresh()
        }
    }

    @objc private func useLocalCodex() {
        UserDefaults.standard.set(false, forKey: "sub2Enabled")
        generation += 1
        isRefreshing = false
        render(QuotaParsingError.missingWindow)
        refresh()
    }

    private func refreshSub2() {
        sourceItem.title = "数据源：Sub2API 分配额度（非上游 20x 总额度）"
        statusItemText.title = "正在查询 Sub2API…"
        lastSub2Attempt = Date()
        let requestGeneration = generation
        Task {
            do {
                let base = UserDefaults.standard.string(forKey: "sub2BaseURL") ?? "https://dodoki.cc"
                let endpoint = try Sub2Configuration(baseURL: base, key: "placeholder").endpoint
                let config = try Sub2Configuration(baseURL: base, key: savedSub2Key(endpoint: endpoint))
                let snapshot = try await Sub2QuotaClient().fetch(config)
                guard generation == requestGeneration else { return }
                isRefreshing = false
                renderSub2(snapshot)
            } catch {
                guard generation == requestGeneration else { return }
                isRefreshing = false
                clearSub2("暂无法获取")
                let last = lastSub2Success.map { " · 上次成功：" + Self.sub2Time($0) } ?? ""
                statusItemText.title = error.localizedDescription + last
            }
        }
    }

    private func savedSub2Key(endpoint: URL) throws -> String {
        if let cached = cachedSub2Key, cached.endpoint == endpoint {
            return cached.value
        }
        let value = try Sub2Keychain.read(endpoint: endpoint)
        cachedSub2Key = (endpoint, value)
        return value
    }

    private func clearSub2(_ message: String) {
        statusItem.button?.title = " Sub2 --%"
        statusItem.button?.toolTip = "Sub2API " + message
        statusItem.button?.image = quotaSymbol(for: 0)
        fiveHourRemainingItem.title = "日额度：" + message
        fiveHourUsedItem.title = "日已用 / 上限：—"
        fiveHourResetItem.title = "日重置：未知"
        weeklyRemainingItem.title = "周额度：" + message
        weeklyUsedItem.title = "周已用 / 上限：—"
        weeklyResetItem.title = "周重置：未知"
    }

    private func renderSub2(_ snapshot: Sub2Snapshot) {
        lastSub2Success = snapshot.fetchedAt
        sourceItem.title = "Sub2API · " + snapshot.scope
        func fill(_ window: Sub2Window?, _ label: String, _ remaining: NSMenuItem, _ used: NSMenuItem, _ reset: NSMenuItem) {
            guard let window else {
                remaining.title = "\(label)额度：未返回或未设上限"
                used.title = "\(label)已用 / 上限：—"
                reset.title = "\(label)重置：未知"
                return
            }
            let percent = Int(window.remainingPercent.rounded())
            remaining.title = "\(label)剩余：\(Self.amount(window.remaining)) USD（\(percent)%）"
            used.title = "\(label)已用 / 上限：\(Self.amount(window.used)) / \(Self.amount(window.limit)) USD"
            reset.title = "\(label)重置：\(formatReset(window.reset))"
        }
        fill(snapshot.daily, "日", fiveHourRemainingItem, fiveHourUsedItem, fiveHourResetItem)
        fill(snapshot.weekly, "周", weeklyRemainingItem, weeklyUsedItem, weeklyResetItem)
        statusItem.button?.title = snapshot.menuBarTitle
        if snapshot.daily == nil && snapshot.weekly == nil, let summary = snapshot.summary {
            weeklyRemainingItem.title = "综合剩余：\(Self.amount(summary)) USD（非周额度）"
        }
        let minimum = [snapshot.daily, snapshot.weekly].compactMap { $0?.remainingPercent }.min() ?? 100
        statusItem.button?.image = quotaSymbol(for: Int(minimum))
        statusItem.button?.toolTip = [sourceItem.title, fiveHourRemainingItem.title, weeklyRemainingItem.title].joined(separator: " · ")
        statusItemText.title = "5 分钟自动刷新 · 更新：" + Self.sub2Time(snapshot.fetchedAt)
    }

    private static func amount(_ value: Double) -> String { String(format: "%.2f", value) }
    private static func sub2Time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func render(_ snapshot: QuotaSnapshot) {
        guard let display = snapshot.preferredDisplayWindow else {
            render(QuotaParsingError.missingWindow)
            return
        }

        let displayRemaining = Int(display.remainingPercent.rounded())
        let warningRemaining = [snapshot.fiveHour, snapshot.weekly]
            .compactMap { $0 }
            .map { Int($0.remainingPercent.rounded()) }
            .min() ?? displayRemaining

        statusItem.button?.title = snapshot.fiveHour == nil ? " \(displayRemaining)%" : " 5h \(displayRemaining)%"
        statusItem.button?.image = quotaSymbol(for: warningRemaining)
        statusItem.button?.contentTintColor = nil
        statusItem.button?.toolTip = tooltip(for: snapshot)

        renderWindow(
            snapshot.fiveHour,
            remainingItem: fiveHourRemainingItem,
            usedItem: fiveHourUsedItem,
            resetItem: fiveHourResetItem,
            label: "5 小时"
        )
        renderWindow(
            snapshot.weekly,
            remainingItem: weeklyRemainingItem,
            usedItem: weeklyUsedItem,
            resetItem: weeklyResetItem,
            label: "本周"
        )
        statusItemText.title = "每分钟自动刷新 · 刚刚更新"
    }

    private func renderWindow(
        _ window: QuotaWindow?,
        remainingItem: NSMenuItem,
        usedItem: NSMenuItem,
        resetItem: NSMenuItem,
        label: String
    ) {
        guard let window else {
            remainingItem.title = "\(label)剩余：未返回"
            usedItem.title = "\(label)已使用：—"
            resetItem.title = "\(label)重置：—"
            return
        }
        remainingItem.title = "\(label)剩余：\(Int(window.remainingPercent.rounded()))%"
        usedItem.title = "\(label)已使用：\(Int(window.usedPercent.rounded()))%"
        resetItem.title = "\(label)重置：\(formatReset(window.resetsAt))"
    }

    private func tooltip(for snapshot: QuotaSnapshot) -> String {
        var parts: [String] = []
        if let fiveHour = snapshot.fiveHour {
            parts.append("5 小时剩余 \(Int(fiveHour.remainingPercent.rounded()))%")
        }
        if let weekly = snapshot.weekly {
            parts.append("本周剩余 \(Int(weekly.remainingPercent.rounded()))%")
        }
        return "Codex " + parts.joined(separator: " · ")
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
        fiveHourRemainingItem.title = "5 小时剩余：读取失败"
        fiveHourUsedItem.title = "5 小时已使用：—"
        fiveHourResetItem.title = "5 小时重置：—"
        weeklyRemainingItem.title = "本周剩余：读取失败"
        weeklyUsedItem.title = "本周已使用：—"
        weeklyResetItem.title = "本周重置：—"
        statusItemText.title = error.localizedDescription
    }

    private func quotaSymbol(for remaining: Int) -> NSImage? {
        switch remaining {
        case 20...:
            templateSymbol(
                named: "gauge.with.dots.needle.33percent",
                fallback: "gauge",
                description: "Codex 额度"
            )
        default:
            templateSymbol(
                named: "exclamationmark.triangle.fill",
                fallback: "exclamationmark.circle",
                description: "Codex 额度不足"
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
