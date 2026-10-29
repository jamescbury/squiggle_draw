import XCTest
@testable import SquiggleCore

final class PhotoOptimizerTests: XCTestCase {
    private func image(width: Int = 120, height: Int = 100, textured: Bool = false) throws -> Raster {
        let pixels = (0..<(width * height)).map { index -> Pixel in
            let value = textured ? ((index % width + index / width) % 2 == 0 ? 0.1 : 0.9) : 0.5
            return Pixel(value, value, value)
        }
        return try Raster(width: width, height: height, pixels: pixels)
    }

    func testOptimizerPreservesPhysicalPenAndUserChoicesForEveryStyle() throws {
        let photo = try image(textured: true)
        for style in DrawingStyle.allCases {
            var p = Parameters()
            p.style = style; p.color = false; p.seed = 987; p.penWidth = 1.2; p.matchTones = false
            let result = try Engine.optimize(photo, parameters: p)
            XCTAssertEqual(result.parameters.style, style)
            XCTAssertEqual(result.parameters.color, false)
            XCTAssertEqual(result.parameters.seed, 987)
            XCTAssertEqual(result.parameters.penWidth, 1.2)
            XCTAssertTrue(result.parameters.matchTones)
            XCTAssertTrue(result.summary.contains("Photo-based starting point"))
            XCTAssertNoThrow(try result.parameters.validate())
        }
    }

    func testDeterministicAndSensitiveToPhotographicDetail() throws {
        var p = Parameters(); p.style = .circular
        let smooth = try image(), detailed = try image(textured: true)
        let a = try Engine.optimize(smooth, parameters: p)
        let b = try Engine.optimize(smooth, parameters: p)
        let c = try Engine.optimize(detailed, parameters: p)
        XCTAssertEqual(a.parameters, b.parameters)
        XCTAssertEqual(a.summary, b.summary)
        XCTAssertGreaterThan(c.parameters.detail, a.parameters.detail)
        XCTAssertLessThan(c.parameters.maxRadius, a.parameters.maxRadius)
    }

    func testWaveRowsRespondToAspectRatioAndAllStylesHandleTinyInputs() throws {
        var p = Parameters(); p.style = .waves
        let landscape = try Engine.optimize(image(width: 400, height: 80), parameters: p)
        let portrait = try Engine.optimize(image(width: 80, height: 400), parameters: p)
        XCTAssertLessThan(landscape.parameters.lines, portrait.parameters.lines)
        for style in DrawingStyle.allCases {
            p.style = style
            XCTAssertNoThrow(try Engine.optimize(image(width: 2, height: 2), parameters: p).parameters.validate())
        }
    }

    func testOptimizerCancellation() async throws {
        let photo = try image()
        let task = Task { try Engine.optimize(photo, parameters: Parameters()) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testStippleUsesNominalInkMassAndPolySummaryUsesPhotoColors() throws {
        let photo = try image(textured: true)
        var p = Parameters(); p.style = .stipple; p.dotSize = 5
        let stipple = try Engine.optimize(photo, parameters: p)
        XCTAssertEqual(stipple.parameters.dotSize, 2)
        p.style = .poly; p.color = true
        let color = try Engine.optimize(photo, parameters: p)
        XCTAssertTrue(color.summary.contains("photo colors"))
        XCTAssertFalse(color.summary.contains("RGB + black"))
        p.color = false
        XCTAssertTrue(try Engine.optimize(photo, parameters: p).summary.contains("grayscale tones"))
    }

    func testOptimizedFullResolutionCirclesFitGeometryBudget() throws {
        var p = Parameters(); p.style = .circular; p.color = true
        for pixel in [Pixel(0, 0, 0), Pixel(1, 1, 0)] {
            let photo = try Raster(width: 1600, height: 1200, pixels: Array(repeating: pixel, count: 1600 * 1200))
            let optimized = try Engine.optimize(photo, parameters: p)
            do {
                let drawing = try Engine.generate(photo, parameters: optimized.parameters)
                XCTAssertGreaterThan(drawing.vertexCount, 0)
                XCTAssertLessThanOrEqual(drawing.vertexCount, 2400000)
            } catch {
                let settings = optimized.parameters
                var sampleCounts = [Int]()
                for ink in Ink.allCases {
                    let weights = photo.pixels.map { pixel in
                        let weight = pow(pixel.weight(ink, color: true), 1 / settings.gamma)
                        return 1 - Engine.compensatedTone(1 - weight, parameters: settings, scale: 1)
                    }
                    if (weights.max() ?? 0) >= 0.012 {
                        sampleCounts.append(try Engine.sample(photo, weights, settings, 1, ink).count)
                    }
                }
                XCTFail("Generation failed for RGB \(pixel.r),\(pixel.g),\(pixel.b) with detail \(settings.detail), spacing \(settings.spacing), ink samples \(sampleCounts): \(error)")
            }
        }
    }
}
