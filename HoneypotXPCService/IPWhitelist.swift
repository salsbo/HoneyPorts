//
//  IPWhitelist.swift
//  HoneypotXPCService
//

import Foundation

final class IPWhitelist {
    static let shared = IPWhitelist()

    private var entries: [WhitelistEntry] = []
    private let queue = DispatchQueue(label: "com.honeyports.whitelist")

    private init() {
        loadFromDefaults()
    }

    struct WhitelistEntry {
        let address: UInt32
        let mask: UInt32
        let description: String

        func matches(_ ip: UInt32) -> Bool {
            return (ip & mask) == (address & mask)
        }
    }

    func isWhitelisted(_ ipHostOrder: UInt32) -> Bool {
        var result = false
        queue.sync {
            result = entries.contains { $0.matches(ipHostOrder) }
        }
        return result
    }

    func isWhitelisted(_ ipString: String) -> Bool {
        guard let hostOrder = parseIPToHostOrder(ipString) else {
            return false
        }
        return isWhitelisted(hostOrder)
    }

    func updateEntries(_ rawEntries: [[String: Any]]) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            var newEntries: [WhitelistEntry] = []

            for raw in rawEntries {
                guard let addressStr = raw["address"] as? String else { continue }
                let desc = raw["description"] as? String ?? ""

                if let entry = self.parseEntry(addressStr, description: desc) {
                    newEntries.append(entry)
                }
            }

            self.entries = newEntries
            self.saveToDefaults()
        }
    }

    func getEntries() -> [[String: Any]] {
        var result: [[String: Any]] = []
        queue.sync {
            for entry in entries {
                let addressStr = ipString(fromHostOrder: entry.address)
                let cidr = maskToCIDR(entry.mask)
                result.append([
                    "address": cidr > 0 && cidr < 32 ? "\(addressStr)/\(cidr)" : addressStr,
                    "description": entry.description
                ])
            }
        }
        return result
    }

    private func parseEntry(_ input: String, description: String) -> WhitelistEntry? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/")
            guard parts.count == 2,
                  let ipHostOrder = parseIPToHostOrder(String(parts[0])),
                  let cidr = Int(parts[1]),
                  cidr >= 0, cidr <= 32 else {
                return nil
            }
            let mask = cidrToMask(cidr)
            return WhitelistEntry(address: ipHostOrder & mask, mask: mask, description: description)
        } else {
            guard let ipHostOrder = parseIPToHostOrder(trimmed) else {
                return nil
            }
            return WhitelistEntry(address: ipHostOrder, mask: 0xFFFFFFFF, description: description)
        }
    }

    private func parseIPToHostOrder(_ ipString: String) -> UInt32? {
        var addr = in_addr()
        guard inet_pton(AF_INET, ipString, &addr) == 1 else {
            return nil
        }
        return CFSwapInt32BigToHost(addr.s_addr)
    }

    private func ipString(fromHostOrder address: UInt32) -> String {
        var addr = in_addr(s_addr: CFSwapInt32HostToBig(address))
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        _ = buffer.withUnsafeMutableBufferPointer { ptr in
            inet_ntop(AF_INET, &addr, ptr.baseAddress, socklen_t(INET_ADDRSTRLEN))
        }
        return String(cString: buffer)
    }

    private func cidrToMask(_ cidr: Int) -> UInt32 {
        guard cidr > 0 else { return 0 }
        guard cidr < 32 else { return 0xFFFFFFFF }
        return UInt32(0xFFFFFFFF) << (32 - cidr)
    }

    private func maskToCIDR(_ mask: UInt32) -> Int {
        var count = 0
        var m = mask
        while m & 0x80000000 != 0 {
            count += 1
            m <<= 1
        }
        return count
    }

    private let defaultsKey = "HoneyPortsIPWhitelist"

    private func saveToDefaults() {
        let data = entries.map { entry -> [String: Any] in
            let addressStr = ipString(fromHostOrder: entry.address)
            let cidr = maskToCIDR(entry.mask)
            return [
                "address": cidr > 0 && cidr < 32 ? "\(addressStr)/\(cidr)" : addressStr,
                "description": entry.description
            ]
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.array(forKey: defaultsKey) as? [[String: Any]] else {
            return
        }
        updateEntries(data)
    }
}
