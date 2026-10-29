import XCTest
@testable import SquiggleCore
final class ArtworkExportTests: XCTestCase {
    func testDotsExportAsSeparateFilledCircles() {
        var p=Parameters();p.style = .stipple
        let layer=Layer(ink:.black,centers:[],points:[],strokes:[],dots:[Dot(center:Point(3,4),radius:1),Dot(center:Point(8,9),radius:2)])
        let drawing=Drawing(width:20,height:20,layers:[layer],parameters:p)
        XCTAssertTrue(layer.hasArtwork)
        let svg=drawing.svg(inks:[.black])
        XCTAssertEqual(svg.components(separatedBy:"<circle ").count-1,2)
        XCTAssertFalse(svg.contains("<path "))
        XCTAssertFalse(drawing.svg(inks:[]).contains("<circle "))
    }
    func testPolyExportsFilledAndWireframeFaces() {
        var p=Parameters();p.style = .poly
        let layer=Layer(ink:.black,centers:[],points:[],strokes:[],facets:[Facet(vertices:[Point(0,0),Point(20,0),Point(0,20)],color:Pixel(1,0,0))])
        XCTAssertTrue(layer.hasArtwork)
        XCTAssertTrue(Drawing(width:20,height:20,layers:[layer],parameters:p).svg(inks:[.black]).contains("fill=\"#ff0000\""))
        p.polyWireframe=true
        XCTAssertTrue(Drawing(width:20,height:20,layers:[layer],parameters:p).svg(inks:[.black]).contains("fill=\"none\""))
    }
    func testPolyToneChangesColorsAndKeepsMesh() throws {
        let image=try Raster(width:24,height:24,pixels:Array(repeating:Pixel(0.6,0.4,0.2),count:576))
        var p=Parameters();p.style = .poly;p.relief=0
        let first=try Engine.generate(image,parameters:p).layers[0].facets
        p.gamma=2
        let second=try Engine.generate(image,parameters:p).layers[0].facets
        XCTAssertEqual(first.map(\.vertices),second.map(\.vertices))
        XCTAssertLessThan(second[0].color.r,first[0].color.r)
    }
}
