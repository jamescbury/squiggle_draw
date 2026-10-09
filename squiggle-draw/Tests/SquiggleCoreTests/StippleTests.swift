import XCTest
@testable import SquiggleCore

final class StippleTests: XCTestCase {
    func parameters() -> Parameters {
        var p = Parameters()
        p.style = .stipple
        p.stippleCount = 500
        p.relaxation = 4
        return p
    }
    func raster(_ pixel: Pixel, width: Int = 80, height: Int = 64) throws -> Raster {
        try Raster(width: width, height: height, pixels: Array(repeating: pixel, count: width * height))
    }
    func testWhiteIsBlankAndTinyDarkImageHasBoundedDisks() throws {
        let white = try Engine.generate(raster(Pixel(1, 1, 1)), parameters: parameters())
        XCTAssertTrue(white.layers.isEmpty)
        for (w, h) in [(2, 2), (2, 64), (64, 3), (80, 64)] {
            let drawing = try Engine.generate(raster(Pixel(0, 0, 0), width: w, height: h), parameters: parameters())
            XCTAssertEqual(drawing.layers.map(\.ink), [.black])
            let dots = drawing.layers[0].dots
            XCTAssertFalse(dots.isEmpty)
            XCTAssertLessThanOrEqual(dots.count, 500)
            for dot in dots {
                XCTAssertTrue(dot.center.x.isFinite && dot.center.y.isFinite && dot.radius.isFinite)
                XCTAssertGreaterThan(dot.radius, 0)
                XCTAssertGreaterThanOrEqual(dot.center.x - dot.radius, -1e-9)
                XCTAssertGreaterThanOrEqual(dot.center.y - dot.radius, -1e-9)
                XCTAssertLessThanOrEqual(dot.center.x + dot.radius, Double(w) + 1e-9)
                XCTAssertLessThanOrEqual(dot.center.y + dot.radius, Double(h) + 1e-9)
            }
            XCTAssertTrue(drawing.layers[0].points.isEmpty)
            XCTAssertTrue(drawing.layers[0].strokes.isEmpty)
        }
    }
    func testSeedIsRepeatableAndDarknessIncreasesDiskArea() throws {
        let image = try raster(Pixel(0.1, 0.1, 0.1))
        let a = try Engine.generate(image, parameters: parameters())
        let b = try Engine.generate(image, parameters: parameters())
        XCTAssertEqual(a.layers[0].dots.map(\.center), b.layers[0].dots.map(\.center))
        XCTAssertEqual(a.layers[0].dots.map(\.radius), b.layers[0].dots.map(\.radius))
        let light = try Engine.generate(raster(Pixel(0.8, 0.8, 0.8)), parameters: parameters())
        func area(_ drawing: Drawing) -> Double {
            drawing.layers.flatMap(\.dots).reduce(0) { $0 + Double.pi * $1.radius * $1.radius }
        }
        XCTAssertGreaterThan(area(a), 2 * area(light))
    }
    func testColorBudgetAndWhiteHole() throws {
        let image = try Raster(width: 80, height: 64, pixels: (0..<5120).map { i in
            let x = i % 80
            return x < 45 ? Pixel(1, 0, 0) : (x > 64 ? Pixel(0, 0, 1) : Pixel(1, 1, 1))
        })
        var p = parameters()
        // This fixture measures whole-source ink apportionment, including the border.
        p.sketchBackground = 1
        let drawing = try Engine.generate(image, parameters: p)
        XCTAssertEqual(drawing.layers.map(\.ink), [.red, .blue])
        XCTAssertLessThanOrEqual(drawing.layers.flatMap(\.dots).count, 500)
        XCTAssertGreaterThan(drawing.layers[0].dots.count, drawing.layers[1].dots.count * 2)
        XCTAssertTrue(drawing.layers[0].dots.allSatisfy { $0.center.x < 45 })
        XCTAssertTrue(drawing.layers[1].dots.allSatisfy { $0.center.x >= 65 })
    }
    func testMoreRelaxationReducesQuantizationError() throws {
        let image = try raster(Pixel(0, 0, 0), width: 48, height: 40)
        var p = parameters()
        let initial = try Engine.generate(image, parameters: p)
        p.relaxation = 12
        let relaxed = try Engine.generate(image, parameters: p)
        func error(_ drawing: Drawing) -> Double {
            let sites = drawing.layers[0].dots.map(\.center)
            var sum = 0.0
            for y in 0..<image.height { for x in 0..<image.width {
                let q = Point(Double(x) + 0.5, Double(y) + 0.5)
                sum += sites.map { let dx = $0.x - q.x, dy = $0.y - q.y; return dx * dx + dy * dy }.min()!
            } }
            return sum
        }
        XCTAssertLessThanOrEqual(error(relaxed), error(initial) + 1e-8)
    }
    func testCancellation() async throws {
        let image = try raster(Pixel(0, 0, 0), width: 300, height: 300)
        let p = parameters()
        let task = Task { try Engine.generate(image, parameters: p) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
    }
}
