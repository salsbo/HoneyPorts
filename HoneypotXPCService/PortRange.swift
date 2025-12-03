//
//  PortRange.swift
//  HoneypotXPCService
//

import Foundation

struct PortRange {
    static let maxPortsPerRange = 200
    static let minPort = 1
    static let maxPort = 65535

    let start: Int
    let end: Int

    /// Initialise un PortRange avec validation stricte
    /// Retourne nil si les paramètres sont invalides
    init?(start: Int, end: Int) {
        guard start >= PortRange.minPort && start <= PortRange.maxPort else { return nil }
        guard end >= start && end <= PortRange.maxPort else { return nil }
        guard (end - start + 1) <= PortRange.maxPortsPerRange else { return nil }

        self.start = start
        self.end = end
    }

    var ports: [Int] {
        return Array(start...end)
    }

    func contains(_ port: Int) -> Bool {
        return port >= start && port <= end
    }

    /// Valide un port individuel
    static func isValidPort(_ port: Int) -> Bool {
        return port >= minPort && port <= maxPort
    }
}
