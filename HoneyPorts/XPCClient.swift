//
//  XPCClient.swift
//  HoneyPorts
//

import Foundation

class XPCClient {
    static let shared = XPCClient()

    private var connection: NSXPCConnection?
    private let connectionLock = NSLock()

    private init() {
        setupConnection()
    }

    private func setupConnection() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        connection?.invalidate()

        let newConnection = NSXPCConnection(serviceName: "DAHOUSE.HoneypotXPCService")
        newConnection.remoteObjectInterface = NSXPCInterface(with: HoneypotXPCProtocol.self)

        newConnection.invalidationHandler = { [weak self] in
            self?.connection = nil
        }

        newConnection.interruptionHandler = { }

        newConnection.resume()
        self.connection = newConnection
    }

    private func ensureConnection() {
        if connection == nil {
            setupConnection()
        }
    }

    func startListeners(startPort: Int, endPort: Int, completion: @escaping (Bool) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
            completion(false)
        }) as? HoneypotXPCProtocol else {
            completion(false)
            return
        }

        proxy.startListenersOnPortRange(startPort, endPort) { success in
            completion(success)
        }
    }

    func startListeners(ports: [Int], completion: @escaping (Bool) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
            completion(false)
        }) as? HoneypotXPCProtocol else {
            completion(false)
            return
        }

        proxy.startListenersOnPorts(ports) { success in
            completion(success)
        }
    }

    func stopListeners(completion: @escaping (Bool) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
            completion(false)
        }) as? HoneypotXPCProtocol else {
            completion(false)
            return
        }

        proxy.stopAllListeners { success in
            completion(success)
        }
    }

    func getLatestLog(completion: @escaping (String?) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
            completion(nil)
        }) as? HoneypotXPCProtocol else {
            completion(nil)
            return
        }

        proxy.latestLogEntry { entry in
            completion(entry)
        }
    }

    func getRecentLogEntries(limit: Int = 20, completion: @escaping ([[String: Any]]) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
            completion([])
        }) as? HoneypotXPCProtocol else {
            completion([])
            return
        }

        proxy.recentLogEntries(limit: limit) { entries in
            completion(entries)
        }
    }

    func clearLogs(completion: @escaping (Bool) -> Void) {
        ensureConnection()

        guard let conn = connection else {
            completion(false)
            return
        }

        let proxy = conn.remoteObjectProxyWithErrorHandler({ _ in
            completion(false)
        })

        guard let typedProxy = proxy as? HoneypotXPCProtocol else {
            completion(false)
            return
        }

        typedProxy.recentLogEntries(limit: 1) { _ in
            typedProxy.clearLogs { success in
                completion(success)
            }
        }
    }

    func getStats(completion: @escaping ([String: Int]) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
            completion([:])
        }) as? HoneypotXPCProtocol else {
            completion([:])
            return
        }

        proxy.stats { stats in
            completion(stats)
        }
    }

    func startUDPListeners(ports: [Int], completion: @escaping (Bool) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
            completion(false)
        }) as? HoneypotXPCProtocol else {
            completion(false)
            return
        }

        proxy.startUDPListenersOnPorts(ports) { success in
            completion(success)
        }
    }

    func startICMPMonitoring(completion: @escaping (Bool) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
            completion(false)
        }) as? HoneypotXPCProtocol else {
            completion(false)
            return
        }

        proxy.startICMPMonitoring { success in
            completion(success)
        }
    }

    func stopICMPMonitoring(completion: @escaping (Bool) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
            completion(false)
        }) as? HoneypotXPCProtocol else {
            completion(false)
            return
        }

        proxy.stopICMPMonitoring { success in
            completion(success)
        }
    }

    func updateWhitelist(_ entries: [[String: Any]], completion: @escaping (Bool) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
            completion(false)
        }) as? HoneypotXPCProtocol else {
            completion(false)
            return
        }

        proxy.updateWhitelist(entries) { success in
            completion(success)
        }
    }

    func getWhitelist(completion: @escaping ([[String: Any]]) -> Void) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
            completion([])
        }) as? HoneypotXPCProtocol else {
            completion([])
            return
        }

        proxy.getWhitelist { entries in
            completion(entries)
        }
    }
}
