//
//  ConnectionHandler.swift
//  HoneypotXPCService
//

import Foundation
import Network

class ConnectionHandler {
    private let connection: NWConnection
    private let port: Int
    private let startTime: Date
    private let completionHandler: (() -> Void)?
    private var isWhitelisted = false
    private let whitelistLock = NSLock()  // Protection contre race condition

    init(connection: NWConnection, port: Int, completionHandler: (() -> Void)? = nil) {
        self.connection = connection
        self.port = port
        self.startTime = Date()
        self.completionHandler = completionHandler
    }

    func handle() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }

            switch state {
            case .ready:
                self.checkWhitelistStatus()
                if !self.getWhitelistStatus() {
                    self.logEvent(event: "connection_opened", bytesCount: 0, payload: Data())
                }
                self.receiveData()

            case .failed:
                if !self.getWhitelistStatus() {
                    self.logEvent(event: "connection_failed", bytesCount: 0, payload: Data())
                }
                self.connection.cancel()
                self.completionHandler?()

            case .cancelled:
                self.completionHandler?()

            default:
                break
            }
        }

        connection.start(queue: .global(qos: .background))
    }

    /// Accès thread-safe au statut whitelist
    private func getWhitelistStatus() -> Bool {
        whitelistLock.lock()
        defer { whitelistLock.unlock() }
        return isWhitelisted
    }

    /// Modification thread-safe du statut whitelist
    private func setWhitelistStatus(_ value: Bool) {
        whitelistLock.lock()
        defer { whitelistLock.unlock() }
        isWhitelisted = value
    }

    private func receiveData() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            let whitelisted = self.getWhitelistStatus()

            if let data = data, !data.isEmpty, !whitelisted {
                self.logEvent(event: "data_received", bytesCount: data.count, payload: data)
            }

            if error != nil || isComplete {
                if !whitelisted {
                    self.logEvent(event: "connection_closed", bytesCount: 0, payload: Data())
                }
                self.connection.cancel()
                self.completionHandler?()
            } else {
                self.receiveData()
            }
        }
    }

    private func logEvent(event: String, bytesCount: Int, payload: Data) {
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)

        var sourceIP = "unknown"
        var sourcePort = 0
        var reverseDNS = "unknown"

        if let endpoint = connection.currentPath?.remoteEndpoint {
            switch endpoint {
            case .hostPort(let host, let port):
                sourceIP = "\(host)"
                sourcePort = Int(port.rawValue)
                reverseDNS = performReverseDNS(for: sourceIP)

            default:
                break
            }
        }

        let hexPayload = payload.prefix(1024).map { String(format: "%02X", $0) }.joined()
        let userAgent = extractUserAgent(from: payload)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

        var logEntry: [String: Any] = [
            "timestamp": timestamp,
            "port": port,
            "sourceIP": sourceIP,
            "sourcePort": sourcePort,
            "reverseDNS": reverseDNS,
            "bytesReceivedCount": bytesCount,
            "hexPayload": hexPayload,
            "event": event,
            "durationMs": duration
        ]

        if let ua = userAgent {
            logEntry["userAgent"] = ua
        }

        HoneypotLogWriter.shared.append(entry: logEntry)

        if event == "connection_opened" {
            ListenerManager.shared.incrementConnectionCount(for: port)
        }
    }

    private func performReverseDNS(for ip: String) -> String {
        return "unknown"
    }

    private static let maxDataForParsing = 8192      // 8KB max pour parsing
    private static let maxUserAgentLength = 256       // 256 chars max pour User-Agent

    private func extractUserAgent(from data: Data) -> String? {
        // Limiter la taille des données à parser pour éviter buffer overflow
        let limitedData = data.prefix(ConnectionHandler.maxDataForParsing)

        guard let string = String(data: limitedData, encoding: .utf8) else {
            return nil
        }

        let lines = string.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().hasPrefix("user-agent:") {
                // Trouver le premier ":" et extraire le reste
                if let colonIndex = line.firstIndex(of: ":") {
                    let afterColon = line.index(after: colonIndex)
                    let userAgent = String(line[afterColon...])
                        .trimmingCharacters(in: .whitespaces)
                    // Limiter la longueur du User-Agent
                    return String(userAgent.prefix(ConnectionHandler.maxUserAgentLength))
                }
            }
        }

        return nil
    }

    private func checkWhitelistStatus() {
        guard let endpoint = connection.currentPath?.remoteEndpoint else { return }

        switch endpoint {
        case .hostPort(let host, _):
            let ipString = "\(host)"
            let cleanIP: String
            if ipString.hasPrefix("::ffff:") {
                cleanIP = String(ipString.dropFirst(7))
            } else {
                cleanIP = ipString
            }

            if IPWhitelist.shared.isWhitelisted(cleanIP) {
                setWhitelistStatus(true)
            }
        default:
            break
        }
    }
}
