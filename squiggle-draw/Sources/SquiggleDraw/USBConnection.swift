import Foundation
import Combine

/// Uses the same Android USB transport as Inkwell, on Squiggle's own port.
/// It never changes Inkwell's tunnel or reads another app's credentials.
@MainActor final class USBConnection:ObservableObject {
    @Published private(set) var busy=false
    @Published private(set) var status="Connect your BOOX by USB to pair without typing."
    private var watch:Task<Void,Never>?
    private var generation=0
    func stop() { generation+=1;watch?.cancel();watch=nil;busy=false;status="Connect your BOOX by USB to pair without typing." }
    func resume(libraryID:UUID) {
        guard UserDefaults.standard.string(forKey:"SquiggleDraw.usbLibrary")==libraryID.uuidString,
              let serial=UserDefaults.standard.string(forKey:"SquiggleDraw.usbSerial") else { return }
        stop();let request=generation
        watch=Task { [weak self] in try? await self?.monitor(serial:serial,request:request) }
    }
    private func monitor(serial:String,request:Int) async throws {
        while !Task.isCancelled {
            let connected=await Task.detached { (try? USBTransport.maintain(serial:serial)) == true }.value
            guard !Task.isCancelled,generation==request else { return }
            status=connected ? "USB ready · choose Sync now on BOOX" : "USB disconnected · your saved Wi-Fi connection is ready"
            try await Task.sleep(for:.seconds(5))
        }
    }
    func pair(address:String,libraryID:UUID) {
        guard !busy else { return }
        stop();busy=true;status="Pairing connected BOOX…"
        let request=generation
        watch=Task { [weak self] in
            do {
                let serial=try await Task.detached { try USBTransport.pair(address:address,libraryID:libraryID) }.value
                guard let self,!Task.isCancelled,self.generation==request else { return }
                self.busy=false;self.status="Paired · choose Sync now on BOOX. USB first, Wi-Fi when unplugged."
                UserDefaults.standard.set(serial,forKey:"SquiggleDraw.usbSerial")
                UserDefaults.standard.set(libraryID.uuidString,forKey:"SquiggleDraw.usbLibrary")
                try await self.monitor(serial:serial,request:request)
            } catch {
                guard let self,!Task.isCancelled,self.generation==request else { return }
                self.busy=false;self.status=error.localizedDescription
            }
        }
    }
}
private enum USBError:LocalizedError {
    case missingTools,device,command,pairing
    var errorDescription:String? {
        switch self {
        case .missingTools: "Install Android platform tools to use USB pairing. Manual Wi-Fi pairing remains available."
        case .device: "Connect one BOOX by USB, unlock it, and allow USB debugging for this Mac, then try again."
        case .command: "The USB connection did not respond. Reconnect the BOOX and try again."
        case .pairing: "Install Squiggle 0.16 or later on the BOOX, then try pairing again."
        }
    }
}
enum USBTransport {
    private static func adb()->URL? {
        let paths=[FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Android/sdk/platform-tools/adb").path,"/opt/homebrew/bin/adb","/usr/local/bin/adb"]
        return paths.first{FileManager.default.isExecutableFile(atPath:$0)}.map{URL(fileURLWithPath:$0)}
    }
    private static func run(_ args:[String]) throws ->String {
        guard let executable=adb() else { throw USBError.missingTools }
        let process=Process(),pipe=Pipe(),finished=DispatchSemaphore(value:0)
        process.executableURL=executable;process.arguments=args
        process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
        process.terminationHandler={_ in finished.signal()}
        do { try process.run() } catch { throw USBError.command }
        guard finished.wait(timeout:.now()+10) == .success else { process.terminate();throw USBError.command }
        guard process.terminationStatus==0 else { throw USBError.command }
        return String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)
    }
    static func pair(address:String,libraryID:UUID) throws ->String {
        let devices=try run(["devices","-l"]).split(separator:"\n").filter { $0.contains(" device ") && $0.contains("usb:") }
        guard devices.count==1,let serial=devices[0].split(whereSeparator:{$0.isWhitespace}).first else { throw USBError.device }
        let id=String(serial)
        _=try run(["-s",id,"reverse","tcp:48765","tcp:48765"])
        let response=try run(["-s",id,"shell","am","broadcast","-f","32","-n","art.squiggle.player/.PairingReceiver","-a","art.squiggle.player.PAIR_USB","--es","address",address,"--es","libraryId",libraryID.uuidString.lowercased()])
        guard response.contains("result=0"),response.contains("Squiggle paired") else { throw USBError.pairing }
        return id
    }
    static func maintain(serial:String) throws ->Bool {
        let devices=try run(["devices","-l"])
        guard devices.split(separator:"\n").contains(where: { $0.split(whereSeparator:{$0.isWhitespace}).first == Substring(serial) && $0.contains(" device ") && $0.contains("usb:") }) else { return false }
        _=try run(["-s",serial,"reverse","tcp:48765","tcp:48765"])
        return true
    }
}
