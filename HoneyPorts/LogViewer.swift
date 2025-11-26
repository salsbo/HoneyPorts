//
//  LogViewer.swift
//  HoneypotApp
//

import Cocoa
import UniformTypeIdentifiers

class LogViewer: NSWindowController {

    private var textView: NSTextView!
    private var scrollView: NSScrollView!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Honeypot Logs"
        window.center()

        self.init(window: window)
        setupUI()
        loadLogs()
    }

    private func setupUI() {
        guard let window = window else { return }

        scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder

        textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        textView.textColor = NSColor.white

        scrollView.documentView = textView

        let toolbar = NSToolbar(identifier: "LogViewerToolbar")
        toolbar.displayMode = .iconOnly
        let refreshButton = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("refresh"))
        refreshButton.label = "Refresh"
        refreshButton.paletteLabel = "Refresh"
        refreshButton.toolTip = "Refresh logs"
        refreshButton.target = self
        refreshButton.action = #selector(refreshLogs)

        window.toolbar = toolbar
        window.contentView = scrollView

        let button = NSButton(frame: NSRect(x: 10, y: window.contentView!.bounds.height - 40, width: 100, height: 30))
        button.title = "Refresh"
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(refreshLogs)
        button.autoresizingMask = [.minYMargin]

        window.contentView?.addSubview(button)

        let exportButton = NSButton(frame: NSRect(x: 120, y: window.contentView!.bounds.height - 40, width: 120, height: 30))
        exportButton.title = "Exporter TXT"
        exportButton.bezelStyle = .rounded
        exportButton.target = self
        exportButton.action = #selector(exportLogs)
        exportButton.autoresizingMask = [.minYMargin]
        if let downloadImage = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: "Export") {
            exportButton.image = downloadImage
            exportButton.imagePosition = .imageLeading
        }

        window.contentView?.addSubview(exportButton)
    }

    @objc private func refreshLogs() {
        loadLogs()
    }

    @objc private func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "honeypot_logs_\(formattedDate()).txt"
        savePanel.title = "Exporter les logs"
        savePanel.message = "Choisissez où enregistrer le fichier de logs"

        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            guard let self = self else { return }

            let content = self.textView.string
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                NSLog("Logs exportés vers: \(url.path)")

                // Show success alert
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Export réussi"
                    alert.informativeText = "Les logs ont été exportés vers:\n\(url.path)"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Ouvrir dans Finder")
                    let result = alert.runModal()
                    if result == .alertSecondButtonReturn {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                    }
                }
            } catch {
                NSLog("Erreur export logs: \(error)")
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Erreur d'export"
                    alert.informativeText = "Impossible d'exporter les logs: \(error.localizedDescription)"
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter.string(from: Date())
    }

    private func loadLogs() {
        // Fetch logs from XPC service (in sandboxed container)
        XPCClient.shared.getRecentLogEntries(limit: 1000) { [weak self] entries in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if entries.isEmpty {
                    self.textView.string = ""
                } else {
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                    let minuteFormatter = DateFormatter()
                    minuteFormatter.dateFormat = "yyyy-MM-dd HH:mm"
                    minuteFormatter.timeZone = .current

                    let dateTimeFormatter = DateFormatter()
                    dateTimeFormatter.dateFormat = "dd/MM/yyyy HH:mm"
                    dateTimeFormatter.timeZone = .current
                    dateTimeFormatter.locale = Locale(identifier: "fr_FR")

                    // Group entries by minute, source IP, and type (port for TCP/UDP, "icmp" for ICMP)
                    struct GroupKey: Hashable {
                        let minute: String
                        let sourceIP: String
                        let type: String // port number as string, or "icmp"
                    }

                    var groups: [GroupKey: (count: Int, latestTimestamp: Date, protocol: String)] = [:]

                    for entry in entries {
                        let sourceIP = entry["sourceIP"] as? String ?? "unknown"
                        let port = entry["port"] as? Int ?? 0
                        let event = entry["event"] as? String ?? ""
                        let proto = entry["protocol"] as? String ?? "TCP"
                        let timestampStr = entry["timestamp"] as? String ?? ""
                        let timestamp = isoFormatter.date(from: timestampStr) ?? Date.distantPast
                        let minuteKey = minuteFormatter.string(from: timestamp)

                        let type: String
                        if port == 0 || event == "icmp_ping" {
                            type = "icmp"
                        } else {
                            type = "\(port)"
                        }

                        let key = GroupKey(minute: minuteKey, sourceIP: sourceIP, type: type)

                        if var existing = groups[key] {
                            existing.count += 1
                            if timestamp > existing.latestTimestamp {
                                existing.latestTimestamp = timestamp
                            }
                            groups[key] = existing
                        } else {
                            groups[key] = (count: 1, latestTimestamp: timestamp, protocol: type == "icmp" ? "ICMP" : proto)
                        }
                    }

                    // Convert to array and sort by timestamp (most recent first)
                    var sortedGroups = groups.map { (key: $0.key, value: $0.value) }
                    sortedGroups.sort { $0.value.latestTimestamp > $1.value.latestTimestamp }

                    // Build attributed string with human-readable phrases
                    let attributedText = NSMutableAttributedString()

                    let normalFont = NSFont.systemFont(ofSize: 13, weight: .regular)
                    let boldFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

                    // Filter out entries with count == 0
                    let validGroups = sortedGroups.filter { $0.value.count > 0 }

                    for (index, group) in validGroups.enumerated() {
                        let dateTimeStr = dateTimeFormatter.string(from: group.value.latestTimestamp)
                        let sourceIP = group.key.sourceIP
                        let count = group.value.count
                        let proto = group.value.protocol

                        var phrase: String
                        var color: NSColor

                        if group.key.type == "icmp" {
                            color = NSColor.systemOrange
                            if count == 1 {
                                phrase = "Le \(dateTimeStr), 1 ping de \(sourceIP)"
                            } else {
                                phrase = "Le \(dateTimeStr), \(count) pings de \(sourceIP)"
                            }
                        } else {
                            let port = group.key.type
                            if proto == "UDP" {
                                color = NSColor.systemCyan
                            } else {
                                color = NSColor.systemGreen
                            }

                            if count == 1 {
                                phrase = "Le \(dateTimeStr), 1 tentative \(proto) de \(sourceIP) sur le port \(port)"
                            } else {
                                phrase = "Le \(dateTimeStr), \(count) tentatives \(proto) de \(sourceIP) sur le port \(port)"
                            }
                        }

                        // Main phrase
                        attributedText.append(NSAttributedString(string: phrase, attributes: [
                            .font: boldFont,
                            .foregroundColor: color
                        ]))

                        // Newline
                        if index < validGroups.count - 1 {
                            attributedText.append(NSAttributedString(string: "\n\n", attributes: [.font: normalFont]))
                        }
                    }

                    self.textView.textStorage?.setAttributedString(attributedText)
                }
            }
        }
    }
}
