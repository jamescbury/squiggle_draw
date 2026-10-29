import XCTest
@testable import SquiggleCore

final class DrawingStyleQualityTests: XCTestCase {
    func testCurveCompactionBoundsDeviationAndPreservesClosedLoops() throws {
        let points=(0...2048).map { i in
            let angle=Double(i)*Double.pi/512
            return Point(50+20*cos(angle),50+12*sin(angle))
        }
        let compact=try Engine.compactCurve(points,tolerance:0.039)
        XCTAssertEqual(compact.first,points.first);XCTAssertEqual(compact.last,points.last)
        XCTAssertLessThan(compact.count,points.count/3)
        var lower=0
        for (a,b) in zip(compact,compact.dropFirst()) {
            let upper=points[(lower+1)...].firstIndex(of:b)!
            let dx=b.x-a.x,dy=b.y-a.y,length=dx*dx+dy*dy
            for q in points[lower...upper] {
                let t=length>0 ? min(1,max(0,((q.x-a.x)*dx+(q.y-a.y)*dy)/length)) : 0
                XCTAssertLessThanOrEqual(hypot(q.x-a.x-t*dx,q.y-a.y-t*dy),0.039000001)
            }
            lower=upper
        }
        XCTAssertEqual(lower,points.count-1)
    }
    private let styles:[DrawingStyle]=[.circular,.flowing,.crossHatch]
    private func isolatedShapes() throws ->Raster {
        try Raster(width:128,height:80,pixels:(0..<10240).map { i in
            let x=i%128,y=i/128
            let active=y>=12 && y<68 && ((x>=12 && x<42)||(x>=86 && x<116))
            return active ? Pixel(0.2,0.2,0.2) : Pixel(1,1,1)
        })
    }
    func testWhiteGapUsesPenLiftsWithoutJoiningSeparateSubjects() throws {
        let image=try isolatedShapes()
        for style in styles {
            var p=Parameters();p.style=style;p.color=false;p.connectHatches=false;p.sketchBackground=1
            let drawing=try Engine.generate(image,parameters:p)
            let strokes=drawing.layers.flatMap(\.strokes)
            XCTAssertGreaterThan(strokes.count,1,style.rawValue)
            for stroke in strokes {
                XCTAssertFalse(zip(stroke,stroke.dropFirst()).contains { a,b in (a.x<50 && b.x>78)||(b.x<50 && a.x>78) },style.rawValue)
            }
        }
    }
    func testBackgroundPaperPreservesSubjectAndRemovesBorderTone() throws {
        let image=try Raster(width:100,height:100,pixels:(0..<10000).map { i in
            let x=Double(i%100)-50,y=Double(i/100)-50
            let v=hypot(x,y)<25 ? 0.25 : 0.85
            return Pixel(v,v,v)
        })
        for style in styles {
            var p=Parameters();p.style=style;p.color=false;p.connectHatches=false;p.sketchBackground=0
            let clean=try Engine.generate(image,parameters:p)
            p.sketchBackground=1
            let restored=try Engine.generate(image,parameters:p)
            func outerLength(_ drawing:Drawing)->Double {
                drawing.layers.flatMap(\.strokes).reduce(0) { sum,line in
                    sum+zip(line,line.dropFirst()).reduce(0) { partial,pair in
                        let (a,b)=pair,mid=Point((a.x+b.x)/2,(a.y+b.y)/2)
                        return partial+(hypot(mid.x-50,mid.y-50)>35 ? a.distance(b) : 0)
                    }
                }
            }
            XCTAssertGreaterThan(clean.vertexCount,0,style.rawValue)
            XCTAssertLessThan(outerLength(clean),outerLength(restored)*0.5,style.rawValue)
        }
    }
    func testSharedDepthAndDeterminismKeepGeometryFinite() throws {
        let image=try Raster(width:96,height:80,pixels:(0..<7680).map { i in
            let value=0.2+0.7*Double(i%96)/95
            return Pixel(value,value,value)
        })
        for style in styles {
            var p=Parameters();p.style=style;p.color=false;p.sketchBackground=1;p.sketchShading=0.4
            let light=try Engine.generate(image,parameters:p)
            p.sketchShading=1
            let dark=try Engine.generate(image,parameters:p)
            XCTAssertGreaterThan(dark.layers.reduce(0){$0+$1.length},light.layers.reduce(0){$0+$1.length},style.rawValue)
            XCTAssertEqual(dark.svg(inks:[.black]),try Engine.generate(image,parameters:p).svg(inks:[.black]),style.rawValue)
            XCTAssertTrue(dark.layers.flatMap(\.points).allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...95).contains($0.x) && (0...79).contains($0.y) },style.rawValue)
        }
    }
    func testLiftRetainsShortCrossingsButRemovesSustainedBlankRuns() throws {
        let image=try Raster(width:20,height:2,pixels:(0..<40).map { i in let x=i%20;return Pixel(x>=7 && x<=12 ? 1 : 0,0,0) })
        let pigment=(0..<40).map { i in (7...12).contains(i%20) ? 0.0 : 1.0 }
        let points=(0..<20).map { Point(Double($0),0) }
        XCTAssertEqual(try Engine.liftAcrossPaper(points,image,pigment,minimumGap:2).count,2)
        XCTAssertEqual(try Engine.liftAcrossPaper(points,image,pigment,minimumGap:20).count,1)
    }
}
