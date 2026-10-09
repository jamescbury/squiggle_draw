import XCTest
@testable import SquiggleCore

final class FormSketchTests:XCTestCase {
    private func parameters()->Parameters {
        var p=Parameters();p.style = .formSketch;p.color=false;p.sketchBackground=1;return p
    }
    func testBlankThinImagesAndBounds() throws {
        let white=try Raster(width:40,height:40,pixels:Array(repeating:Pixel(1,1,1),count:1600))
        XCTAssertTrue(try Engine.generate(white,parameters:parameters()).layers.isEmpty)
        for (w,h) in [(2,2),(2,60),(60,2),(48,64)] {
            let image=try Raster(width:w,height:h,pixels:Array(repeating:Pixel(0.3,0.3,0.3),count:w*h))
            let drawing=try Engine.generate(image,parameters:parameters())
            for q in drawing.layers.flatMap(\.points) {
                XCTAssertTrue(q.x.isFinite && q.y.isFinite)
                XCTAssertGreaterThanOrEqual(q.x,0);XCTAssertLessThan(q.x,Double(w))
                XCTAssertGreaterThanOrEqual(q.y,0);XCTAssertLessThan(q.y,Double(h))
            }
        }
    }
    func testStructureFirstAndSequenceSurvivesCoverageToggleAndExport() throws {
        let w=100,h=100,image=try Raster(width:w,height:h,pixels:(0..<w*h).map{i in
            let x=i%w,y=i/w,v=(20...80).contains(x) && (20...80).contains(y) ? 0.25 : 1.0
            return Pixel(v,v,v)
        })
        var p=parameters();let drawing=try Engine.generate(image,parameters:p)
        let first=try XCTUnwrap(drawing.layers.first?.strokes.first)
        XCTAssertGreaterThan(first.count,10)
        XCTAssertTrue(first.allSatisfy{q in min(abs(q.x-20),abs(q.x-80),abs(q.y-20),abs(q.y-80))<3})
        p.spreadAcrossCanvas=false
        XCTAssertEqual(drawing.svg(inks:[.black]),try Engine.generate(image,parameters:p).svg(inks:[.black]))
        XCTAssertEqual(drawing.layers[0].strokes,try Engine.spreadOrder(drawing).layers[0].strokes)
        let plan=try DrawTestPlan(drawing,inks:[.black])
        XCTAssertEqual(plan.strokes.count,drawing.layers[0].strokes.count)
        XCTAssertEqual(plan.strokes[0].points,first)
    }
    func testToneFieldGuidesHatchingAlongSurfaceInsteadOfFixedPageAngle() throws {
        func drawing(horizontal:Bool) throws ->Drawing {
            let image=try Raster(width:100,height:100,pixels:(0..<10000).map{i in
                let position=horizontal ? i/100 : i%100,v=0.2+Double(position)/140
                return Pixel(v,v,v)
            })
            return try Engine.generate(image,parameters:parameters())
        }
        func directionRatio(_ drawing:Drawing)->Double {
            var x=0.0,y=0.0
            for run in drawing.layers.flatMap(\.strokes) { for (a,b) in zip(run,run.dropFirst()) { x+=abs(a.x-b.x);y+=abs(a.y-b.y) } }
            return x/max(1e-9,y)
        }
        XCTAssertGreaterThan(directionRatio(try drawing(horizontal:true)),1.5)
        XCTAssertLessThan(directionRatio(try drawing(horizontal:false)),0.67)
    }
    func testBackgroundControlReducesSmoothBorderShadingAndSeedIsReproducible() throws {
        let image=try Raster(width:80,height:80,pixels:Array(repeating:Pixel(0.4,0.5,0.7),count:6400))
        var p=parameters();let full=try Engine.generate(image,parameters:p)
        p.sketchBackground=0.08;let quiet=try Engine.generate(image,parameters:p)
        XCTAssertLessThan(quiet.layers.reduce(0){$0+$1.length},full.layers.reduce(0){$0+$1.length}*0.3)
        XCTAssertEqual(quiet.svg(inks:[.black]),try Engine.generate(image,parameters:p).svg(inks:[.black]))
        p.sketchBackground=1;p.seed=43;XCTAssertNotEqual(full.svg(inks:[.black]),try Engine.generate(image,parameters:p).svg(inks:[.black]))
    }
    func testBackgroundSimplificationDoesNotFloodThroughLowContrastContour() throws {
        let image=try Raster(width:80,height:80,pixels:(0..<6400).map{i in
            let radius=hypot(Double(i%80)-40,Double(i/80)-40)
            let v=(20...26).contains(radius) ? 0.51 : 0.6
            return Pixel(v,v,v)
        })
        var p=parameters();p.sketchBackground=0
        let drawing=try Engine.generate(image,parameters:p)
        XCTAssertTrue(drawing.layers.flatMap(\.points).contains{hypot($0.x-40,$0.y-40)<10})
    }
    func testStageJoinsUseFieldCoordinatesAndReturnFullResolutionGeometry() throws {
        let image=try Raster(width:1000,height:80,pixels:Array(repeating:Pixel(0.3,0.3,0.3),count:80000))
        var p=parameters();p.connectHatches=false
        let raw=try Engine.generate(image,parameters:p)
        p.connectHatches=true;let joined=try Engine.generate(image,parameters:p)
        let layer=try XCTUnwrap(joined.layers.first)
        XCTAssertGreaterThan(layer.points.map(\.x).max() ?? 0,900)
        XCTAssertTrue(layer.points.allSatisfy{$0.x>=0 && $0.x<1000 && $0.y>=0 && $0.y<80})
        XCTAssertLessThan(layer.strokes.count,raw.layers[0].strokes.count)
        XCTAssertGreaterThanOrEqual(layer.length,raw.layers[0].length-1e-6)
        XCTAssertLessThanOrEqual(layer.length,raw.layers[0].length*1.031)
    }
    func testValidationColorSeparationAndCancellation() async throws {
        let image=try Raster(width:50,height:50,pixels:Array(repeating:Pixel(1,0,0),count:2500))
        var p=parameters();p.color=true
        XCTAssertEqual(try Engine.generate(image,parameters:p).layers.map(\.ink),[.red])
        p.sketchBackground = .nan;XCTAssertThrowsError(try p.validate())
        p=parameters();p.sketchDetail=2;XCTAssertThrowsError(try p.validate())
        let valid=parameters(),task=Task { withUnsafeCurrentTask{$0?.cancel()};return try Engine.generate(image,parameters:valid) }
        do { _=try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
