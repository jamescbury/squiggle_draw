import XCTest
@testable import SquiggleCore

final class PhotoColorsTests:XCTestCase {
    func image() throws ->Raster {
        try Raster(width:80,height:60,pixels:(0..<4800).map { i in
            let x=Double(i%80)/79,y=Double(i/80)/59
            return Pixel(x,0.1+0.7*y,0.2+0.6*(1-x))
        })
    }
    func source()->Drawing {
        var p=Parameters();p.color=false;p.penWidth=0.8
        let strokes=(0..<20).map { y in [Point(0,Double(y*3)),Point(79,Double(y*3))] }
        return Drawing(width:80,height:60,layers:[Layer(ink:.black,centers:[],points:strokes.flatMap{$0},strokes:strokes,widthFactors:Array(repeating:2,count:20))],parameters:p)
    }
    func testPhotoPaletteUsesAtMostSelectedColorsAndIsDeterministic() throws {
        for count in [12,24] {
            var p=Parameters();p.colorMode = .photoPalette;p.paletteSize=count
            let a=try Engine.photoColored(source(),image:image(),parameters:p)
            let b=try Engine.photoColored(source(),image:image(),parameters:p)
            let colors=a.layers.flatMap(\.strokeColors).map(\.hex)
            XCTAssertGreaterThan(Set(colors).count,4);XCTAssertLessThanOrEqual(Set(colors).count,count)
            XCTAssertEqual(a.svg(inks:[.black]),b.svg(inks:[.black]))
            XCTAssertEqual(a.parameters,p)
        }
    }
    func testFullColorFollowsPhotoWhileKeepingStrokeGeometryAndWidth() throws {
        var p=Parameters();p.colorMode = .fullColor
        let original=source(),colored=try Engine.photoColored(original,image:image(),parameters:p)
        XCTAssertEqual(colored.layers[0].length,original.layers[0].length,accuracy:1e-6)
        XCTAssertEqual(colored.layers[0].strokes.first?.first,original.layers[0].strokes.first?.first)
        XCTAssertEqual(colored.layers[0].strokes.last?.last,original.layers[0].strokes.last?.last)
        XCTAssertTrue(colored.layers[0].widthFactors.allSatisfy{$0==2})
        XCTAssertGreaterThan(Set(colored.layers.flatMap(\.strokeColors).map(\.hex)).count,24)
        let first=colored.layers[0].strokeColors.first!,last=colored.layers[0].strokeColors.last!
        XCTAssertLessThan(first.r,last.r);XCTAssertGreaterThan(first.b,last.b)
        let plan=try DrawTestPlan(colored,inks:[.black])
        XCTAssertEqual(plan.penLifts,19)
        XCTAssertEqual(plan.strokes.first?.color,first)
    }
    func testSVGSizeAndSequentialReaderPreserveColors() throws {
        var p=Parameters();p.colorMode = .fullColor
        let colored=try Engine.photoColored(source(),image:image(),parameters:p)
        let svg=colored.svg(inks:[.black]),size=try colored.svgSize(inks:[.black])
        XCTAssertEqual(size.fileBytes,svg.utf8.count)
        let parsed=try SequenceArtwork(svg:Data(svg.utf8))
        XCTAssertEqual(parsed.strokes.count,colored.layers[0].strokes.count)
        for (a,b) in zip(parsed.strokes,colored.layers[0].strokeColors) { XCTAssertEqual(a.color.hex,b.hex) }
    }
    func testGenerationAndOptimizationKeepRequestedMode() throws {
        var p=Parameters();p.style = .waves;p.lines=20;p.colorMode = .photoPalette;p.paletteSize=12
        let drawing=try Engine.generate(image(),parameters:p)
        XCTAssertEqual(drawing.parameters,p);XCTAssertFalse(drawing.layers.flatMap(\.strokeColors).isEmpty)
        XCTAssertEqual(try Engine.optimize(image(),parameters:p).parameters.colorMode,.photoPalette)
    }
    func testColoredDotsAndFacetsRoundTrip() throws {
        var p=Parameters();p.colorMode = .photoPalette;p.paletteSize=12
        let dot=Dot(center:Point(20,30),radius:2)
        let source=Drawing(width:80,height:60,layers:[Layer(ink:.black,centers:[],points:[],dots:[dot],facets:[Facet(vertices:[Point(30,30),Point(35,30),Point(35,35)],color:Pixel(1,0,0))])],parameters:p)
        let colored=try Engine.photoColored(source,image:image(),parameters:p)
        let svg=colored.svg(inks:[.black])
        XCTAssertEqual(try colored.svgSize(inks:[.black]).fileBytes,svg.utf8.count)
        XCTAssertTrue(svg.contains(colored.layers[0].dotColors[0].hex))
        XCTAssertEqual(try SequenceArtwork(svg:Data(svg.utf8)).strokes.count,2)
        XCTAssertNotNil(try DrawTestPlan(colored,inks:[.black],fillDots:true).strokes.first?.fill)
        XCTAssertNil(try DrawTestPlan(colored,inks:[.black]).strokes.first?.fill)
    }
    func testDisplayPresetsAndLegacyColorCompatibility() {
        let p=Parameters()
        XCTAssertEqual(DisplayMedium.eInk.applying(to:p).colorMode,.monochrome)
        XCTAssertEqual(DisplayMedium.eInkRGB.applying(to:p).colorMode,.rgb)
        XCTAssertEqual(DisplayMedium.tv.applying(to:p).colorMode,.fullColor)
        XCTAssertEqual(DisplayMedium.monitor.applying(to:p).colorMode,.photoPalette)
        XCTAssertFalse(DisplayMedium.plotter.applying(to:p).toneWidth)
        XCTAssertFalse(DisplayMedium.tv.isEInk);XCTAssertFalse(DisplayMedium.monitor.isEInk)
        XCTAssertTrue(DisplayMedium.eInk.isEInk);XCTAssertTrue(DisplayMedium.eInkRGB.isEInk)
        var old=p;old.color=false;XCTAssertEqual(old.colorMode,.monochrome);old.color=true;XCTAssertEqual(old.colorMode,.rgb)
    }
    func testScreenOnlyGalleryEntryDoesNotPublishToTablet() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=LibraryStore(rootURL:root)
        let catalog=try store.add(svg:Data("<svg/>".utf8),thumbnail:Data(),title:"TV artwork",style:"Form",available:false)
        XCTAssertFalse(catalog.entries[0].available)
        XCTAssertFalse(String(data:try store.manifest(catalog),encoding:.utf8)!.contains("TV artwork"))
    }
}
