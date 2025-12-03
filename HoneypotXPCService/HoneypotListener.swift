//
//  HoneypotListener.swift
//  HoneypotXPCService
//

import Foundation
import Network

class HoneypotListener {
    private static let maxConnectionsPerPort = 500  // Limite par port pour éviter DoS

    private var listener: NWListener?
    let port: Int
    private var isActive = false
    private var activeHandlers: [UUID: ConnectionHandler] = [:]
    private let handlersQueue = DispatchQueue(label: "com.honeypot.handlers", attributes: .concurrent)

    init(port: Int) {
        self.port = port
    }

    func start(completion: @escaping (Bool) -> Void) {
        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = false
            tcpOptions.connectionTimeout = 5

            let params = NWParameters(tls: nil, tcp: tcpOptions)
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

                // Vérifier la limite de connexions avant d'accepter
                var shouldAccept = false
                self.handlersQueue.sync {
                    shouldAccept = self.activeHandlers.count < HoneypotListener.maxConnectionsPerPort
                }

                guard shouldAccept else {
                    // Refuser la connexion si limite atteinte
                    connection.cancel()
                    return
                }

                let handlerID = UUID()
                let handler = ConnectionHandler(connection: connection, port: self.port) { [weak self] in
                    self?.removeHandler(id: handlerID)
                }

                self.handlersQueue.async(flags: .barrier) {
                    // Double vérification après avoir obtenu le lock
                    guard self.activeHandlers.count < HoneypotListener.maxConnectionsPerPort else {
                        connection.cancel()
                        return
                    }
                    self.activeHandlers[handlerID] = handler
                }

                handler.handle()
            }

            listener?.start(queue: .global(qos: .userInitiated))

        } catch {
            completion(false)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isActive = false

        handlersQueue.async(flags: .barrier) { [weak self] in
            self?.activeHandlers.removeAll()
        }
    }

    private func removeHandler(id: UUID) {
        handlersQueue.async(flags: .barrier) { [weak self] in
            self?.activeHandlers.removeValue(forKey: id)
        }
    }

    var active: Bool {
        return isActive
    }
}
