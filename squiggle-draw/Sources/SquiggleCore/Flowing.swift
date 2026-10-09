import Foundation

extension Engine {
    // Incommensurate oscillators never repeat a circle. A slowly turning, stretched
    // frame makes long ribbons and self-crossings, while the moving center follows
    // image regions. No crossing-removal step is applied to the drawn line.
    static func flowingScribble(_ tour:[Point],_ image:Raster,_ weights:[Double],_ edges:[Double],_ p:Parameters,_ scale:Double,_ cap:Int,_ ink:Ink,field:PhotoAnalysis?=nil) throws -> [Point] {
        guard let first=tour.first else { return [] }
        var random=Random(state:p.seed &+ UInt64(ink.index)*7919)
        let phase=random.unit()*2*Double.pi,rotation=random.unit()*2*Double.pi
        var theta=phase,result=[Point](),smoothRadius=p.minRadius,frameAngle=rotation
        let angular=Double.pi/18
        // Reflection keeps the centerline in the picture without clamping
        // whole runs onto the frame.
        func fold(_ v:Double,_ limit:Double)->Double {
            if v>=0 && v<=limit { return v }
            let period=2*limit
            let t=v.truncatingRemainder(dividingBy:period)
            let positive=t<0 ? t+period : t
            return positive<=limit ? positive : period-positive
        }
        let pairs=tour.count==1 ? [(first,first)] : Array(zip(tour,tour.dropFirst()+[first]))
        for (a,b) in pairs {
            try Task.checkCancellation()
            let distance=a.distance(b)
            var t=0.0
            repeat {
                if result.count%512==0 { try Task.checkCancellation() }
                guard result.count<cap else { throw DrawError.tooDetailed }
                let center=Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
                let tone=1-bilinear(weights,image,center)
                let target=radius(tone:tone,distance:edges[image.index(center)]/sqrt(p.curveStretch),parameters:p)
                // Grow gradually, but tighten immediately when entering a feature.
                smoothRadius = min(target,smoothRadius+(target-smoothRadius)*0.03)
                let wander=p.curveWander
                let u=(1-0.3*wander)*sin(theta)+0.3*wander*sin(theta*0.371+phase)
                let v=(1-0.45*wander)*cos(theta*(1-0.29*wander))+0.45*wander*sin(theta*1.137+phase)
                let angle:Double
                if let field {
                    let q=field.fieldPoint(center)
                    let tangent=0.5*atan2(bilinear(field.ty,field.image,q),bilinear(field.tx,field.image,q))
                    let targetAngle=tangent+0.16*sin(theta*0.031+rotation)*wander
                    var turn=(targetAngle-frameAngle).truncatingRemainder(dividingBy:Double.pi)
                    if turn>Double.pi/2 { turn-=Double.pi };if turn < -Double.pi/2 { turn+=Double.pi }
                    frameAngle+=turn*0.035
                    angle=frameAngle
                } else { angle=rotation+theta*(0.025+0.045*wander) }
                let x=smoothRadius*sqrt(p.curveStretch)*u,y=smoothRadius/sqrt(p.curveStretch)*v
                result.append(Point(fold(center.x+x*cos(angle)-y*sin(angle),Double(image.width-1)),fold(center.y+x*sin(angle)+y*cos(angle),Double(image.height-1))))
                theta += angular
                // Two samples per circular-style step retain a smooth curve and
                // comparable ink coverage; shadows advance slowly and overlap.
                let advance=min((1.0/15+tone*(4-1.0/15))*p.spacing*scale/2,smoothRadius*angular*0.85)
                t += distance>0 ? max(0.0125*scale,advance)/distance : 1.0/36
            } while t<1
        }
        // A quadratic B-spline filter softens direction changes in the moving
        // center and reflected frame, without adding vertices or pen lifts.
        if result.count>2 {
            var previous=result[0]
            for i in 1..<result.count-1 {
                if i%512==0 { try Task.checkCancellation() }
                let current=result[i],next=result[i+1]
                result[i]=Point((previous.x+4*current.x+next.x)/6,(previous.y+4*current.y+next.y)/6)
                previous=current
            }
        }
        return result
    }
}
