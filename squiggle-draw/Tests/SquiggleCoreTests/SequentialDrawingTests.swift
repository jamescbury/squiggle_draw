import XCTest
import CoreGraphics
@testable import SquiggleCore

final class SequentialDrawingTests:XCTestCase {
    private func art(_ paths:String,width:Int=100,height:Int=100)throws->SequenceArtwork {
        try SequenceArtwork(svg:Data("<svg width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\">\(paths)</svg>".utf8))
    }
    private func line(_ d:String,color:String="#000000",width:Int=3)->String {
        "<path fill=\"none\" stroke=\"\(color)\" stroke-width=\"\(width)\" d=\"\(d)\"/>"
    }
    private func pixels(_ image:CGImage?)->[UInt8] {
        guard let image,let data=image.dataProvider?.data else { return [] }
        return Array(UnsafeBufferPointer(start:CFDataGetBytePtr(data),count:CFDataGetLength(data)))
    }
    func testGeneratedRGBAndVariableWidthRoundTrip() throws {
        var p=Parameters();p.penWidth=1.7
        let drawing=Drawing(width:100,height:80,layers:[Layer(ink:.red,centers:[],points:[Point(2,3),Point(70,60)],widthFactors:[2]),Layer(ink:.black,centers:[],points:[Point(0,1),Point(5,9)])],parameters:p)
        let result=try SequenceArtwork(svg:Data(drawing.svg(inks:[.red,.black]).utf8))
        XCTAssertEqual(result.width,100);XCTAssertEqual(result.height,80);XCTAssertEqual(result.strokes.count,2)
        XCTAssertEqual(result.strokes[0].widthFactor,3.4,accuracy:0.001)
        XCTAssertEqual(result.strokes[0].points,[Point(2,3),Point(70,60)])
        XCTAssertGreaterThan(result.strokes[0].color.r,result.strokes[0].color.g)
    }
    func testEachStrokeScheduledExactlyOnceWithLengthTiming() throws {
        let a=try art((0..<30).map{line("M0 \($0*3)L100 \($0*3)")}.joined()),b=try art(line("M20 0L20 100"))
        let plan=SequenceTransition(source:a,target:b)
        XCTAssertEqual(plan.events.count,31)
        XCTAssertEqual(Set(plan.events.filter{!$0.incoming}.map(\.index)),Set(0..<30))
        XCTAssertEqual(plan.events.filter(\.incoming).map(\.index),[0])
        XCTAssertEqual(plan.events.first?.start,0)
        for (a,b) in zip(plan.events,plan.events.dropFirst()) { XCTAssertEqual(a.end,b.start) }
        let e=plan.events[0]
        XCTAssertEqual(e.fraction(at:e.start),0);XCTAssertEqual(e.fraction(at:e.end),1)
        XCTAssertEqual(e.fraction(at:(e.start+e.end)/2),0.5,accuracy:1e-9)
        XCTAssertNotEqual(plan.events.filter{!$0.incoming}.map(\.index),Array(0..<30))
    }
    func testExactRGBEndpointsAndLoopBoundaryAcrossAspectRatios() throws {
        let a=try art(line("M10 10L90 90",color:"#ff0000")+line("M10 90L90 10",color:"#000000"))
        let b=try art(line("M5 50L160 50",color:"#0000ff"),width:180,height:100)
        let ab=try SequenceRenderer(transition:SequenceTransition(source:a,target:b),width:160,height:90)
        let aa=try SequenceRenderer(transition:SequenceTransition(source:a,target:a),width:160,height:90)
        let ba=try SequenceRenderer(transition:SequenceTransition(source:b,target:a),width:160,height:90)
        XCTAssertEqual(pixels(ab.frame(at:0)),pixels(aa.frame(at:0)))
        XCTAssertEqual(pixels(ab.frame(at:1)),pixels(ba.frame(at:0)))
        XCTAssertEqual(pixels(ba.frame(at:1)),pixels(aa.frame(at:0)))
        XCTAssertNotEqual(pixels(ab.frame(at:0.5)),pixels(ab.frame(at:0)))
        XCTAssertEqual(pixels(ab.frame(at:0.5)),pixels(ab.frame(at:0.5)))
    }
    func testSharedInkNeverDisappearsIncludingCrossingStrokes() throws {
        let a=try art(line("M10 50L90 50")+line("M50 10L50 90",color:"#008800"))
        let renderer=try SequenceRenderer(transition:SequenceTransition(source:a,target:a),width:160,height:90)
        let original=pixels(renderer.frame(at:0))
        XCTAssertFalse(original.isEmpty)
        for f in [0.1,0.25,0.5,0.75,0.9,1] { XCTAssertEqual(pixels(renderer.frame(at:f)),original) }
    }
    func testErasureFollowsSourcePathWithoutCuttingCrossingPath() throws {
        let a=try art(line("M10 50L90 50")+line("M50 10L50 90")),b=try art(line("M5 5L10 5"))
        let plan=SequenceTransition(source:a,target:b)
        let firstErase=try XCTUnwrap(plan.events.first(where:{!$0.incoming}))
        let renderer=try SequenceRenderer(transition:plan,width:100,height:100)
        let half=pixels(renderer.frame(at:(firstErase.start+0.7*(firstErase.end-firstErase.start))/plan.length))
        // The remaining orthogonal stroke still passes through the crossing.
        let center=(50*100+50)*4
        XCTAssertLessThan(half[center],UInt8(30))
    }
    func testInvalidSVGIsRejectedAndFilledStylesAreReadable() throws {
        for svg in ["<!DOCTYPE svg SYSTEM 'file:///etc/passwd'><svg/>","<svg/>","<svg width=\"100\" height=\"100\" viewBox=\"0 0 100 100\"><image href=\"x\"/></svg>"] {
            XCTAssertThrowsError(try SequenceArtwork(svg:Data(svg.utf8)))
        }
        XCTAssertThrowsError(try art(line("M0 0Q5 5 10 10")))
        XCTAssertThrowsError(try art(line("M0 0Lnan 2")))
        let filled=try art("<circle cx=\"10\" cy=\"10\" r=\"2\" fill=\"#000000\" stroke=\"#000000\" stroke-width=\"0\"/><polygon points=\"20,20 30,20 30,30\" fill=\"#ff0000\" stroke=\"#ff0000\" stroke-width=\"0.25\"/>")
        XCTAssertEqual(filled.strokes.count,2);XCTAssertEqual(filled.strokes[0].widthFactor,4);XCTAssertNotNil(filled.strokes[1].fill)
    }
    func testPlaylistRoundTripKeepsDuplicatesOrderAndTiming() throws {
        let id=UUID(),items=[SequenceItem(sketchID:id,minutes:60),SequenceItem(sketchID:UUID(),minutes:15),SequenceItem(sketchID:id,minutes:90)]
        XCTAssertEqual(try JSONDecoder().decode([SequenceItem].self,from:JSONEncoder().encode(items)),items)
        XCTAssertNotEqual(items[0].id,items[2].id)
    }
}
