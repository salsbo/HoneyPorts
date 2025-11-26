//
//  WhitelistWindow.swift
//  HoneyPorts
//

import Cocoa

class WhitelistWindow: NSWindowController {

    private var tableView: NSTableView!
    private var entries: [(address: String, description: String)] = []
    private var addButton: NSButton!
    private var removeButton: NSButton!
    private var addressField: NSTextField!
    private var descriptionField: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Whitelist IP"
        window.center()
        window.minSize = NSSize(width: 400, height: 300)

        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)

        self.init(window: window)
        setupUI()
        loadWhitelist()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.headerView = nil

        let addressColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("address"))
        addressColumn.title = "IP / Subnet"
        addressColumn.width = 150
        tableView.addTableColumn(addressColumn)

        let descColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("description"))
        descColumn.title = "Description"
        descColumn.width = 200
        tableView.addTableColumn(descColumn)

        scrollView.documentView = tableView

        let addressLabel = NSTextField(labelWithString: "IP/Subnet:")
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(addressLabel)

        addressField = NSTextField()
        addressField.placeholderString = "192.168.1.0/24"
        addressField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(addressField)

        let descLabel = NSTextField(labelWithString: "Description:")
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descLabel)

        descriptionField = NSTextField()
        descriptionField.placeholderString = "Mon réseau local"
        descriptionField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descriptionField)

        addButton = NSButton(title: "Ajouter", target: self, action: #selector(addEntry))
        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(addButton)

        removeButton = NSButton(title: "Supprimer", target: self, action: #selector(removeEntry))
        removeButton.bezelStyle = .rounded
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(removeButton)

        let saveButton = NSButton(title: "Enregistrer", target: self, action: #selector(saveAndClose))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(saveButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: addressLabel.topAnchor, constant: -12),

            // Address label and field
            addressLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            addressLabel.bottomAnchor.constraint(equalTo: descLabel.topAnchor, constant: -8),
            addressLabel.widthAnchor.constraint(equalToConstant: 80),

            addressField.leadingAnchor.constraint(equalTo: addressLabel.trailingAnchor, constant: 8),
            addressField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            addressField.centerYAnchor.constraint(equalTo: addressLabel.centerYAnchor),

            // Description label and field
            descLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            descLabel.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -12),
            descLabel.widthAnchor.constraint(equalToConstant: 80),

            descriptionField.leadingAnchor.constraint(equalTo: descLabel.trailingAnchor, constant: 8),
            descriptionField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            descriptionField.centerYAnchor.constraint(equalTo: descLabel.centerYAnchor),

            // Buttons
            addButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 8),
            removeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    private func loadWhitelist() {
        XPCClient.shared.getWhitelist { [weak self] rawEntries in
            DispatchQueue.main.async {
                self?.entries = rawEntries.map { entry in
                    let address = entry["address"] as? String ?? ""
                    let desc = entry["description"] as? String ?? ""
                    return (address: address, description: desc)
                }
                self?.tableView.reloadData()
            }
        }
    }

    @objc private func addEntry() {
        let address = addressField.stringValue.trimmingCharacters(in: .whitespaces)
        let desc = descriptionField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !address.isEmpty else {
            NSSound.beep()
            return
        }

        // Validate format
        if !isValidIPOrSubnet(address) {
            let alert = NSAlert()
            alert.messageText = "Format invalide"
            alert.informativeText = "Entrez une IP (ex: 192.168.1.1) ou un subnet CIDR (ex: 10.0.0.0/8)"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        entries.append((address: address, description: desc))
        tableView.reloadData()
        addressField.stringValue = ""
        descriptionField.stringValue = ""
    }

    @objc private func removeEntry() {
        let selectedRows = tableView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        for index in selectedRows.reversed() {
            entries.remove(at: index)
        }
        tableView.reloadData()
    }

    @objc private func saveAndClose() {
        let xpcEntries: [[String: Any]] = entries.map { entry in
            return [
                "address": entry.address,
                "description": entry.description
            ]
        }

        XPCClient.shared.updateWhitelist(xpcEntries) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.close()
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Erreur"
                    alert.informativeText = "Impossible d'enregistrer la whitelist"
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }

    private func isValidIPOrSubnet(_ input: String) -> Bool {
        if input.contains("/") {
            let parts = input.split(separator: "/")
            guard parts.count == 2,
                  let cidr = Int(parts[1]),
                  cidr >= 0, cidr <= 32 else {
                return false
            }
            return isValidIP(String(parts[0]))
        }
        return isValidIP(input)
    }

    private func isValidIP(_ ip: String) -> Bool {
        var addr = in_addr()
        return inet_pton(AF_INET, ip, &addr) == 1
    }
}

// MARK: - NSTableViewDataSource
extension WhitelistWindow: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return entries.count
    }
}

// MARK: - NSTableViewDelegate
extension WhitelistWindow: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < entries.count else { return nil }

        let entry = entries[row]
        let identifier = tableColumn?.identifier.rawValue ?? ""

        let textField = NSTextField()
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.drawsBackground = false

        switch identifier {
        case "address":
            textField.stringValue = entry.address
        case "description":
            textField.stringValue = entry.description
        default:
            break
        }

        return textField
    }
}
