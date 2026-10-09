import XCTest
@testable import SquiggleCore

final class DrawProgressTests:XCTestCase {
    func testOrderingNeverSplitsExistingStrokes() throws {
        let runs=[[Point(0,0),Point(300,0),Point(300,400)],[Point(0,400),Point(300,0)]]
        let layer=Layer(ink:.black,centers:[],points:runs.flatMap{$0},strokes:runs)
        let drawing=Drawing(width:301,height:401,layers:[layer],parameters:Parameters())
        let result=try Engine.spreadOrder(drawing).layers[0]
        XCTAssertEqual(result.strokes.count,2)
        for run in runs { XCTAssertTrue(result.strokes.contains(run)) }
        XCTAssertEqual(result.length,layer.length,accuracy:1e-8)
    }
    func testRandomRoutesStayContinuousAndVisitSeveralRegionsEarly() throws {
        let w=128,h=96,image=try Raster(width:w,height:h,pixels:Array(repeating:Pixel(0.5,0.5,0.5),count:w*h))
        for style in [DrawingStyle.circular,.flowing,.singleLine] {
            var p=Parameters();p.style=style;p.color=false;p.detail=0.1;p.stippleCount=500;p.relaxation=4
            let drawing=try Engine.generate(image,parameters:p),layer=drawing.layers[0]
            XCTAssertEqual(layer.strokes.count,1,style.rawValue)
            XCTAssertEqual(drawing.svg(inks:[.black]).components(separatedBy:"<path ").count-1,1)
            let firstPass=Array(layer.centers.prefix(max(1,layer.centers.count/4)))
            // Random gestures need broad early coverage, without imposing a sweep quota.
            let quadrants=Set(firstPass.map{($0.x<Double(w)/2 ? 0 : 1)+($0.y<Double(h)/2 ? 0 : 2)})
            XCTAssertGreaterThanOrEqual(quadrants.count,3,style.rawValue)
            XCTAssertTrue(layer.points.allSatisfy{$0.x.isFinite && $0.y.isFinite && $0.x>=0 && $0.x<Double(w) && $0.y>=0 && $0.y<Double(h)})
            p.spreadAcrossCanvas=false
            let local=try Engine.generate(image,parameters:p)
            XCTAssertNotEqual(layer.centers,local.layers[0].centers)
        }
    }
    func testFirstPassReachesWholeCanvasAndIsReproducible() throws {
        let points=(0..<256).map{Point(Double($0%16)*10+5,Double($0/16)*10+5)}
        let ordered=try Engine.spatialOrder(points,width:160,height:160,seed:42){$0}
        XCTAssertEqual(ordered,try Engine.spatialOrder(points,width:160,height:160,seed:42){$0})
        let first=Array(ordered.prefix(20))
        XCTAssertGreaterThan(first.map(\.x).max()!-first.map(\.x).min()!,100)
        XCTAssertGreaterThan(first.map(\.y).max()!-first.map(\.y).min()!,100)
        XCTAssertEqual(Set(ordered.map{"\($0.x),\($0.y)"}),Set(points.map{"\($0.x),\($0.y)"}))
    }
    func testEveryStyleUsesSharedOrderAndPreservesArtwork() throws {
        let image=try Raster(width:48,height:48,pixels:(0..<2304).map{i in let v=Double((i%48+i/48)%25)/40;return Pixel(v,v,v)})
        for style in DrawingStyle.allCases {
            var p=Parameters();p.style=style;p.color=false;p.connectHatches=false;p.lines=20;p.stippleCount=500;p.relaxation=4
            let raw=try Engine.generateRaw(image,parameters:p,progress:{_ in})
            let ordered=try Engine.spreadOrder(raw),actual=try Engine.generate(image,parameters:p)
            let expected=try style == .circular && p.toneWidth ? Engine.toneWidths(ordered,image) : ordered
            XCTAssertEqual(actual.svg(inks:[.black]),expected.svg(inks:[.black]),style.rawValue)
            let svg=actual.svg(inks:[.black]),size=try actual.svgSize(inks:[.black])
            XCTAssertEqual(size.fileBytes,svg.utf8.count,style.rawValue)
            XCTAssertEqual(size.elements,svg.components(separatedBy:"<").filter{!$0.hasPrefix("/") && !$0.hasPrefix("?") && !$0.isEmpty}.count)
            XCTAssertEqual(size.pathDataBytes,svg.components(separatedBy:" d=\"").dropFirst().reduce(0){$0+$1.prefix(while:{$0 != "\""}).utf8.count})
            XCTAssertEqual(actual.layers.reduce(0){$0+$1.length},raw.layers.reduce(0){$0+$1.length},accuracy:1e-6,style.rawValue)
            XCTAssertEqual(actual.layers.reduce(0){$0+$1.dots.count},raw.layers.reduce(0){$0+$1.dots.count})
            XCTAssertEqual(actual.layers.reduce(0){$0+$1.facets.count},raw.layers.reduce(0){$0+$1.facets.count})
            p.spreadAcrossCanvas=false
            let localRaw=try Engine.generateRaw(image,parameters:p,progress:{_ in})
            let local=try style == .circular && p.toneWidth ? Engine.toneWidths(localRaw,image) : localRaw
            XCTAssertEqual(try Engine.generate(image,parameters:p).svg(inks:[.black]),local.svg(inks:[.black]))
        }
    }
    private func plan() throws ->DrawTestPlan {
        let runs=[[Point(0,0),Point(10,0)],[Point(100,100),Point(100,110)]]
        let drawing=Drawing(width:120,height:120,layers:[Layer(ink:.black,centers:[],points:runs.flatMap{$0},strokes:runs)],parameters:Parameters())
        return try DrawTestPlan(drawing,inks:[.black])
    }
    func testPlaybackHasDistanceSpeedAndPenLiftPause() throws {
        let plan=try plan();var state=DrawTestState()
        try state.advance(seconds:0.5,speed:10,plan:plan)
        XCTAssertEqual(state.drawn,5,accuracy:1e-9);XCTAssertEqual(state.pen(plan),Point(5,0))
        try state.advance(seconds:0.6,speed:10,plan:plan)
        XCTAssertEqual(state.drawn,10,accuracy:1e-9);XCTAssertEqual(state.liftRemaining,0.1,accuracy:1e-9)
        XCTAssertEqual(state.pen(plan),Point(10,0))
        try state.advance(seconds:0.2,speed:10,plan:plan)
        XCTAssertEqual(state.drawn,11,accuracy:1e-9);XCTAssertEqual(state.pen(plan),Point(100,101))
        try state.advance(seconds:5,speed:10,plan:plan)
        XCTAssertTrue(state.done(plan));XCTAssertEqual(state.fraction(plan),1)
        XCTAssertEqual(plan.estimatedSeconds(speed:10,canvasWidth:168,canvasHeight:168),2.2,accuracy:1e-9)
    }
    func testSeekAndPartialSegmentsExcludePenUpTravel() throws {
        let plan=try plan();var state=DrawTestState()
        try state.restore(0.75,plan:plan)
        XCTAssertEqual(state.stroke,1);XCTAssertEqual(state.pen(plan),Point(100,105))
        XCTAssertEqual(plan.strokes[1].portion(from:2,to:7),[Point(100,102),Point(100,107)])
        try state.restore(0.5,plan:plan);XCTAssertEqual(state.pen(plan),Point(100,100))
        try state.restore(1,plan:plan);XCTAssertTrue(state.done(plan))
        XCTAssertThrowsError(try state.restore(.nan,plan:plan))
        XCTAssertThrowsError(try state.advance(seconds:1,speed:0,plan:plan))
    }
    func testInkFilteringAndClosedShapePlayback() throws {
        let red=Layer(ink:.red,centers:[],points:[],strokes:[],dots:[Dot(center:Point(5,5),radius:2)])
        let black=Layer(ink:.black,centers:[],points:[],strokes:[],facets:[Facet(vertices:[Point(0,0),Point(10,0),Point(0,10)],color:Pixel(1,0,0))])
        let drawing=Drawing(width:20,height:20,layers:[red,black],parameters:Parameters())
        let plan=try DrawTestPlan(drawing,inks:[.red])
        XCTAssertEqual(plan.strokes.count,1);XCTAssertEqual(plan.strokes[0].ink,.red)
        XCTAssertEqual(plan.strokes[0].color.r,221.0/255);XCTAssertEqual(plan.strokes[0].color.g,48.0/255)
        XCTAssertEqual(plan.strokes[0].length,4*Double.pi,accuracy:0.1)
        XCTAssertEqual(plan.strokes[0].points.first!.distance(plan.strokes[0].points.last!),0,accuracy:1e-9)
        let all=try DrawTestPlan(drawing,inks:[.red,.black])
        XCTAssertNil(all.strokes[0].fill)
        XCTAssertEqual(all.strokes[1].fill?.r,1)
        XCTAssertEqual(all.strokes[1].color.r,1);XCTAssertEqual(all.strokes[1].color.g,0)
        XCTAssertEqual(all.strokes.count,2);XCTAssertEqual(all.strokes[1].points.first,all.strokes[1].points.last)
    }
    func testPolyWireframeHasNoPlaybackFill() throws {
        var p=Parameters();p.style = .poly;p.polyWireframe=true
        let f=Facet(vertices:[Point(0,0),Point(10,0),Point(0,10)],color:Pixel(0.3,0.4,0.5))
        let drawing=Drawing(width:20,height:20,layers:[Layer(ink:.black,centers:[],points:[],strokes:[],facets:[f])],parameters:p)
        XCTAssertNil(try DrawTestPlan(drawing,inks:[]).strokes[0].fill)
        p.polyWireframe=false
        let filled=Drawing(width:20,height:20,layers:drawing.layers,parameters:p)
        XCTAssertEqual(try DrawTestPlan(filled,inks:[]).strokes[0].fill?.r,Double(Int(0.3*255))/255)
    }
    func testAdaptivePolyUsesSmallerFacetsInDetailedRegion() throws {
        let w=128,h=96,image=try Raster(width:w,height:h,pixels:(0..<w*h).map{i in
            let x=i%w,y=i/w,v=x<w/2 ? 0.5 : ((x/2+y/2)%2==0 ? 0.05 : 0.95)
            return Pixel(v,v,v)
        })
        var p=Parameters();p.style = .poly;p.polyAdaptation=1;p.polyDetail=0.5
        let facets=try Engine.generate(image,parameters:p).layers[0].facets
        func area(_ f:Facet)->Double { let a=f.vertices[0],b=f.vertices[1],c=f.vertices[2];return abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))/2 }
        let smooth=facets.filter{$0.vertices.allSatisfy{$0.x<56}},detailed=facets.filter{$0.vertices.allSatisfy{$0.x>72}}
        XCTAssertFalse(smooth.isEmpty);XCTAssertFalse(detailed.isEmpty)
        let smoothArea=smooth.reduce(0){$0+area($1)}/Double(smooth.count),detailedArea=detailed.reduce(0){$0+area($1)}/Double(detailed.count)
        XCTAssertGreaterThan(smoothArea,detailedArea*4)
        XCTAssertEqual(facets.reduce(0){$0+area($1)},Double(w*h),accuracy:1e-7)
        p.polyAdaptation = .nan;XCTAssertThrowsError(try p.validate())
    }
}
