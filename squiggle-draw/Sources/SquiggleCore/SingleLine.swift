import Foundation

extension Engine {
    static func singleLine(_ image:Raster,_ p:Parameters,_ progress:@Sendable(String)->Void) throws -> Drawing {
        let stippled=try stipple(image,p,progress)
        guard !stippled.layers.isEmpty else { return stippled }
        progress("Grouping path regions…")
        let labels=p.spreadAcrossCanvas ? [] : try regions(image)
        var layers=[Layer]()
        for layer in stippled.layers {
            try Task.checkCancellation()
            progress("Connecting \(layer.ink.rawValue) stipple points…")
            let tour:[Point]
            if p.spreadAcrossCanvas {
                tour=try coverageTrace(layer.centers,image,seed:p.seed &+ UInt64(layer.ink.index)*7919)
            } else {
                let regional=try trace(layer.centers,labels,image)
                progress("Shortening \(layer.ink.rawValue) route…")
                tour=try improveStippleRoute(regional,width:image.width,height:image.height)
            }
            progress("Rounding \(layer.ink.rawValue) corners…")
            let points=try roundedRoute(tour,rounding:p.cornerRounding)
            layers.append(Layer(ink:layer.ink,centers:tour,points:points,strokes:[points]))
        }
        return Drawing(width:image.width,height:image.height,layers:layers,parameters:p)
    }

    // Spatially restricted global 2-opt removes detours between regional cycles.
    // Bound both candidate checks and reversed elements; cancellation never waits
    // for an unbounded traveling-salesman search.
    static func improveStippleRoute(_ points:[Point],width:Int,height:Int) throws -> [Point] {
        try Task.checkCancellation()
        guard points.count>3 else { return points }
        let cell=max(2,sqrt(Double(width*height)/Double(points.count))*2)
        let columns=Int(ceil(Double(width)/cell))+1
        func key(_ x:Int,_ y:Int)->Int { y*columns+x }
        var grid=[Int:[Int]]()
        for id in points.indices { grid[key(Int(points[id].x/cell),Int(points[id].y/cell)),default:[]].append(id) }
        var order=Array(points.indices),position=order
        for _ in 0..<3 {
            var changed=false,reverseWork=0
            for i in order.indices {
                if i%64==0 { try Task.checkCancellation() }
                if reverseWork>points.count*40 { break }
                let a=points[order[i]],gx=Int(a.x/cell),gy=Int(a.y/cell)
                var candidates=[Int]()
                for y in max(0,gy-2)...gy+2 { for x in max(0,gx-2)...min(columns-1,gx+2) { candidates += grid[key(x,y)] ?? [] } }
                candidates.sort { lhs,rhs in
                    let l=points[lhs],r=points[rhs]
                    let dl=(l.x-a.x)*(l.x-a.x)+(l.y-a.y)*(l.y-a.y),dr=(r.x-a.x)*(r.x-a.x)+(r.y-a.y)*(r.y-a.y)
                    return dl==dr ? lhs<rhs : dl<dr
                }
                for id in candidates.prefix(32) {
                    let j=position[id],lo=min(i,j),hi=max(i,j)
                    if hi-lo<2 || hi-lo==points.count-1 { continue }
                    let a=points[order[lo]],b=points[order[lo+1]],c=points[order[hi]],d=points[order[(hi+1)%order.count]]
                    if a.distance(c)+b.distance(d)+1e-7<a.distance(b)+c.distance(d) {
                        order[(lo+1)...hi].reverse()
                        for k in lo+1...hi { position[order[k]]=k }
                        reverseWork+=hi-lo;changed=true;break
                    }
                }
            }
            if !changed { break }
        }
        return order.map{points[$0]}
    }

    // Trim adjacent edges, then replace each corner with a quadratic Bézier.
    // Flatten curves to <=0.08px chord error so every exporter/preview shares
    // the same continuous geometry, including path-only plotter readers.
    static func roundedRoute(_ tour:[Point],rounding:Double) throws -> [Point] {
        try Task.checkCancellation()
        guard let first=tour.first else { return [] }
        if tour.count==1 { return [first,first] }
        if tour.count==2 { return tour+[first] }
        if rounding==0 { return tour+[first] }
        func interpolate(_ a:Point,_ b:Point,_ t:Double) -> Point { Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t) }
        var output=[Point]();output.reserveCapacity(tour.count*6)
        for i in tour.indices {
            if i%256==0 { try Task.checkCancellation() }
            let prev=tour[(i+tour.count-1)%tour.count],q=tour[i],next=tour[(i+1)%tour.count]
            let incoming=prev.distance(q),outgoing=q.distance(next)
            let cut=0.45*rounding*min(incoming,outgoing)
            guard cut>1e-9 else { output.append(q);continue }
            let entry=interpolate(q,prev,cut/incoming),exit=interpolate(q,next,cut/outgoing)
            output.append(entry)
            // For a quadratic, maximum deviation from the chord is bounded by
            // |entry-2*control+exit|/(4*n²) for n equal parameter intervals.
            let curvature=hypot(entry.x-2*q.x+exit.x,entry.y-2*q.y+exit.y)
            let steps=max(2,Int(ceil(sqrt(curvature/(4*0.08)))))
            for k in 1...steps {
                let t=Double(k)/Double(steps),u=1-t
                output.append(Point(u*u*entry.x+2*u*t*q.x+t*t*exit.x,u*u*entry.y+2*u*t*q.y+t*t*exit.y))
            }
        }
        if let start=output.first { output.append(start) }
        return output
    }
}
