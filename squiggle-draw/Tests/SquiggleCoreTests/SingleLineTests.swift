import XCTest
@testable import SquiggleCore

final class SingleLineTests:XCTestCase {
    func testGlobalRouteImprovementRemovesCrossingWithoutDroppingPoints() throws {
        let crossed=[Point(0,0),Point(10,10),Point(10,0),Point(0,10)]
        let improved=try Engine.improveStippleRoute(crossed,width:12,height:12)
        XCTAssertEqual(Set(improved.map{ "\($0.x),\($0.y)" }),Set(crossed.map{ "\($0.x),\($0.y)" }))
        let points=improved+[improved[0]],length=zip(points,points.dropFirst()).reduce(0.0){$0+$1.0.distance($1.1)}
        XCTAssertEqual(length,40,accuracy:1e-6)
    }
    func testConnectsEveryStippleIntoOneStrokeAndNoDots() throws {
        let image=try Raster(width:80,height:64,pixels:(0..<5120).map { i in let v=Double(i%80)/100;return Pixel(v,v,v) })
        var p=Parameters();p.spreadAcrossCanvas=false;p.style = .singleLine;p.color=false;p.stippleCount=500;p.relaxation=4;p.cornerRounding=0
        let dots=try Engine.stipple(image,p,{_ in}).layers[0]
        let drawing=try Engine.generate(image,parameters:p),layer=drawing.layers[0]
        XCTAssertEqual(Set(layer.centers.map{ "\($0.x),\($0.y)" }),Set(dots.centers.map{ "\($0.x),\($0.y)" }))
        XCTAssertEqual(layer.strokes.count,1);XCTAssertTrue(layer.dots.isEmpty)
        XCTAssertEqual(layer.points.first,layer.points.last)
        XCTAssertEqual(layer.points.count,layer.centers.count+1)
        let svg=drawing.svg(inks:[.black])
        XCTAssertEqual(svg.components(separatedBy:"<path ").count-1,1)
        XCTAssertFalse(svg.contains("<circle "))
        XCTAssertEqual(svg,try Engine.generate(image,parameters:p).svg(inks:[.black]))
    }
    func testRoundingChangesCenterlineAndStaysInBounds() throws {
        let pair=[Point(2,3),Point(8,9)]
        XCTAssertEqual(try Engine.roundedRoute(pair,rounding:0.65),pair+[pair[0]])
        let square=[Point(0,0),Point(20,0),Point(20,20),Point(0,20)]
        let sharp=try Engine.roundedRoute(square,rounding:0),smooth=try Engine.roundedRoute(square,rounding:1)
        XCTAssertEqual(sharp.count,5);XCTAssertGreaterThan(smooth.count,sharp.count)
        XCTAssertEqual(smooth.first,smooth.last)
        XCTAssertFalse(smooth.contains(square[0]))
        XCTAssertTrue(smooth.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...20).contains($0.x) && (0...20).contains($0.y) })
        let length={ (points:[Point]) in zip(points,points.dropFirst()).reduce(0.0){$0+$1.0.distance($1.1)} }
        XCTAssertLessThan(length(smooth),length(sharp))
    }
    func testWhiteTinyAndMulticolorRoutes() throws {
        var p=Parameters();p.spreadAcrossCanvas=false;p.style = .singleLine;p.stippleCount=500;p.relaxation=4
        let white=try Raster(width:2,height:2,pixels:Array(repeating:Pixel(1,1,1),count:4))
        XCTAssertTrue(try Engine.generate(white,parameters:p).layers.isEmpty)
        let yellow=try Raster(width:24,height:20,pixels:Array(repeating:Pixel(1,1,0),count:480))
        let drawing=try Engine.generate(yellow,parameters:p)
        XCTAssertEqual(drawing.layers.map(\.ink),[.red,.green])
        XCTAssertTrue(drawing.layers.allSatisfy { $0.strokes.count==1 && $0.dots.isEmpty && $0.points.allSatisfy { $0.x>=0 && $0.x<=24 && $0.y>=0 && $0.y<=20 } })
    }
    func testRoundingValidationAndCancellation() async throws {
        var p=Parameters();p.cornerRounding = .nan
        XCTAssertThrowsError(try p.validate())
        let task=Task { try Engine.roundedRoute((0..<20000).map { Point(Double($0),0) },rounding:0.65) }
        task.cancel()
        do { _=try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
