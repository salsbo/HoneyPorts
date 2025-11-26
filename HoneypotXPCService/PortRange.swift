//
//  PortRange.swift
//  HoneypotXPCService
//

import Foundation

struct PortRange {
    let start: Int
    let end: Int

    var ports: [Int] {
        return Array(start...end)
    }

    func contains(_ port: Int) -> Bool {
        return port >= start && port <= end
    }
}
