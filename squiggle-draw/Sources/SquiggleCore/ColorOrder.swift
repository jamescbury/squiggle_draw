import Foundation

extension Drawing {
    /// One-pen exports retain the original unbroken paths, even when the
    /// combined drawing alternates colors. All consumers share this order.
    public func drawingLayers(inks:Set<Ink>)->[Layer] {
        let active=Set(layers.filter{inks.contains($0.ink) && $0.hasArtwork}.map(\.ink))
        return (active.count>1 ? colorPasses ?? layers : layers).filter{inks.contains($0.ink)}
    }
    func svgLayers(inks:Set<Ink>)->[(id:String,layer:Layer)] {
        var counts=[Ink:Int]()
        return drawingLayers(inks:inks).map { layer in
            counts[layer.ink,default:0]+=1
            let count=counts[layer.ink]!
            return (layer.ink.rawValue+(count==1 ? "" : "-\(count)"),layer)
        }
    }
}

extension Engine {
    /// Progress each ink by the same fraction per round. This retains each
    /// ink's internal artistic sequence and resumes a paused curve at its exact
    /// endpoint. Dots are indivisible marks; polygon photo colors are excluded.
    static func alternateColorOrder(_ drawing:Drawing) throws ->Drawing {
        let p=drawing.parameters
        guard p.alternateColors,p.color,p.style != .poly,
              Set(drawing.layers.filter(\.hasArtwork).map(\.ink)).count>1 else { return drawing }
        var batches=[[Layer]]()
        for ink in Ink.allCases {
            try Task.checkCancellation()
            let source=drawing.layers.filter{$0.ink==ink && $0.hasArtwork}
            guard !source.isEmpty else { continue }
            let runs=source.flatMap(\.strokes),dots=source.flatMap(\.dots)
            let variable=source.contains { !$0.widthFactors.isEmpty }
            let widths=source.flatMap { layer in layer.strokes.indices.map { layer.widthFactor(at:$0) } }
            var total=0.0
            for run in runs { for (i,pair) in zip(run,run.dropFirst()).enumerated() {
                if i%2048==0 { try Task.checkCancellation() };total+=pair.0.distance(pair.1)
            } }
            total+=dots.reduce(0){$0+2*Double.pi*$1.radius}
            guard total>1e-9 else { continue }
            let interval=total/Double(p.colorRounds)
            var strokes=Array(repeating:[[Point]](),count:p.colorRounds)
            var disks=Array(repeating:[Dot](),count:p.colorRounds)
            var factors=Array(repeating:[Double](),count:p.colorRounds)
            var round=0,covered=0.0
            for (runIndex,run) in runs.enumerated() {
                if runIndex%128==0 { try Task.checkCancellation() }
                guard let first=run.first else { continue }
                var part=[first],a=first
                for (i,b) in run.dropFirst().enumerated() {
                    if i%2048==0 { try Task.checkCancellation() }
                    var distance=a.distance(b)
                    while round<p.colorRounds-1 && covered+distance>=Double(round+1)*interval {
                        let remaining=max(0,Double(round+1)*interval-covered)
                        if distance<=1e-12 { break }
                        let t=min(1,remaining/distance)
                        let boundary=Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
                        if part.last != boundary { part.append(boundary) }
                        if part.count>1 { strokes[round].append(part);factors[round].append(widths[runIndex]) }
                        covered+=remaining;round+=1;part=[boundary];a=boundary;distance=a.distance(b)
                    }
                    if part.last != b { part.append(b) }
                    covered+=distance;a=b
                }
                if part.count>1 { strokes[round].append(part);factors[round].append(widths[runIndex]) }
            }
            for (i,dot) in dots.enumerated() {
                if i%512==0 { try Task.checkCancellation() }
                round=min(p.colorRounds-1,Int(covered/interval))
                disks[round].append(dot);covered+=2*Double.pi*dot.radius
            }
            batches.append((0..<p.colorRounds).map { index in
                Layer(ink:ink,centers:[],points:strokes[index].flatMap{$0},strokes:strokes[index],dots:disks[index],widthFactors:variable ? factors[index] : [])
            })
        }
        var passes=[Layer]()
        for round in 0..<p.colorRounds {
            try Task.checkCancellation()
            for ink in batches where ink[round].hasArtwork { passes.append(ink[round]) }
        }
        return Drawing(width:drawing.width,height:drawing.height,layers:drawing.layers,parameters:p,colorPasses:passes)
    }
}
