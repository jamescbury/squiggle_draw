import XCTest
@testable import SquiggleCore
final class EngineTests: XCTestCase {
    func circularParameters() -> Parameters { var p=Parameters();p.style = .circular;p.matchTones=false;return p }
    func raster(_ pixel:Pixel,width:Int=80,height:Int=64) throws -> Raster { try Raster(width:width,height:height,pixels:Array(repeating:pixel,count:width*height)) }
    func testColorSeparation() {
        let cases:[(Pixel,[Double])]=[(Pixel(1,0,0),[1,0,0,0]),(Pixel(0,1,0),[0,1,0,0]),(Pixel(0,0,1),[0,0,1,0]),(Pixel(1,1,0),[1,1,0,0]),(Pixel(0,1,1),[0,1,1,0]),(Pixel(1,0,1),[1,0,1,0]),(Pixel(0.4,0.4,0.4),[0,0,0,0.6]),(Pixel(1,1,1),[0,0,0,0])]
        for (pixel,expected) in cases { for ink in Ink.allCases { XCTAssertEqual(pixel.weight(ink,color:true),expected[ink.index],accuracy:1e-9) } }
    }
    func testWhiteHasNoInkAndBlackIsBounded() throws {
        let p=circularParameters()
        let white=try Engine.generate(raster(Pixel(1,1,1)),parameters:p)
        XCTAssertTrue(white.layers.isEmpty)
        let black=try Engine.generate(raster(Pixel(0,0,0)),parameters:p)
        XCTAssertEqual(black.layers.count,1);XCTAssertEqual(black.layers[0].ink,.black)
        XCTAssertGreaterThan(black.vertexCount,10);XCTAssertLessThan(black.vertexCount,1000000)
        for point in black.layers[0].points { XCTAssertTrue(point.x.isFinite && point.y.isFinite);XCTAssertTrue((0...79).contains(point.x));XCTAssertTrue((0...63).contains(point.y)) }
    }
    func testMinimumAndThinImages() throws {
        for (w,h) in [(2,2),(4,64),(64,3),(1600,2)] {
            let image=try raster(Pixel(0,0,0),width:w,height:h)
            let drawing=try Engine.generate(image,parameters:circularParameters())
            XCTAssertGreaterThan(drawing.vertexCount,0)
            XCTAssertTrue(drawing.layers.flatMap(\.points).allSatisfy { $0.x.isFinite && $0.y.isFinite })
        }
    }
    func testDeterminism() throws {
        let image=try raster(Pixel(0.5,0.2,0.1))
        let a=try Engine.generate(image,parameters:circularParameters()),b=try Engine.generate(image,parameters:circularParameters())
        XCTAssertEqual(a.layers.map(\.points),b.layers.map(\.points))
    }
    func testEdgeRadiusAndTourCoverage() throws {
        var p=circularParameters();p.minRadius=2;p.maxRadius=10
        XCTAssertEqual(Engine.radius(tone:1,distance:3,parameters:p),3)
        XCTAssertEqual(Engine.radius(tone:1,distance:0,parameters:p),2)
        p.protectEdges=false;XCTAssertEqual(Engine.radius(tone:1,distance:0,parameters:p),10)
        let image=try raster(Pixel(0,0,0)),points=[Point(2,3),Point(15,10),Point(30,40),Point(70,50),Point(20,20)]
        let tour=try Engine.trace(points,Engine.regions(image),image)
        XCTAssertEqual(tour.count,points.count)
        for q in points { XCTAssertEqual(tour.filter{$0==q}.count,1) }
    }
    func testSVGExportLayerOrderAndSinglePen() throws {
        let image=try Raster(width:80,height:64,pixels:(0..<5120).map { i in i%80<40 ? Pixel(1,0,0) : Pixel(0,0,1) })
        let drawing=try Engine.generate(image,parameters:circularParameters())
        let full=drawing.svg(inks:Set(Ink.allCases)),red=drawing.svg(inks:[.red])
        XCTAssertTrue(full.contains("viewBox=\"0 0 80 64\""));XCTAssertTrue(full.contains("stroke=\"#dd3039\""));XCTAssertTrue(full.contains("stroke=\"#285bd7\""))
        XCTAssertEqual(red.components(separatedBy:"<path ").count-1,drawing.layers.first{$0.ink == .red}!.strokes.count);XCTAssertFalse(red.contains("id=\"blue\""));XCTAssertFalse(full.contains("NaN"))
    }
    func testToneRampProgression() throws {
        var p=circularParameters();p.color=false
        let dark=try Engine.generate(raster(Pixel(0.1,0.1,0.1)),parameters:p),light=try Engine.generate(raster(Pixel(0.8,0.8,0.8)),parameters:p)
        XCTAssertGreaterThan(dark.sampleCount,light.sampleCount)
        XCTAssertGreaterThan(dark.layers[0].length,light.layers[0].length)
    }
    func testInputAndVertexLimits() throws {
        XCTAssertThrowsError(try Raster(width:2,height:2,pixels:[]))
        var p=circularParameters();p.minRadius=10;p.maxRadius=1
        XCTAssertThrowsError(try Engine.generate(raster(Pixel(0,0,0)),parameters:p))
        let image=try raster(Pixel(0,0,0))
        XCTAssertThrowsError(try Engine.scribble([Point(0,0),Point(79,63)],image,Array(repeating:1,count:5120),Array(repeating:10,count:5120),Parameters(),1,10))
    }
    func testCancellation() async throws {
        let image=try raster(Pixel(0,0,0),width:300,height:300)
        let settings=circularParameters()
        let task=Task { try Engine.generate(image,parameters:settings) };task.cancel()
        do { _=try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
