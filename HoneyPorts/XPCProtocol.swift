//
//  XPCProtocol.swift
//  HoneypotXPCService
//

import Foundation

@objc protocol HoneypotXPCProtocol {
    // TCP Listeners
    func startListenersOnPortRange(_ start: Int, _ end: Int, reply: @escaping (Bool) -> Void)
    func startListenersOnPorts(_ ports: [Int], reply: @escaping (Bool) -> Void)

    // UDP Listeners
    func startUDPListenersOnPorts(_ ports: [Int], reply: @escaping (Bool) -> Void)

    // ICMP Monitoring
    func startICMPMonitoring(reply: @escaping (Bool) -> Void)
    func stopICMPMonitoring(reply: @escaping (Bool) -> Void)

    // Control
    func stopAllListeners(reply: @escaping (Bool) -> Void)
    func latestLogEntry(reply: @escaping (String?) -> Void)
    func recentLogEntries(limit: Int, reply: @escaping ([[String: Any]]) -> Void)
    func clearLogs(reply: @escaping (Bool) -> Void)
    func stats(reply: @escaping ([String: Int]) -> Void)

    // Test
    func runMinimalListenerTest(reply: @escaping (Bool) -> Void)

    // Whitelist
    func updateWhitelist(_ entries: [[String: Any]], reply: @escaping (Bool) -> Void)
    func getWhitelist(reply: @escaping ([[String: Any]]) -> Void)
}
