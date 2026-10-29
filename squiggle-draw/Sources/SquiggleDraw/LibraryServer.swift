import Foundation
import Combine
@preconcurrency import Network
import Darwin
import SquiggleCore

@MainActor
final class LibraryServer: ObservableObject {
    @Published private(set) var running=false
    @Published private(set) var address=""
    @Published private(set) var status="Sharing is off · BOOX cannot download new sketches"
    let usb=USBConnection()
    var connectionAddress:String { "http://\(Self.localIPv4() ?? "127.0.0.1"):\(port)/\(token)/" }
    private var listener: NWListener?
    private var store: LibraryStore?
    private var catalog: LibraryCatalog?
    private var connections=[UUID:NWConnection]()
    private var buffers=[UUID:Data]()
    private var timeouts=[UUID:Task<Void,Never>]()
    private var responding=Set<UUID>()
    private let queue=DispatchQueue(label:"SquiggleDraw.libraryHTTP")
    private let port: UInt16=48765
    private let token: String
    private var session=UUID()
    private let sharingKey="SquiggleDraw.booxLibrarySharingEnabled"
    init() {
        let key="SquiggleDraw.booxLibraryToken"
        if let saved=UserDefaults.standard.string(forKey:key),saved.count==64,saved.allSatisfy(\.isHexDigit) { token=saved }
        else {
            token=(UUID().uuidString+UUID().uuidString).replacingOccurrences(of:"-",with:"").lowercased()
            UserDefaults.standard.set(token,forKey:key)
        }
    }
    func setSharing(_ enabled:Bool,store:LibraryStore,catalog:LibraryCatalog) {
        UserDefaults.standard.set(enabled,forKey:sharingKey)
        if enabled { start(store:store,catalog:catalog) } else { stop() }
    }
    func restoreSharing(store:LibraryStore,catalog:LibraryCatalog) {
        if UserDefaults.standard.bool(forKey:sharingKey) { start(store:store,catalog:catalog) }
    }
    func start(store: LibraryStore,catalog: LibraryCatalog) {
        stop();self.store=store;self.catalog=catalog
        let request=session
        do {
            let listener=try NWListener(using:.tcp,on:NWEndpoint.Port(rawValue:port)!)
            self.listener=listener
            listener.stateUpdateHandler={ [weak self] state in
                Task { @MainActor in
                    guard let self,self.session==request else { return }
                    switch state {
                    case .ready:
                        self.running=true
                        self.usb.resume(libraryID:catalog.libraryID)
                        let host=Self.localIPv4() ?? "127.0.0.1"
                        self.address=host=="127.0.0.1" ? "" : "http://\(host):\(self.port)/\(self.token)/"
                        self.status=host=="127.0.0.1" ? "Sharing started · connect this Mac to the same Wi-Fi as BOOX" : "Sharing selected sketches on your Wi-Fi"
                    case .failed:
                        self.stop();self.status="Could not share on port 48765. Close another running copy and try again."
                    default:break
                    }
                }
            }
            listener.newConnectionHandler={ [weak self] connection in
                Task { @MainActor in
                    guard let self,self.session==request else { connection.cancel();return }
                    self.accept(connection)
                }
            }
            status="Starting Wi-Fi sharing…"
            listener.start(queue:queue)
        } catch { status="Could not share on port 48765. Close another running copy and try again." }
    }
    func update(catalog: LibraryCatalog) { self.catalog=catalog }
    func stop() {
        usb.stop()
        session=UUID();listener?.cancel();listener=nil
        for connection in connections.values { connection.cancel() }
        for timeout in timeouts.values { timeout.cancel() }
        connections.removeAll();buffers.removeAll();timeouts.removeAll();responding.removeAll()
        running=false;address="";status="Sharing is off · BOOX cannot download new sketches"
        store=nil;catalog=nil
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count<8 else { connection.cancel();return }
        let id=UUID();connections[id]=connection;buffers[id]=Data()
        timeouts[id]=Task { [weak self] in
            do { try await Task.sleep(for:.seconds(60)) } catch { return }
            self?.close(id)
        }
        connection.stateUpdateHandler={ [weak self] state in
            if case .failed=state { Task { @MainActor in self?.close(id) } }
            if case .cancelled=state { Task { @MainActor in self?.close(id) } }
        }
        connection.start(queue:queue);receive(id)
    }
    private func receive(_ id: UUID) {
        guard let connection=connections[id],!responding.contains(id) else { return }
        connection.receive(minimumIncompleteLength:1,maximumLength:8193) { [weak self] data,_,complete,error in
            Task { @MainActor in
                guard let self,self.connections[id] != nil,!self.responding.contains(id) else { return }
                if let data { self.buffers[id,default:Data()].append(data) }
                guard let request=self.buffers[id] else { self.close(id);return }
                if request.count>8192 || request.range(of:Data("\r\n\r\n".utf8)) != nil { self.respond(id,request:request) }
                else if complete || error != nil { self.close(id) }
                else { self.receive(id) }
            }
        }
    }
    private func respond(_ id: UUID,request: Data) {
        guard let store,let catalog else { close(id);return }
        responding.insert(id);buffers[id]=nil
        let token=self.token
        Task { [weak self] in
            let response=await Task.detached(priority:.utility) {
                LibraryRouter.response(request:request,token:token,store:store,catalog:catalog).encoded()
            }.value
            guard let self,let connection=self.connections[id] else { return }
            connection.send(content:response,completion:.contentProcessed { [weak self] _ in
                Task { @MainActor in self?.close(id) }
            })
        }
    }
    private func close(_ id: UUID) {
        let connection=connections.removeValue(forKey:id)
        timeouts.removeValue(forKey:id)?.cancel();buffers[id]=nil;responding.remove(id)
        connection?.cancel()
    }
    private static func localIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head)==0,let first=head else { return nil }
        defer { freeifaddrs(head) }
        var addresses=[(String,String)](),cursor: UnsafeMutablePointer<ifaddrs>?=first
        while let item=cursor {
            defer { cursor=item.pointee.ifa_next }
            guard let socket=item.pointee.ifa_addr,socket.pointee.sa_family==UInt8(AF_INET),item.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var host=[CChar](repeating:0,count:Int(NI_MAXHOST))
            guard getnameinfo(socket,socklen_t(socket.pointee.sa_len),&host,socklen_t(host.count),nil,0,NI_NUMERICHOST)==0 else { continue }
            let address=String(decoding:host.prefix{ $0 != 0 }.map{UInt8(bitPattern:$0)},as:UTF8.self),parts=address.split(separator:".").compactMap { Int($0) }
            guard parts.count==4,parts[0]==10 || (parts[0]==172 && (16...31).contains(parts[1])) || (parts[0]==192 && parts[1]==168) else { continue }
            addresses.append((String(cString:item.pointee.ifa_name),address))
        }
        return addresses.sorted { a,b in
            if (a.0=="en0") != (b.0=="en0") { return a.0=="en0" }
            if a.0.hasPrefix("en") != b.0.hasPrefix("en") { return a.0.hasPrefix("en") }
            return a.0<b.0
        }.first?.1
    }
}
