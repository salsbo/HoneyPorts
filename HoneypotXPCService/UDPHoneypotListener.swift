//
//  UDPHoneypotListener.swift
//  HoneypotXPCService
//

import Foundation
import Network

class UDPHoneypotListener {
    private var listener: NWListener?
    let port: Int
    private var isActive = false

    init(port: Int) {
        self.port = port
    }

    func start(completion: @escaping (Bool) -> Void) {
        do {
            let params = NWParameters.udp
            params.acceptLocalOnly = false
            params.allowLocalEndpointReuse = true

            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                completion(false)
                return
            }

            listener = try NWListener(using: params, on: nwPort)

            var completionCalled = false
            let completionLock = NSLock()

            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                completionLock.lock()
                defer { completionLock.unlock() }

                if !completionCalled {
                    completionCalled = true
                    completion(false)
                }
            }

            listener?.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }

                switch state {
                case .ready:
                    self.isActive = true
                    completionLock.lock()
                    if !completionCalled {
                        completionCalled = true
                        completionLock.unlock()
                        completion(true)
                    } else {
                        completionLock.unlock()
                    }

                case .failed:
                    self.isActive = false
                    completionLock.lock()
                    if !completionCalled {
                        completionCalled = true
                        completionLock.unlock()
                        completion(false)
                    } else {
                        completionLock.unlock()
                    }

                case .cancelled:
                    self.isActive = false
                    completionLock.lock()
                    if !completionCalled {
                        completionCalled = true
                        completionLock.unlock()
                        completion(false)
                    } else {
                        completionLock.unlock()
                    }

                case .waiting:
                    break

                case .setup:
                    break

                @unknown default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                self.handleUDPConnection(connection)
            }

            listener?.start(queue: .global(qos: .userInitiated))

        } catch {
            completion(false)
        }
    }

    private func handleUDPConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }

            switch state {
            case .ready:
                self.receiveUDPData(connection)

            case .failed:
                connection.cancel()

            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
    }

    private func receiveUDPData(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self = self else { return }

            if error != nil {
                connection.cancel()
                return
            }

            var sourceIP = "unknown"
            var sourcePort = 0

            if let endpoint = connection.currentPath?.remoteEndpoint,
               case .hostPort(let host, let port) = endpoint {
                switch host {
                case .ipv4(let addr):
                    sourceIP = "\(addr)"
                case .ipv6(let addr):
                    sourceIP = "\(addr)"
                default:
                    break
                }
                sourcePort = Int(port.rawValue)
            }

            let cleanIP = sourceIP.hasPrefix("::ffff:") ? String(sourceIP.dropFirst(7)) : sourceIP
            if IPWhitelist.shared.isWhitelisted(cleanIP) {
                self.receiveUDPData(connection)
                return
            }

            let bytesCount = data?.count ?? 0
            let hexPayload = data?.prefix(1024).map { String(format: "%02X", $0) }.joined() ?? ""

            let logEntry: [String: Any] = [
                "timestamp": HoneypotLogWriter.shared.timestamp(),
                "port": self.port,
                "sourceIP": sourceIP,
                "sourcePort": sourcePort,
                "reverseDNS": "unknown",
                "bytesReceivedCount": bytesCount,
                "hexPayload": hexPayload,
                "event": "udp_packet",
                "protocol": "UDP"
            ]

            HoneypotLogWriter.shared.append(entry: logEntry)
            ListenerManager.shared.incrementConnectionCount(for: self.port)

            self.receiveUDPData(connection)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isActive = false
    }

    var active: Bool {
        return isActive
    }
}
