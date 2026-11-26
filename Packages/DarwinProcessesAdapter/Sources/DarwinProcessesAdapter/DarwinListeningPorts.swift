import Darwin
import Foundation
import SmaltiCore

/// `ListeningPorts` from libproc: for each of the user's processes, its socket descriptors; TCP in LISTEN and UDP
/// with a local port and no peer. Other users' descriptors cannot be read without privileges, as with lsof.
public struct DarwinListeningPorts: ListeningPorts {
    private let uid = getuid()

    public init() {}

    public func current() async -> [ListeningSocket] {
        var found: [ListeningSocket] = []
        var seen: Set<ListeningSocket> = []
        for process in KernelProcessTable.all() where process.uid == uid {
            for socket in Self.sockets(of: process.pid) where seen.insert(socket).inserted {
                found.append(socket)
            }
        }
        return found
    }

    private static func sockets(of pid: Int32) -> [ListeningSocket] {
        descriptors(of: pid).compactMap { descriptor in
            guard descriptor.proc_fdtype == PROX_FDTYPE_SOCKET else { return nil }
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size else {
                return nil
            }
            return listening(info.psi, pid: pid)
        }
    }

    private static func descriptors(of pid: Int32) -> [proc_fdinfo] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        // Room for descriptors opened between the two calls.
        var list = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + 16)
        let read = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &list, Int32(list.count * stride))
        return read > 0 ? Array(list.prefix(Int(read) / stride)) : []
    }

    private static func listening(_ socket: socket_info, pid: Int32) -> ListeningSocket? {
        switch Int(socket.soi_kind) {
        case SOCKINFO_TCP:
            let tcp = socket.soi_proto.pri_tcp
            guard tcp.tcpsi_state == TSI_S_LISTEN else { return nil }
            return entry(tcp.tcpsi_ini, transport: .tcp, pid: pid)
        case SOCKINFO_IN where Int(socket.soi_protocol) == Int(IPPROTO_UDP):
            let udp = socket.soi_proto.pri_in
            guard udp.insi_fport == 0 else { return nil }
            return entry(udp, transport: .udp, pid: pid)
        default:
            return nil
        }
    }

    private static let ipv4Flag: UInt8 = 0x1
    private static let ipv6Flag: UInt8 = 0x2

    private static func entry(_ address: in_sockinfo, transport: Transport, pid: Int32) -> ListeningSocket? {
        // The port is stored in network byte order in the low 16 bits.
        let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: address.insi_lport))
        guard port != 0, let local = text(address) else { return nil }
        return ListeningSocket(pid: pid, transport: transport, port: port, address: local)
    }

    private static func text(_ address: in_sockinfo) -> String? {
        if address.insi_vflag & ipv6Flag != 0 {
            var value: in6_addr = address.insi_laddr.ina_6
            return presentation(AF_INET6, bytes: &value, length: INET6_ADDRSTRLEN)
        }
        if address.insi_vflag & ipv4Flag != 0 {
            var value: in_addr = address.insi_laddr.ina_46.i46a_addr4
            return presentation(AF_INET, bytes: &value, length: INET_ADDRSTRLEN)
        }
        return nil
    }

    /// `inet_ntop` over a plain C address struct (`in_addr`, `in6_addr`: bytes only, no references).
    private static func presentation(_ family: Int32, bytes: UnsafeRawPointer, length: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(length))
        guard inet_ntop(family, bytes, &buffer, socklen_t(length)) != nil else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
