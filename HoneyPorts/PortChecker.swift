//
//  PortChecker.swift
//  HoneyPorts
//

import Foundation
import Darwin

class PortChecker {

    static func isPortInUse(_ port: Int, protocol netProtocol: NetworkProtocol = .tcp) -> Bool {
        switch netProtocol {
        case .tcp:
            return isTCPPortInUse(port)
        case .udp:
            return isUDPPortInUse(port)
        }
    }

    private static func isTCPPortInUse(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketFD != -1 else { return false }

        defer { close(socketFD) }

        var reuseAddr: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindResult == 0 {
            return false
        } else {
            return errno == EADDRINUSE
        }
    }

    private static func isUDPPortInUse(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD != -1 else { return false }

        defer { close(socketFD) }

        var reuseAddr: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindResult == 0 {
            return false
        } else {
            return errno == EADDRINUSE
        }
    }

    enum NetworkProtocol {
        case tcp
        case udp
    }
}
