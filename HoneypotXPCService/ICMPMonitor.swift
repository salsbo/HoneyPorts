//
//  ICMPMonitor.swift
//  HoneypotXPCService
//

import Foundation
import Darwin

private let IOCPARM_MASK: UInt32 = 0x1fff
private let IOC_VOID: UInt32 = 0x20000000
private let IOC_OUT: UInt32 = 0x40000000
private let IOC_IN: UInt32 = 0x80000000
private let IOC_INOUT: UInt32 = IOC_IN | IOC_OUT
private let BPF_IOC_MAGIC: UInt32 = 66

private func ioctlRequest(_ direction: UInt32, _ group: UInt32, _ num: UInt32, _ length: UInt32) -> UInt {
    return UInt(direction | ((length & IOCPARM_MASK) << 16) | (group << 8) | num)
}

private func _IO(_ group: UInt32, _ num: UInt32) -> UInt {
    return UInt(IOC_VOID | (group << 8) | num)
}

private func _IOR(_ group: UInt32, _ num: UInt32, _ length: UInt32) -> UInt {
    return ioctlRequest(IOC_OUT, group, num, length)
}

private func _IOW(_ group: UInt32, _ num: UInt32, _ length: UInt32) -> UInt {
    return ioctlRequest(IOC_IN, group, num, length)
}

private func _IOWR(_ group: UInt32, _ num: UInt32, _ length: UInt32) -> UInt {
    return ioctlRequest(IOC_INOUT, group, num, length)
}

private let BIOCIMMEDIATE = _IOW(BPF_IOC_MAGIC, 112, UInt32(MemoryLayout<u_int>.size))
private let BIOCGBLEN = _IOR(BPF_IOC_MAGIC, 102, UInt32(MemoryLayout<u_int>.size))
private let BIOCSETIF = _IOW(BPF_IOC_MAGIC, 108, UInt32(MemoryLayout<ifreq>.size))
private let BIOCSETF = _IOW(BPF_IOC_MAGIC, 103, UInt32(MemoryLayout<bpf_program>.size))
private let ETHERTYPE_IP: UInt16 = 0x0800
private let interfaceNameSize = 16
private let IFF_UP: Int32 = 0x1
private let IFF_LOOPBACK: Int32 = 0x8

@discardableResult
private func ioctlPointer<T>(_ fd: Int32, _ request: UInt, _ value: inout T) -> Int32 {
    return withUnsafeMutablePointer(to: &value) { ptr in
        ioctl(fd, request, UnsafeMutableRawPointer(ptr))
    }
}

final class ICMPMonitor {
    static let shared = ICMPMonitor()

    private struct InterfaceInfo {
        let name: String
        let addresses: [UInt32]
    }

    private let monitorQueue = DispatchQueue(label: "com.honeyports.icmpmonitor")
    private var isMonitoring = false
    private var totalPingsDetected = 0
    private var bpfFileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var interfaceInfo: InterfaceInfo?
    private var bpfBufferSize: Int = 4096

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }

        guard let info = primaryInterfaceInfo() else { return }

        guard let fd = openBPFDevice() else { return }

        guard configureBPF(fd: fd, interface: info.name) else {
            close(fd)
            return
        }

        interfaceInfo = info
        bpfFileDescriptor = fd
        totalPingsDetected = 0
        isMonitoring = true

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: monitorQueue)
        source.setEventHandler { [weak self] in
            self?.processPackets()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        readSource = source
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false
        interfaceInfo = nil

        readSource?.cancel()
        readSource = nil

        if bpfFileDescriptor >= 0 {
            close(bpfFileDescriptor)
            bpfFileDescriptor = -1
        }
    }

    func getStats() -> [String: Int] {
        return [
            "icmpPingsDetected": totalPingsDetected,
            "icmpMonitoring": isMonitoring ? 1 : 0
        ]
    }

    func resetStats() {
        totalPingsDetected = 0
    }

    private func openBPFDevice() -> Int32? {
        for index in 0..<256 {
            let path = "/dev/bpf\(index)"
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                return fd
            }
        }
        return nil
    }

    private func configureBPF(fd: Int32, interface: String) -> Bool {
        var ifr = ifreq()
        memset(&ifr, 0, MemoryLayout<ifreq>.size)
        _ = interface.withCString { cString in
            withUnsafeMutablePointer(to: &ifr.ifr_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: interfaceNameSize) { dest in
                    strncpy(dest, cString, interfaceNameSize)
                }
            }
        }

        if ioctlPointer(fd, BIOCSETIF, &ifr) == -1 {
            return false
        }

        var bufLen = u_int(0)
        if ioctlPointer(fd, BIOCGBLEN, &bufLen) == 0 {
            bpfBufferSize = Int(bufLen)
        } else {
            bpfBufferSize = 32768
        }

        var enable = u_int(1)
        _ = ioctlPointer(fd, BIOCIMMEDIATE, &enable)

        var bpfInstructions: [bpf_insn] = [
            bpf_insn(code: 0x28, jt: 0, jf: 0, k: 12),
            bpf_insn(code: 0x15, jt: 0, jf: 3, k: 0x0800),
            bpf_insn(code: 0x30, jt: 0, jf: 0, k: 23),
            bpf_insn(code: 0x15, jt: 0, jf: 1, k: 1),
            bpf_insn(code: 0x06, jt: 0, jf: 0, k: 0xFFFFFFFF),
            bpf_insn(code: 0x06, jt: 0, jf: 0, k: 0)
        ]

        var prog = bpf_program()
        prog.bf_len = UInt32(bpfInstructions.count)
        _ = bpfInstructions.withUnsafeMutableBufferPointer { buffer in
            prog.bf_insns = buffer.baseAddress
            return ioctlPointer(fd, BIOCSETF, &prog)
        }

        return true
    }

    private func processPackets() {
        guard bpfFileDescriptor >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: bpfBufferSize)
        let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return read(bpfFileDescriptor, baseAddress, bpfBufferSize)
        }

        if bytesRead <= 0 { return }

        buffer.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset < bytesRead {
                guard bytesRead - offset >= MemoryLayout<bpf_hdr>.size else { break }

                let header = rawBuffer.load(fromByteOffset: offset, as: bpf_hdr.self)
                let packetOffset = offset + Int(header.bh_hdrlen)
                let packetLength = Int(header.bh_caplen)

                guard packetOffset + packetLength <= bytesRead else { break }

                if let packetBase = rawBuffer.baseAddress?.advanced(by: packetOffset) {
                    handlePacket(bytes: packetBase, length: packetLength)
                }

                let totalLength = Int(header.bh_hdrlen) + Int(header.bh_caplen)
                let alignedLength = (totalLength + MemoryLayout<Int>.size - 1) & ~(MemoryLayout<Int>.size - 1)
                offset += alignedLength
            }
        }
    }

    private func handlePacket(bytes: UnsafeRawPointer, length: Int) {
        guard length >= 34 else { return }

        let ethernetHeaderLength = 14
        let etherType = readUInt16(from: bytes, offset: 12)
        guard etherType == ETHERTYPE_IP else { return }

        let ipHeaderStart = bytes.advanced(by: ethernetHeaderLength)
        let versionAndHeaderLength = ipHeaderStart.load(as: UInt8.self)
        let ipHeaderLength = Int(versionAndHeaderLength & 0x0F) * 4
        guard ipHeaderLength >= 20, length >= ethernetHeaderLength + ipHeaderLength else { return }

        let protocolNumber = ipHeaderStart.load(fromByteOffset: 9, as: UInt8.self)
        guard protocolNumber == 1 else { return }

        let sourceNetworkOrder = ipHeaderStart.load(fromByteOffset: 12, as: UInt32.self)
        let destinationNetworkOrder = ipHeaderStart.load(fromByteOffset: 16, as: UInt32.self)
        let sourceHostOrder = CFSwapInt32BigToHost(sourceNetworkOrder)
        let destinationHostOrder = CFSwapInt32BigToHost(destinationNetworkOrder)

        let icmpOffset = ethernetHeaderLength + ipHeaderLength
        guard length >= icmpOffset + 8 else { return }

        let icmpType = bytes.load(fromByteOffset: icmpOffset, as: UInt8.self)

        guard icmpType == 8 else { return }

        guard let info = interfaceInfo, info.addresses.contains(destinationHostOrder) else { return }

        if IPWhitelist.shared.isWhitelisted(sourceHostOrder) {
            return
        }

        totalPingsDetected += 1

        let sourceIP = ipString(fromHostOrder: sourceHostOrder)
        let destIP = ipString(fromHostOrder: destinationHostOrder)

        logPingDetection(sourceIP: sourceIP, destinationIP: destIP, packetLength: length - ethernetHeaderLength)
    }

    private func logPingDetection(sourceIP: String, destinationIP: String, packetLength: Int) {
        let entry: [String: Any] = [
            "timestamp": HoneypotLogWriter.shared.timestamp(),
            "port": 0,
            "sourceIP": sourceIP,
            "sourcePort": 0,
            "reverseDNS": "unknown",
            "bytesReceivedCount": packetLength,
            "hexPayload": "",
            "event": "icmp_ping",
            "protocol": "ICMP",
            "destinationIP": destinationIP
        ]

        HoneypotLogWriter.shared.append(entry: entry)
        ListenerManager.shared.incrementConnectionCount(for: 0)
    }

    private func primaryInterfaceInfo() -> InterfaceInfo? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let start = ifaddrPointer else { return nil }
        defer { freeifaddrs(start) }

        var candidates: [String: Set<UInt32>] = [:]

        var pointer: UnsafeMutablePointer<ifaddrs>? = start
        while let current = pointer {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)

            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback,
               let namePtr = interface.ifa_name,
               let addrPointer = interface.ifa_addr,
               addrPointer.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: namePtr)
                let rawAddress = addrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ptr in
                    ptr.pointee.sin_addr.s_addr
                }
                let address = CFSwapInt32BigToHost(rawAddress)

                var set = candidates[name] ?? Set<UInt32>()
                set.insert(address)
                candidates[name] = set
            }

            pointer = interface.ifa_next
        }

        guard let selected = candidates.sorted(by: { lhs, rhs in
            if lhs.key.hasPrefix("en") && !rhs.key.hasPrefix("en") { return true }
            if rhs.key.hasPrefix("en") && !lhs.key.hasPrefix("en") { return false }
            if lhs.value.count == rhs.value.count {
                return lhs.key < rhs.key
            }
            return lhs.value.count > rhs.value.count
        }).first else {
            return nil
        }

        return InterfaceInfo(name: selected.key, addresses: Array(selected.value))
    }

    private func ipString(fromHostOrder address: UInt32) -> String {
        var addr = in_addr(s_addr: CFSwapInt32HostToBig(address))
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        _ = buffer.withUnsafeMutableBufferPointer { ptr in
            inet_ntop(AF_INET, &addr, ptr.baseAddress, socklen_t(INET_ADDRSTRLEN))
        }
        return String(cString: buffer)
    }

    private func readUInt16(from pointer: UnsafeRawPointer, offset: Int) -> UInt16 {
        let high = UInt16(pointer.load(fromByteOffset: offset, as: UInt8.self))
        let low = UInt16(pointer.load(fromByteOffset: offset + 1, as: UInt8.self))
        return (high << 8) | low
    }
}
