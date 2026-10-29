import Foundation

/// A loop may be broad along a contour and shallow across it. Probe the whole
/// displacement, not just the center: a large loop can otherwise jump straight
/// over a narrow highlight or silhouette even when its center is far from it.
struct CircularContours {
    let field:PhotoAnalysis
    let red:[Double],green:[Double],blue:[Double]
    init(_ source:Raster) throws {
        field=try PhotoAnalysis(source)
        let image=field.image
        red=try PhotoAnalysis.blur(image.pixels.map(\.r),image.width,image.height,1)
        green=try PhotoAnalysis.blur(image.pixels.map(\.g),image.width,image.height,1)
        blue=try PhotoAnalysis.blur(image.pixels.map(\.b),image.width,image.height,1)
    }
    func tangent(at point:Point)->Double {
        let q=field.fieldPoint(point)
        return 0.5*atan2(Engine.bilinear(field.ty,field.image,q),Engine.bilinear(field.tx,field.image,q))
    }
    func color(_ q:Point)->Pixel {
        Pixel(Engine.bilinear(red,field.image,q),Engine.bilinear(green,field.image,q),Engine.bilinear(blue,field.image,q))
    }
    func confined(_ center:Point,_ proposed:Point)->Point {
        let a=field.fieldPoint(center),b=field.fieldPoint(proposed)
        let count=max(1,Int(ceil(a.distance(b)/0.75)))
        let origin=color(a)
        var last=a
        for i in 1...count {
            let t=Double(i)/Double(count),q=Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
            if q.x<0 || q.y<0 || q.x>Double(field.image.width-1) || q.y>Double(field.image.height-1) { return field.sourcePoint(last) }
            let c=color(q)
            let difference=max(abs(c.r-origin.r),abs(c.g-origin.g),abs(c.b-origin.b))
            // Small texture is tolerated, but strong tonal or chromatic edges
            // bend the loop back on itself. Interpolation softens the contact.
            if difference>0.16 {
                let previous=color(last)
                let before=max(abs(previous.r-origin.r),abs(previous.g-origin.g),abs(previous.b-origin.b))
                let blend=max(0,min(1,(0.16-before)/max(1e-8,difference-before)))
                return field.sourcePoint(Point(last.x+(q.x-last.x)*blend,last.y+(q.y-last.y)*blend))
            }
            last=q
        }
        return proposed
    }
}
