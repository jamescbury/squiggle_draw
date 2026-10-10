import Foundation

public enum DrawingColorMode:String,CaseIterable,Sendable {
    case monochrome="Black ink",rgb="RGB + black",photoPalette="Photo palette",fullColor="Full color"
    public var usesPhotoColors:Bool { self == .photoPalette || self == .fullColor }
}
public enum DisplayMedium:String,CaseIterable,Sendable {
    case eInk="E-ink",eInkRGB="E-ink RGB",tv="TV",monitor="Monitor",plotter="Pen plotter"
    public var isEInk:Bool { self == .eInk || self == .eInkRGB }
    public var symbol:String { switch self { case .eInk,.eInkRGB:"ipad";case .tv:"tv";case .monitor:"desktopcomputer";case .plotter:"pencil.tip" } }
    public var detail:String { switch self {
        case .eInk:"Clear black strokes for monochrome e-ink screens."
        case .eInkRGB:"RGB + black strokes for color e-ink screens."
        case .tv:"Full-color artwork and slow transitions on a landscape display."
        case .monitor:"A photo-based palette for desktop artwork."
        case .plotter:"Fixed-width ink and separate passes for physical pens."
    } }
    public func applying(to original:Parameters)->Parameters {
        var p=original
        p.colorMode = self == .tv ? .fullColor : self == .monitor ? .photoPalette : self == .eInkRGB ? .rgb : .monochrome
        p.paletteSize=24;p.alternateColors=false
        p.toneWidth = self != .plotter
        p.penWidth = isEInk ? 0.85 : self == .plotter ? 0.65 : 0.7
        p.sketchDetail = self == .tv ? 0.8 : self == .monitor ? 0.7 : 0.6
        p.polyWireframe = self == .plotter
        return p
    }
}

extension Engine {
    static func photoColored(_ drawing:Drawing,image:Raster,parameters p:Parameters) throws ->Drawing {
        let palette=p.colorMode == .photoPalette ? try photoPalette(image,count:p.paletteSize) : []
        func color(_ q:Point)->Pixel {
            let pixel=image.pixels[image.index(Point(q.x*Double(image.width)/Double(drawing.width),q.y*Double(image.height)/Double(drawing.height)))]
            let pigment=photoPigment(pixel)
            return palette.min(by:{colorDistance($0,pigment)<colorDistance($1,pigment)}) ?? pigment
        }
        var layers=[Layer](),count=0
        let span=Double(max(drawing.width,drawing.height))/32
        for layer in drawing.layers {
            var runs=[[Point]](),colors=[Pixel](),widths=[Double]()
            for (i,stroke) in layer.strokes.enumerated() {
                if i%128==0 { try Task.checkCancellation() }
                guard let first=stroke.first,stroke.count>1 else { continue }
                var part=[first],distance=0.0,a=first
                func append() throws {
                    guard part.count>1,part.contains(where:{$0 != part[0]}) else { return }
                    count+=1;guard count<=200000 else { throw DrawError.tooDetailed }
                    let sample=part[part.count/2]
                    runs.append(part);colors.append(color(sample));widths.append(layer.widthFactor(at:i))
                }
                for (vertex,b) in stroke.dropFirst().enumerated() {
                    if vertex%2048==0 { try Task.checkCancellation() }
                    var gap=a.distance(b)
                    while distance+gap>=span && gap>1e-9 {
                        let step=span-distance,t=step/gap,boundary=Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
                        part.append(boundary);try append();part=[boundary];a=boundary;gap=a.distance(b);distance=0
                    }
                    part.append(b);distance+=gap;a=b
                }
                try append()
            }
            let facets=layer.facets.map { f in
                let c=p.colorMode == .photoPalette ? palette.min(by:{colorDistance($0,f.color)<colorDistance($1,f.color)}) ?? f.color : f.color
                return Facet(vertices:f.vertices,color:c)
            }
            layers.append(Layer(ink:.black,centers:layer.centers,points:runs.flatMap{$0},strokes:runs,dots:layer.dots,facets:facets,widthFactors:widths,strokeColors:colors,dotColors:layer.dots.map{color($0.center)}))
        }
        return Drawing(width:drawing.width,height:drawing.height,layers:layers,parameters:p)
    }
    private static func photoPigment(_ pixel:Pixel)->Pixel {
        // Darker pigment compensates for the white paper between tonal strokes.
        Pixel(pixel.r*0.72,pixel.g*0.72,pixel.b*0.72)
    }
    private static func colorDistance(_ a:Pixel,_ b:Pixel)->Double {
        let r=a.r-b.r,g=a.g-b.g,b=a.b-b.b
        return 0.3*r*r+0.59*g*g+0.11*b*b
    }
    static func photoPalette(_ image:Raster,count:Int) throws ->[Pixel] {
        let step=max(1,image.pixels.count/4096)
        let samples=stride(from:0,to:image.pixels.count,by:step).map{photoPigment(image.pixels[$0])}
        var centers=[samples[samples.count/2]],distances=Array(repeating:Double.infinity,count:samples.count)
        for _ in 1..<count {
            try Task.checkCancellation()
            let last=centers.last!
            for i in samples.indices { distances[i]=min(distances[i],colorDistance(samples[i],last)) }
            let index=distances.indices.max(by:{distances[$0]<distances[$1]})!
            centers.append(samples[index])
        }
        for _ in 0..<10 {
            try Task.checkCancellation()
            var totals=Array(repeating:Pixel(0,0,0),count:count),weights=Array(repeating:0.0,count:count)
            for sample in samples {
                let i=centers.indices.min(by:{colorDistance(centers[$0],sample)<colorDistance(centers[$1],sample)})!
                totals[i].r+=sample.r;totals[i].g+=sample.g;totals[i].b+=sample.b;weights[i]+=1
            }
            for i in centers.indices where weights[i]>0 { centers[i]=Pixel(totals[i].r/weights[i],totals[i].g/weights[i],totals[i].b/weights[i]) }
        }
        return centers
    }
}
