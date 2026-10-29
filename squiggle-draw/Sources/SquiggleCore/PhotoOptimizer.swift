import Foundation

public struct OptimizationResult: Sendable {
    public let parameters: Parameters
    public let summary: String
    public init(parameters: Parameters, summary: String) {
        self.parameters = parameters
        self.summary = summary
    }
}

extension Engine {
    /// Bounded, deterministic photo analysis. This does not render candidate drawings or
    /// promise a global optimum: coverage estimates guide a practical first set of controls.
    public static func optimize(_ image: Raster, parameters original: Parameters) throws -> OptimizationResult {
        try original.validate()
        try Task.checkCancellation()
        let photo = try PhotoMeasurements(image, color: original.color && !original.colorMode.usesPhotoColors)
        var p = original
        p.matchTones = true
        p.gamma = photo.suggestedGamma
        let scale = Double(max(image.width, image.height)) / 1600
        let texture = photo.texture

        switch p.style {
        case .formSketch:
            p.sketchDetail = bounded(0.45 + texture * 0.45, 0.4, 0.85)
            p.sketchShading = 1

        case .crossHatch:
            p.hatchSpacing = bounded(p.penWidth / max(0.01,scale) * 2.5, 1, 8)
            p.hatchCurve = bounded(5 - 2 * texture, 2, 5)
            p.hatchPasses = 8
            for _ in 0..<24 {
                try Task.checkCancellation()
                let gap=max(p.penWidth*1.35,p.hatchSpacing*scale)
                let dose = -log(max(0.02,1-p.penWidth/gap))
                var passes=0.0
                for histogram in photo.inkHistograms {
                    for bin in 1..<histogram.count {
                        let weight=pow(Double(bin)/255,1/p.gamma)
                        passes+=Double(histogram[bin])*min(8,hatchLevel(weight,dose,p))
                    }
                }
                let vertices=Double(image.width*image.height)*passes/(gap*2)*1.15
                if vertices<7000000 || p.hatchSpacing>=8 { break }
                p.hatchSpacing=min(8,p.hatchSpacing*1.12)
            }
        case .waves:
            p = try optimizeWaves(image, photo, p)
        case .circular, .flowing:
            // Broad circular gestures stay readable in shadows. Optional width
            // modulation supplies pigment without shrinking the loops.
            p.detail = bounded(0.42 + 0.4 * texture + 0.12 * photo.shadowFraction, 0.25, 0.92)
            p.minRadius = bounded(24 - 6 * texture, 18, 24)
            p.maxRadius = bounded(90 - 20 * texture, 70, 90)
            p.spacing = bounded(1.14 - 0.32 * photo.shadowFraction - 0.16 * texture, 0.68, 1.15)
            p.protectEdges = true
            // Thick physical pens need less packed geometry; radii remain canonical units.
            let relativePen = p.penWidth / max(0.05, scale)
            p.spacing = bounded(p.spacing * sqrt(max(0.5, relativePen / 0.65)), 0.6, 2.2)
            if p.style == .flowing {
                p.minRadius = bounded(8 - 3 * texture, 4, 8)
                p.maxRadius = bounded(58 - 22 * texture, 30, 58)
                p.curveStretch = bounded(2.8 - 0.7 * texture, 1.8, 2.8)
                p.curveWander = 0.75
            }
            p = try budgetCircles(image, photo, p, scale: scale)
        case .stipple, .singleLine:
            // Prefer fine dots for detailed photos, increasing diameter when the BOOX-friendly 18,000-dot count
            // budget cannot cover the photograph at its actual working dimensions.
            let area = Double(image.width * image.height)
            let desiredCoverage = -log(max(0.08, 1 - photo.meanInk))
            let preferredDiameter = max(0.6, (3.8 - 1.8 * texture) * scale)
            let budgetDiameter = sqrt(4 * area * desiredCoverage / (Double.pi * 18000))
            let targetDiameter = bounded(max(preferredDiameter, budgetDiameter), 0.3, 8)
            let count = area * desiredCoverage / (Double.pi * targetDiameter * targetDiameter / 4)
            p.stippleCount = Int(bounded(count.rounded(), 500, 18000))
            // The engine derives variable radii from each cell's ink mass. Dot size is
            // a dimensionless multiplier, with 2 preserving that calibrated ink mass.
            p.dotSize = 2
            p.relaxation = Int(bounded((18 + 18 * texture).rounded(), 4, 60))
            if p.style == .singleLine {
                // A route's tone comes from line length, not the disk area of stipples.
                // L ≈ 0.75√(count × area); invert coverage ≈ penWidth × L / area.
                let count=area*pow(photo.meanInk/max(0.075,0.75*p.penWidth),2)
                p.stippleCount=Int(bounded(count.rounded(),500,50000))
            }
        case .poly:
            p.polyAdaptation = bounded(0.8 + 0.15 * texture, 0.8, 0.95)
            p.polyDetail = bounded(0.32 + 0.52 * texture + 0.1 * photo.contrast, 0.2, 0.95)
            p.relief = bounded(0.24 + 0.22 * photo.contrast - 0.08 * texture, 0.12, 0.55)
        }
        try p.validate()
        try Task.checkCancellation()
        let tones = photo.contrast < 0.25 ? "a narrow tone range" : "a broad tone range"
        let detail = texture > 0.55 ? "strong fine detail" : (texture > 0.2 ? "moderate detail" : "mostly smooth areas")
        let color = p.colorMode == .fullColor ? "locally sampled photo colors" : p.colorMode == .photoPalette ? "a \(p.paletteSize)-color photo palette" : p.style == .poly ? (p.color ? "photo colors" : "grayscale tones") : (p.color ? "RGB + black coverage" : "black ink coverage")
        let summary = "Photo-based starting point for \(p.style.displayName): \(tones), \(detail), and \(color). Pen width and seed were kept; adjust the preview to taste."
        return OptimizationResult(parameters: p, summary: summary)
    }

    private static func bounded(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }

    private static func budgetCircles(_ image: Raster, _ photo: PhotoMeasurements, _ initial: Parameters, scale: Double) throws -> Parameters {
        var p = initial
        let area = Double(image.width * image.height)
        // Approximate regional-tour length per square pixel from local Poisson spacing.
        // Include all ink histograms: saturated yellow requires two dense tours.
        for _ in 0..<32 {
            try Task.checkCancellation()
            let base = max(1.8, (6 - 4 * (0.3*p.detail+0.7*p.sketchDetail)) * scale * sqrt(max(1, p.spacing)))
            var vertices = 0.0, samples = 0.0
            for histogram in photo.inkHistograms {
                for bin in histogram.indices where bin > 0 && histogram[bin] > 0 {
                    let weight = pow(Double(bin) / 255, 1 / p.gamma)
                    let tone = compensatedTone(1 - weight, parameters: p, scale: scale)
                    if 1 - tone < 0.012 { continue }
                    let localSpacing = base * (1 + 3.5 * tone)
                    let advance = max(0.025 * scale, (1.0 / 15 + tone * (4 - 1.0 / 15)) * p.spacing * scale)
                    vertices += area * histogram[bin] * (p.style == .circular ? 1.6 : 0.8) / (localSpacing * advance)
                    samples += area * histogram[bin] * 0.65 / (localSpacing * localSpacing)
                }
            }
            if vertices <= 1450000 && samples <= 52000 { break }
            if p.spacing < 3 { p.spacing = min(3, p.spacing * 1.18) }
            else if p.detail > 0 { p.detail = max(0, p.detail - 0.12) }
            else if p.sketchDetail > 0 { p.sketchDetail = max(0,p.sketchDetail-0.12) }
            else { break }
        }
        return p
    }

    private static func optimizeWaves(_ image: Raster, _ photo: PhotoMeasurements, _ initial: Parameters) throws -> Parameters {
        let aspectHeight = Double(image.height) / Double(max(image.width, image.height))
        let idealLines = bounded((145 + 110 * photo.texture) * aspectHeight, 35, 280)
        var lineChoices = Set([20, 40, 80, 120, 160, 200, 240, 280, 300])
        for factor in [0.8, 1.0, 1.2] {
            lineChoices.insert(Int(bounded((idealLines * factor).rounded(), 20, 300)))
        }
        var best = initial
        var bestScore = Double.infinity
        for lines in lineChoices.sorted() {
            try Task.checkCancellation()
            let rows = min(lines, max(1, image.height / 2))
            let gap = Double(image.height) / Double(rows)
            for height in [0.55, 0.7, 0.85, 1.0] {
                for frequency in [1.5, 2.0, 2.4, 2.8] {
                    // The same sine arc-length estimate used by the tone response model.
                    let slope = 2 * Double.pi * height * frequency / 0.8
                    var arcSum = 0.0
                    for sample in 0..<16 {
                        let angle = (Double(sample) + 0.5) * Double.pi / 16
                        let derivative = slope * cos(angle)
                        arcSum += sqrt(1 + derivative * derivative)
                    }
                    let arcRatio = arcSum / 16
                    let minimum = initial.penWidth / gap
                    let maximum = initial.penWidth * arcRatio / gap
                    var error = 0.0
                    for histogram in photo.inkHistograms {
                        for bin in histogram.indices where histogram[bin] > 0 {
                            let wanted = pow(Double(bin) / 255, 1 / initial.gamma)
                            // Mono has flat highlight rows; color lifts absent pigment.
                            let actual = initial.color && wanted < 0.012 ? 0 : bounded(wanted, minimum, maximum)
                            error += histogram[bin] * pow(actual - wanted, 2)
                        }
                    }
                    error /= Double(photo.inkHistograms.count)
                    let rowPenalty = 0.006 * pow((Double(lines) - idealLines) / idealLines, 2)
                    let texturePenalty = 0.0015 * pow(height - (0.62 + 0.22 * photo.texture), 2)
                    // Bound predicted output work across all present inks before recommending
                    // settings. This is conservative: real photos usually have slower waves.
                    let smallestStep = min(1, gap * 0.8 / (12 * frequency))
                    let vertexEstimate = Double(rows) * (ceil(Double(image.width - 1) / smallestStep) + 1) * Double(photo.activeInks)
                    let capPenalty = vertexEstimate > 3600000 ? 1 + (vertexEstimate - 3600000) / 3600000 : 0
                    let score = error + rowPenalty + texturePenalty + 0.0003 * frequency + capPenalty
                    if score < bestScore {
                        bestScore = score
                        best.lines = lines
                        best.waveHeight = height
                        best.waveFrequency = frequency
                    }
                }
            }
        }
        return best
    }
}

private struct PhotoMeasurements {
    let inkHistograms: [[Double]]
    let meanInk: Double
    let contrast: Double
    let shadowFraction: Double
    let texture: Double
    let activeInks: Int
    let suggestedGamma: Double

    init(_ image: Raster, color: Bool) throws {
        // At most approximately 65k sites, including extremely wide or tall images.
        let strideSize = max(1, Int(ceil(sqrt(Double(image.width * image.height) / 65536))))
        let inks: [Ink] = color ? Ink.allCases : [.black]
        var luminanceHistogram = [Double](repeating: 0, count: 256)
        var inkBins = inks.map { _ in [Double](repeating: 0, count: 256) }
        var sum = 0.0, inkSum = 0.0, shadows = 0.0, gradient = 0.0, strong = 0.0, count = 0.0
        for y in stride(from: 0, to: image.height, by: strideSize) {
            try Task.checkCancellation()
            for x in stride(from: 0, to: image.width, by: strideSize) {
                let pixel = image.pixels[y * image.width + x]
                let l = pixel.luminance
                luminanceHistogram[min(255, Int((l * 255).rounded()))] += 1
                sum += l
                if l < 0.3 { shadows += 1 }
                var siteInk = 0.0
                for (k, ink) in inks.enumerated() {
                    let weight = pixel.weight(ink, color: color)
                    inkBins[k][min(255, Int((weight * 255).rounded()))] += 1
                    siteInk += weight
                }
                inkSum += min(1, siteInk)
                let right = image.pixels[y * image.width + min(image.width - 1, x + strideSize)]
                let down = image.pixels[min(image.height - 1, y + strideSize) * image.width + x]
                let dx = Self.difference(pixel, right, color: color)
                let dy = Self.difference(pixel, down, color: color)
                let g = hypot(dx, dy)
                gradient += g
                if g > 0.08 { strong += 1 }
                count += 1
            }
        }
        let normalized = inkBins.map { bins in bins.map { $0 / count } }
        inkHistograms = normalized
        activeInks = max(1, normalized.filter { histogram in histogram.dropFirst(4).reduce(0, +) > 0.001 }.count)
        meanInk = inkSum / count
        shadowFraction = shadows / count
        func percentile(_ fraction: Double) -> Double {
            var accumulated = 0.0
            for (bin, n) in luminanceHistogram.enumerated() {
                accumulated += n
                if accumulated >= count * fraction { return Double(bin) / 255 }
            }
            return 1
        }
        contrast = percentile(0.95) - percentile(0.05)
        texture = min(1, 4 * gradient / count + 0.55 * strong / count)
        // Small adjustments for low-contrast exposures; the optimizer leaves photographs
        // with broad tonal information near their original gamma.
        let mean = sum / count
        suggestedGamma = contrast < 0.35 ? min(1.2, max(0.8, 1 + (mean - 0.5) * 0.35)) : 1
    }

    private static func difference(_ a: Pixel, _ b: Pixel, color: Bool) -> Double {
        if !color { return abs(a.luminance - b.luminance) }
        return max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b)))
    }
}
