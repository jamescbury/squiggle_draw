import Foundation

extension Engine {
    /// Randomized local wandering with occasional longer crossings. Coverage
    /// only biases the choices; there are no stripes, ordered cells, or passes.
    static func coverageTrace(_ samples:[Point],_ image:Raster,seed:UInt64) throws ->[Point] {
        guard samples.count>2 else { return samples }
        var random=Random(state:seed),pool=Array(samples.indices),poolPositions=pool
        let cell=max(1,sqrt(Double(image.width*image.height)/Double(samples.count))*3)
        let columns=Int(ceil(Double(image.width)/cell))+1,rows=Int(ceil(Double(image.height)/cell))+1
        var grid=Array(repeating:[Int](),count:columns*rows),gridPositions=pool,cellIDs=pool
        let side=8
        var regionIDs=pool,totals=Array(repeating:0,count:side*side),used=totals
        for (i,q) in samples.enumerated() {
            if i%512==0 { try Task.checkCancellation() }
            let id=Int(q.y/cell)*columns+Int(q.x/cell)
            cellIDs[i]=id;gridPositions[i]=grid[id].count;grid[id].append(i)
            let rx=min(side-1,Int(q.x/Double(image.width)*Double(side))),ry=min(side-1,Int(q.y/Double(image.height)*Double(side))),region=ry*side+rx
            regionIDs[i]=region;totals[region]+=1
        }
        func remove(_ id:Int) {
            let pos=poolPositions[id],last=pool.last!;pool[pos]=last;poolPositions[last]=pos;pool.removeLast()
            let cell=cellIDs[id],offset=gridPositions[id],tail=grid[cell].last!
            grid[cell][offset]=tail;gridPositions[tail]=offset;grid[cell].removeLast();used[regionIDs[id]]+=1
        }
        func coverage(_ id:Int)->Double { Double(used[regionIDs[id]])/Double(max(1,totals[regionIDs[id]])) }
        var current=pool[Int(random.unit()*Double(pool.count))],result=[Point](),direction=Point(0,0)
        while !pool.isEmpty {
            if result.count%64==0 { try Task.checkCancellation() }
            let q=samples[current];result.append(q);remove(current)
            if pool.isEmpty { break }
            var candidates=[Int]()
            // A small random chance of a longer gesture prevents a local tour
            // from finishing one isolated patch before drawing elsewhere.
            let crossing=random.unit()<max(0.015,min(0.08,24/Double(samples.count)))
            if !crossing {
                let gx=cellIDs[current]%columns,gy=cellIDs[current]/columns
                for radius in 1...3 {
                    for y in max(0,gy-radius)...min(rows-1,gy+radius) { for x in max(0,gx-radius)...min(columns-1,gx+radius) {
                        if radius>1 && max(abs(x-gx),abs(y-gy)) != radius { continue }
                        let ids=grid[y*columns+x]
                        if ids.count<=32 { candidates.append(contentsOf:ids) }
                        else { for _ in 0..<32 { candidates.append(ids[Int(random.unit()*Double(ids.count))]) } }
                    } }
                    if candidates.count>=12 { break }
                }
            }
            if crossing || candidates.isEmpty { for _ in 0..<32 { candidates.append(pool[Int(random.unit()*Double(pool.count))]) } }
            var best=candidates[0],bestCost=Double.infinity
            for id in candidates {
                let p=samples[id],distance=q.distance(p),progress=coverage(id)
                let turn=distance>0 ? 1-(direction.x*(p.x-q.x)+direction.y*(p.y-q.y))/distance : 0
                let jitter=0.75+random.unit()*0.65
                let cost=crossing ? (0.15+progress)*jitter+distance/Double(max(image.width,image.height))*0.12 : max(1e-6,distance)*(1+0.2*turn)*(0.85+0.3*progress)*jitter
                if cost<bestCost { bestCost=cost;best=id }
            }
            let next=samples[best],length=max(1e-9,q.distance(next));direction=Point((next.x-q.x)/length,(next.y-q.y)/length);current=best
        }
        return result
    }
    /// Account for extra travel through changing tones, so page-spanning
    /// routes do not simply multiply the amount of ink in the photograph.
    static func routeEffort(_ tour:[Point],_ image:Raster,_ weights:[Double],_ p:Parameters,_ scale:Double) throws ->Double {
        guard tour.count>1 else { return 0 }
        var effort=0.0
        for i in tour.indices {
            if i%512==0 { try Task.checkCancellation() }
            let a=tour[i],b=tour[(i+1)%tour.count],length=a.distance(b)
            let steps=max(1,Int(ceil(length/max(1,16*scale))))
            for j in 0..<steps {
                let t=(Double(j)+0.5)/Double(steps),q=Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
                let tone=1-bilinear(weights,image,q)
                let advance=max(0.025*scale,(1.0/15+tone*(4-1.0/15))*p.spacing*scale)
                effort+=length/Double(steps)/advance
            }
        }
        return effort
    }
}
