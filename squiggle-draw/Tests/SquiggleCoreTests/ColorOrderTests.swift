import XCTest
@testable import SquiggleCore

final class ColorOrderTests:XCTestCase {
    private func drawing(rounds:Int=4,enabled:Bool=true)->Drawing {
        var p=Parameters();p.style = .formSketch;p.alternateColors=enabled;p.colorRounds=rounds
        let layers=[Ink.red,.black].map { ink ->Layer in
            let y=Double(ink.index)*10,run=[Point(0,y),Point(40,y),Point(100,y)]
            return Layer(ink:ink,centers:run,points:run,strokes:[run])
        }
        return Drawing(width:101,height:40,layers:layers,parameters:p)
    }
    func testAlternatesAtEqualInkProgressAndResumesExactEndpoints() throws {
        let result=try Engine.alternateColorOrder(drawing()),layers=result.drawingLayers(inks:[.red,.black])
        XCTAssertEqual(layers.map(\.ink),[.red,.black,.red,.black,.red,.black,.red,.black])
        for ink in [Ink.red,.black] {
            let passes=layers.filter{$0.ink==ink}
            XCTAssertEqual(passes.reduce(0){$0+$1.length},100,accuracy:1e-8)
            for i in passes.indices {
                XCTAssertEqual(passes[i].strokes[0].first?.x,Double(i)*25)
                XCTAssertEqual(passes[i].strokes[0].last?.x,Double(i+1)*25)
                if i>0 { XCTAssertEqual(passes[i-1].strokes[0].last,passes[i].strokes[0].first) }
            }
        }
        XCTAssertEqual(try DrawTestPlan(result,inks:[.red,.black]).strokes.map(\.ink),layers.map(\.ink))
    }
    func testDefaultOffAndIndividualPenExportsKeepOriginalContinuousPaths() throws {
        XCTAssertFalse(Parameters().alternateColors)
        let original=drawing(enabled:false),grouped=try Engine.alternateColorOrder(original)
        XCTAssertNil(grouped.colorPasses)
        XCTAssertEqual(grouped.drawingLayers(inks:[.red,.black]).map(\.ink),[.red,.black])
        let mixed=try Engine.alternateColorOrder(drawing())
        for ink in [Ink.red,.black] {
            XCTAssertEqual(mixed.svg(inks:[ink]),original.svg(inks:[ink]))
            XCTAssertEqual(try DrawTestPlan(mixed,inks:[ink]).strokes.count,1)
            XCTAssertEqual(mixed.drawingLayers(inks:[ink])[0].strokes,original.layers.first{$0.ink==ink}!.strokes)
        }
        XCTAssertTrue(mixed.drawingLayers(inks:[]).isEmpty)
    }
    func testSVGOrderUniqueGroupsAndExactSizeMatchPlayback() throws {
        let result=try Engine.alternateColorOrder(drawing()),svg=result.svg(inks:[.red,.black])
        let ids=svg.components(separatedBy:"<g id=\"").dropFirst().map{String($0.prefix(while:{$0 != "\""}))}
        XCTAssertEqual(ids,["red","black","red-2","black-2","red-3","black-3","red-4","black-4"])
        XCTAssertEqual(Set(ids).count,ids.count)
        let colors=svg.components(separatedBy:"<path ").dropFirst().map{String($0.components(separatedBy:"stroke=\"")[1].prefix(while:{$0 != "\""}))}
        XCTAssertEqual(colors,try DrawTestPlan(result,inks:[.red,.black]).strokes.map{$0.ink.hex})
        let size=try result.svgSize(inks:[.red,.black])
        XCTAssertEqual(size.fileBytes,svg.utf8.count);XCTAssertEqual(size.elements,17)
        XCTAssertEqual(size.pathDataBytes,svg.components(separatedBy:" d=\"").dropFirst().reduce(0){$0+$1.prefix(while:{$0 != "\""}).utf8.count})
        XCTAssertEqual(try result.svgSize(inks:[.red]).fileBytes,result.svg(inks:[.red]).utf8.count)
    }
    func testDotsStayWholeAndInkSequenceIsPreserved() throws {
        var p=Parameters();p.style = .stipple;p.alternateColors=true;p.colorRounds=4
        let layers=[Ink.red,.green].map { ink in
            Layer(ink:ink,centers:[],points:[],strokes:[],dots:(0..<8).map{Dot(center:Point(Double($0)*3,Double(ink.index)*5),radius:1)})
        }
        let result=try Engine.alternateColorOrder(Drawing(width:30,height:20,layers:layers,parameters:p))
        let passes=result.drawingLayers(inks:[.red,.green])
        XCTAssertEqual(passes.map(\.ink),[.red,.green,.red,.green,.red,.green,.red,.green])
        for ink in [Ink.red,.green] {
            XCTAssertEqual(passes.filter{$0.ink==ink}.flatMap(\.dots).map(\.center),layers.first{$0.ink==ink}!.dots.map(\.center))
            XCTAssertTrue(passes.filter{$0.ink==ink}.flatMap(\.dots).allSatisfy{$0.radius==1})
        }
        let plan=try DrawTestPlan(result,inks:[.red,.green])
        XCTAssertEqual(plan.strokes.first{$0.ink == .red}?.color.r,221.0/255)
        XCTAssertEqual(plan.strokes.first{$0.ink == .green}?.color.g,139.0/255)
        let svg=result.svg(inks:[.red,.green]);XCTAssertTrue(svg.contains("stroke=\"#dd3039\" stroke-width=\"0\""));XCTAssertEqual(try result.svgSize(inks:[.red,.green]).fileBytes,svg.utf8.count)
    }
    func testInactiveForMonoAndPolyAndHonorsCancellation() async throws {
        let base=drawing();var p=base.parameters;p.color=false
        XCTAssertNil(try Engine.alternateColorOrder(Drawing(width:101,height:40,layers:base.layers,parameters:p)).colorPasses)
        p.color=true;p.style = .poly
        XCTAssertNil(try Engine.alternateColorOrder(Drawing(width:101,height:40,layers:base.layers,parameters:p)).colorPasses)
        p.colorRounds=1;XCTAssertThrowsError(try p.validate())
        let task=Task { withUnsafeCurrentTask{$0?.cancel()};return try Engine.alternateColorOrder(base) }
        do { _=try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    func testGeneratedFormSketchUsesAlternationAndOptimizerKeepsChoice() throws {
        let image=try Raster(width:60,height:60,pixels:Array(repeating:Pixel(0.8,0.3,0.1),count:3600))
        var p=Parameters();p.style = .formSketch;p.sketchBackground=1;p.alternateColors=true;p.colorRounds=8
        let optimized=try Engine.optimize(image,parameters:p).parameters
        XCTAssertTrue(optimized.alternateColors);XCTAssertEqual(optimized.colorRounds,8)
        let drawing=try Engine.generate(image,parameters:p)
        XCTAssertNotNil(drawing.colorPasses)
        XCTAssertGreaterThan(drawing.drawingLayers(inks:Set(Ink.allCases)).count,drawing.layers.count)
    }
}
