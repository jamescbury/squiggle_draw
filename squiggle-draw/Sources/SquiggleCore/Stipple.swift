import Foundation

extension Engine {
    // A raster quadrature of density-weighted Lloyd relaxation. The nearest-site
    // query is exact; the density integral is bounded to 512 cells on either axis.
    // Features attract sites, while a separate true-ink integral sizes each disk.
    static func stipple(_ source: Raster, _ p: Parameters, _ progress: @Sendable (String) -> Void) throws -> Drawing {
        try p.validate()
        try Task.checkCancellation()
        let analysis = try PhotoAnalysis(source)
        let image = try analysis.preparedSource(source, background: p.sketchBackground)
        var attention = [Double](repeating: 1, count: image.pixels.count)
        for i in attention.indices {
            if i % 4096 == 0 { try Task.checkCancellation() }
            let q = analysis.fieldPoint(Point(Double(i % image.width), Double(i / image.width)))
            attention[i] += 3 * min(1, Engine.bilinear(analysis.featureEnergy, analysis.image, q) * 32)
        }
        let inks: [Ink] = p.color ? Ink.allCases : [.black]
        let gridScale = min(1, 512 / Double(max(image.width, image.height)))
        let gw = max(1, Int(ceil(Double(image.width) * gridScale)))
        let gh = max(1, Int(ceil(Double(image.height) * gridScale)))
        var fields = [StippleField]()
        let response = (0...255).map { pow(Double($0) / 255, 1 / p.gamma) }
        for ink in inks {
            progress("Measuring \(ink.rawValue) ink density…")
            var mass = [Double](repeating: 0, count: gw * gh)
            var sx = mass, sy = mass, density = mass
            for (i, pixel) in image.pixels.enumerated() {
                if i % 4096 == 0 { try Task.checkCancellation() }
                let raw = pixel.weight(ink, color: p.color)
                let weight = response[min(255, Int((raw * 255).rounded()))]
                if weight < 0.012 { continue }
                let x = i % image.width, y = i / image.width
                let gx = min(gw - 1, x * gw / image.width)
                let gy = min(gh - 1, y * gh / image.height)
                let k = gy * gw + gx
                mass[k] += weight
                let placement = weight * attention[i]
                density[k] += placement
                sx[k] += (Double(x) + 0.5) * placement
                sy[k] += (Double(y) + 0.5) * placement
            }
            var cells = [StippleCell]()
            for i in mass.indices where mass[i] > 0 {
                cells.append(StippleCell(point: Point(sx[i] / density[i], sy[i] / density[i]), mass: mass[i], density: density[i]))
            }
            if !cells.isEmpty { fields.append(StippleField(ink: ink, cells: cells)) }
        }
        let totalMass = fields.reduce(0) { $0 + $1.mass }
        guard totalMass > 0 else {
            return Drawing(width: image.width, height: image.height, layers: [], parameters: p)
        }
        // Largest-remainder apportionment keeps all ink passes within one budget.
        let shares = fields.map { Double(p.stippleCount) * $0.mass / totalMass }
        var counts = shares.map { Int($0.rounded(.down)) }
        let extras = p.stippleCount - counts.reduce(0, +)
        let order = shares.indices.sorted {
            let a = shares[$0] - Double(counts[$0]), b = shares[$1] - Double(counts[$1])
            return a == b ? $0 < $1 : a > b
        }
        for i in order.prefix(extras) { counts[i] += 1 }
        var layers = [Layer]()
        for (fieldIndex, field) in fields.enumerated() {
            try Task.checkCancellation()
            let count = min(counts[fieldIndex], field.cells.count)
            if count == 0 { continue }
            var rng = Random(state: p.seed &+ UInt64(field.ink.index) * 773)
            let cdf = field.cumulativeDensity
            let fieldMass = cdf.last!
            func select(_ target: Double) -> Point {
                var lo = 0, hi = cdf.count - 1
                while lo < hi {
                    let mid = (lo + hi) / 2
                    if cdf[mid] < target { lo = mid + 1 } else { hi = mid }
                }
                return field.cells[lo].point
            }
            var sites = [Point]()
            sites.reserveCapacity(count)
            let jitterX = Double(image.width) / Double(gw) * 0.8
            let jitterY = Double(image.height) / Double(gh) * 0.8
            for i in 0..<count {
                if i % 1024 == 0 { try Task.checkCancellation() }
                let q = select((Double(i) + rng.unit()) / Double(count) * fieldMass)
                sites.append(Point(min(Double(image.width) - 0.001, max(0.001, q.x + (rng.unit() - 0.5) * jitterX)),
                                   min(Double(image.height) - 0.001, max(0.001, q.y + (rng.unit() - 0.5) * jitterY))))
            }
            var finalMass = [Double](repeating: 0, count: count)
            // The final assignment measures cells at the final, relaxed locations.
            for iteration in 0...p.relaxation {
                try Task.checkCancellation()
                progress("Relaxing \(field.ink.rawValue) dots · \(min(iteration + 1, p.relaxation)) / \(p.relaxation)…")
                let tree = try StippleTree(sites)
                var mass = [Double](repeating: 0, count: count)
                var sx = mass, sy = mass, density = mass
                for (i, cell) in field.cells.enumerated() {
                    if i % 1024 == 0 { try Task.checkCancellation() }
                    let k = tree.nearest(cell.point)
                    mass[k] += cell.mass
                    density[k] += cell.density
                    sx[k] += cell.point.x * cell.density
                    sy[k] += cell.point.y * cell.density
                }
                if iteration == p.relaxation { finalMass = mass; break }
                for i in sites.indices {
                    if density[i] > 0 { sites[i] = Point(sx[i] / density[i], sy[i] / density[i]) }
                    else {
                        let q = select(rng.unit() * fieldMass)
                        sites[i] = Point(min(Double(image.width) - 0.001, max(0.001, q.x + (rng.unit() - 0.5) * jitterX)),
                                         min(Double(image.height) - 0.001, max(0.001, q.y + (rng.unit() - 0.5) * jitterY)))
                    }
                }
            }
            var dots = [Dot]()
            for i in sites.indices where finalMass[i] > 0 {
                if i % 1024 == 0 { try Task.checkCancellation() }
                let q = sites[i]
                // A cell centroid can fall inside a white hole in a concave region.
                // Lift that dot rather than putting pigment on blank paper.
                if image.pixels[image.index(q)].weight(field.ink, color: p.color) < 0.012 { continue }
                let desiredRadius = sqrt(finalMass[i] / Double.pi) * p.dotSize / 2
                let border = min(q.x, q.y, Double(image.width) - q.x, Double(image.height) - q.y)
                let radius = min(desiredRadius, border)
                if radius > 0 { dots.append(Dot(center: q, radius: radius)) }
            }
            if !dots.isEmpty {
                layers.append(Layer(ink: field.ink, centers: dots.map(\.center), points: [], strokes: [], dots: dots))
            }
        }
        return Drawing(width: image.width, height: image.height, layers: layers, parameters: p)
    }
}

private struct StippleCell {
    let point: Point
    let mass: Double
    let density: Double
}
private struct StippleField {
    let ink: Ink
    let cells: [StippleCell]
    var mass: Double { cells.reduce(0) { $0 + $1.mass } }
    var cumulativeDensity: [Double] {
        var total = 0.0
        return cells.map { total += $0.density; return total }
    }
}

// A balanced kd-tree with deterministic partition and squared-distance pruning.
// No approximate neighbor search or unbounded pixel-by-dot scan is used.
private struct StippleTree {
    private struct Node {
        let site: Int
        let axis: Int
        var left = -1
        var right = -1
    }
    private let sites: [Point]
    private var nodes = [Node]()
    private var root = -1
    init(_ sites: [Point]) throws {
        self.sites = sites
        nodes.reserveCapacity(sites.count)
        var ids = Array(sites.indices)
        root = try build(&ids, 0, ids.count, 0)
    }
    private mutating func build(_ ids: inout [Int], _ lower: Int, _ upper: Int, _ depth: Int) throws -> Int {
        if lower >= upper { return -1 }
        if nodes.count % 1024 == 0 { try Task.checkCancellation() }
        let middle = (lower + upper) / 2, axis = depth % 2
        func less(_ a: Int, _ b: Int) -> Bool {
            let x = axis == 0 ? sites[a].x : sites[a].y
            let y = axis == 0 ? sites[b].x : sites[b].y
            return x == y ? a < b : x < y
        }
        var lo = lower, hi = upper - 1
        while lo < hi {
            let pivot = ids[(lo + hi) / 2]
            ids.swapAt((lo + hi) / 2, hi)
            var boundary = lo
            for i in lo..<hi where less(ids[i], pivot) {
                ids.swapAt(i, boundary); boundary += 1
            }
            ids.swapAt(boundary, hi)
            if boundary == middle { break }
            if boundary < middle { lo = boundary + 1 } else { hi = boundary - 1 }
        }
        let index = nodes.count
        nodes.append(Node(site: ids[middle], axis: axis))
        let left = try build(&ids, lower, middle, depth + 1)
        let right = try build(&ids, middle + 1, upper, depth + 1)
        nodes[index].left = left; nodes[index].right = right
        return index
    }
    func nearest(_ q: Point) -> Int {
        var best = nodes[root].site, distance = Double.infinity
        func visit(_ index: Int) {
            if index < 0 { return }
            let node = nodes[index], p = sites[node.site]
            let dx = p.x - q.x, dy = p.y - q.y, d = dx * dx + dy * dy
            if d < distance || (d == distance && node.site < best) { best = node.site; distance = d }
            let delta = node.axis == 0 ? q.x - p.x : q.y - p.y
            visit(delta <= 0 ? node.left : node.right)
            if delta * delta <= distance { visit(delta <= 0 ? node.right : node.left) }
        }
        visit(root)
        return best
    }
}
