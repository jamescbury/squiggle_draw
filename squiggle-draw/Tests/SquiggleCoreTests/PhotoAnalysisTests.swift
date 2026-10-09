import XCTest
@testable import SquiggleCore

final class PhotoAnalysisTests: XCTestCase {
    private func subject(width:Int=96,height:Int=80) throws ->Raster {
        try Raster(width:width,height:height,pixels:(0..<width*height).map { i in
            let x=i%width,y=i/width
            return x>width/4 && x<3*width/4 && y>height/4 && y<3*height/4 ? Pixel(0.15,0.25,0.35) : Pixel(0.7,0.7,0.7)
        })
    }
    func testAnalysisIsBoundedAndTransformsRoundTrip() throws {
        for (w,h) in [(2,2),(1600,2),(3,1400),(1000,800)] {
            let source=try Raster(width:w,height:h,pixels:Array(repeating:Pixel(0.4,0.4,0.4),count:w*h))
            let field=try PhotoAnalysis(source)
            XCTAssertLessThanOrEqual(max(field.image.width,field.image.height),720)
            for q in [Point(0,0),Point(Double(w-1),Double(h-1)),Point(Double(w-1)*0.43,Double(h-1)*0.27)] {
                let result=field.sourcePoint(field.fieldPoint(q))
                XCTAssertEqual(result.x,q.x,accuracy:1e-9);XCTAssertEqual(result.y,q.y,accuracy:1e-9)
            }
            XCTAssertTrue(field.featureEnergy.allSatisfy { $0.isFinite && $0>=0 })
        }
    }
    func testBackgroundControlRestoresPhotoAndProtectsInterior() throws {
        let source=try subject(),field=try PhotoAnalysis(source)
        let removed=try field.preparedSource(source,background:0)
        let restored=try field.preparedSource(source,background:1)
        let middle=source.width*(source.height/2)+source.width/2
        XCTAssertGreaterThan(removed.pixels[0].luminance,0.99)
        XCTAssertEqual(removed.pixels[middle].r,source.pixels[middle].r,accuracy:1e-12)
        XCTAssertEqual(restored.pixels.map(\.r),source.pixels.map(\.r))
        XCTAssertEqual(try field.preparedSource(source,background:0).pixels.map(\.b),removed.pixels.map(\.b))
        for p in [Pixel(1,1,1),Pixel(0,0,0),Pixel(1,1,0),Pixel(0.6,0.6,0.6)] {
            let flat=try Raster(width:40,height:32,pixels:Array(repeating:p,count:1280))
            XCTAssertEqual(try PhotoAnalysis(flat).preparedSource(flat,background:0).pixels.map(\.r),flat.pixels.map(\.r))
        }
    }
    func testChromaticBoundaryContributesFeatureEnergy() throws {
        // The same luminance, different channels: a grayscale-only edge misses it.
        let a=Pixel(0.9,0.2,0.2),b=Pixel(0.2,0.2+0.7*0.2126/0.7152,0.2)
        let image=try Raster(width:80,height:64,pixels:(0..<5120).map { $0%80<40 ? a:b })
        let field=try PhotoAnalysis(image)
        XCTAssertLessThan(field.edge.max() ?? 1,1e-10)
        XCTAssertGreaterThan(field.featureEnergy.max() ?? 0,0.1)
    }
    func testStippleUsesTrueMassAndBackgroundControl() throws {
        let image=try subject();var p=Parameters();p.style = .stipple;p.color=false;p.stippleCount=500;p.relaxation=4;p.dotSize=0.3;p.sketchBackground=1
        let first=try Engine.stipple(image,p,{_ in}),second=try Engine.stipple(image,p,{_ in})
        XCTAssertEqual(first.layers.flatMap(\.dots).map(\.center),second.layers.flatMap(\.dots).map(\.center))
        func area(_ d:Drawing)->Double { d.layers.flatMap(\.dots).reduce(0){$0+Double.pi*$1.radius*$1.radius} }
        let expected=image.pixels.reduce(0){$0+Double(Int(((1-$1.luminance)*255).rounded()))/255}*pow(p.dotSize/2,2)
        XCTAssertEqual(area(first),expected,accuracy:expected*0.015)
        p.sketchBackground=0
        let removed=try Engine.stipple(image,p,{_ in})
        XCTAssertLessThan(area(removed),area(first)*0.65)
        XCTAssertTrue(removed.layers.flatMap(\.dots).allSatisfy { $0.center.x>20 && $0.center.x<76 && $0.center.y>15 && $0.center.y<65 })
    }
    func testFeatureDensityAttractsDotsWithoutAddingInk() throws {
        let image=try Raster(width:128,height:96,pixels:(0..<12288).map { i in
            let x=i%128,y=i/128
            let tone=x<64 ? ((x/4+y/4)%2==0 ? 0.35:0.65):0.5
            return Pixel(tone,tone,tone)
        })
        var p=Parameters();p.style = .stipple;p.color=false;p.stippleCount=500;p.relaxation=12;p.dotSize=0.3;p.sketchBackground=1
        let dots=try Engine.stipple(image,p,{_ in}).layers.flatMap(\.dots)
        let featured=dots.filter{$0.center.x<64}.count,plain=dots.filter{$0.center.x>=64}.count
        XCTAssertGreaterThan(Double(featured),Double(plain)*1.15)
        let area=dots.reduce(0){$0+Double.pi*$1.radius*$1.radius}
        XCTAssertEqual(area,Double(image.width*image.height)*0.5*pow(p.dotSize/2,2),accuracy:3)
    }
    func testPreparationClampsFloatingPointMaskAtExtremeColors() throws {
        let image=try Raster(width:301,height:239,pixels:(0..<301*239).map { i in
            let x=i%301,y=i/301
            if x>90 && x<200 && y>70 && y<170 { return Pixel(0,0,0) }
            let tone=0.84+0.06*Double(x)/300
            return Pixel(tone,tone,tone)
        })
        for background in [0.0,0.01,0.6,1.0] {
            let prepared=try PhotoAnalysis(image).preparedSource(image,background:background)
            XCTAssertTrue(prepared.pixels.allSatisfy { [ $0.r,$0.g,$0.b ].allSatisfy { (0...1).contains($0) } })
        }
    }
    func testPolyUsesBackgroundAndKeepsMeshGeometryDeterministic() throws {
        let image=try subject();var p=Parameters();p.style = .poly;p.relief=0;p.polyDetail=0.15;p.sketchBackground=1
        let original=try Engine.poly(image,p,{_ in});p.sketchBackground=0
        let cleared=try Engine.poly(image,p,{_ in}),again=try Engine.poly(image,p,{_ in})
        XCTAssertEqual(cleared.layers[0].centers,again.layers[0].centers)
        let a=original.layers[0].facets.map{$0.color.luminance}.reduce(0,+)/Double(original.layers[0].facets.count)
        let b=cleared.layers[0].facets.map{$0.color.luminance}.reduce(0,+)/Double(cleared.layers[0].facets.count)
        XCTAssertGreaterThan(b,a)
        XCTAssertTrue(cleared.layers[0].facets.allSatisfy { $0.vertices.allSatisfy { (0...96).contains($0.x) && (0...80).contains($0.y) } })
    }
    func testCancellationAndBackgroundValidation() async throws {
        let source=try subject(),field=try PhotoAnalysis(source)
        XCTAssertThrowsError(try field.preparedSource(source,background:Double.nan))
        let task=Task { try Task.checkCancellation();return try PhotoAnalysis(source) }
        task.cancel()
        do { _=try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected \(error)") }
    }
}
