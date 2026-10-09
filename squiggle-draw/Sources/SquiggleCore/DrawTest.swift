import Foundation

public struct TestStroke:Sendable {
    public let ink:Ink
    public let color:Pixel
    public let fill:Pixel?
    public let widthFactor:Double
    public let continues:Bool
    public let points:[Point]
    public let distances:[Double]
    public var length:Double { distances.last ?? 0 }
    init(ink:Ink,color:Pixel,fill:Pixel?=nil,points:[Point],widthFactor:Double=1,continues:Bool=false) throws {
        self.ink=ink;self.color=color;self.fill=fill;self.points=points;self.widthFactor=widthFactor;self.continues=continues
        var cumulative=[0.0]
        for i in 1..<points.count {
            if i%2048==0 { try Task.checkCancellation() }
            cumulative.append(cumulative.last!+points[i-1].distance(points[i]))
        }
        distances=cumulative
    }
    public func point(at distance:Double)->Point {
        let d=max(0,min(length,distance)),i=upperBound(distances,d)
        if i==0 { return points[0] };if i>=points.count { return points[points.count-1] }
        let a=points[i-1],b=points[i],gap=distances[i]-distances[i-1],t=gap>0 ? (d-distances[i-1])/gap : 0
        return Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
    }
    public func portion(from:Double,to:Double)->[Point] {
        guard to>from else { return [] }
        let lo=max(0,min(length,from)),hi=max(lo,min(length,to))
        var result=[point(at:lo)]
        let start=upperBound(distances,lo),end=upperBound(distances,hi)
        if start<end { for i in start..<min(end,points.count) where distances[i]<hi { result.append(points[i]) } }
        result.append(point(at:hi));return result
    }
}
func upperBound(_ values:[Double],_ target:Double)->Int {
    var lo=0,hi=values.count
    while lo<hi { let mid=(lo+hi)/2;if values[mid]<=target { lo=mid+1 } else { hi=mid } }
    return lo
}
public struct DrawTestPlan:Sendable {
    public let id=UUID()
    public let width:Int,height:Int
    public let strokes:[TestStroke]
    public let ends:[Double]
    public var penLifts:Int { max(0,strokes.filter { !$0.continues }.count-1) }
    public var totalLength:Double { ends.last ?? 0 }
    public init(_ drawing:Drawing,inks:Set<Ink>) throws {
        width=drawing.width;height=drawing.height
        var output=[TestStroke](),ends=[Double](),total=0.0
        func add(_ ink:Ink,_ points:[Point],color:Pixel? = nil,fill:Pixel? = nil,widthFactor:Double=1,variable:Bool=false) throws {
            guard points.count>1 else { return }
            let hex=ink.hex.dropFirst(),rgb=UInt32(hex,radix:16)!
            let inkColor=Pixel(Double((rgb>>16)&255)/255,Double((rgb>>8)&255)/255,Double(rgb&255)/255)
            let rounded=points.map{Point(($0.x*1000).rounded()/1000,($0.y*1000).rounded()/1000)}
            let s=try TestStroke(ink:ink,color:color ?? inkColor,fill:fill,points:rounded,widthFactor:widthFactor,continues:variable && output.last?.ink == ink && output.last?.points.last == rounded.first)
            if s.length>1e-9 { output.append(s);total+=s.length;ends.append(total) }
        }
        for layer in drawing.drawingLayers(inks:drawing.parameters.style == .poly ? [.black] : inks) {
            for (i,stroke) in layer.strokes.enumerated() { if i%128==0 { try Task.checkCancellation() };try add(layer.ink,stroke,widthFactor:layer.widthFactor(at:i),variable:!layer.widthFactors.isEmpty) }
            for (i,dot) in layer.dots.enumerated() {
                if i%128==0 { try Task.checkCancellation() }
                let steps=max(16,min(256,Int(ceil(Double.pi*sqrt(dot.radius/0.03)))))
                let points=(0...steps).map { k in let t=2*Double.pi*Double(k)/Double(steps);return Point(dot.center.x+dot.radius*cos(t),dot.center.y+dot.radius*sin(t)) }
                try add(layer.ink,points)
            }
            for (i,facet) in layer.facets.enumerated() {
                if i%128==0 { try Task.checkCancellation() }
                if let first=facet.vertices.first {
                    let color=Pixel(Double(Int(facet.color.r*255))/255,Double(Int(facet.color.g*255))/255,Double(Int(facet.color.b*255))/255)
                    try add(layer.ink,facet.vertices+[first],color:drawing.parameters.polyWireframe ? nil : color,fill:drawing.parameters.polyWireframe ? nil : color)
                }
            }
        }
        strokes=output;self.ends=ends
    }
    public func fitScale(canvasWidth:Double=800,canvasHeight:Double=1100)->Double {
        min(max(1,canvasWidth-48)/Double(width),max(1,canvasHeight-48)/Double(height))
    }
    public func estimatedSeconds(speed:Double=70,canvasWidth:Double=800,canvasHeight:Double=1100)->Double {
        totalLength*fitScale(canvasWidth:canvasWidth,canvasHeight:canvasHeight)/max(1,speed)+Double(penLifts)*0.2
    }
    public func location(at distance:Double)->(index:Int,distance:Double) {
        let d=max(0,min(totalLength,distance)),index=upperBound(ends,d)
        return (index,index<ends.count ? d-(index==0 ? 0 : ends[index-1]) : 0)
    }
}
/// Mirrors squiggle-player/Playback.java: screen-distance speed, 0.2-second
/// pen lifts, and progress measured by ink length. Refresh/display latency is separate.
public struct DrawTestState:Sendable {
    public private(set) var stroke=0
    public private(set) var distance=0.0
    public private(set) var drawn=0.0
    public private(set) var liftRemaining=0.0
    public init() {}
    public func fraction(_ plan:DrawTestPlan)->Double { plan.totalLength==0 ? 1 : drawn/plan.totalLength }
    public func done(_ plan:DrawTestPlan)->Bool { stroke>=plan.strokes.count }
    public mutating func restore(_ fraction:Double,plan:DrawTestPlan) throws {
        guard fraction.isFinite,(0...1).contains(fraction) else { throw DrawError.invalidParameters }
        drawn=plan.totalLength*fraction
        let position=plan.location(at:drawn);stroke=position.index;distance=position.distance;liftRemaining=0
    }
    public mutating func advance(seconds:Double,speed:Double,plan:DrawTestPlan) throws {
        guard seconds.isFinite,speed.isFinite,seconds>=0,speed>0 else { throw DrawError.invalidParameters }
        var time=seconds
        while time>1e-9 && !done(plan) {
            if liftRemaining>0 { let used=min(time,liftRemaining);liftRemaining-=used;time-=used;continue }
            let remaining=plan.strokes[stroke].length-distance,step=min(remaining,time*speed)
            distance+=step;drawn+=step;time-=step/speed
            if distance>=plan.strokes[stroke].length-1e-7 {
                stroke+=1;distance=0;liftRemaining=done(plan) || plan.strokes[stroke].continues ? 0 : 0.2
            }
        }
        if done(plan) { drawn=plan.totalLength }
    }
    public func pen(_ plan:DrawTestPlan)->Point? {
        if plan.strokes.isEmpty { return nil }
        if liftRemaining>0 || done(plan) { return plan.strokes[min(stroke-1,plan.strokes.count-1)].points.last }
        return plan.strokes[stroke].point(at:distance)
    }
}

public struct SVGSize:Sendable {
    public let elements:Int,pathDataBytes:Int,fileBytes:Int
}
extension Drawing {
    /// Counts the exact UTF-8 size of this app's SVG without allocating a whole
    /// serialized drawing. Preparation remains cancellable on large artwork.
    public func svgSize(inks:Set<Ink>) throws ->SVGSize {
        func number(_ value:Double)->String {
            let n=Int((value*1000).rounded()),fraction=String(abs(n%1000))
            return "\(n/1000).\(String(repeating:"0",count:3-fraction.count))\(fraction)"
        }
        func numericBytes(_ value:Double)->Int {
            var integer=Int((value*1000).rounded())/1000
            var count=4 // decimal point and exactly three fraction digits
            if integer<0 { count+=1;integer = -integer }
            repeat { count+=1;integer/=10 } while integer>0
            return count
        }
        let included=svgLayers(inks:inks)
        var elements=1,pathBytes=0,fileBytes=0
        fileBytes="<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\">\n".utf8.count+"\n</svg>\n".utf8.count+max(0,included.count-1)
        for entry in included {
            let layer=entry.layer
            try Task.checkCancellation();elements+=1
            fileBytes+="<g id=\"\(entry.id)\">\n\n\n\n</g>".utf8.count
            var paths=0
            for (index,stroke) in layer.strokes.enumerated() where !stroke.isEmpty {
                paths+=1;elements+=1;fileBytes+=pathHeader(layer,index:index).utf8.count+3
                for (i,q) in stroke.enumerated() {
                    if i%2048==0 { try Task.checkCancellation() }
                    let n=2+numericBytes(q.x)+numericBytes(q.y) // M/L plus separator
                    pathBytes+=n;fileBytes+=n
                }
            }
            fileBytes+=max(0,paths-1)+max(0,layer.dots.count-1)+max(0,layer.facets.count-1)
            for (i,dot) in layer.dots.enumerated() {
                if i%512==0 { try Task.checkCancellation() }
                elements+=1
                fileBytes+="<circle cx=\"\(number(dot.center.x))\" cy=\"\(number(dot.center.y))\" r=\"\(number(dot.radius))\" fill=\"\(layer.ink.hex)\" stroke=\"\(layer.ink.hex)\" stroke-width=\"0\"/>".utf8.count
            }
            for (i,facet) in layer.facets.enumerated() {
                if i%512==0 { try Task.checkCancellation() }
                elements+=1
                let color=String(format:"#%02x%02x%02x",Int(facet.color.r*255),Int(facet.color.g*255),Int(facet.color.b*255))
                fileBytes+="<polygon points=\"\" fill=\"\(parameters.polyWireframe ? "none" : color)\" stroke=\"\(parameters.polyWireframe ? layer.ink.hex : color)\" stroke-width=\"\(number(parameters.polyWireframe ? parameters.penWidth : 0.25))\"/>".utf8.count
                fileBytes+=max(0,facet.vertices.count-1)
                for q in facet.vertices { fileBytes+=numericBytes(q.x)+1+numericBytes(q.y) }
            }
        }
        return SVGSize(elements:elements,pathDataBytes:pathBytes,fileBytes:fileBytes)
    }
}
