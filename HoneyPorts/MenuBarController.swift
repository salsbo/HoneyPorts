//
//  MenuBarController.swift
//  HoneyPorts
//

import Cocoa
import ServiceManagement

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var isRunning = false
    private var totalConnections = 0
    private var lastKnownConnections = 0
    private var statsTimer: Timer?
    private var hasRecentAttempt = false
    private var attemptResetTimer: Timer?
    private var blinkTimer: Timer?
    private var blinkState = false
    private var activeHoneypotPorts: [Int] = []

    private var statusMenuItem: NSMenuItem!
    private var startStopMenuItem: NSMenuItem!
    private var portsMenuItem: NSMenuItem!
    private var attemptsMenuItem: NSMenuItem!
    private var autoStartMenuItem: NSMenuItem?
    private var inhibitAlarmMenuItem: NSMenuItem?
    private var languageMenuItem: NSMenuItem?
    private var isAlarmInhibited = false
    private var configWindow: PortConfigurationWindow?
    private var whitelistWindow: WhitelistWindow?

    private let autoStartKey = "HoneyPortsAutoStartEnabled"
    private let lastTCPPortsKey = "HoneyPortsLastTCPPorts"
    private let lastUDPPortsKey = "HoneyPortsLastUDPPorts"
    private let languageKey = "HoneyPortsLanguage"
    private var recentAttempts: [ConnectionAttempt] = []

    private enum IconState {
        case stopped
        case running
        case alert
    }

    // MARK: - Localization

    private enum Language: String {
        case french = "fr"
        case english = "en"
    }

    private var currentLanguage: Language {
        get {
            let saved = UserDefaults.standard.string(forKey: languageKey) ?? "fr"
            return Language(rawValue: saved) ?? .french
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
            refreshMenuTitles()
        }
    }

    private struct Strings {
        let statusStopped: String
        let statusRunning: String
        let start: String
        let stop: String
        let showLogs: String
        let clearBadgeLogs: String
        let inhibitAlarm: String
        let whitelist: String
        let honeypotPorts: String
        let attempts: String
        let noAttempt: String
        let autoStartLogin: String
        let quit: String
        let noActiveHoneypot: String
        let configRequired: String
        let configRequiredMsg: String
        let noPortSelected: String
        let noPortSelectedMsg: String
        let error: String
        let startFailed: String
        let honeypotRunning: String
        let stopAndQuit: String
        let cancel: String
        let stopAndQuitMsg: String
    }

    private var strings: Strings {
        switch currentLanguage {
        case .french:
            return Strings(
                statusStopped: "État: Arrêté",
                statusRunning: "État: En marche",
                start: "🚀 Démarrer",
                stop: "⏹️ Arrêter",
                showLogs: "Voir les logs",
                clearBadgeLogs: "Effacer badge & logs",
                inhibitAlarm: "Inhiber alarme",
                whitelist: "Whitelist IP...",
                honeypotPorts: "Ports honeypot",
                attempts: "Tentatives",
                noAttempt: "Aucune tentative",
                autoStartLogin: "Lancer au démarrage",
                quit: "Quitter",
                noActiveHoneypot: "Aucun honeypot actif",
                configRequired: "Configuration requise",
                configRequiredMsg: "Démarrez le honeypot manuellement au moins une fois pour enregistrer les ports.",
                noPortSelected: "Aucun port sélectionné",
                noPortSelectedMsg: "Veuillez sélectionner au moins un port ou activer ICMP/PING",
                error: "Erreur",
                startFailed: "Échec du démarrage du honeypot",
                honeypotRunning: "Honeypot en cours",
                stopAndQuit: "Arrêter et quitter",
                cancel: "Annuler",
                stopAndQuitMsg: "Voulez-vous arrêter le honeypot et quitter?"
            )
        case .english:
            return Strings(
                statusStopped: "Status: Stopped",
                statusRunning: "Status: Running",
                start: "🚀 Start",
                stop: "⏹️ Stop",
                showLogs: "Show Logs",
                clearBadgeLogs: "Clear badge & logs",
                inhibitAlarm: "Inhibit alarm",
                whitelist: "Whitelist IP...",
                honeypotPorts: "Honeypot ports",
                attempts: "Attempts",
                noAttempt: "No attempts",
                autoStartLogin: "Launch at login",
                quit: "Quit",
                noActiveHoneypot: "No active honeypot",
                configRequired: "Configuration required",
                configRequiredMsg: "Start the honeypot manually at least once to save the ports.",
                noPortSelected: "No port selected",
                noPortSelectedMsg: "Please select at least one port or enable ICMP/PING",
                error: "Error",
                startFailed: "Failed to start honeypot",
                honeypotRunning: "Honeypot is running",
                stopAndQuit: "Stop and Quit",
                cancel: "Cancel",
                stopAndQuitMsg: "Do you want to stop the honeypot and quit?"
            )
        }
    }

    override init() {
        super.init()
        setupMenuBar()
        startStatsPolling()
    }

    init(existingStatusItem: NSStatusItem) {
        super.init()
        self.statusItem = existingStatusItem
        setupMenuWithExistingStatusItem()
        startStatsPolling()
    }

    deinit {
        statsTimer?.invalidate()
        attemptResetTimer?.invalidate()
        blinkTimer?.invalidate()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "🍯"
        }

        menu = NSMenu()
        buildMenu()
        statusItem.menu = menu
        updateIcon(state: .stopped)
    }

    private func setupMenuWithExistingStatusItem() {
        menu = NSMenu()
        buildMenu()
        statusItem.menu = menu
        updateIcon(state: .stopped)
    }

    private func buildMenu() {
        menu.removeAllItems()

        statusMenuItem = NSMenuItem(title: strings.statusStopped, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        startStopMenuItem = NSMenuItem(title: strings.start, action: #selector(toggleHoneypot), keyEquivalent: "s")
        startStopMenuItem.target = self
        menu.addItem(startStopMenuItem)

        menu.addItem(NSMenuItem.separator())

        let logsItem = NSMenuItem(title: strings.showLogs, action: #selector(showLogs), keyEquivalent: "l")
        logsItem.target = self
        menu.addItem(logsItem)

        let clearItem = NSMenuItem(title: strings.clearBadgeLogs, action: #selector(clearAll), keyEquivalent: "c")
        clearItem.target = self
        menu.addItem(clearItem)

        let inhibitItem = NSMenuItem(title: strings.inhibitAlarm, action: #selector(toggleInhibitAlarm), keyEquivalent: "i")
        inhibitItem.target = self
        inhibitItem.state = isAlarmInhibited ? .on : .off
        menu.addItem(inhibitItem)
        inhibitAlarmMenuItem = inhibitItem

        menu.addItem(NSMenuItem.separator())

        let whitelistItem = NSMenuItem(title: strings.whitelist, action: #selector(showWhitelist), keyEquivalent: "w")
        whitelistItem.target = self
        menu.addItem(whitelistItem)

        menu.addItem(NSMenuItem.separator())

        portsMenuItem = NSMenuItem(title: strings.honeypotPorts, action: nil, keyEquivalent: "")
        let portsSubmenu = NSMenu()
        portsMenuItem.submenu = portsSubmenu
        menu.addItem(portsMenuItem)

        attemptsMenuItem = NSMenuItem(title: strings.attempts, action: nil, keyEquivalent: "")
        let attemptsSubmenu = NSMenu()
        attemptsMenuItem.submenu = attemptsSubmenu
        menu.addItem(attemptsMenuItem)

        menu.addItem(NSMenuItem.separator())

        let autoStartItem = NSMenuItem(title: strings.autoStartLogin, action: #selector(toggleAutoStartPreference), keyEquivalent: "")
        autoStartItem.target = self
        autoStartItem.state = isAutoStartEnabled ? .on : .off
        menu.addItem(autoStartItem)
        autoStartMenuItem = autoStartItem

        let langItem = NSMenuItem(title: currentLanguage == .french ? "Langue" : "Language", action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu()

        let frItem = NSMenuItem(title: "Français", action: #selector(setLanguageFrench), keyEquivalent: "")
        frItem.target = self
        frItem.state = currentLanguage == .french ? .on : .off
        langSubmenu.addItem(frItem)

        let enItem = NSMenuItem(title: "English", action: #selector(setLanguageEnglish), keyEquivalent: "")
        enItem.target = self
        enItem.state = currentLanguage == .english ? .on : .off
        langSubmenu.addItem(enItem)

        langItem.submenu = langSubmenu
        menu.addItem(langItem)
        languageMenuItem = langItem

        let quitItem = NSMenuItem(title: strings.quit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        updatePortsSubmenu()
        refreshAttemptsMenu()
    }

    private func refreshMenuTitles() {
        buildMenu()
        updateMenuStatus()
    }

    @objc private func setLanguageFrench() {
        currentLanguage = .french
    }

    @objc private func setLanguageEnglish() {
        currentLanguage = .english
    }

    private func updateMenuStatus() {
        if isRunning {
            statusMenuItem.title = strings.statusRunning
            startStopMenuItem.title = strings.stop
            updateIcon(state: hasRecentAttempt ? .alert : .running)
        } else {
            statusMenuItem.title = strings.statusStopped
            startStopMenuItem.title = strings.start
            updateIcon(state: .stopped)
        }
        updatePortsSubmenu()
        updateAttemptsSubmenu()
    }

    // MARK: - Icon Management

    private func updateIcon(state: IconState) {
        guard let button = statusItem.button else { return }

        let imageName: String
        let fallbackEmoji: String
        switch state {
        case .stopped:
            imageName = "grey"
            fallbackEmoji = "⚪"
        case .running, .alert:
            imageName = "or"
            fallbackEmoji = "🍯"
        }

        if let image = NSImage(named: imageName) {
            image.size = NSSize(width: 40, height: 40)
            image.isTemplate = false
            button.image = image
            updateButtonTitle()
        } else {
            button.image = nil
            button.title = fallbackEmoji
        }
    }

    private func updateButtonTitle() {
        guard let button = statusItem.button else { return }

        let newConnections = totalConnections - lastKnownConnections
        let title = NSMutableAttributedString()

        if newConnections > 0 && isRunning {
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.systemRed,
                .font: NSFont.boldSystemFont(ofSize: 10)
            ]
            title.append(NSAttributedString(string: "\(newConnections)", attributes: badgeAttrs))
        }

        if hasRecentAttempt && !isAlarmInhibited && blinkState {
            let alertAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.boldSystemFont(ofSize: 14)
            ]
            title.append(NSAttributedString(string: "!", attributes: alertAttrs))
        }

        button.attributedTitle = title
    }

    private func triggerAlertIcon() {
        hasRecentAttempt = true
        if !isAlarmInhibited {
            startBlinking()
        }
    }

    private func startBlinking() {
        blinkTimer?.invalidate()
        blinkState = true
        updateButtonTitle()

        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning, !self.isAlarmInhibited else {
                self?.stopBlinking()
                return
            }
            self.blinkState.toggle()
            self.updateButtonTitle()
        }
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkState = false
        updateButtonTitle()
    }

    @objc private func toggleInhibitAlarm() {
        isAlarmInhibited.toggle()
        inhibitAlarmMenuItem?.state = isAlarmInhibited ? .on : .off

        if isAlarmInhibited {
            stopBlinking()
        } else {
            if hasRecentAttempt {
                startBlinking()
            }
        }
    }

    // MARK: - Ports Submenu

    private func updatePortsSubmenu() {
        guard let submenu = portsMenuItem.submenu else { return }
        submenu.removeAllItems()

        if activeHoneypotPorts.isEmpty {
            let emptyItem = NSMenuItem(title: strings.noActiveHoneypot, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for port in activeHoneypotPorts.sorted() {
                let service = getServiceName(for: port)
                let item = NSMenuItem(title: "🍯 \(port) - \(service)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                submenu.addItem(item)
            }
        }
    }

    // MARK: - Attempts Submenu

    private func updateAttemptsSubmenu() {
        guard attemptsMenuItem.submenu != nil else { return }
        attemptsMenuItem.title = totalConnections > 0 ? "\(strings.attempts) (\(totalConnections))" : strings.attempts
        loadRecentAttempts()
    }

    private func refreshAttemptsMenu() {
        guard let submenu = attemptsMenuItem.submenu else { return }
        submenu.removeAllItems()

        if recentAttempts.isEmpty {
            let emptyItem = NSMenuItem(title: strings.noAttempt, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "dd/MM HH:mm:ss"

            for attempt in recentAttempts {
                let dateStr = displayFormatter.string(from: attempt.timestamp)
                let title: String
                if attempt.destinationPort == 0 {
                    title = "🏓 [\(dateStr)] \(attempt.sourceIP) → ICMP"
                } else {
                    let service = getServiceName(for: attempt.destinationPort)
                    title = "🚨 [\(dateStr)] \(attempt.sourceIP) → \(attempt.destinationPort) (\(service))"
                }

                let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                menuItem.isEnabled = false
                submenu.addItem(menuItem)
            }
        }
    }

    private func loadRecentAttempts() {
        XPCClient.shared.getRecentLogEntries(limit: 10) { [weak self] entries in
            guard let self = self else { return }

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            var newAttempts: [ConnectionAttempt] = []

            for json in entries {
                let sourceIP = json["sourceIP"] as? String ?? "unknown"
                let sourcePort = json["sourcePort"] as? Int ?? 0
                let destPort = json["port"] as? Int ?? 0
                let timestampStr = json["timestamp"] as? String ?? ""

                var timestamp = dateFormatter.date(from: timestampStr)
                if timestamp == nil {
                    let fallbackFormatter = ISO8601DateFormatter()
                    timestamp = fallbackFormatter.date(from: timestampStr)
                }

                newAttempts.append(ConnectionAttempt(
                    timestamp: timestamp ?? Date(),
                    sourceIP: sourceIP,
                    sourcePort: sourcePort,
                    destinationPort: destPort,
                    service: self.getServiceName(for: destPort)
                ))
            }

            DispatchQueue.main.async {
                self.recentAttempts = newAttempts
                self.refreshAttemptsMenu()
            }
        }
    }

    // MARK: - Honeypot Control

    @objc private func toggleHoneypot() {
        if isRunning {
            stopHoneypot()
        } else {
            startHoneypot()
        }
    }

    private func startHoneypot() {
        configWindow = PortConfigurationWindow { [weak self] configurations, icmpEnabled in
            guard let self = self else { return }

            var tcpPorts: [Int] = []
            var udpPorts: [Int] = []

            for config in configurations {
                switch config.netProtocol {
                case .tcp:
                    tcpPorts.append(config.port)
                case .udp:
                    udpPorts.append(config.port)
                }
            }

            tcpPorts = Array(tcpPorts.prefix(200))
            udpPorts = Array(udpPorts.prefix(200))

            guard !tcpPorts.isEmpty || !udpPorts.isEmpty || icmpEnabled else {
                let errorAlert = NSAlert()
                errorAlert.messageText = self.strings.noPortSelected
                errorAlert.informativeText = self.strings.noPortSelectedMsg
                errorAlert.alertStyle = .warning
                self.presentAlert(errorAlert)
                return
            }

            self.startHoneypotWithPorts(tcpPorts: tcpPorts, udpPorts: udpPorts, icmpEnabled: icmpEnabled)
        }

        configWindow?.showWindow(nil)
        configWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startHoneypotWithPorts(tcpPorts: [Int], udpPorts: [Int], icmpEnabled: Bool = false) {
        guard !tcpPorts.isEmpty || !udpPorts.isEmpty || icmpEnabled else {
            showAlert(title: strings.noPortSelected, message: strings.noPortSelectedMsg)
            return
        }

        XPCClient.shared.stopListeners { [weak self] _ in
            guard let self = self else { return }

            let group = DispatchGroup()
            var tcpSuccess = tcpPorts.isEmpty
            var udpSuccess = udpPorts.isEmpty
            var icmpSuccess = !icmpEnabled

            if !tcpPorts.isEmpty {
                group.enter()
                XPCClient.shared.startListeners(ports: tcpPorts) { success in
                    tcpSuccess = success
                    group.leave()
                }
            }

            if !udpPorts.isEmpty {
                group.enter()
                XPCClient.shared.startUDPListeners(ports: udpPorts) { success in
                    udpSuccess = success
                    group.leave()
                }
            }

            if icmpEnabled {
                group.enter()
                XPCClient.shared.startICMPMonitoring { success in
                    icmpSuccess = success
                    group.leave()
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                let overallSuccess = tcpSuccess || udpSuccess || icmpSuccess

                if overallSuccess {
                    self.isRunning = true
                    self.activeHoneypotPorts = tcpPorts + udpPorts
                    self.persistPortConfiguration(tcpPorts: tcpPorts, udpPorts: udpPorts)
                    self.updateMenuStatus()
                } else {
                    self.showAlert(title: self.strings.error, message: self.strings.startFailed)
                }
            }
        }
    }

    private func stopHoneypot() {
        XPCClient.shared.stopListeners { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.isRunning = false
                    self?.activeHoneypotPorts = []
                    self?.hasRecentAttempt = false
                    self?.attemptResetTimer?.invalidate()
                    self?.updateMenuStatus()
                }
            }
        }
    }

    // MARK: - Auto-Start (App only, not honeypot)

    private var isAutoStartEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return UserDefaults.standard.bool(forKey: autoStartKey)
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Silently handle error
                }
            } else {
                UserDefaults.standard.set(newValue, forKey: autoStartKey)
            }
        }
    }

    private func persistPortConfiguration(tcpPorts: [Int], udpPorts: [Int]) {
        UserDefaults.standard.set(tcpPorts, forKey: lastTCPPortsKey)
        UserDefaults.standard.set(udpPorts, forKey: lastUDPPortsKey)
    }

    @objc private func toggleAutoStartPreference() {
        isAutoStartEnabled.toggle()
        autoStartMenuItem?.state = isAutoStartEnabled ? .on : .off
    }

    // MARK: - Menu Actions

    @objc private func showLogs() {
        let logViewer = LogViewer()
        logViewer.showWindow(nil)
        logViewer.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showWhitelist() {
        whitelistWindow = WhitelistWindow()
        whitelistWindow?.showWindow(nil)
        whitelistWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        if isRunning {
            let alert = NSAlert()
            alert.messageText = strings.honeypotRunning
            alert.informativeText = strings.stopAndQuitMsg
            alert.alertStyle = .warning
            alert.addButton(withTitle: strings.stopAndQuit)
            alert.addButton(withTitle: strings.cancel)

            let presentQuitDecision: (NSApplication.ModalResponse) -> Void = { response in
                if response == .alertFirstButtonReturn {
                    XPCClient.shared.stopListeners { _ in
                        DispatchQueue.main.async {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
            }

            if let window = NSApp.keyWindow ?? NSApp.windows.first {
                alert.beginSheetModal(for: window, completionHandler: presentQuitDecision)
            } else {
                let response = alert.runModal()
                presentQuitDecision(response)
            }
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    @objc private func clearAll() {
        XPCClient.shared.clearLogs { [weak self] _ in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.recentAttempts.removeAll()
                self.lastKnownConnections = 0
                self.totalConnections = 0
                self.attemptsMenuItem.title = self.strings.attempts
                self.hasRecentAttempt = false
                self.stopBlinking()
                self.refreshAttemptsMenu()
                self.updateIcon(state: self.isRunning ? .running : .stopped)
                self.updateMenuBarBadge()
            }
        }
    }

    // MARK: - Helpers

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        presentAlert(alert)
    }

    private func presentAlert(_ alert: NSAlert) {
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func getServiceName(for port: Int) -> String {
        let knownPorts: [Int: String] = [
            3000: "dev server", 3001: "dev server", 4200: "Angular",
            5000: "Flask/dev", 5173: "Vite", 8000: "HTTP alt",
            8080: "HTTP proxy", 8443: "HTTPS alt", 8888: "HTTP alt",
            9000: "PHP-FPM", 1433: "MSSQL", 3306: "MySQL",
            5432: "PostgreSQL", 6379: "Redis", 9200: "Elasticsearch",
            27017: "MongoDB", 22: "SSH", 2222: "SSH alt",
            3389: "RDP", 5900: "VNC", 1080: "SOCKS",
            2375: "Docker", 3128: "Squid", 5601: "Kibana",
            11211: "Memcached"
        ]
        return knownPorts[port] ?? "port \(port)"
    }

    // MARK: - Stats Polling

    private func startStatsPolling() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        statsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollStatsAndRefresh()
        }
    }

    @objc private func handleWakeFromSleep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.pollStatsAndRefresh()
        }
    }

    private func pollStatsAndRefresh() {
        guard isRunning else { return }

        XPCClient.shared.getStats { [weak self] stats in
            guard let self = self else { return }

            DispatchQueue.main.async {
                let newTotal = stats["totalConnections"] ?? 0

                if newTotal > self.totalConnections {
                    self.triggerAlertIcon()
                    self.loadRecentAttempts()
                }
                self.totalConnections = newTotal
                self.updateMenuBarBadge()
                self.attemptsMenuItem.title = newTotal > 0 ? "\(self.strings.attempts) (\(newTotal))" : self.strings.attempts
            }
        }
    }

    private func updateMenuBarBadge() {
        updateButtonTitle()
    }
}

// MARK: - ConnectionAttempt

struct ConnectionAttempt {
    let timestamp: Date
    let sourceIP: String
    let sourcePort: Int
    let destinationPort: Int
    let service: String

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            return "\(Int(interval / 60))min"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else {
            return "\(Int(interval / 86400))d"
        }
    }
}
