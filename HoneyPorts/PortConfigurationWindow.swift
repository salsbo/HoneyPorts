//
//  PortConfigurationWindow.swift
//  HoneyPorts
//

import Cocoa

struct PortConfiguration {
    let port: Int
    let netProtocol: NetworkProtocol
    let description: String
    var isEnabled: Bool
    var isInUse: Bool  // Indicates if port is already occupied by system

    enum NetworkProtocol: String {
        case tcp = "TCP"
        case udp = "UDP"
    }
}

class PortConfigurationWindow: NSWindowController, NSWindowDelegate {

    private var tableView: NSTableView!
    private var configurations: [PortConfiguration] = []
    private var selectedCountLabel: NSTextField!
    private var icmpCheckbox: NSButton!
    private var completion: (([PortConfiguration], Bool) -> Void)?  // Bool = ICMP enabled

    convenience init(completion: @escaping ([PortConfiguration], Bool) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Configuration du Honeypot"
        window.center()

        self.init(window: window)

        self.completion = completion
        setupUI()
        loadDefaultConfigurations()
    }

    private func setupUI() {
        guard let window = window else { return }

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        // Header
        let headerLabel = NSTextField(labelWithString: "Sélectionnez les ports à surveiller")
        headerLabel.font = NSFont.boldSystemFont(ofSize: 16)
        headerLabel.frame = NSRect(x: 20, y: 470, width: 660, height: 30)
        contentView.addSubview(headerLabel)

        // Three main preset buttons: TCP, UDP, TOUS
        let buttonWidth: CGFloat = 200
        let buttonSpacing: CGFloat = 15
        let buttonY: CGFloat = 435

        let tcpBtn = createPresetButton(title: "TCP", x: 20, y: buttonY, width: buttonWidth)
        tcpBtn.target = self
        tcpBtn.action = #selector(addTCPPorts)
        contentView.addSubview(tcpBtn)

        let udpBtn = createPresetButton(title: "UDP", x: 20 + buttonWidth + buttonSpacing, y: buttonY, width: buttonWidth)
        udpBtn.target = self
        udpBtn.action = #selector(addUDPPorts)
        contentView.addSubview(udpBtn)

        let allPortsBtn = createPresetButton(title: "TOUS (TCP+UDP)", x: 20 + (buttonWidth + buttonSpacing) * 2, y: buttonY, width: buttonWidth)
        allPortsBtn.target = self
        allPortsBtn.action = #selector(addAllPorts)
        contentView.addSubview(allPortsBtn)

        // ICMP/PING checkbox
        icmpCheckbox = NSButton(checkboxWithTitle: "ICMP/PING", target: nil, action: nil)
        icmpCheckbox.frame = NSRect(x: 20, y: 405, width: 150, height: 20)
        icmpCheckbox.state = .off
        contentView.addSubview(icmpCheckbox)

        // Table view
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 100, width: 660, height: 290))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.autoresizingMask = [.width, .height]

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.style = .fullWidth
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.usesAlternatingRowBackgroundColors = true

        // Columns
        let enabledColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
        enabledColumn.title = "Actif"
        enabledColumn.width = 50
        tableView.addTableColumn(enabledColumn)

        let portColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("port"))
        portColumn.title = "Port"
        portColumn.width = 80
        tableView.addTableColumn(portColumn)

        let protocolColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("protocol"))
        protocolColumn.title = "Protocole"
        protocolColumn.width = 100
        tableView.addTableColumn(protocolColumn)

        let descColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("description"))
        descColumn.title = "Description"
        descColumn.width = 430
        tableView.addTableColumn(descColumn)

        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        // Add/Remove buttons (no emojis)
        let addButton = NSButton(frame: NSRect(x: 20, y: 60, width: 110, height: 32))
        addButton.title = "Ajouter port"
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addCustomPort)
        contentView.addSubview(addButton)

        let removeButton = NSButton(frame: NSRect(x: 140, y: 60, width: 100, height: 32))
        removeButton.title = "Supprimer"
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeSelectedPort)
        contentView.addSubview(removeButton)

        let clearButton = NSButton(frame: NSRect(x: 250, y: 60, width: 100, height: 32))
        clearButton.title = "Tout effacer"
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearAll)
        contentView.addSubview(clearButton)

        // Selected count
        selectedCountLabel = NSTextField(labelWithString: "0 ports sélectionnés")
        selectedCountLabel.font = NSFont.systemFont(ofSize: 12)
        selectedCountLabel.frame = NSRect(x: 420, y: 68, width: 260, height: 20)
        selectedCountLabel.alignment = .right
        contentView.addSubview(selectedCountLabel)

        // Bottom buttons
        let cancelButton = NSButton(frame: NSRect(x: 480, y: 20, width: 90, height: 32))
        cancelButton.title = "Annuler"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        contentView.addSubview(cancelButton)

        let startButton = NSButton(frame: NSRect(x: 580, y: 20, width: 100, height: 32))
        startButton.title = "Démarrer"
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.target = self
        startButton.action = #selector(start)
        contentView.addSubview(startButton)

        window.delegate = self
    }

    private func createPresetButton(title: String, x: CGFloat, y: CGFloat, width: CGFloat = 120) -> NSButton {
        let button = NSButton(frame: NSRect(x: x, y: y, width: width, height: 28))
        button.title = title
        button.bezelStyle = .rounded
        return button
    }

    private func loadDefaultConfigurations() {
        // Start with empty configurations - user will click buttons to add ports
        configurations = []
        tableView?.reloadData()
        updateSelectedCount()
    }

    private let commonTCPPorts: [(Int, String)] = [
        // Development
        (3000, "Node.js/React"),
        (3001, "Next.js dev"),
        (4200, "Angular dev"),
        (5000, "Flask/React"),
        (8000, "HTTP alt"),
        (8080, "HTTP proxy"),
        (8443, "HTTPS alt"),
        (8888, "Jupyter"),
        (9000, "SonarQube"),
        // Databases
        (1433, "MS SQL Server"),
        (3306, "MySQL"),
        (5432, "PostgreSQL"),
        (6379, "Redis"),
        (9200, "Elasticsearch"),
        (27017, "MongoDB"),
        // Remote Access
        (2222, "SSH alternatif"),
        (3389, "RDP (Remote Desktop)"),
        (5900, "VNC"),
        // Services
        (1080, "SOCKS proxy"),
        (2375, "Docker"),
        (3128, "Squid proxy"),
        (5601, "Kibana"),
        (11211, "Memcached")
    ]

    private let commonUDPPorts: [(Int, String)] = [
        (53, "DNS"),
        (69, "TFTP"),
        (123, "NTP"),
        (137, "NetBIOS Name"),
        (138, "NetBIOS Datagram"),
        (161, "SNMP"),
        (162, "SNMP Trap"),
        (500, "IKE/IPsec"),
        (514, "Syslog"),
        (1194, "OpenVPN"),
        (1900, "SSDP/UPnP"),
        (4500, "NAT-T IPsec"),
        (5353, "mDNS"),
        (5060, "SIP")
    ]

    @objc private func addTCPPorts() {
        togglePortsForProtocol(ports: commonTCPPorts, proto: .tcp)
    }

    @objc private func addUDPPorts() {
        togglePortsForProtocol(ports: commonUDPPorts, proto: .udp)
    }

    private func togglePortsForProtocol(ports: [(Int, String)], proto: PortConfiguration.NetworkProtocol) {
        let allExist = ports.allSatisfy { (port, _) in
            configurations.contains(where: { $0.port == port && $0.netProtocol == proto })
        }

        if allExist {
            // Remove all ports of this protocol from this preset
            let portNumbers = Set(ports.map { $0.0 })
            configurations.removeAll { config in
                portNumbers.contains(config.port) && config.netProtocol == proto
            }
        } else {
            // Add missing ports (keeping existing ones)
            let protoChecker: PortChecker.NetworkProtocol = proto == .tcp ? .tcp : .udp
            for (port, desc) in ports {
                // Only add if not already present with same protocol
                if !configurations.contains(where: { $0.port == port && $0.netProtocol == proto }) {
                    let isInUse = PortChecker.isPortInUse(port, protocol: protoChecker)
                    configurations.append(PortConfiguration(
                        port: port,
                        netProtocol: proto,
                        description: desc,
                        isEnabled: !isInUse,
                        isInUse: isInUse
                    ))
                }
            }
        }

        configurations.sort { $0.port < $1.port }
        tableView.reloadData()
        updateSelectedCount()
    }

    @objc private func addAllPorts() {
        configurations.removeAll()

        for (port, desc) in commonTCPPorts {
            let isInUse = PortChecker.isPortInUse(port, protocol: .tcp)
            let config = PortConfiguration(
                port: port,
                netProtocol: .tcp,
                description: desc,
                isEnabled: !isInUse,
                isInUse: isInUse
            )
            configurations.append(config)
        }

        for (port, desc) in commonUDPPorts {
            let isInUse = PortChecker.isPortInUse(port, protocol: .udp)
            let config = PortConfiguration(
                port: port,
                netProtocol: .udp,
                description: desc,
                isEnabled: !isInUse,
                isInUse: isInUse
            )
            configurations.append(config)
        }

        configurations.sort { $0.port < $1.port }
        icmpCheckbox.state = .on

        tableView.reloadData()
        updateSelectedCount()
    }

    private func togglePorts(_ ports: [(Int, String)]) {
        let portNumbers = ports.map { $0.0 }
        let allExist = portNumbers.allSatisfy { port in
            configurations.contains(where: { $0.port == port })
        }

        if allExist {
            // Remove all ports from this preset
            configurations.removeAll { config in
                portNumbers.contains(config.port)
            }
        } else {
            for (port, desc) in ports {
                if !configurations.contains(where: { $0.port == port }) {
                    let isInUse = PortChecker.isPortInUse(port, protocol: .tcp)
                    configurations.append(PortConfiguration(
                        port: port,
                        netProtocol: .tcp,
                        description: desc,
                        isEnabled: !isInUse,  // Disable if in use
                        isInUse: isInUse
                    ))
                }
            }
        }

        configurations.sort { $0.port < $1.port }
        tableView.reloadData()
        updateSelectedCount()
    }

    @objc private func addCustomPort() {
        let alert = NSAlert()
        alert.messageText = "Ajouter un port personnalisé"
        alert.informativeText = "Entrez le numéro de port (1024-65535):"
        alert.alertStyle = .informational

        let portField = NSTextField(frame: NSRect(x: 0, y: 30, width: 200, height: 24))
        portField.placeholderString = "Port (ex: 1234)"
        portField.isEditable = true
        portField.isSelectable = true
        portField.isBordered = true
        portField.isBezeled = true
        portField.bezelStyle = .squareBezel
        portField.drawsBackground = true
        portField.backgroundColor = .white

        let descField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        descField.placeholderString = "Description (optionnelle)"
        descField.isEditable = true
        descField.isSelectable = true
        descField.isBordered = true
        descField.isBezeled = true
        descField.bezelStyle = .squareBezel
        descField.drawsBackground = true
        descField.backgroundColor = .white

        let protocolPopup = NSPopUpButton(frame: NSRect(x: 0, y: 60, width: 200, height: 24))
        protocolPopup.addItems(withTitles: ["TCP", "UDP"])

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 90))
        accessoryView.addSubview(protocolPopup)
        accessoryView.addSubview(portField)
        accessoryView.addSubview(descField)

        alert.accessoryView = accessoryView
        alert.addButton(withTitle: "Ajouter")
        alert.addButton(withTitle: "Annuler")

        if alert.runModal() == .alertFirstButtonReturn {
            if let port = Int(portField.stringValue), port >= 1024, port <= 65535 {
                let proto: PortConfiguration.NetworkProtocol = protocolPopup.indexOfSelectedItem == 0 ? .tcp : .udp
                let desc = descField.stringValue.isEmpty ? "Port personnalisé" : descField.stringValue

                if !configurations.contains(where: { $0.port == port }) {
                    let protoEnum: PortChecker.NetworkProtocol = proto == .tcp ? .tcp : .udp
                    let isInUse = PortChecker.isPortInUse(port, protocol: protoEnum)

                    configurations.append(PortConfiguration(
                        port: port,
                        netProtocol: proto,
                        description: desc,
                        isEnabled: !isInUse,  // Disable if in use
                        isInUse: isInUse
                    ))
                    configurations.sort { $0.port < $1.port }
                    tableView.reloadData()
                    updateSelectedCount()
                }
            }
        }
    }

    @objc private func removeSelectedPort() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < configurations.count else { return }

        configurations.remove(at: selectedRow)
        tableView.reloadData()
        updateSelectedCount()
    }

    @objc private func clearAll() {
        configurations.removeAll()
        tableView.reloadData()
        updateSelectedCount()
    }

    private func updateSelectedCount() {
        let enabledCount = configurations.filter { $0.isEnabled }.count
        let tcpCount = configurations.filter { $0.isEnabled && $0.netProtocol == .tcp }.count
        let udpCount = configurations.filter { $0.isEnabled && $0.netProtocol == .udp }.count

        selectedCountLabel.stringValue = "\(enabledCount) ports sélectionnés (TCP: \(tcpCount), UDP: \(udpCount))"
    }

    @objc private func cancel() {
        window?.close()
    }

    @objc private func start() {
        let availableConfigs = configurations.filter { $0.isEnabled && !$0.isInUse }
        let icmpEnabled = icmpCheckbox.state == .on

        completion?(availableConfigs, icmpEnabled)
        window?.close()
    }
}

// MARK: - NSTableViewDataSource
extension PortConfigurationWindow: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return configurations.count
    }
}

// MARK: - NSTableViewDelegate
extension PortConfigurationWindow: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < configurations.count else { return nil }
        let config = configurations[row]

        let identifier = tableColumn?.identifier.rawValue ?? ""

        if identifier == "enabled" {
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
            checkbox.state = config.isEnabled ? .on : .off
            checkbox.tag = row
            return checkbox
        }

        let cellView = NSTextField(labelWithString: "")
        cellView.isEditable = false
        cellView.isBordered = false
        cellView.backgroundColor = .clear

        switch identifier {
        case "port":
            cellView.stringValue = "\(config.port)"
            cellView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            cellView.textColor = config.isInUse ? .systemGray : .labelColor
        case "protocol":
            cellView.stringValue = config.netProtocol.rawValue
            cellView.textColor = config.isInUse ? .systemGray : (config.netProtocol == .tcp ? .systemBlue : .systemGreen)
            cellView.font = NSFont.boldSystemFont(ofSize: 11)
        case "description":
            if config.isInUse {
                cellView.stringValue = "⚠️ " + config.description + " (déjà utilisé)"
                cellView.textColor = .systemOrange
            } else {
                cellView.stringValue = config.description
                cellView.textColor = .labelColor
            }
        default:
            break
        }

        return cellView
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = sender.tag
        guard row < configurations.count else { return }

        configurations[row].isEnabled = sender.state == .on
        updateSelectedCount()
    }
}
