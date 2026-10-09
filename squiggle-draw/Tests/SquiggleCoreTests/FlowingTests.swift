import XCTest
@testable import SquiggleCore

final class FlowingTests:XCTestCase {
    func testContinuousCrossingCurvesAndDeterministicExport() throws {
        let image=try Raster(width:160,height:160,pixels:Array(repeating:Pixel(0.5,0.5,0.5),count:25600))
        var p=Parameters();p.spreadAcrossCanvas=false;p.style = .flowing;p.color=false;p.minRadius=12;p.maxRadius=12
        let points=try Engine.flowingScribble([Point(60,80),Point(100,80)],image,Array(repeating:0.5,count:25600),Array(repeating:100,count:25600),p,1,50000,.black)
        func cross(_ a:Point,_ b:Point,_ c:Point)->Double { (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x) }
        var crossings=0
        for i in 0..<points.count-4 {
            for j in i+3..<points.count-1 {
                let a=points[i],b=points[i+1],c=points[j],d=points[j+1]
                if cross(a,b,c)*cross(a,b,d)<0 && cross(c,d,a)*cross(c,d,b)<0 { crossings+=1 }
            }
        }
        XCTAssertGreaterThan(crossings,0,"The drawn line must freely overlap itself")
        XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...159).contains($0.x) && (0...159).contains($0.y) })
        let drawing=try Engine.generate(image,parameters:p)
        XCTAssertEqual(drawing.layers.count,1);XCTAssertEqual(drawing.layers[0].strokes.count,1)
        XCTAssertEqual(drawing.svg(inks:[.black]).components(separatedBy:"<path ").count-1,1)
        XCTAssertEqual(drawing.layers[0].points,try Engine.generate(image,parameters:p).layers[0].points)
        p.seed=43
        XCTAssertNotEqual(drawing.layers[0].points,try Engine.generate(image,parameters:p).layers[0].points)
    }
    func testWhiteAndColorSeparationAndOptimization() throws {
        var p=Parameters();p.spreadAcrossCanvas=false;p.style = .flowing
        let white=try Raster(width:20,height:20,pixels:Array(repeating:Pixel(1,1,1),count:400))
        XCTAssertTrue(try Engine.generate(white,parameters:p).layers.isEmpty)
        let yellow=try Raster(width:40,height:40,pixels:Array(repeating:Pixel(1,1,0),count:1600))
        let optimized=try Engine.optimize(yellow,parameters:p).parameters
        XCTAssertEqual(optimized.style,.flowing);XCTAssertEqual(optimized.penWidth,p.penWidth)
        let drawing=try Engine.generate(yellow,parameters:optimized)
        XCTAssertEqual(drawing.layers.map(\.ink),[.red,.green])
        XCTAssertTrue(drawing.layers.allSatisfy { $0.strokes.count==1 && $0.dots.isEmpty })
    }
    func testValidationBudgetAndCancellation() async throws {
        var p=Parameters();p.curveStretch = .infinity
        XCTAssertThrowsError(try p.validate());p.curveStretch=2;p.curveWander = .nan
        XCTAssertThrowsError(try p.validate());p=Parameters()
        let image=try Raster(width:2,height:2,pixels:Array(repeating:Pixel(0,0,0),count:4))
        XCTAssertThrowsError(try Engine.flowingScribble([Point(0,0)],image,[1,1,1,1],[1,1,1,1],p,1,3,.black))
        let valid=p
        let task=Task { withUnsafeCurrentTask { $0?.cancel() };return try Engine.flowingScribble([Point(0,0)],image,[1,1,1,1],[1,1,1,1],valid,1,500,.black) }
        task.cancel()
        do { _=try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
