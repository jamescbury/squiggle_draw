import XCTest
@testable import SquiggleCore

final class CircularContourTests:XCTestCase {
    func boundary(_ left:Pixel=Pixel(0.1,0.1,0.1),_ right:Pixel=Pixel(1,1,1)) throws ->Raster {
        try Raster(width:160,height:160,pixels:(0..<25600).map { $0%160<80 ? left : right })
    }
    func testLoopsFlattenAlongSilhouetteWithoutShrinkingLongAxis() throws {
        let image=try boundary(),guide=try CircularContours(image)
        var p=Parameters();p.style = .circular;p.minRadius=26;p.maxRadius=26;p.protectEdges=true
        let center=Point(73,80),weights=Array(repeating:0.5,count:25600),edges=try Engine.edges(image)
        let protected=try Engine.scribble([center],image,weights,edges,p,1,10000,contours:guide)
        let round=try Engine.scribble([center],image,weights,edges,p,1,10000)
        XCTAssertGreaterThan(round.map(\.x).max()!,95)
        XCTAssertLessThan(protected.map(\.x).max()!,80)
        XCTAssertGreaterThan(protected.map(\.y).max()!-protected.map(\.y).min()!,40)
        XCTAssertLessThan(protected.map(\.x).max()!-protected.map(\.x).min()!,15)
        XCTAssertEqual(protected.count,round.count)
    }
    func testRadialProbeDetectsNarrowHighlightBetweenEndpoints() throws {
        let image=try Raster(width:160,height:160,pixels:(0..<25600).map { (78...82).contains($0%160) ? Pixel(1,1,1) : Pixel(0.1,0.1,0.1) })
        let guide=try CircularContours(image)
        let point=guide.confined(Point(60,80),Point(100,80))
        XCTAssertLessThan(point.x,78);XCTAssertGreaterThan(point.x,70)
    }
    func testChromaticBoundaryAndImageFrameConstrainLoops() throws {
        // Approximately equal luminance: the RGB barrier must still detect it.
        let guide=try CircularContours(boundary(Pixel(1,0,0),Pixel(0,0.2973,0)))
        XCTAssertLessThan(guide.confined(Point(70,80),Point(100,80)).x,80)
        let flat=try Raster(width:160,height:160,pixels:Array(repeating:Pixel(0.5,0.5,0.5),count:25600))
        let field=try CircularContours(flat)
        XCTAssertEqual(field.confined(Point(80,80),Point(105,105)),Point(105,105))
        let atFrame=field.confined(Point(8,80),Point(-30,80));XCTAssertGreaterThanOrEqual(atFrame.x,0)
    }
    func testProtectedGenerationIsDeterministicAndReducesHighlightSpill() throws {
        let photo=try boundary()
        var p=Parameters();p.style = .circular;p.color=false;p.toneWidth=false;p.matchTones=false;p.minRadius=80;p.maxRadius=80
        let protected=try Engine.generate(photo,parameters:p)
        XCTAssertEqual(protected.layers.map(\.points),try Engine.generate(photo,parameters:p).layers.map(\.points))
        p.protectEdges=false
        let unprotected=try Engine.generate(photo,parameters:p)
        func spill(_ d:Drawing)->Double {
            var length=0.0
            for layer in d.layers { for stroke in layer.strokes { for (a,b) in zip(stroke,stroke.dropFirst()) where (a.x+b.x)/2>82 { length+=a.distance(b) } } }
            return length
        }
        XCTAssertGreaterThan(spill(unprotected),1)
        XCTAssertLessThan(spill(protected),spill(unprotected)*0.2)
    }
}
