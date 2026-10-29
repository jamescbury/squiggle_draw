import XCTest
import CoreGraphics
@testable import SquiggleCore

final class CrossHatchTests:XCTestCase {
    func testTonesAreMonotonicAndCrossingLayersAddShadows() throws {
        var p=Parameters();p.style = .crossHatch;p.color=false
        var previous=0.0
        for value in [1.0,0.8,0.5,0.2,0.0] {
            let image=try Raster(width:120,height:100,pixels:Array(repeating:Pixel(value,value,value),count:12000))
            let drawing=try Engine.generate(image,parameters:p)
            let length=drawing.layers.reduce(0){$0+$1.length}
            if value==1 { XCTAssertTrue(drawing.layers.isEmpty) } else { XCTAssertGreaterThan(length,previous) }
            previous=length
        }
        let image=try Raster(width:80,height:80,pixels:Array(repeating:Pixel(0,0,0),count:6400))
        p.hatchPasses=2;let fewer=try Engine.generate(image,parameters:p)
        p.hatchPasses=8;let more=try Engine.generate(image,parameters:p)
        XCTAssertGreaterThan(more.layers[0].length,fewer.layers[0].length*1.2)
    }
    func testContinuousToneModelMatchesFractionalAreaCoverage() {
        var p=Parameters();p.color=false
        let charcoal=Pixel(32.0/255,34.0/255,31.0/255).luminance
        for fraction in [0.2,0.4,0.7] {
            let dose = -log(1-fraction)
            for gray in [0.2,0.4,0.6,0.8,0.95] {
                let level=Engine.hatchLevel(1-gray,dose,p),full=floor(level)
                let actual=charcoal+(1-charcoal)*pow(1-fraction,full)*(1-fraction*(level-full))
                XCTAssertEqual(actual,gray,accuracy:1e-8)
            }
        }
    }
    func testStrokesStayInFrameAndExportsDoNotJoinBreaks() throws {
        let image=try Raster(width:80,height:60,pixels:(0..<4800).map { i in let v=Double(i%80)/80;return Pixel(v,v,v) })
        var p=Parameters();p.style = .crossHatch;p.color=false;p.connectHatches=false
        let drawing=try Engine.generate(image,parameters:p),layer=drawing.layers[0]
        XCTAssertGreaterThan(layer.strokes.count,10)
        XCTAssertTrue(layer.strokes.allSatisfy { $0.count>1 })
        XCTAssertTrue(layer.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...79).contains($0.x) && (0...59).contains($0.y) })
        let svg=drawing.svg(inks:[.black]);XCTAssertEqual(svg.components(separatedBy:"<path ").count-1,layer.strokes.count)
        XCTAssertEqual(svg,try Engine.generate(image,parameters:p).svg(inks:[.black]))
        p.seed=43;XCTAssertNotEqual(layer.points,try Engine.generate(image,parameters:p).layers[0].points)
    }
    func testColorSeparationTinyInputsAndOptimizer() throws {
        var p=Parameters();p.style = .crossHatch
        let yellow=try Raster(width:100,height:80,pixels:Array(repeating:Pixel(1,1,0),count:8000))
        let optimized=try Engine.optimize(yellow,parameters:p).parameters
        XCTAssertEqual(optimized.style,.crossHatch);XCTAssertEqual(optimized.penWidth,p.penWidth);XCTAssertEqual(optimized.seed,p.seed)
        XCTAssertEqual(try Engine.generate(yellow,parameters:optimized).layers.map(\.ink),[.red,.green])
        let tiny=try Raster(width:2,height:2,pixels:Array(repeating:Pixel(0,0,0),count:4))
        let tinyDrawing=try Engine.generate(tiny,parameters:p)
        XCTAssertGreaterThan(tinyDrawing.vertexCount,0);XCTAssertLessThan(tinyDrawing.vertexCount,500)
    }
    func testOptimizerKeepsFullSizeTwoInkArtworkWithinBudget() throws {
        let image=try Raster(width:1600,height:1200,pixels:Array(repeating:Pixel(1,1,0),count:1920000))
        var p=Parameters();p.style = .crossHatch
        let optimized=try Engine.optimize(image,parameters:p).parameters
        let drawing=try Engine.generate(image,parameters:optimized)
        XCTAssertEqual(drawing.layers.map(\.ink),[.red,.green])
        XCTAssertGreaterThan(drawing.vertexCount,0);XCTAssertLessThanOrEqual(drawing.vertexCount,8000000)
    }
    func testValidationAndCancellation() async throws {
        var p=Parameters();p.hatchSpacing = .nan;XCTAssertThrowsError(try p.validate())
        p=Parameters();p.hatchPasses=9;XCTAssertThrowsError(try p.validate())
        p=Parameters();p.hatchCurve = .infinity;XCTAssertThrowsError(try p.validate())
        let image=try Raster(width:20,height:20,pixels:Array(repeating:Pixel(0,0,0),count:400))
        let task=Task { withUnsafeCurrentTask{$0?.cancel()};var valid=Parameters();valid.style = .crossHatch;return try Engine.generate(image,parameters:valid) }
        do { _=try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
    }
}
