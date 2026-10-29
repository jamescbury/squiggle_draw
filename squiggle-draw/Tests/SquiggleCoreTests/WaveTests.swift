import XCTest
@testable import SquiggleCore
final class WaveTests: XCTestCase {
    func raster(_ value: Double) throws -> Raster { try Raster(width:80,height:64,pixels:Array(repeating:Pixel(value,value,value),count:5120)) }
    func testDefaultFullSizeDarkPhotoDoesNotHitCap() throws {
        let image=try Raster(width:1600,height:1200,pixels:Array(repeating:Pixel(0,0,0),count:1600*1200))
        let drawing=try Engine.generate(image,parameters:Parameters())
        XCTAssertGreaterThan(drawing.vertexCount,1000000)
        XCTAssertLessThan(drawing.vertexCount,4000000)
        XCTAssertEqual(drawing.layers.map(\.ink),[.black])
    }
    func testRowsAreSeparateAndNeverBacktrack() throws {
        var p=Parameters();p.color=false;p.spreadAcrossCanvas=false
        let drawing=try Engine.generate(raster(0.3),parameters:p)
        XCTAssertEqual(drawing.layers.count,1);XCTAssertEqual(drawing.layers[0].strokes.count,32)
        for stroke in drawing.layers[0].strokes {
            XCTAssertEqual(stroke.first?.x,0);XCTAssertEqual(stroke.last?.x,79)
            XCTAssertTrue(zip(stroke,stroke.dropFirst()).allSatisfy { $0.0.x<$0.1.x })
            XCTAssertTrue(stroke.allSatisfy { $0.y.isFinite && (0...63).contains($0.y) })
        }
        XCTAssertEqual(drawing.svg(inks:[.black]).components(separatedBy:"<path ").count-1,32)
    }
    func testDefaultWideTwoColorPhotoDoesNotHitCap() throws {
        let image=try Raster(width:1600,height:360,pixels:Array(repeating:Pixel(1,1,0),count:1600*360))
        let drawing=try Engine.generate(image,parameters:Parameters())
        XCTAssertEqual(drawing.layers.map(\.ink),[.red,.green])
        XCTAssertGreaterThan(drawing.vertexCount,4000000)
        XCTAssertLessThan(drawing.vertexCount,6000000)
    }
    func testHighlightsFlattenAndDarknessIncreasesInk() throws {
        var p=Parameters();p.color=false
        let white=try Engine.generate(raster(1),parameters:p),dark=try Engine.generate(raster(0.1),parameters:p)
        XCTAssertTrue(white.layers[0].strokes.allSatisfy { stroke in stroke.allSatisfy { $0.y==stroke[0].y } })
        XCTAssertGreaterThan(dark.layers[0].length,white.layers[0].length*2)
    }
    func testAbsentColorDoesNotConnectAcrossBlankPaper() throws {
        let image=try Raster(width:80,height:64,pixels:(0..<5120).map { i in (i%80<20 || i%80>60) ? Pixel(1,0,0) : Pixel(1,1,1) })
        let drawing=try Engine.generate(image,parameters:Parameters())
        XCTAssertEqual(drawing.layers.map(\.ink),[.red])
        XCTAssertTrue(drawing.layers[0].strokes.allSatisfy { $0.last!.x<21 || $0.first!.x>59 })
    }
    func testToneCompensationIsMonotoneAndAccountsForPenWidth() {
        var p=Parameters();p.style = .circular
        // Legacy fine-loop response, independent of the new broad-loop defaults.
        p.minRadius=3.2;p.maxRadius=53.3;p.toneWidth=false
        let tones=(0...10).map { Engine.compensatedTone(Double($0)/10,parameters:p,scale:1) }
        XCTAssertTrue(zip(tones,tones.dropFirst()).allSatisfy { $0.0<=$0.1 })
        XCTAssertLessThan(tones[5],0.5)
        let thin=Engine.compensatedTone(0.5,parameters:p,scale:1)
        p.penWidth=1.5
        XCTAssertGreaterThan(Engine.compensatedTone(0.5,parameters:p,scale:1),thin)
        XCTAssertEqual(tones.last,1)
    }
}
