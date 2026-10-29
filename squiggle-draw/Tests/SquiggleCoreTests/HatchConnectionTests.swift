import XCTest
@testable import SquiggleCore

final class HatchConnectionTests:XCTestCase {
    private func image(_ whiteGap:Bool=false) throws ->Raster {
        try Raster(width:120,height:40,pixels:(0..<4800).map{ i in
            let v=whiteGap && (10...11).contains(i/120) ? 1.0 : 0.0
            return Pixel(v,v,v)
        })
    }
    private var runs:[[Point]] {
        var result=[[Point]]()
        for i in 0..<4 { let y=Double(10+i);result.append([Point(10,y),Point(60,y),Point(110,y)]) }
        return result
    }
    func testJoinsPreserveEveryOriginalSegmentAndLimitAddedInk() throws {
        let image=try image(),joined=try Engine.joinHatchStrokes(runs,image,Array(repeating:1,count:4800),reach:4,vertexBudget:1000)
        XCTAssertEqual(joined.count,1)
        for run in runs { for (a,b) in zip(run,run.dropFirst()) {
            XCTAssertTrue(joined.contains{line in zip(line,line.dropFirst()).contains{($0==a && $1==b) || ($0==b && $1==a)}})
        } }
        var length=0.0
        for line in joined { for (a,b) in zip(line,line.dropFirst()) { length+=a.distance(b) } }
        XCTAssertGreaterThan(length,400);XCTAssertLessThanOrEqual(length,412)
        for line in joined { for q in line {
            XCTAssertGreaterThanOrEqual(q.x,0);XCTAssertLessThan(q.x,120)
            XCTAssertGreaterThanOrEqual(q.y,0);XCTAssertLessThan(q.y,40)
        } }
    }
    func testHighlightGapIsNotBridged() throws {
        let image=try image(true),weights=image.pixels.map{1-$0.luminance}
        let separated=[[Point(10,9),Point(110,9)],[Point(10,12),Point(110,12)]]
        XCTAssertEqual(try Engine.joinHatchStrokes(separated,image,weights,reach:4,vertexBudget:1000),separated)
    }
    func testLargeReachCannotSkipOnePixelHighlightBetweenCurveVertices() throws {
        let image=try Raster(width:1100,height:100,pixels:(0..<110000).map{i in
            let v=i/1100==23 ? 1.0 : 0.0;return Pixel(v,v,v)
        })
        let separated=[[Point(0,10),Point(1000,10)],[Point(1000,50),Point(0,50)]]
        let joined=try Engine.joinHatchStrokes(separated,image,image.pixels.map{1-$0.luminance},reach:40,vertexBudget:1000)
        XCTAssertEqual(joined,separated)
    }
    func testFaintEndpointsDoNotAllowInterpolationToHideWhitePixels() throws {
        let image=try Raster(width:1100,height:100,pixels:(0..<110000).map{i in
            let row=i/1100,v=row==23 ? 1.0 : (row==10 || row==50 ? 0.96 : 0.0)
            return Pixel(v,v,v)
        })
        let separated=[[Point(0,10),Point(1000,10)],[Point(1000,50),Point(0,50)]]
        let joined=try Engine.joinHatchStrokes(separated,image,image.pixels.map{1-$0.luminance},reach:40,vertexBudget:1000)
        XCTAssertEqual(joined,separated)
    }
    func testVertexBudgetAndDisabledConnectionsKeepOriginalStrokes() throws {
        let image=try image()
        XCTAssertEqual(try Engine.joinHatchStrokes(runs,image,Array(repeating:1,count:4800),reach:4,vertexBudget:0),runs)
        let joined=try Engine.joinHatchStrokes(runs,image,Array(repeating:1,count:4800),reach:4,vertexBudget:5)
        XCTAssertLessThanOrEqual(joined.flatMap{$0}.count,runs.flatMap{$0}.count+5)
        var p=Parameters();p.style = .crossHatch;p.connectHatches=false
        let drawing=Drawing(width:120,height:40,layers:[Layer(ink:.black,centers:[],points:runs.flatMap{$0},strokes:runs)],parameters:p)
        XCTAssertEqual(try Engine.connectCrossHatch(drawing,image).layers[0].strokes,runs)
    }
    func testConnectionStageKeepsInkLayersSeparate() throws {
        let image=try Raster(width:120,height:40,pixels:Array(repeating:Pixel(0.3,0.2,0.2),count:4800))
        var p=Parameters();p.style = .crossHatch;p.hatchJoinReach=40
        let redRuns=runs.map{$0.map{Point($0.x,$0.y+10)}}
        let layers=[Layer(ink:.black,centers:[],points:runs.flatMap{$0},strokes:runs),Layer(ink:.red,centers:[],points:redRuns.flatMap{$0},strokes:redRuns)]
        let drawing=Drawing(width:120,height:40,layers:layers,parameters:p)
        let result=try Engine.connectCrossHatch(drawing,image)
        XCTAssertEqual(result.layers.map(\.ink),[.black,.red])
        XCTAssertEqual(result.layers[0].strokes.count,1);XCTAssertEqual(result.layers[1].strokes.count,1)
        XCTAssertTrue(result.layers[0].points.allSatisfy{$0.y<15})
        XCTAssertTrue(result.layers[1].points.allSatisfy{$0.y>19})
    }
    func testConnectionsHonorCancellation() async throws {
        let image=try image(),runs=self.runs
        let task=Task {
            withUnsafeCurrentTask{$0?.cancel()}
            return try Engine.joinHatchStrokes(runs,image,Array(repeating:1,count:4800),reach:4,vertexBudget:1000)
        }
        do { _=try await task.value;XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    func testRandomCoveragePreservesPointsWithLocalAndLongerGestures() throws {
        let image=try Raster(width:160,height:160,pixels:Array(repeating:Pixel(0.5,0.5,0.5),count:25600))
        let points=(0..<1024).map{Point(Double($0%32)*5,Double($0/32)*5)}
        let tour=try Engine.coverageTrace(points,image,seed:42)
        XCTAssertEqual(tour,try Engine.coverageTrace(points,image,seed:42))
        XCTAssertNotEqual(tour,try Engine.coverageTrace(points,image,seed:43))
        XCTAssertEqual(Set(tour.map{"\($0.x),\($0.y)"}),Set(points.map{"\($0.x),\($0.y)"}))
        let distances=zip(tour,tour.dropFirst()).map{$0.distance($1)}
        XCTAssertGreaterThan(distances.filter{$0>60}.count,5)
        XCTAssertGreaterThan(distances.filter{$0<20}.count,800)
    }
}
