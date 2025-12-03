//
//  ListenerManager.swift
//  HoneypotXPCService
//

import Foundation

class ListenerManager {
    static let shared = ListenerManager()

    private var listeners: [Int: HoneypotListener] = [:]
    private var udpListeners: [Int: UDPHoneypotListener] = [:]
    private let queue = DispatchQueue(label: "com.honeypot.listenermanager", attributes: .concurrent)

    private var connectionStats: [Int: Int] = [:]
    private var totalConnections = 0

    private init() {}

    func startListeners(in range: PortRange, completion: @escaping (Bool) -> Void) {
        let ports = range.ports
        startListenersOnPorts(ports, completion: completion)
    }

    func startListenersOnPorts(_ ports: [Int], completion: @escaping (Bool) -> Void) {
        var successCount = 0
        let group = DispatchGroup()

        for port in ports {
            group.enter()

            queue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    group.leave()
                    return
                }

                if self.listeners[port] != nil {
                    group.leave()
                    return
                }

                let listener = HoneypotListener(port: port)
                self.listeners[port] = listener

                listener.start { success in
                    self.queue.async(flags: .barrier) {
                        if !success {
                            self.listeners[port] = nil
                        } else {
                            successCount += 1
                        }
                        group.leave()
                    }
                }
            }

            usleep(500)
        }

        group.notify(queue: .global()) {
            completion(successCount > 0)
        }
    }

    // MARK: - UDP Listeners

    func startUDPListenersOnPorts(_ ports: [Int], completion: @escaping (Bool) -> Void) {
        var successCount = 0
        let group = DispatchGroup()

        for port in ports {
            group.enter()

            queue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    group.leave()
                    return
                }

                if self.udpListeners[port] != nil {
                    group.leave()
                    return
                }

                let listener = UDPHoneypotListener(port: port)
                self.udpListeners[port] = listener

                listener.start { success in
                    self.queue.async(flags: .barrier) {
                        if !success {
                            self.udpListeners[port] = nil
                        } else {
                            successCount += 1
                        }
                        group.leave()
                    }
                }
            }

            usleep(500)
        }

        group.notify(queue: .global()) {
            completion(successCount > 0)
        }
    }

    // MARK: - ICMP Monitoring

    func startICMPMonitoring() {
        ICMPMonitor.shared.startMonitoring()
    }

    func stopICMPMonitoring() {
        ICMPMonitor.shared.stopMonitoring()
    }

    func stopAllListeners(completion: @escaping (Bool) -> Void) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }

            for (_, listener) in self.listeners {
                listener.stop()
            }
            self.listeners.removeAll()

            for (_, listener) in self.udpListeners {
                listener.stop()
            }
            self.udpListeners.removeAll()

            ICMPMonitor.shared.stopMonitoring()

            self.connectionStats.removeAll()
            self.totalConnections = 0

            completion(true)
        }
    }

    func getLatestLogEntry(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let containerURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            let logFileURL = containerURL.appendingPathComponent("honeypot_logs.json")

            guard FileManager.default.fileExists(atPath: logFileURL.path) else {
                completion(nil)
                return
            }

            do {
                let content = try String(contentsOf: logFileURL, encoding: .utf8)
                let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

                if let lastLine = lines.last {
                    completion(lastLine)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
    }

    func getStats(completion: @escaping ([String: Int]) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                completion([:])
                return
            }

            var stats: [String: Int] = [:]
            stats["activeListeners"] = self.listeners.count

            let logCount = self.countLogEntries()
            stats["totalConnections"] = logCount

            for (port, count) in self.connectionStats {
                stats["port_\(port)"] = count
            }

            let icmpStats = ICMPMonitor.shared.getStats()
            for (key, value) in icmpStats {
                stats[key] = value
            }

            completion(stats)
        }
    }

    private func countLogEntries() -> Int {
        let containerURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logFileURL = containerURL.appendingPathComponent("honeypot_logs.json")

        guard FileManager.default.fileExists(atPath: logFileURL.path) else {
            return 0
        }

        do {
            let content = try String(contentsOf: logFileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
            return lines.count
        } catch {
            return 0
        }
    }

    func incrementConnectionCount(for port: Int) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.totalConnections += 1
            self.connectionStats[port, default: 0] += 1
        }
    }
}

// MARK: - HoneypotXPCProtocol

extension ListenerManager: HoneypotXPCProtocol {
    func startListenersOnPortRange(_ start: Int, _ end: Int, reply: @escaping (Bool) -> Void) {
        // Validation stricte du range pour éviter DoS
        guard let range = PortRange(start: start, end: end) else {
            reply(false)
            return
        }
        startListeners(in: range, completion: reply)
    }

    func startListenersOnPorts(_ ports: [Int], reply: @escaping (Bool) -> Void) {
        // Validation: limite le nombre de ports et vérifie chaque port
        guard !ports.isEmpty && ports.count <= PortRange.maxPortsPerRange else {
            reply(false)
            return
        }
        guard ports.allSatisfy({ PortRange.isValidPort($0) }) else {
            reply(false)
            return
        }
        startListenersOnPorts(ports, completion: reply)
    }

    func startUDPListenersOnPorts(_ ports: [Int], reply: @escaping (Bool) -> Void) {
        // Validation: limite le nombre de ports et vérifie chaque port
        guard !ports.isEmpty && ports.count <= PortRange.maxPortsPerRange else {
            reply(false)
            return
        }
        guard ports.allSatisfy({ PortRange.isValidPort($0) }) else {
            reply(false)
            return
        }
        startUDPListenersOnPorts(ports, completion: reply)
    }

    func startICMPMonitoring(reply: @escaping (Bool) -> Void) {
        startICMPMonitoring()
        reply(true)
    }

    func stopICMPMonitoring(reply: @escaping (Bool) -> Void) {
        stopICMPMonitoring()
        reply(true)
    }

    func stopAllListeners(reply: @escaping (Bool) -> Void) {
        stopAllListeners(completion: reply)
    }

    func latestLogEntry(reply: @escaping (String?) -> Void) {
        getLatestLogEntry(completion: reply)
    }

    func recentLogEntries(limit: Int, reply: @escaping ([[String: Any]]) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let containerURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            let logFileURL = containerURL.appendingPathComponent("honeypot_logs.json")

            guard FileManager.default.fileExists(atPath: logFileURL.path) else {
                reply([])
                return
            }

            do {
                let content = try String(contentsOf: logFileURL, encoding: .utf8)
                let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

                let recentLines = Array(lines.suffix(limit))
                var entries: [[String: Any]] = []

                for line in recentLines.reversed() {
                    if let data = line.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        entries.append(json)
                    }
                }

                reply(entries)
            } catch {
                reply([])
            }
        }
    }

    func clearLogs(reply: @escaping (Bool) -> Void) {
        HoneypotLogWriter.shared.clear { success in
            reply(success)
        }
    }

    func stats(reply: @escaping ([String: Int]) -> Void) {
        getStats(completion: reply)
    }

    func runMinimalListenerTest(reply: @escaping (Bool) -> Void) {
        let test = MinimalListenerTest()
        test.runTest()
        reply(true)
    }

    func updateWhitelist(_ entries: [[String: Any]], reply: @escaping (Bool) -> Void) {
        IPWhitelist.shared.updateEntries(entries)
        reply(true)
    }

    func getWhitelist(reply: @escaping ([[String: Any]]) -> Void) {
        let entries = IPWhitelist.shared.getEntries()
        reply(entries)
    }
}
