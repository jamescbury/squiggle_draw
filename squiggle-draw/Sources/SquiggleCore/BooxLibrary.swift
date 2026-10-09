import Foundation
import CryptoKit

public struct LibraryEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public let style: String
    public let createdAt: Date
    public let bytes: Int
    public let sha256: String
    public var available: Bool
}
public struct LibraryCatalog: Codable, Sendable {
    public let libraryID: UUID
    public var entries: [LibraryEntry]
    public init(libraryID: UUID, entries: [LibraryEntry]) { self.libraryID=libraryID;self.entries=entries }
}
public enum LibraryError: LocalizedError {
    case corruptCatalog, full, tooLarge, invalidTitle, missingEntry, invalidFile
    public var errorDescription: String? {
        switch self {
        case .corruptCatalog: "The saved sketch library could not be read. Its files were kept."
        case .full: "The library holds up to 64 sketches and 256 MB of SVG artwork. Remove an older sketch first."
        case .tooLarge: "Choose SVG artwork smaller than 32 MB and a thumbnail smaller than 4 MB."
        case .invalidTitle: "Enter a sketch title of up to 200 characters."
        case .missingEntry: "This sketch is no longer in the library."
        case .invalidFile: "The saved SVG is missing or changed. Add the sketch again."
        }
    }
}
/// Synchronous disk transactions; callers should run these off the main actor.
/// One process-wide lock also protects separate values targeting the same folder.
public struct LibraryStore: Sendable {
    public let rootURL: URL
    private static let transactionLock=NSLock()
    public init(rootURL: URL) { self.rootURL=rootURL }
    public func svgURL(id: UUID) -> URL { rootURL.appendingPathComponent(id.uuidString.lowercased()+".svg") }
    public func thumbnailURL(id: UUID) -> URL { rootURL.appendingPathComponent(id.uuidString.lowercased()+".png") }
    private var indexURL: URL { rootURL.appendingPathComponent("catalog.json") }
    public func load() throws -> LibraryCatalog {
        Self.transactionLock.lock();defer { Self.transactionLock.unlock() }
        return try readCatalog()
    }
    public func add(svg: Data, thumbnail: Data, title: String, style: String) throws -> LibraryCatalog {
        Self.transactionLock.lock();defer { Self.transactionLock.unlock() }
        var catalog=try readCatalog()
        let clean=try cleanTitle(title)
        guard !svg.isEmpty,svg.count<=32*1024*1024,thumbnail.count<=4*1024*1024 else { throw LibraryError.tooLarge }
        guard catalog.entries.count<64,catalog.entries.reduce(0,{$0+$1.bytes})+svg.count<=256*1024*1024 else { throw LibraryError.full }
        let entry=LibraryEntry(id:UUID(),title:clean,style:String(style.prefix(100)),createdAt:Date(),bytes:svg.count,sha256:Self.hash(svg),available:true)
        do {
            try svg.write(to:svgURL(id:entry.id),options:.atomic)
            try thumbnail.write(to:thumbnailURL(id:entry.id),options:.atomic)
            catalog.entries.insert(entry,at:0)
            try writeCatalog(catalog)
        } catch {
            // Only files created by this failed transaction are eligible for cleanup.
            try? FileManager.default.removeItem(at:svgURL(id:entry.id))
            try? FileManager.default.removeItem(at:thumbnailURL(id:entry.id))
            throw error
        }
        return catalog
    }
    public func update(id: UUID, title: String?=nil, available: Bool?=nil) throws -> LibraryCatalog {
        Self.transactionLock.lock();defer { Self.transactionLock.unlock() }
        var catalog=try readCatalog()
        guard let index=catalog.entries.firstIndex(where:{$0.id==id}) else { throw LibraryError.missingEntry }
        if let title { catalog.entries[index].title=try cleanTitle(title) }
        if let available { catalog.entries[index].available=available }
        try writeCatalog(catalog);return catalog
    }
    public func remove(id: UUID) throws -> LibraryCatalog {
        Self.transactionLock.lock();defer { Self.transactionLock.unlock() }
        var catalog=try readCatalog()
        guard catalog.entries.contains(where:{$0.id==id}) else { throw LibraryError.missingEntry }
        catalog.entries.removeAll { $0.id==id }
        // Commit first. A crash may leave an orphan, but can never advertise deleted data.
        try writeCatalog(catalog)
        try? FileManager.default.removeItem(at:svgURL(id:id))
        try? FileManager.default.removeItem(at:thumbnailURL(id:id))
        return catalog
    }
    public func manifest(_ catalog: LibraryCatalog) throws -> Data {
        struct Sketch: Encodable { let id:String;let title:String;let style:String;let createdAt:String;let bytes:Int;let sha256:String;let file:String }
        struct Manifest: Encodable { let schemaVersion:Int;let libraryID:String;let sketches:[Sketch] }
        let formatter=ISO8601DateFormatter()
        let sketches=catalog.entries.filter(\.available).map { Sketch(id:$0.id.uuidString.lowercased(),title:$0.title,style:$0.style,createdAt:formatter.string(from:$0.createdAt),bytes:$0.bytes,sha256:$0.sha256,file:$0.id.uuidString.lowercased()+".svg") }
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return try encoder.encode(Manifest(schemaVersion:1,libraryID:catalog.libraryID.uuidString.lowercased(),sketches:sketches))
    }
    public func verifiedSVG(_ entry: LibraryEntry) throws -> Data {
        let url=svgURL(id:entry.id)
        let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile==true,values.isSymbolicLink != true,values.fileSize==entry.bytes,entry.bytes<=32*1024*1024 else { throw LibraryError.invalidFile }
        let data=try Data(contentsOf:url)
        guard data.count==entry.bytes,Self.hash(data)==entry.sha256 else { throw LibraryError.invalidFile }
        return data
    }
    private func cleanTitle(_ title: String) throws -> String {
        let clean=title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty,clean.count<=200,!clean.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else { throw LibraryError.invalidTitle }
        return clean
    }
    private func readCatalog() throws -> LibraryCatalog {
        try FileManager.default.createDirectory(at:rootURL,withIntermediateDirectories:true)
        guard FileManager.default.fileExists(atPath:indexURL.path) else {
            // Missing index with managed artwork is treated as damaged, never reset.
            let contents=try FileManager.default.contentsOfDirectory(at:rootURL,includingPropertiesForKeys:nil)
            if contents.contains(where:{ ["svg","png"].contains($0.pathExtension) && UUID(uuidString:$0.deletingPathExtension().lastPathComponent) != nil }) { throw LibraryError.corruptCatalog }
            let catalog=LibraryCatalog(libraryID:UUID(),entries:[]);try writeCatalog(catalog);return catalog
        }
        do {
            let size=try indexURL.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size<=1024*1024 else { throw LibraryError.corruptCatalog }
            let catalog=try JSONDecoder().decode(LibraryCatalog.self,from:Data(contentsOf:indexURL))
            guard catalog.entries.count<=64,Set(catalog.entries.map(\.id)).count==catalog.entries.count,
                  catalog.entries.allSatisfy({ $0.bytes>0 && $0.bytes<=32*1024*1024 && $0.sha256.count==64 && $0.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) && !$0.title.isEmpty && $0.title.count<=200 && $0.style.count<=100 }),
                  catalog.entries.reduce(0,{$0+$1.bytes})<=256*1024*1024 else { throw LibraryError.corruptCatalog }
            return catalog
        } catch { throw LibraryError.corruptCatalog }
    }
    private func writeCatalog(_ catalog: LibraryCatalog) throws {
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(catalog).write(to:indexURL,options:.atomic)
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
}

public struct LibraryHTTPResponse: Sendable {
    public let status: Int
    public let contentType: String
    public let body: Data
    public func encoded() -> Data {
        let reason: String
        switch status { case 200:reason="OK";case 400:reason="Bad Request";case 405:reason="Method Not Allowed";case 413:reason="Content Too Large";default:reason="Not Found" }
        var data=Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n".utf8)
        data.append(body);return data
    }
}
/// Exact routes only: no percent decoding, redirects, queries, or filesystem path input.
public enum LibraryRouter {
    public static func response(request: Data, token: String, store: LibraryStore, catalog: LibraryCatalog) -> LibraryHTTPResponse {
        func error(_ code: Int) -> LibraryHTTPResponse { LibraryHTTPResponse(status:code,contentType:"text/plain; charset=utf-8",body:Data("Request unavailable.\n".utf8)) }
        guard request.count<=8192 else { return error(413) }
        guard let text=String(data:request,encoding:.utf8),text.hasSuffix("\r\n\r\n"),!text.contains("\0") else { return error(400) }
        let lines=text.components(separatedBy:"\r\n")
        let start=lines[0].split(separator:" ",omittingEmptySubsequences:false)
        guard start.count==3,start[2]=="HTTP/1.1" || start[2]=="HTTP/1.0",!start[1].isEmpty else { return error(400) }
        guard start[0]=="GET" else { return error(405) }
        for line in lines.dropFirst().dropLast(2) {
            guard let colon=line.firstIndex(of:":"),colon != line.startIndex,!line.hasPrefix(" "),!line.hasPrefix("\t") else { return error(400) }
            let name=line[..<colon].lowercased(),value=line[line.index(after:colon)...].trimmingCharacters(in:.whitespaces)
            if name=="transfer-encoding" || (name=="content-length" && value != "0") { return error(400) }
        }
        let path=String(start[1]),prefix="/"+token+"/"
        guard token.count==64,token.allSatisfy(\.isHexDigit),path.hasPrefix(prefix) else { return error(404) }
        if path==prefix+"manifest.json" {
            guard let body=try? store.manifest(catalog) else { return error(404) }
            return LibraryHTTPResponse(status:200,contentType:"application/json",body:body)
        }
        guard let entry=catalog.entries.first(where:{$0.available && path==prefix+$0.id.uuidString.lowercased()+".svg"}),let body=try? store.verifiedSVG(entry) else { return error(404) }
        return LibraryHTTPResponse(status:200,contentType:"image/svg+xml",body:body)
    }
}
