import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SquiggleCore

// Reproducible gallery generator. Inputs are explicit paths; nothing scans personal photo folders.
func raster(_ url:URL,maxDimension:Int=960) throws ->Raster {
    guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:maxDimension,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else {throw DrawError.invalidImage}
    var bytes=[UInt8](repeating:255,count:image.width*image.height*4)
    bytes.withUnsafeMutableBytes { buffer in
        let ctx=CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:image.width,height:image.height));ctx.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
    }
    return try Raster(width:image.width,height:image.height,pixels:stride(from:0,to:bytes.count,by:4).map{Pixel(Double(bytes[$0])/255,Double(bytes[$0+1])/255,Double(bytes[$0+2])/255)})
}
func path(_ points:[Point])->CGPath {
    let p=CGMutablePath();if let first=points.first {p.move(to:CGPoint(x:first.x,y:first.y));for point in points.dropFirst(){p.addLine(to:CGPoint(x:point.x,y:point.y))}};return p
}
func png(_ drawing:Drawing,_ url:URL) throws {
    let w=drawing.width,h=drawing.height
    let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:w,height:h));ctx.translateBy(x:0,y:CGFloat(h));ctx.scaleBy(x:1,y:-1);ctx.setLineCap(.round);ctx.setLineJoin(.round)
    for layer in drawing.drawingLayers(inks:Set(Ink.allCases)) {
        let hex=UInt32(layer.ink.hex.dropFirst(),radix:16)!,color=CGColor(srgbRed:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255,alpha:1)
        ctx.setStrokeColor(color);ctx.setFillColor(color);ctx.setLineWidth(drawing.parameters.penWidth)
        for (i,stroke) in layer.strokes.enumerated() {ctx.setLineWidth(drawing.parameters.penWidth*layer.widthFactor(at:i));ctx.addPath(path(stroke));ctx.strokePath()}
        for dot in layer.dots {ctx.fillEllipse(in:CGRect(x:dot.center.x-dot.radius,y:dot.center.y-dot.radius,width:dot.radius*2,height:dot.radius*2))}
        for face in layer.facets {
            ctx.addPath(path(face.vertices));ctx.closePath()
            if drawing.parameters.polyWireframe {ctx.strokePath()}
            else {let c=face.color;let fill=CGColor(srgbRed:c.r,green:c.g,blue:c.b,alpha:1);ctx.setFillColor(fill);ctx.setStrokeColor(fill);ctx.setLineWidth(0.25);ctx.drawPath(using:.fillStroke)}
        }
    }
    guard let image=ctx.makeImage(),let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else {throw DrawError.invalidImage}
    CGImageDestinationAddImage(destination,image,nil);guard CGImageDestinationFinalize(destination) else {throw DrawError.invalidImage}
}
let args=CommandLine.arguments
if args.count<3 { print("Usage: swift run -c release SquiggleSamples INPUT.png OUTPUT_DIRECTORY [color|mono] [style-index] [max-dimension]");exit(2) }
let maximum=args.count>5 ? min(1600,max(2,Int(args[5]) ?? 960)) : 960
let image=try raster(URL(fileURLWithPath:args[1]),maxDimension:maximum),folder=URL(fileURLWithPath:args[2],isDirectory:true)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
var results=[[String:Any]]()
for (index,style) in DrawingStyle.studioStyles.enumerated() {
    if args.count>4,let selected=Int(args[4]),index != selected {continue}
    var p=Parameters();p.style=style;p.color=args.count>3 && args[3]=="color"
    p=try Engine.optimize(image,parameters:p).parameters
    if args.contains("uniform") { p.toneWidth=false;p=try Engine.optimize(image,parameters:p).parameters }
    let start=Date(),drawing=try Engine.generate(image,parameters:p),size=try drawing.svgSize(inks:Set(Ink.allCases))
    let name=["form","circular","continuous","hatching","stipple","poly"][index]
    try png(drawing,folder.appendingPathComponent(name+".png"))
    try drawing.svg(inks:Set(Ink.allCases)).write(to:folder.appendingPathComponent(name+".svg"),atomically:true,encoding:.utf8)
    let record:[String:Any] = ["style":style.displayName,"name":name,"seconds":Date().timeIntervalSince(start),"vertices":drawing.vertexCount,"elements":size.elements,"bytes":size.fileBytes,"pathBytes":size.pathDataBytes]
    results.append(record);print(String(data:try JSONSerialization.data(withJSONObject:record,options:.sortedKeys),encoding:.utf8)!);fflush(stdout)
}
try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("metrics.json"),options:.atomic)
