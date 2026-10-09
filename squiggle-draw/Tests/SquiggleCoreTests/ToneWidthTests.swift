import XCTest
@testable import SquiggleCore

final class ToneWidthTests:XCTestCase {
    func drawing(alternate:Bool=false)->Drawing {
        var p=Parameters();p.style = .circular;p.alternateColors=alternate;p.colorRounds=8
        let strokes=[[Point(0,0),Point(10,0)],[Point(10,0),Point(20,0)],[Point(30,0),Point(40,0)]]
        let layers:[Layer]=[.red,.blue].map { Layer(ink:$0,centers:[],points:strokes.flatMap{$0},strokes:strokes,widthFactors:[1,4,2]) }
        return Drawing(width:50,height:20,layers:layers,parameters:p)
    }
    func testWidthRunsPreserveGeometryAndConnectivity() throws {
        let points=(0...200).map { Point(Double($0),sin(Double($0)*0.1)*10) }
        let runs=try Engine.widthRuns([points],minimumRun:4,maximum:4) { $0.x<100 ? 1 : 4 }
        XCTAssertEqual(runs.strokes.first?.first,points.first);XCTAssertEqual(runs.strokes.last?.last,points.last)
        XCTAssertEqual(runs.strokes.first!+runs.strokes.dropFirst().flatMap{$0.dropFirst()},points)
        XCTAssertEqual(runs.factors.first,1);XCTAssertEqual(runs.factors.last,4)
        for i in 1..<runs.strokes.count { XCTAssertEqual(runs.strokes[i-1].last,runs.strokes[i].first) }
    }
    func testSVGWidthsExactSizeAndContinuousPlayback() throws {
        let d=drawing(),svg=d.svg(inks:[.red]),plan=try DrawTestPlan(d,inks:[.red])
        XCTAssertTrue(svg.contains("stroke-width=\"2.600\" data-squiggle-width-scale=\"4.000\""))
        XCTAssertEqual(try d.svgSize(inks:[.red]).fileBytes,svg.utf8.count)
        XCTAssertEqual(plan.strokes.map(\.widthFactor),[1,4,2]);XCTAssertEqual(plan.penLifts,1)
        var state=DrawTestState();try state.advance(seconds:1.1,speed:10,plan:plan)
        XCTAssertEqual(state.stroke,1);XCTAssertEqual(state.distance,1,accuracy:1e-6);XCTAssertEqual(state.liftRemaining,0)
        try state.advance(seconds:1,speed:10,plan:plan)
        XCTAssertEqual(state.stroke,2);XCTAssertEqual(state.distance,0);XCTAssertEqual(state.liftRemaining,0.1,accuracy:1e-6)
    }
    func testAlternationPreservesWidthWeightedLengthAndSinglePenPaths() throws {
        let original=drawing(alternate:true),ordered=try Engine.alternateColorOrder(original)
        func inkArea(_ layers:[Layer])->Double { layers.reduce(0) { sum,l in sum+l.strokes.enumerated().reduce(0) { $0+zip($1.element,$1.element.dropFirst()).reduce(0){$0+$1.0.distance($1.1)}*l.widthFactor(at:$1.offset) } } }
        XCTAssertEqual(inkArea(original.layers),inkArea(ordered.drawingLayers(inks:[.red,.blue])),accuracy:1e-6)
        XCTAssertEqual(ordered.drawingLayers(inks:[.red]).first?.widthFactors,[1,4,2])
        let svg=ordered.svg(inks:[.red,.blue]);XCTAssertEqual(try ordered.svgSize(inks:[.red,.blue]).fileBytes,svg.utf8.count)
        let plan=try DrawTestPlan(ordered,inks:[.red,.blue]);for i in 1..<plan.strokes.count where plan.strokes[i].ink != plan.strokes[i-1].ink { XCTAssertFalse(plan.strokes[i].continues) }
    }
    func testOptimizerUsesBroadLoopsAndRespectsUniformPenChoice() throws {
        let image=try Raster(width:100,height:80,pixels:Array(repeating:Pixel(0.4,0.4,0.4),count:8000))
        var p=Parameters();p.style = .circular;p.color=false;p.toneWidth=false
        p=try Engine.optimize(image,parameters:p).parameters
        XCTAssertGreaterThanOrEqual(p.minRadius,18);XCTAssertGreaterThanOrEqual(p.maxRadius,70);XCTAssertFalse(p.toneWidth)
        let d=try Engine.generate(image,parameters:p)
        XCTAssertTrue(d.layers.allSatisfy{$0.widthFactors.isEmpty});XCTAssertFalse(d.svg(inks:[.black]).contains("data-squiggle-width-scale"))
        p.toneWidth=true
        let variable=try Engine.generate(image,parameters:p)
        XCTAssertTrue(variable.layers.allSatisfy{$0.widthFactors.count == $0.strokes.count})
        XCTAssertTrue(variable.layers.flatMap(\.widthFactors).allSatisfy{$0>1})
        XCTAssertLessThan(try variable.svgSize(inks:[.black]).elements,20000)
    }
}
