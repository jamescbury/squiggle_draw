import CoreGraphics
import XCTest
@testable import SquiggleCore

final class PhotoCropTests:XCTestCase {
    private func image() throws ->Raster {
        try Raster(width:8,height:6,pixels:(0..<48).map {Pixel(Double($0%8)/8,Double($0/8)/6,0)})
    }
    func testCropPreservesPositionColorAndOrientation() throws {
        let source=try image(),crop=try source.cropped(to:CGRect(x:0.25,y:0.5,width:0.5,height:0.5))
        XCTAssertEqual(crop.width,4);XCTAssertEqual(crop.height,3)
        for y in 0..<3 {for x in 0..<4 {
            XCTAssertEqual(crop.pixels[y*4+x].r,source.pixels[(y+3)*8+x+2].r)
            XCTAssertEqual(crop.pixels[y*4+x].g,source.pixels[(y+3)*8+x+2].g)
        }}
        XCTAssertEqual(source.width,8);XCTAssertEqual(source.height,6)
    }
    func testFullPhotoAndOutOfBoundsSelection() throws {
        let source=try image(),crop=try source.cropped(to:CGRect(x:-1,y:-1,width:3,height:3))
        XCTAssertEqual(crop.width,8);XCTAssertEqual(crop.height,6)
        XCTAssertEqual(crop.pixels.map(\.r),source.pixels.map(\.r))
        XCTAssertEqual(crop.pixels.map(\.g),source.pixels.map(\.g))
    }
    func testInvalidAndTinySelectionsAreRejected() throws {
        let source=try image()
        for rect in [CGRect.zero,CGRect(x:2,y:2,width:1,height:1),CGRect(x:0,y:0,width:0.01,height:0.01),CGRect(x:Double.nan,y:0,width:1,height:1)] {
            XCTAssertThrowsError(try source.cropped(to:rect))
        }
    }
}
