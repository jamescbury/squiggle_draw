import XCTest
@testable import SquiggleCore

final class PolyTests: XCTestCase {
    private func image(width: Int=96,height: Int=72) throws -> Raster {
        try Raster(width:width,height:height,pixels:(0..<width*height).map { i in Pixel(Double(i%width)/Double(width-1),Double(i/width)/Double(height-1),0.2) })
    }
    private func settings() -> Parameters { var p=Parameters();p.style = .poly;return p }
    private func area(_ vertices: [Point]) -> Double {
        let a=vertices[0],b=vertices[1],c=vertices[2]
        return ((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))/2
    }
    func testConformingMeshCoversCanvasWithFinitePositiveFaces() throws {
        let raster=try image(),drawing=try Engine.generate(raster,parameters:settings())
        let facets=drawing.layers[0].facets
        XCTAssertFalse(facets.isEmpty)
        XCTAssertLessThan(facets.count,5000)
        XCTAssertEqual(facets.reduce(0) { $0+area($1.vertices) },Double(raster.width*raster.height),accuracy:1e-6)
        var edgeCounts=[String:Int]()
        for face in facets {
            XCTAssertEqual(face.vertices.count,3);XCTAssertGreaterThan(area(face.vertices),0)
            XCTAssertTrue(face.vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...Double(raster.width)).contains($0.x) && (0...Double(raster.height)).contains($0.y) })
            XCTAssertTrue([face.color.r,face.color.g,face.color.b].allSatisfy { $0.isFinite && (0...1).contains($0) })
            for i in 0..<3 {
                let a=face.vertices[i],b=face.vertices[(i+1)%3]
                let sa="\(a.x),\(a.y)",sb="\(b.x),\(b.y)"
                let key=sa<sb ? sa+"/"+sb : sb+"/"+sa
                edgeCounts[key,default:0]+=1
                let boundary=(a.x==0 && b.x==0)||(a.x==Double(raster.width) && b.x==Double(raster.width))||(a.y==0 && b.y==0)||(a.y==Double(raster.height) && b.y==Double(raster.height))
                if boundary { XCTAssertEqual(edgeCounts[key],1) }
            }
        }
        XCTAssertTrue(edgeCounts.values.allSatisfy { $0==1 || $0==2 })
        // Every singly owned edge must lie on the canvas boundary: no cracks or holes.
        for face in facets { for i in 0..<3 {
            let a=face.vertices[i],b=face.vertices[(i+1)%3],sa="\(a.x),\(a.y)",sb="\(b.x),\(b.y)"
            let key=sa<sb ? sa+"/"+sb : sb+"/"+sa
            if edgeCounts[key]==1 { XCTAssertTrue((a.x==0 && b.x==0)||(a.x==Double(raster.width) && b.x==Double(raster.width))||(a.y==0 && b.y==0)||(a.y==Double(raster.height) && b.y==Double(raster.height))) }
        } }
    }
    func testReproducibleTopologyAndGrayscale() throws {
        let raster=try image();var p=settings();p.color=false
        let first=try Engine.generate(raster,parameters:p),second=try Engine.generate(raster,parameters:p)
        XCTAssertEqual(first.svg(inks:[.black]),second.svg(inks:[.black]))
        XCTAssertTrue(first.layers[0].facets.allSatisfy { $0.color.r == $0.color.g && $0.color.g == $0.color.b })
        XCTAssertTrue(first.layers[0].points.isEmpty);XCTAssertTrue(first.layers[0].strokes.isEmpty)
    }
    func testPhotoColorAndRelief() throws {
        var p=settings();p.relief=0
        let solid=try Raster(width:48,height:32,pixels:Array(repeating:Pixel(0.8,0.2,0.1),count:48*32))
        let flat=try Engine.generate(solid,parameters:p)
        for face in flat.layers[0].facets { XCTAssertEqual(face.color.r,0.8,accuracy:1e-12);XCTAssertEqual(face.color.g,0.2,accuracy:1e-12) }
        let raster=try image(),unlit=try Engine.generate(raster,parameters:p)
        p.relief=1
        let lit=try Engine.generate(raster,parameters:p)
        XCTAssertEqual(unlit.layers[0].centers,lit.layers[0].centers)
        XCTAssertTrue(zip(unlit.layers[0].facets,lit.layers[0].facets).contains { abs($0.0.color.r-$0.1.color.r)>0.005 })
    }
    func testDetailAndTinyExtremeAspectRatios() throws {
        let raster=try image();var p=settings();p.polyDetail=0
        let low=try Engine.generate(raster,parameters:p);p.polyDetail=1
        XCTAssertGreaterThan(try Engine.generate(raster,parameters:p).layers[0].facets.count,low.layers[0].facets.count)
        for (w,h) in [(2,2),(2,100),(100,2)] {
            let drawing=try Engine.generate(image(width:w,height:h),parameters:p)
            XCTAssertEqual(drawing.layers[0].facets.reduce(0) { $0+area($1.vertices) },Double(w*h),accuracy:1e-6)
        }
    }
    func testCancelledTaskStopsDuringMesh() async throws {
        let raster=try image(),p=settings()
        let task=Task { try Engine.generate(raster,parameters:p,progress: { stage in
            if stage.contains("Triangulating") { withUnsafeCurrentTask { $0?.cancel() } }
        }) }
        do { _=try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
