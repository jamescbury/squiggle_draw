import Foundation
import CoreGraphics

public enum SequenceError: LocalizedError {
    case unsupported, empty
    public var errorDescription:String? {
        switch self {
        case .unsupported: "This sketch cannot be read. Save it again from the Draw tab."
        case .empty: "This sketch has no drawable strokes."
        }
    }
}

public struct SequenceArtwork:Sendable {
    public let width:Double,height:Double,strokes:[TestStroke]
    public init(svg:Data) throws {
        guard svg.count<=32*1024*1024,
              let text=String(data:svg,encoding:.utf8),!text.contains("<!") else { throw SequenceError.unsupported }
        let reader=SequenceSVGReader(),parser=XMLParser(data:svg)
        parser.shouldResolveExternalEntities=false;parser.delegate=reader
        guard parser.parse(),!reader.failed,reader.width>0,reader.height>0 else { throw SequenceError.unsupported }
        guard !reader.strokes.isEmpty else { throw SequenceError.empty }
        width=reader.width;height=reader.height;strokes=reader.strokes
    }
}

private final class SequenceSVGReader:NSObject,XMLParserDelegate {
    var width=0.0,height=0.0,strokes=[TestStroke](),failed=false,vertices=0
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes a:[String:String]) {
        do {
            try Task.checkCancellation()
            guard a["transform"]==nil else { throw SequenceError.unsupported }
            if name=="svg" {
                guard width==0,let w=Double(a["width"] ?? ""),let h=Double(a["height"] ?? ""),
                      w.isFinite,h.isFinite,(1...20000).contains(w),(1...20000).contains(h),
                      a["viewBox"]=="0 0 \(a["width"]!) \(a["height"]!)" else { throw SequenceError.unsupported }
                width=w;height=h;return
            }
            if name=="g" { return }
            guard ["path","circle","polygon"].contains(name),width>0,strokes.count<200000 else { throw SequenceError.unsupported }
            func number(_ key:String)throws->Double {
                guard let n=Double(a[key] ?? ""),n.isFinite,abs(n)<=100000 else { throw SequenceError.unsupported };return n
            }
            func color(_ value:String?) throws ->Pixel {
                guard let value,value.count==7,value.first=="#",let n=UInt32(value.dropFirst(),radix:16) else { throw SequenceError.unsupported }
                return Pixel(Double(n>>16&255)/255,Double(n>>8&255)/255,Double(n&255)/255)
            }
            var points=[Point](),fill:Pixel?,lineWidth=try number("stroke-width")
            guard lineWidth>=0 else { throw SequenceError.unsupported }
            let inkColor=try color(a["stroke"])
            if name=="path" {
                guard a["fill"]=="none",let d=a["d"] else { throw SequenceError.unsupported }
                let scan=Scanner(string:d)
                while !scan.isAtEnd {
                    guard scan.scanString(points.isEmpty ? "M" : "L") != nil,
                          let x=scan.scanDouble(),let y=scan.scanDouble(),x.isFinite,y.isFinite,abs(x)<=100000,abs(y)<=100000 else { throw SequenceError.unsupported }
                    guard vertices+points.count<2_000_000 else { throw SequenceError.unsupported }
                    points.append(Point(x,y))
                    if points.count%4096==0 { try Task.checkCancellation() }
                }
            } else if name=="circle" {
                let x=try number("cx"),y=try number("cy"),r=try number("r")
                guard r>0 else { throw SequenceError.unsupported }
                // A stipple is a short, round pen mark; its width retains the filled dot.
                lineWidth=2*r;points=[Point(x,y),Point(x+0.001,y)]
            } else {
                let values=(a["points"] ?? "").split(whereSeparator:{$0=="," || $0.isWhitespace})
                guard values.count>=6,values.count%2==0 else { throw SequenceError.unsupported }
                for i in stride(from:0,to:values.count,by:2) {
                    guard let x=Double(values[i]),let y=Double(values[i+1]),x.isFinite,y.isFinite,abs(x)<=100000,abs(y)<=100000 else { throw SequenceError.unsupported }
                    points.append(Point(x,y))
                }
                points.append(points[0]);if a["fill"] != "none" { fill=try color(a["fill"]) }
            }
            vertices+=points.count
            guard vertices<=2_000_000 else { throw SequenceError.unsupported }
            if points.count>1 {
                let s=try TestStroke(ink:.black,color:inkColor,fill:fill,points:points,widthFactor:lineWidth)
                if s.length>0 { strokes.append(s) }
            }
        } catch { failed=true;parser.abortParsing() }
    }
}

public struct SequenceEvent:Sendable {
    public let incoming:Bool,index:Int,start:Double,end:Double
    public func fraction(at position:Double)->Double { max(0,min(1,(position-start)/(end-start))) }
}

public struct SequenceTransition:Sendable {
    public let source:SequenceArtwork,target:SequenceArtwork,events:[SequenceEvent]
    public var length:Double { events.last?.end ?? 1 }
    public init(source:SequenceArtwork,target:SequenceArtwork,seed:UInt64=1931) {
        self.source=source;self.target=target
        struct Candidate { let incoming:Bool,index:Int,center:Point,cost:Double }
        var remaining=[Candidate]()
        for (incoming,art) in [(false,source),(true,target)] {
            let scale=min(1200/art.width,675/art.height)
            for (i,s) in art.strokes.enumerated() {
                let p=s.point(at:s.length/2)
                remaining.append(Candidate(incoming:incoming,index:i,center:Point((p.x-art.width/2)*scale,(p.y-art.height/2)*scale),cost:max(12,s.length*scale)))
            }
        }
        var random=Random(state:seed),output=[SequenceEvent](),position=0.0,focus=Point(0,0)
        while !remaining.isEmpty {
            var selected=min(remaining.count-1,Int(random.unit()*Double(remaining.count)))
            if output.count%7 != 0 {
                for _ in 0..<36 {
                    let j=min(remaining.count-1,Int(random.unit()*Double(remaining.count)))
                    if remaining[j].center.distance(focus)<remaining[selected].center.distance(focus) { selected=j }
                }
            }
            let c=remaining[selected];remaining.swapAt(selected,remaining.count-1);remaining.removeLast()
            output.append(SequenceEvent(incoming:c.incoming,index:c.index,start:position,end:position+c.cost))
            position+=c.cost;focus=c.center
        }
        events=output
    }
}

public struct SequenceItem:Codable,Identifiable,Equatable,Sendable {
    public let id:UUID
    public let sketchID:UUID
    public var minutes:Double
    public init(sketchID:UUID,minutes:Double=60) { id=UUID();self.sketchID=sketchID;self.minutes=minutes }
}

/// All strokes remain stationary. Removing one stroke never cuts its neighbours.
/// The component-wise common ink remains while the two differences are drawn/erased.
public final class SequenceRenderer {
    public let transition:SequenceTransition
    public let width:Int,height:Int
    private let sourcePaths:[CGPath],targetPaths:[CGPath]
    private let sourceFull:[UInt8],targetFull:[UInt8]
    private let old:CGContext,new:CGContext,output:CGContext
    public init(transition:SequenceTransition,width:Int=1280,height:Int=720) throws {
        self.transition=transition;self.width=width;self.height=height
        func context() throws ->CGContext {
            guard width>0,height>0,width<=4096,height<=4096,let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw SequenceError.unsupported };return c
        }
        old=try context();new=try context();output=try context()
        sourcePaths=transition.source.strokes.map{Self.path($0.points)}
        targetPaths=transition.target.strokes.map{Self.path($0.points)}
        Self.paint(transition.source,paths:sourcePaths,progress:[:],incoming:false,in:old,width:width,height:height)
        Self.paint(transition.target,paths:targetPaths,progress:[:],incoming:false,in:new,width:width,height:height)
        sourceFull=Array(UnsafeBufferPointer(start:old.data!.assumingMemoryBound(to:UInt8.self),count:width*height*4))
        targetFull=Array(UnsafeBufferPointer(start:new.data!.assumingMemoryBound(to:UInt8.self),count:width*height*4))
    }
    public func frame(at fraction:Double)->CGImage? {
        let t=fraction.isFinite ? max(0,min(1,fraction)) : 0,position=t*transition.length
        var erased=[Int:Double](),drawn=[Int:Double]()
        for event in transition.events {
            if event.start>=position { break }
            let f=event.fraction(at:position)
            if event.incoming { drawn[event.index]=f } else { erased[event.index]=f }
        }
        Self.paint(transition.source,paths:sourcePaths,progress:erased,incoming:false,in:old,width:width,height:height)
        Self.paint(transition.target,paths:targetPaths,progress:drawn,incoming:true,in:new,width:width,height:height)
        let a=old.data!.assumingMemoryBound(to:UInt8.self),b=new.data!.assumingMemoryBound(to:UInt8.self),out=output.data!.assumingMemoryBound(to:UInt8.self)
        for i in stride(from:0,to:width*height*4,by:4) {
            for channel in 0..<3 {
                let j=i+channel,sa=255-Int(sourceFull[j]),sb=255-Int(targetFull[j])
                let ink=min(sa,sb)+max(0,min(sa,255-Int(a[j]))-sb)+max(0,min(sb,255-Int(b[j]))-sa)
                out[j]=UInt8(255-ink)
            }
            out[i+3]=255
        }
        return output.makeImage()
    }
    private static func path(_ points:[Point])->CGPath {
        let p=CGMutablePath()
        if let q=points.first { p.move(to:CGPoint(x:q.x,y:q.y));for q in points.dropFirst() { p.addLine(to:CGPoint(x:q.x,y:q.y)) } }
        return p
    }
    private static func paint(_ art:SequenceArtwork,paths:[CGPath],progress:[Int:Double],incoming:Bool,in c:CGContext,width:Int,height:Int) {
        c.setFillColor(CGColor(gray:1,alpha:1));c.fill(CGRect(x:0,y:0,width:width,height:height));c.saveGState()
        let scale=min(Double(width)/art.width,Double(height)/art.height)*0.94
        c.translateBy(x:Double(width)/2,y:Double(height)/2);c.scaleBy(x:scale,y: -scale);c.translateBy(x: -art.width/2,y: -art.height/2)
        c.setLineCap(.round);c.setLineJoin(.round)
        for (i,s) in art.strokes.enumerated() {
            let f=progress[i] ?? 0,amount=incoming ? f : 1-f
            if amount<=0 { continue }
            c.setStrokeColor(CGColor(srgbRed:s.color.r,green:s.color.g,blue:s.color.b,alpha:1));c.setLineWidth(s.widthFactor)
            c.addPath(amount>=1 ? paths[i] : path(s.portion(from:incoming ? 0 : f*s.length,to:incoming ? f*s.length : s.length)));c.strokePath()
            if amount>=1,let fill=s.fill { c.setFillColor(CGColor(srgbRed:fill.r,green:fill.g,blue:fill.b,alpha:1));c.addPath(paths[i]);c.fillPath() }
        }
        c.restoreGState()
    }
}
