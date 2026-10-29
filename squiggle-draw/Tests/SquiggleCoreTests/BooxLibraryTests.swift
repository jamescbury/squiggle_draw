import XCTest
@testable import SquiggleCore

final class BooxLibraryTests: XCTestCase {
    private let token=String(repeating:"a",count:64)
    private let svg=Data("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><path d=\"M0 0L10 10\"/></svg>".utf8)
    private func store() throws -> LibraryStore {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("boox-test-"+UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        return LibraryStore(rootURL:root)
    }
    private func request(_ path: String,method: String="GET",headers: String="Host: example\r\n") -> Data {
        Data("\(method) \(path) HTTP/1.1\r\n\(headers)\r\n".utf8)
    }
    func testPersistentIdentityAddRenameToggleAndRemove() throws {
        let store=try store(),initial=try store.load()
        XCTAssertTrue(initial.entries.isEmpty)
        let added=try store.add(svg:svg,thumbnail:Data([1,2,3]),title:" My portrait ",style:"Form sketch")
        let entry=try XCTUnwrap(added.entries.first)
        XCTAssertEqual(entry.title,"My portrait");XCTAssertTrue(entry.available)
        XCTAssertEqual(entry.bytes,svg.count);XCTAssertEqual(entry.sha256.count,64)
        XCTAssertEqual(try store.verifiedSVG(entry),svg)
        let reloaded=try LibraryStore(rootURL:store.rootURL).load()
        XCTAssertEqual(reloaded.libraryID,initial.libraryID);XCTAssertEqual(reloaded.entries.first?.id,entry.id)
        let changed=try store.update(id:entry.id,title:"Renamed",available:false)
        XCTAssertEqual(changed.entries.first?.title,"Renamed");XCTAssertFalse(changed.entries[0].available)
        let manifest=try JSONSerialization.jsonObject(with:store.manifest(changed)) as? [String:Any]
        XCTAssertEqual((manifest?["sketches"] as? [[String:Any]])?.count,0)
        XCTAssertTrue(try store.remove(id:entry.id).entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:store.svgURL(id:entry.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:store.thumbnailURL(id:entry.id).path))
        XCTAssertEqual(try store.load().libraryID,initial.libraryID)
    }
    func testManifestContractAndSelection() throws {
        let store=try store(),catalog=try store.add(svg:svg,thumbnail:Data(),title:"One",style:"Squiggle waves")
        let root=try XCTUnwrap(JSONSerialization.jsonObject(with:store.manifest(catalog)) as? [String:Any])
        XCTAssertEqual(root["schemaVersion"] as? Int,1);XCTAssertEqual(root["libraryID"] as? String,catalog.libraryID.uuidString.lowercased())
        let sketch=try XCTUnwrap((root["sketches"] as? [[String:Any]])?.first),entry=catalog.entries[0]
        XCTAssertEqual(sketch["id"] as? String,entry.id.uuidString.lowercased());XCTAssertEqual(sketch["file"] as? String,entry.id.uuidString.lowercased()+".svg")
        XCTAssertEqual(sketch["bytes"] as? Int,svg.count);XCTAssertEqual(sketch["sha256"] as? String,entry.sha256)
        XCTAssertNotNil(ISO8601DateFormatter().date(from:sketch["createdAt"] as? String ?? ""))
    }
    func testCorruptCatalogAndUnrelatedFilesKept() throws {
        let store=try store();_=try store.load()
        let unrelated=store.rootURL.appendingPathComponent("keep.txt"),index=store.rootURL.appendingPathComponent("catalog.json")
        try Data("keep".utf8).write(to:unrelated)
        try Data("broken".utf8).write(to:index)
        XCTAssertThrowsError(try store.load());XCTAssertThrowsError(try store.add(svg:svg,thumbnail:Data(),title:"New",style:"waves"))
        XCTAssertEqual(try Data(contentsOf:index),Data("broken".utf8));XCTAssertEqual(try Data(contentsOf:unrelated),Data("keep".utf8))
    }
    func testMissingIndexWithManagedArtworkDoesNotResetIdentity() throws {
        let store=try store(),catalog=try store.add(svg:svg,thumbnail:Data(),title:"One",style:"waves")
        try FileManager.default.removeItem(at:store.rootURL.appendingPathComponent("catalog.json"))
        XCTAssertThrowsError(try store.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath:store.svgURL(id:catalog.entries[0].id).path))
    }
    func testRemoveDoesNotDeleteUnrelatedFiles() throws {
        let store=try store(),catalog=try store.add(svg:svg,thumbnail:Data(),title:"One",style:"waves")
        let unrelated=store.rootURL.appendingPathComponent("else.svg");try svg.write(to:unrelated)
        _=try store.remove(id:catalog.entries[0].id)
        XCTAssertEqual(try Data(contentsOf:unrelated),svg)
    }
    func testCatalogLimitAndTitleValidation() throws {
        let store=try store()
        XCTAssertThrowsError(try store.add(svg:svg,thumbnail:Data(),title:"\n",style:"waves"))
        for index in 0..<64 { _=try store.add(svg:svg,thumbnail:Data(),title:"Sketch \(index)",style:"waves") }
        XCTAssertThrowsError(try store.add(svg:svg,thumbnail:Data(),title:"Overflow",style:"waves"))
        XCTAssertEqual(try store.load().entries.count,64)
        XCTAssertThrowsError(try store.add(svg:Data(repeating:0,count:32*1024*1024+1),thumbnail:Data(),title:"Large",style:"waves"))
    }
    func testRouterAllowsOnlyAuthenticatedSelectedExactRoutes() throws {
        let store=try store(),catalog=try store.add(svg:svg,thumbnail:Data(),title:"One",style:"waves")
        let entry=catalog.entries[0],prefix="/\(token)/"
        func route(_ path: String) -> LibraryHTTPResponse { LibraryRouter.response(request:request(path),token:token,store:store,catalog:catalog) }
        XCTAssertEqual(route(prefix+"manifest.json").status,200)
        XCTAssertEqual(route(prefix+entry.id.uuidString.lowercased()+".svg").body,svg)
        for path in ["/manifest.json","/wrong/manifest.json",prefix+"../catalog.json",prefix+"%2e%2e/catalog.json",prefix+"catalog.json",prefix+entry.id.uuidString.lowercased()+".png",prefix+entry.id.uuidString.lowercased()+".svg?x=1",prefix+"/manifest.json"] { XCTAssertEqual(route(path).status,404,path) }
        let hidden=try store.update(id:entry.id,available:false)
        XCTAssertEqual(LibraryRouter.response(request:request(prefix+entry.id.uuidString.lowercased()+".svg"),token:token,store:store,catalog:hidden).status,404)
    }
    func testRouterRejectsMethodsMalformedRequestsAndChangedData() throws {
        let store=try store(),catalog=try store.add(svg:svg,thumbnail:Data(),title:"One",style:"waves"),path="/\(token)/manifest.json"
        func route(_ data: Data) -> Int { LibraryRouter.response(request:data,token:token,store:store,catalog:catalog).status }
        XCTAssertEqual(route(request(path,method:"POST")),405)
        XCTAssertEqual(route(Data("GET /".utf8)),400)
        XCTAssertEqual(route(request(path,headers:"Broken header\r\n")),400)
        XCTAssertEqual(route(request(path,headers:"Content-Length: 12\r\n")),400)
        XCTAssertEqual(route(request(path,headers:"Transfer-Encoding: chunked\r\n")),400)
        XCTAssertEqual(route(Data(repeating:65,count:8193)),413)
        let entry=catalog.entries[0]
        try Data(repeating:65,count:svg.count).write(to:store.svgURL(id:entry.id))
        XCTAssertEqual(route(request("/\(token)/\(entry.id.uuidString.lowercased()).svg")),404)
    }
    func testRouterNeverServesSymlink() throws {
        let store=try store(),catalog=try store.add(svg:svg,thumbnail:Data(),title:"One",style:"waves"),entry=catalog.entries[0]
        let unrelated=store.rootURL.appendingPathComponent("unrelated.txt");try svg.write(to:unrelated)
        try FileManager.default.removeItem(at:store.svgURL(id:entry.id))
        try FileManager.default.createSymbolicLink(at:store.svgURL(id:entry.id),withDestinationURL:unrelated)
        XCTAssertThrowsError(try store.verifiedSVG(entry))
    }
}
