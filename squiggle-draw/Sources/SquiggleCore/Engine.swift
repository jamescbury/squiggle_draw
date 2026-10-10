import Foundation

public struct Point: Sendable, Equatable {
    public var x: Double; public var y: Double
    public init(_ x: Double, _ y: Double) { self.x=x; self.y=y }
    public func distance(_ p: Point) -> Double { hypot(x-p.x,y-p.y) }
}
public enum Ink: String, CaseIterable, Sendable {
    case red, green, blue, black
    public var hex: String { switch self { case .red: "#dd3039"; case .green: "#218b4c"; case .blue: "#285bd7"; case .black: "#20221f" } }
    public var index: Int { Self.allCases.firstIndex(of:self)! }
}
public struct Pixel: Sendable, Equatable {
    public var hex:String { String(format:"#%02x%02x%02x",Int((max(0,min(1,r))*255).rounded()),Int((max(0,min(1,g))*255).rounded()),Int((max(0,min(1,b))*255).rounded())) }
    public var r: Double; public var g: Double; public var b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r=r; self.g=g; self.b=b }
    public var luminance: Double { 0.2126*r + 0.7152*g + 0.0722*b }
    public func weight(_ ink: Ink, color: Bool) -> Double {
        if !color { return ink == .black ? 1-luminance : 0 }
        switch ink {
        case .black: return 1-max(r,max(g,b))
        case .red: return max(0,r-min(g,b))
        case .green: return max(0,g-min(r,b))
        case .blue: return max(0,b-min(r,g))
        }
    }
}
public struct Raster: Sendable {
    public let width: Int; public let height: Int; public let pixels: [Pixel]
    public init(width: Int, height: Int, pixels: [Pixel]) throws {
        guard width>=2, height>=2, width<=2000, height<=2000, pixels.count==width*height,
              pixels.allSatisfy({ [$0.r,$0.g,$0.b].allSatisfy { $0.isFinite && $0>=0 && $0<=1 } }) else { throw DrawError.invalidImage }
        self.width=width; self.height=height; self.pixels=pixels
    }
    public func index(_ p: Point) -> Int { min(height-1,max(0,Int(p.y)))*width + min(width-1,max(0,Int(p.x))) }
}
public enum DrawingStyle: String, CaseIterable, Sendable {
    case formSketch = "Form sketch", waves = "Squiggle waves", circular = "Circular scribbles", flowing = "Flowing scribble", crossHatch = "Tonal cross-hatching", stipple = "Stipple dots", singleLine = "Single-line stipple", poly = "3D poly"
}
extension DrawingStyle {
    /// Curated techniques shown in the studio. Earlier experiments remain readable in code fixtures.
    public static var studioStyles:[DrawingStyle] { [.formSketch,.circular,.flowing,.crossHatch,.stipple,.poly] }
    public var displayName:String { self == .flowing ? "Continuous sketch" : rawValue }
}
public struct Parameters: Sendable, Equatable {
    public var style = DrawingStyle.waves
    public var lines = 180
    public var waveHeight = 0.7
    public var waveFrequency = 2.4
    public var colorMode = DrawingColorMode.rgb
    public var paletteSize = 24
    public var color:Bool {
        get { colorMode != .monochrome }
        set { colorMode = newValue ? .rgb : .monochrome }
    }
    public var alternateColors = false
    public var colorRounds = 20
    public var detail = 0.5
    private var minimumRadius:Double?
    private var maximumRadius:Double?
    public var minRadius:Double {
        get { minimumRadius ?? (style == .circular ? 24 : 3.2) }
        set { minimumRadius=newValue }
    }
    public var maxRadius:Double {
        get { maximumRadius ?? (style == .circular ? 90 : 53.3) }
        set { maximumRadius=newValue }
    }
    public var toneWidth = true
    public var shadowWidth = 4.0
    public var spacing = 1.0
    public var gamma = 1.0
    public var penWidth = 0.65
    public var protectEdges = true
    public var matchTones = true
    public var seed: UInt64 = 42
    public var stippleCount = 18000
    public var dotSize = 2.0
    public var relaxation = 24
    public var cornerRounding = 0.65
    public var curveStretch = 2.4
    public var curveWander = 0.7
    public var hatchSpacing = 2.2
    public var hatchCurve = 4.0
    public var hatchPasses = 8
    public var sketchDetail = 0.6
    public var sketchShading = 1.0
    public var sketchBackground = 0.0
    public var connectHatches = true
    public var hatchJoinReach = 8.0
    public var spreadAcrossCanvas = true
    public var polyDetail = 0.5
    public var polyAdaptation = 0.85
    public var relief = 0.35
    public var polyWireframe = false
    public init() {}
    public func validate() throws {
        guard [12,24].contains(paletteSize), (2...100).contains(colorRounds), sketchDetail.isFinite, (0...1).contains(sketchDetail), sketchShading.isFinite, (0.2...1.2).contains(sketchShading), sketchBackground.isFinite, (0...1).contains(sketchBackground), hatchJoinReach.isFinite, (1...40).contains(hatchJoinReach), hatchSpacing.isFinite, (1...8).contains(hatchSpacing), hatchCurve.isFinite, (0...20).contains(hatchCurve), (2...8).contains(hatchPasses), curveStretch.isFinite, (1...4).contains(curveStretch), curveWander.isFinite, (0...1).contains(curveWander), cornerRounding.isFinite, (0...1).contains(cornerRounding), (500...50000).contains(stippleCount), (4...60).contains(relaxation), dotSize.isFinite, (0.3...8).contains(dotSize),
              polyAdaptation.isFinite, (0...1).contains(polyAdaptation), polyDetail.isFinite, (0...1).contains(polyDetail), relief.isFinite, (0...1).contains(relief),
              (20...300).contains(lines), waveHeight.isFinite, (0.1...1.5).contains(waveHeight),
              waveFrequency.isFinite, (0.3...3).contains(waveFrequency), detail.isFinite, (0...1).contains(detail), minRadius.isFinite, maxRadius.isFinite,
              minRadius>=0.3, maxRadius>=minRadius, maxRadius<=160,
              shadowWidth.isFinite, (1...6).contains(shadowWidth),
              spacing.isFinite, (0.3...3).contains(spacing), gamma.isFinite, (0.3...3).contains(gamma),
              penWidth.isFinite, (0.1...5).contains(penWidth) else { throw DrawError.invalidParameters }
    }
}
public struct Dot: Sendable {
    public let center: Point; public let radius: Double
    public init(center: Point, radius: Double) { self.center=center; self.radius=radius }
}
public struct Facet: Sendable {
    public let vertices: [Point]; public let color: Pixel
    public init(vertices: [Point], color: Pixel) { self.vertices=vertices; self.color=color }
}
public struct Layer: Sendable {
    public let ink: Ink; public let centers: [Point]; public let points: [Point]
    public let strokes: [[Point]]
    /// Width multipliers for successive connected runs; an empty array means a uniform pen.
    public let strokeColors:[Pixel]
    public let dotColors:[Pixel]
    public func strokeColor(at index:Int)->Pixel? { strokeColors.isEmpty ? nil : strokeColors[index] }
    public func strokeHex(at index:Int)->String { strokeColor(at:index)?.hex ?? ink.hex }
    public func dotHex(at index:Int)->String { dotColors.isEmpty ? ink.hex : dotColors[index].hex }
    public let widthFactors: [Double]
    public func widthFactor(at index:Int)->Double { widthFactors.isEmpty ? 1 : widthFactors[index] }
    public let dots: [Dot]
    public let facets: [Facet]
    public var hasArtwork: Bool { !points.isEmpty || !dots.isEmpty || !facets.isEmpty }
    public init(ink: Ink, centers: [Point], points: [Point], strokes: [[Point]]? = nil, dots: [Dot] = [], facets: [Facet] = [], widthFactors:[Double] = [],strokeColors:[Pixel] = [],dotColors:[Pixel] = []) {
        self.ink=ink; self.centers=centers; self.points=points; self.strokes=strokes ?? [points]
        self.dots=dots; self.facets=facets
        precondition(widthFactors.isEmpty || (widthFactors.count == self.strokes.count && widthFactors.allSatisfy { $0.isFinite && (0.25...6).contains($0) }))
        precondition(strokeColors.isEmpty || strokeColors.count == self.strokes.count)
        precondition(dotColors.isEmpty || dotColors.count == dots.count)
        self.strokeColors=strokeColors;self.dotColors=dotColors
        self.widthFactors=widthFactors
    }
    public var length: Double { strokes.reduce(0) { sum,stroke in sum + zip(stroke,stroke.dropFirst()).reduce(0) { $0+$1.0.distance($1.1) } } }
}
public struct Drawing: Sendable {
    public let id = UUID()
    public let width: Int; public let height: Int; public let layers: [Layer]; public let parameters: Parameters
    public let colorPasses:[Layer]?
    public init(width:Int,height:Int,layers:[Layer],parameters:Parameters,colorPasses:[Layer]?=nil) {
        self.width=width;self.height=height;self.layers=layers;self.parameters=parameters;self.colorPasses=colorPasses
    }
    public var vertexCount: Int { layers.reduce(0) { $0+$1.points.count } }
    public var sampleCount: Int { layers.reduce(0) { $0+$1.centers.count } }
    public func svg(inks: Set<Ink>) -> String {
        let paths = svgLayers(inks:inks).map { entry -> String in
            let layer=entry.layer
            let paths=layer.strokes.enumerated().compactMap { index,stroke -> String? in
                guard let first=stroke.first else { return nil }
                let data="M\(Self.number(first.x)) \(Self.number(first.y))" + stroke.dropFirst().map { "L\(Self.number($0.x)) \(Self.number($0.y))" }.joined()
                return pathHeader(layer,index:index)+data+"\"/>"
            }.joined(separator:"\n")
            let dots=layer.dots.enumerated().map { i,dot in "<circle cx=\"\(Self.number(dot.center.x))\" cy=\"\(Self.number(dot.center.y))\" r=\"\(Self.number(dot.radius))\" fill=\"\(layer.dotHex(at:i))\" stroke=\"\(layer.dotHex(at:i))\" stroke-width=\"0\"/>" }.joined(separator:"\n")
            let facets=layer.facets.map { facet in
                let vertices=facet.vertices.map { "\(Self.number($0.x)),\(Self.number($0.y))" }.joined(separator:" ")
                let c=facet.color
                let color=String(format:"#%02x%02x%02x",Int(c.r*255),Int(c.g*255),Int(c.b*255))
                return "<polygon points=\"\(vertices)\" fill=\"\(parameters.polyWireframe ? "none" : color)\" stroke=\"\(parameters.polyWireframe ? layer.ink.hex : color)\" stroke-width=\"\(Self.number(parameters.polyWireframe ? parameters.penWidth : 0.25))\"/>"
            }.joined(separator:"\n")
            return "<g id=\"\(entry.id)\">\n\(paths)\n\(dots)\n\(facets)\n</g>"
        }.joined(separator:"\n")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\">\n\(paths)\n</svg>\n"
    }
    func pathHeader(_ layer:Layer,index:Int)->String {
        let factor=layer.widthFactor(at:index)
        let metadata=layer.widthFactors.isEmpty ? "" : " data-squiggle-width-scale=\"\(Self.number(factor))\""
        return "<path fill=\"none\" stroke=\"\(layer.strokeHex(at:index))\" stroke-width=\"\(Self.number(parameters.penWidth*factor))\"\(metadata) stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\""
    }
    private static func number(_ d: Double) -> String {
        let n=Int((d*1000).rounded()),fraction=String(abs(n%1000))
        return "\(n/1000).\(String(repeating:"0",count:3-fraction.count))\(fraction)"
    }
}
public enum DrawError: LocalizedError {
    case invalidImage, invalidParameters, tooDetailed
    public var errorDescription: String? {
        switch self {
        case .invalidImage: "Choose a readable image at least 2 pixels wide and tall."
        case .invalidParameters: "Check the loop size, spacing, and tone controls."
        case .tooDetailed: "This drawing is too dense. For Form sketch, reduce Shading depth or Feature detail. For waves, reduce Number of lines or Wave frequency. For circles or flowing scribbles, reduce Detail or increase Loop spacing / Stroke spacing. For cross-hatching, increase Hatch spacing or reduce Shading layers."
        }
    }
}
struct Random {
    var state: UInt64
    mutating func unit() -> Double {
        state &+= 0x9e3779b97f4a7c15
        var z=state; z=(z^(z>>30)) &* 0xbf58476d1ce4e5b9; z=(z^(z>>27)) &* 0x94d049bb133111eb
        return Double((z^(z>>31))>>11)/9007199254740992
    }
}
public enum Engine {
    public static func radius(tone: Double, distance: Double, parameters: Parameters) -> Double {
        let original=parameters.minRadius+tone*(parameters.maxRadius-parameters.minRadius)
        return parameters.protectEdges ? max(parameters.minRadius,min(original,distance)) : original
    }
    public static func generate(_ image: Raster, parameters p: Parameters, progress: @Sendable (String) -> Void = {_ in}) throws -> Drawing {
        if p.colorMode.usesPhotoColors {
            try p.validate()
            var geometry=p;geometry.color=false;geometry.alternateColors=false
            if p.style == .poly { geometry.color=true }
            let drawing=try generate(image,parameters:geometry,progress:progress)
            progress("Choosing colors from the photograph…")
            return try photoColored(drawing,image: image,parameters:p)
        }
        var drawing=try generateRaw(image,parameters:p,progress:progress)
        if p.spreadAcrossCanvas && p.style != .formSketch && p.style != .crossHatch { progress("Spreading strokes across the canvas…");drawing=try spreadOrder(drawing) }
        if p.style == .circular && p.toneWidth { progress("Shaping shadow widths…");drawing=try toneWidths(drawing,image) }
        if p.alternateColors && p.color { progress("Arranging alternating colors…") }
        return try alternateColorOrder(drawing)
    }
    static func generateRaw(_ image:Raster,parameters p:Parameters,progress:@Sendable(String)->Void) throws -> Drawing {
        try p.validate(); try Task.checkCancellation()
        if p.style == .formSketch { return try formSketch(image,p,progress) }
        if p.style == .crossHatch { return try crossHatch(image,p,progress) }
        if p.style == .waves { return try waves(image,p,progress) }
        if p.style == .stipple { return try stipple(image,p,progress) }
        if p.style == .singleLine { return try singleLine(image,p,progress) }
        if p.style == .poly { return try poly(image,p,progress) }
        progress("Studying tone and surface directions…")
        let analysis=try PhotoAnalysis(image)
        let prepared=try analysis.preparedSource(image,background:p.sketchBackground)
        let artworkImage=try shadedSource(prepared,depth:p.sketchShading)
        let scale=Double(max(image.width,image.height))/1600
        var adjusted=p; adjusted.detail=0.3*p.detail+0.7*p.sketchDetail; adjusted.minRadius *= scale; adjusted.maxRadius *= scale
        let edgeDistances=try edges(artworkImage)
        let contours=p.style == .circular && p.protectEdges ? try CircularContours(artworkImage) : nil
        progress("Grouping image regions…")
        let labels=try regions(artworkImage)
        var layers=[Layer](); var totalVertices=0; var totalSamples=0
        for ink in (p.color ? Ink.allCases : [.black]) {
            try Task.checkCancellation(); progress("Sampling \(ink.rawValue) ink…")
            let response=(0...255).map { 1-compensatedTone(1-Double($0)/255,parameters:p,scale:scale) }
            let weights=try inkWeights(artworkImage,ink,p,response)
            let physical=try inkWeights(artworkImage,ink,p,(0...255).map { Double($0)/255 })
            if weights.max() ?? 0 < 0.012 { continue }
            let samples=try sample(artworkImage,weights,adjusted,scale,ink)
            totalSamples += samples.count
            guard totalSamples<=60000 else { throw DrawError.tooDetailed }
            progress("Connecting \(ink.rawValue) strokes…")
            let regional=try trace(samples,labels,image)
            let tour=p.spreadAcrossCanvas ? try coverageTrace(samples,image,seed:p.seed &+ UInt64(ink.index)*7919) : regional
            var synthesis=adjusted
            if p.spreadAcrossCanvas {
                let baseline=try routeEffort(regional,image,weights,p,scale),sweeping=try routeEffort(tour,image,weights,p,scale)
                synthesis.spacing *= max(1,sweeping/max(1,baseline))
            }
            if p.style == .circular {
                // Check the actual route as well as the optimizer's histogram
                // estimate. Large saturated fields can need several full ink
                // passes; reserve geometry for every color before synthesis.
                let remaining=p.color ? 4-ink.index : 1
                let allowance=Double(2400000-totalVertices)/Double(remaining)*0.75
                let effort=try routeEffort(tour,image,weights,synthesis,scale)*2
                synthesis.spacing *= max(1,effort/max(1,allowance))
            }
            progress(p.style == .flowing ? "Drawing \(ink.rawValue) flowing curves…" : "Drawing \(ink.rawValue) loops…")
            let points = p.style == .flowing
                ? try flowingScribble(tour,image,weights,edgeDistances,synthesis,scale,4800000-totalVertices,ink,field:analysis)
                : try scribble(tour,image,weights,edgeDistances,synthesis,scale,2400000-totalVertices,contours:contours)
            totalVertices += points.count
            let gap=contours == nil ? max(adjusted.minRadius*4,p.penWidth*6) : max(8*scale,p.penWidth*4)
            let lifted=try liftAcrossPaper(points,image,physical,minimumGap:gap)
            let strokes=try lifted.map { try compactCurve($0,tolerance:min(0.06,p.penWidth*0.06)) }
            let visible=strokes.flatMap{$0}
            if !visible.isEmpty { layers.append(Layer(ink:ink,centers:tour,points:visible,strokes:strokes)) }
        }
        return Drawing(width:image.width,height:image.height,layers:layers,parameters:p)
    }
    /// Shading depth modifies source pigment once, before gamma and optical compensation.
    static func shadedSource(_ image:Raster,depth:Double) throws ->Raster {
        if depth==1 { return image }
        var pixels=[Pixel]();pixels.reserveCapacity(image.pixels.count)
        for (i,c) in image.pixels.enumerated() {
            if i%4096==0 { try Task.checkCancellation() }
            pixels.append(Pixel(max(0,1-(1-c.r)*depth),max(0,1-(1-c.g)*depth),max(0,1-(1-c.b)*depth)))
        }
        return try Raster(width:image.width,height:image.height,pixels:pixels)
    }
    /// Keep local overlaps and short highlight crossings, but lift over sustained blank paper.
    static func liftAcrossPaper(_ points:[Point],_ image:Raster,_ pigment:[Double],minimumGap:Double) throws ->[[Point]] {
        guard points.count>1 else { return [] }
        var strokes=[[Point]](),current=[Point](),blank=[Point](),blankLength=0.0,lifted=false
        for (i,q) in points.enumerated() {
            if i%512==0 { try Task.checkCancellation() }
            if bilinear(pigment,image,q)<0.025 {
                if let last=blank.last ?? current.last { blankLength+=last.distance(q) }
                if !lifted { blank.append(q) }
                if blankLength>minimumGap {
                    if current.count>1 { strokes.append(current) };current=[];blank=[];lifted=true
                }
            } else {
                if !lifted { current.append(contentsOf:blank) }
                blank=[];blankLength=0;lifted=false;current.append(q)
            }
        }
        if !lifted { current.append(contentsOf:blank) }
        if current.count>1 { strokes.append(current) }
        return strokes
    }
    // Independent optical-density estimate; no upstream learned lookup table is embedded.
    // Invert expected line coverage to compensate for the nonlinear response of loops on paper.
    public static func compensatedTone(_ luminance: Double, parameters p: Parameters, scale: Double) -> Double {
        if luminance>=0.995 { return 1 }
        let desired = -log(max(0.001,luminance))*1.4
        let base=max(1.8/scale,(6-4*p.detail)*sqrt(max(1,p.spacing)))
        func density(_ t: Double) -> Double {
            let r=p.minRadius+t*(p.maxRadius-p.minRadius)
            let advance=(1.0/15+t*(4-1.0/15))*p.spacing
            let width=p.style == .circular && p.toneWidth ? 0.35+(p.shadowWidth-0.35)*pow(1-luminance,1.6) : 1
            return (p.penWidth*width/scale)*2*Double.pi*r/(18*advance*base*(1+3.5*t))
        }
        var lo=0.0,hi=0.985
        for _ in 0..<16 {
            let t=(lo+hi)/2
            if density(t)>desired { lo=t } else { hi=t }
        }
        return (lo+hi)/2
    }
    // Row-based amplitude/frequency modulation, informed by Gregg Wygonik's SquiggleDraw.
    // Each row/run is its own contour: there is no ink connecting adjacent rows or absent pigment.
    static func waves(_ image: Raster,_ p: Parameters,_ progress: @Sendable (String) -> Void) throws -> Drawing {
        let rowCount=min(p.lines,max(1,image.height/2))
        let gap=Double(image.height)/Double(rowCount)
        var layers=[Layer](),totalVertices=0
        for ink in (p.color ? Ink.allCases : [.black]) {
            try Task.checkCancellation();progress("Drawing \(ink.rawValue) waves…")
            let response=(0...255).map { waveWeight(Double($0)/255,gap:gap,parameters:p) }
            let weights=try inkWeights(image,ink,p,response)
            if p.color && (weights.max() ?? 0)<0.012 { continue }
            var strokes=[[Point]](),centers=[Point]()
            let rowOffset=p.color ? Double(ink.index)*gap/8 : 0
            for row in 0..<rowCount {
                try Task.checkCancellation()
                let y=min(Double(image.height-1),(Double(row)+0.5)*gap+rowOffset)
                var x=0.0,phase=0.0,stroke=[Point]()
                while true {
                    if totalVertices%512==0 { try Task.checkCancellation() }
                    let weight=bilinear(weights,image,Point(x,y))
                    // White stays a flat row in mono mode, as in the original; absent color is lifted.
                    let active = !p.color || weight>=0.012
                    let amplitude=gap*p.waveHeight*weight
                    let py=min(Double(image.height-1),max(0,y+sin(phase)*amplitude))
                    if active {
                        guard totalVertices<6000000 else { throw DrawError.tooDetailed }
                        stroke.append(Point(x,py));totalVertices+=1
                    } else if !stroke.isEmpty {
                        if stroke.count>1 { strokes.append(stroke) };stroke.removeAll(keepingCapacity:true)
                    }
                    if x>=Double(image.width-1) { break }
                    // Bright regions flatten and slow down; shadows gain both height and frequency.
                    let wavelength=gap*(5-4.2*weight)/p.waveFrequency
                    let omega=2*Double.pi/wavelength
                    let dx=min(1.0,(Double.pi/6)/omega,Double(image.width-1)-x)
                    phase += omega*dx;x+=dx
                }
                if stroke.count>1 { strokes.append(stroke) }
                centers.append(Point(0,y));centers.append(Point(Double(image.width-1),y))
            }
            if !strokes.isEmpty { layers.append(Layer(ink:ink,centers:centers,points:strokes.flatMap{$0},strokes:strokes)) }
        }
        return Drawing(width:image.width,height:image.height,layers:layers,parameters:p)
    }
    static func inkWeights(_ image: Raster,_ ink: Ink,_ p: Parameters,_ response: [Double]) throws -> [Double] {
        var result=[Double]();result.reserveCapacity(image.pixels.count)
        for (i,pixel) in image.pixels.enumerated() {
            if i%4096==0 { try Task.checkCancellation() }
            let original=pixel.weight(ink,color:p.color)
            let weight=p.gamma == 1 ? original : pow(original,1/p.gamma)
            result.append(p.matchTones ? response[min(255,max(0,Int((weight*255).rounded())))] : weight)
        }
        return result
    }
    static func waveWeight(_ desired: Double,gap: Double,parameters p: Parameters) -> Double {
        if desired<0.012 { return 0 }
        func coverage(_ weight: Double) -> Double {
            let slope=2*Double.pi*p.waveHeight*weight*p.waveFrequency/(5-4.2*weight)
            var sum=0.0
            for i in 0..<16 { let angle=(Double(i)+0.5)*Double.pi/16;let dy=slope*cos(angle);sum+=sqrt(1+dy*dy) }
            let ratio=sum/16
            return p.penWidth*ratio/gap
        }
        var lo=0.0,hi=1.0
        for _ in 0..<16 { let mid=(lo+hi)/2;if coverage(mid)<desired { lo=mid } else { hi=mid } }
        return (lo+hi)/2
    }
    static func bilinear(_ field: [Double],_ image: Raster,_ q: Point) -> Double {
        let x0=max(0,min(image.width-1,Int(q.x))),y0=max(0,min(image.height-1,Int(q.y)))
        let x1=min(image.width-1,x0+1),y1=min(image.height-1,y0+1),tx=q.x-Double(x0),ty=q.y-Double(y0)
        return (field[y0*image.width+x0]*(1-tx)+field[y0*image.width+x1]*tx)*(1-ty)
            + (field[y1*image.width+x0]*(1-tx)+field[y1*image.width+x1]*tx)*ty
    }
    // Gradient edges and a two-pass chamfer distance field; intentionally a substitute for FDoG.
    static func edges(_ image: Raster) throws -> [Double] {
        let w=image.width,h=image.height,l=image.pixels.map(\.luminance)
        var d=[Double](repeating:Double(max(w,h)),count:w*h)
        for y in 1..<h-1 {
            if y%32==0 { try Task.checkCancellation() }
            for x in 1..<w-1 {
                let i=y*w+x
                let gx = -l[i-w-1]+l[i-w+1]-2*l[i-1]+2*l[i+1]-l[i+w-1]+l[i+w+1]
                let gy = -l[i-w-1]-2*l[i-w]-l[i-w+1]+l[i+w-1]+2*l[i+w]+l[i+w+1]
                if hypot(gx,gy)>0.42 { d[i]=0 }
            }
        }
        for y in 0..<h {
            if y%32==0 { try Task.checkCancellation() }
            for x in 0..<w {
                let i=y*w+x
                if x>0 { d[i]=min(d[i],d[i-1]+1) }
                if y>0 { d[i]=min(d[i],d[i-w]+1) }
                if x>0 && y>0 { d[i]=min(d[i],d[i-w-1]+sqrt(2)) }
                if x+1<w && y>0 { d[i]=min(d[i],d[i-w+1]+sqrt(2)) }
            }
        }
        for y in (0..<h).reversed() {
            if y%32==0 { try Task.checkCancellation() }
            for x in (0..<w).reversed() {
                let i=y*w+x
                if x+1<w { d[i]=min(d[i],d[i+1]+1) }
                if y+1<h { d[i]=min(d[i],d[i+w]+1) }
                if x+1<w && y+1<h { d[i]=min(d[i],d[i+w+1]+sqrt(2)) }
                if x>0 && y+1<h { d[i]=min(d[i],d[i+w-1]+sqrt(2)) }
            }
        }
        return d
    }
    struct Region { var x: Double; var y: Double; var l: Double }
    // Localized luminance/spatial k-means, following the SLIC grouping idea.
    static func regions(_ image: Raster) throws -> [Int] {
        let w=image.width,h=image.height,step=max(8,Int(sqrt(Double(w*h)/200)))
        var centers=[Region]()
        for y in stride(from:min(h-1,step/2),to:h,by:step) { for x in stride(from:min(w-1,step/2),to:w,by:step) { centers.append(Region(x:Double(x),y:Double(y),l:image.pixels[y*w+x].luminance)) } }
        var labels=[Int](repeating:0,count:w*h)
        for _ in 0..<4 {
            var distances=[Double](repeating:.infinity,count:w*h)
            for (id,c) in centers.enumerated() {
                try Task.checkCancellation()
                for y in max(0,Int(c.y)-step)...min(h-1,Int(c.y)+step) {
                    for x in max(0,Int(c.x)-step)...min(w-1,Int(c.x)+step) {
                        let i=y*w+x,dl=(image.pixels[i].luminance-c.l)*6
                        let ds=(pow(Double(x)-c.x,2)+pow(Double(y)-c.y,2))/Double(step*step)
                        let cost=dl*dl+ds
                        if cost<distances[i] { distances[i]=cost; labels[i]=id }
                    }
                }
            }
            var sx=[Double](repeating:0,count:centers.count),sy=sx,sl=sx,counts=sx
            for i in labels.indices { let k=labels[i]; sx[k]+=Double(i%w);sy[k]+=Double(i/w);sl[k]+=image.pixels[i].luminance;counts[k]+=1 }
            for k in centers.indices where counts[k]>0 { centers[k]=Region(x:sx[k]/counts[k],y:sy[k]/counts[k],l:sl[k]/counts[k]) }
        }
        return labels
    }
    static func sample(_ image: Raster,_ weights: [Double],_ p: Parameters,_ scale: Double,_ ink: Ink) throws -> [Point] {
        let base=max(1.8,(6-4*p.detail)*scale*sqrt(max(1,p.spacing))),cell=base/sqrt(2)
        let gw=Int(ceil(Double(image.width)/cell)),gh=Int(ceil(Double(image.height)/cell))
        var grid=[[Int]](repeating:[],count:gw*gh),points=[Point](),radii=[Double]()
        var rng=Random(state:p.seed &+ UInt64(ink.index)*773)
        let attempts=min(180000,max(3000,Int(Double(image.width*image.height)/(base*base)*12)))
        let search=Int(ceil(base*4.5/cell))
        for attempt in 0..<attempts {
            if attempt%512==0 { try Task.checkCancellation() }
            let q=Point(rng.unit()*Double(image.width-1),rng.unit()*Double(image.height-1)),weight=weights[image.index(q)]
            // Suppress absent ink rather than tinting the entire white paper.
            if weight<0.012 || rng.unit()>weight { continue }
            let radius=base*(1+3.5*(1-weight)),gx=min(gw-1,Int(q.x/cell)),gy=min(gh-1,Int(q.y/cell))
            var accepted=true
            outer: for y in max(0,gy-search)...min(gh-1,gy+search) { for x in max(0,gx-search)...min(gw-1,gx+search) {
                for k in grid[y*gw+x] { if q.distance(points[k])<max(radius,radii[k]) { accepted=false;break outer } }
            } }
            if accepted {
                guard points.count<60000 else { throw DrawError.tooDetailed }
                grid[gy*gw+gx].append(points.count);points.append(q);radii.append(radius)
            }
        }
        return points
    }
    static func trace(_ samples: [Point],_ labels: [Int],_ image: Raster) throws -> [Point] {
        if samples.count<2 { return samples }
        var groups=[Int:[Point]]()
        for q in samples { groups[labels[image.index(q)],default:[]].append(q) }
        var tours=[[Point]]()
        for id in groups.keys.sorted() {
            try Task.checkCancellation()
            var remaining=groups[id]!,tour=[remaining.removeFirst()]
            while !remaining.isEmpty {
                if remaining.count%32==0 { try Task.checkCancellation() }
                let last=tour.last!,next=remaining.indices.min { last.distance(remaining[$0])<last.distance(remaining[$1]) }!
                tour.append(remaining.remove(at:next))
            }
            if tour.count>3 {
                for _ in 0..<2 {
                    for i in 0..<tour.count-2 {
                        if i%16==0 { try Task.checkCancellation() }
                        for j in i+2..<min(tour.count,i+64) {
                            let a=tour[i],b=tour[i+1],c=tour[j],d=tour[(j+1)%tour.count]
                            if a.distance(c)+b.distance(d)+0.0001<a.distance(b)+c.distance(d) { tour[(i+1)...j].reverse() }
                        }
                    }
                }
            }
            tours.append(tour)
        }
        var merged=tours.removeFirst()
        // Greedily merge regional cycles by edge replacement. Candidate edges are spatially nearby.
        while !tours.isEmpty {
            try Task.checkCancellation()
            var best=Double.infinity,bestTour=0,ai=0,bj=0
            let anchor=merged.last!
            bestTour=tours.indices.min { a,b in
                tours[a][0].distance(anchor)<tours[b][0].distance(anchor)
            }!
            let tour=tours[bestTour]
            for j in tour.indices {
                if j%32==0 { try Task.checkCancellation() }
                let b=tour[j],bn=tour[(j+1)%tour.count]
                let i=merged.indices.min { merged[$0].distance(b)<merged[$1].distance(b) }!
                for candidate in [i,(i+merged.count-1)%merged.count] {
                    let a=merged[candidate],an=merged[(candidate+1)%merged.count]
                    let cost=a.distance(bn)+b.distance(an)-a.distance(an)-b.distance(bn)
                    if cost<best { best=cost;ai=candidate;bj=j }
                }
            }
            let b=tours.remove(at:bestTour)
            let rotated=(0..<b.count).map { b[(bj+1+$0)%b.count] }
            merged.insert(contentsOf:rotated,at:ai+1)
        }
        return merged
    }
    static func scribble(_ tour: [Point],_ image: Raster,_ weights: [Double],_ edges: [Double],_ p: Parameters,_ scale: Double,_ cap: Int,contours:CircularContours?=nil) throws -> [Point] {
        guard !tour.isEmpty else { return [] }
        var result=[Point](),theta=0.0,smoothRadius=p.minRadius
        var anchors=[Point]()
        var angle=contours?.tangent(at:tour[0]) ?? 0
        let angular=Double.pi/18
        let pairs=tour.count==1 ? [(tour[0],tour[0])] : Array(zip(tour,tour.dropFirst()+[tour[0]]))
        for (a,b) in pairs {
            try Task.checkCancellation()
            let distance=a.distance(b)
            var t=0.0
            repeat {
                if result.count%512==0 { try Task.checkCancellation() }
                guard result.count<cap else { throw DrawError.tooDetailed }
                let center=Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t),index=image.index(center),tone=1-bilinear(weights,image,center)
                let featureRadius=contours == nil ? radius(tone:tone,distance:edges[index],parameters:p) : p.minRadius+tone*(p.maxRadius-p.minRadius)
                smoothRadius += (featureRadius-smoothRadius)*0.12
                let frame=min(center.x,center.y,Double(image.width-1)-center.x,Double(image.height-1)-center.y)
                let r=min(smoothRadius,max(0.15*scale,frame))
                var point:Point
                if let contours {
                    var turn=(contours.tangent(at:center)-angle).truncatingRemainder(dividingBy:Double.pi)
                    if turn>Double.pi/2 { turn-=Double.pi };if turn < -Double.pi/2 { turn+=Double.pi }
                    angle+=turn*0.12
                    // Keep the long dimension broad; only the normal dimension
                    // narrows at a feature. These become curved ribbons, not
                    // tiny circles attempting to squeeze inside the boundary.
                    let normal=min(r,max(0.7*scale,edges[index]*0.75))
                    let u=r*cos(theta),v=normal*sin(theta)
                    point=contours.confined(center,Point(center.x+u*cos(angle)-v*sin(angle),center.y+u*sin(angle)+v*cos(angle)))
                } else { point=Point(center.x+r*cos(theta),center.y+r*sin(theta)) }
                result.append(Point(min(Double(image.width-1),max(0,point.x)),min(Double(image.height-1),max(0,point.y))))
                if contours != nil { anchors.append(center) }
                theta += angular
                let advance=min((1.0/15+tone*(4-1.0/15))*p.spacing*scale*0.5,r*angular*0.85)
                t += distance>0 ? max(0.025*scale,advance)/distance : 1.0/18
            } while t<1
        }
        if let contours,result.count>2 {
            // Round contact corners, then recheck each softened point against
            // its local boundary so smoothing cannot bleed into highlights.
            for _ in 0..<2 {
                var previous=result[0]
                for i in 1..<result.count-1 {
                    if i%512==0 { try Task.checkCancellation() }
                    let current=result[i],next=result[i+1]
                    let softened=Point((previous.x+2*current.x+next.x)/4,(previous.y+2*current.y+next.y)/4)
                    result[i]=contours.confined(anchors[i],softened)
                    previous=current
                }
            }
        }
        return result
    }
}
