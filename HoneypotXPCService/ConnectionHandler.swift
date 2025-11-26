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
                if !self.isWhitelisted {
                    self.logEvent(event: "connection_opened", bytesCount: 0, payload: Data())
                }
                self.receiveData()

            case .failed:
                self.logEvent(event: "connection_failed", bytesCount: 0, payload: Data())
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

    private func receiveData() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty, !self.isWhitelisted {
                self.logEvent(event: "data_received", bytesCount: data.count, payload: data)
            }

            if error != nil || isComplete {
                if !self.isWhitelisted {
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

    private func extractUserAgent(from data: Data) -> String? {
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = string.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().hasPrefix("user-agent:") {
                let parts = line.components(separatedBy: ":")
                if parts.count > 1 {
                    return parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
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
                isWhitelisted = true
            }
        default:
            break
        }
    }
}
