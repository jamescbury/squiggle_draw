import Foundation

extension Engine {
    static func connectCrossHatch(_ drawing:Drawing,_ image:Raster) throws ->Drawing {
        let p=drawing.parameters
        guard p.style == .crossHatch,p.connectHatches else { return drawing }
        let reach=p.hatchJoinReach*Double(max(image.width,image.height))/1600
        var layers=[Layer](),budget=max(0,8000000-drawing.vertexCount)
        for layer in drawing.layers {
            try Task.checkCancellation()
            let weights=try inkWeights(image,layer.ink,p,(0...255).map{Double($0)/255})
            let joined=try joinHatchStrokes(layer.strokes,image,weights,reach:reach,vertexBudget:budget)
            let points=joined.flatMap{$0}
            budget-=max(0,points.count-layer.points.count)
            layers.append(Layer(ink:layer.ink,centers:layer.centers,points:points,strokes:joined))
        }
        return Drawing(width:drawing.width,height:drawing.height,layers:layers,parameters:p)
    }
    /// Match nearby free ends, retaining every original hatch segment. Short
    /// rounded bridges may join different families, but cannot cross highlights.
    /// A forest of endpoint links creates long chains without redundant loops.
    static func joinHatchStrokes(_ input:[[Point]],_ image:Raster,_ weights:[Double],reach:Double,vertexBudget:Int) throws ->[[Point]] {
        let runs=input.filter{$0.count>1}
        guard runs.count>1,reach>0,vertexBudget>0 else { return input }
        guard runs.count<=120000 else { throw DrawError.tooDetailed }
        struct End { let point:Point,direction:Point }
        struct Edge { let a:Int,b:Int,cost:Double }
        let columns=Int(ceil(Double(image.width)/reach))+1
        func key(_ x:Int,_ y:Int)->Int { y*columns+x }
        var ends=[End](),grid=[Int:[Int]]()
        var originalLength=0.0
        for (i,run) in runs.enumerated() {
            if i%128==0 { try Task.checkCancellation() }
            originalLength+=zip(run,run.dropFirst()).reduce(0){$0+$1.0.distance($1.1)}
            for side in 0...1 {
                let q=side==0 ? run[0] : run[run.count-1],neighbor=side==0 ? run[1] : run[run.count-2]
                let length=max(1e-9,q.distance(neighbor))
                let end=End(point:q,direction:Point((q.x-neighbor.x)/length,(q.y-neighbor.y)/length))
                grid[key(Int(q.x/reach),Int(q.y/reach)),default:[]].append(ends.count);ends.append(end)
            }
        }
        var candidates=[Edge](),seen=Set<UInt64>()
        for a in ends.indices {
            if a%128==0 { try Task.checkCancellation() }
            let end=ends[a],x=Int(end.point.x/reach),y=Int(end.point.y/reach)
            var nearest=[Edge]()
            for gy in max(0,y-1)...y+1 { for gx in max(0,x-1)...min(columns-1,x+1) {
                let ids=grid[key(gx,gy)] ?? [],stride=max(1,ids.count/96)
                for offset in Swift.stride(from:0,to:ids.count,by:stride) {
                    let b=ids[offset]
                    if a/2==b/2 { continue }
                    let other=ends[b],distance=end.point.distance(other.point)
                    if distance>reach { continue }
                    let dx=(other.point.x-end.point.x)/max(1e-9,distance),dy=(other.point.y-end.point.y)/max(1e-9,distance)
                    let turn=2-(end.direction.x*dx+end.direction.y*dy)+(other.direction.x*dx+other.direction.y*dy)
                    let brightness=1-min(bilinear(weights,image,end.point),bilinear(weights,image,other.point))
                    nearest.append(Edge(a:min(a,b),b:max(a,b),cost:distance*(1+0.15*brightness)+reach*0.035*turn))
                }
            } }
            nearest.sort{$0.cost==$1.cost ? $0.b<$1.b : $0.cost<$1.cost}
            for edge in nearest.prefix(4) {
                let id=UInt64(edge.a)<<32|UInt64(edge.b)
                if seen.insert(id).inserted { candidates.append(edge) }
            }
        }
        candidates.sort { a,b in a.cost==b.cost ? (a.a==b.a ? a.b<b.b : a.a<b.a) : a.cost<b.cost }
        var links=Array(repeating:-1,count:ends.count),bridgeIDs=links,parents=Array(runs.indices),sizes=Array(repeating:1,count:runs.count)
        func root(_ value:Int)->Int {
            var q=value
            while parents[q] != q { parents[q]=parents[parents[q]];q=parents[q] }
            return q
        }
        var bridges=[[Point]](),bridgeStarts=[Int](),addedLength=0.0,addedVertices=0
        for (i,edge) in candidates.enumerated() {
            if i%128==0 { try Task.checkCancellation() }
            if links[edge.a]>=0 || links[edge.b]>=0 { continue }
            let ra=root(edge.a/2),rb=root(edge.b/2)
            if ra==rb { continue }
            let a=ends[edge.a],b=ends[edge.b],distance=a.point.distance(b.point),handle=distance*0.45
            func bound(_ q:Point)->Point { Point(max(0,min(Double(image.width-1),q.x)),max(0,min(Double(image.height-1),q.y))) }
            let c1=bound(Point(a.point.x+a.direction.x*handle,a.point.y+a.direction.y*handle))
            let c2=bound(Point(b.point.x+b.direction.x*handle,b.point.y+b.direction.y*handle))
            let steps=max(4,Int(ceil(sqrt((distance+4*handle)/0.08))))
            let threshold=max(0.025,min(bilinear(weights,image,a.point),bilinear(weights,image,b.point))*0.65)
            var bridge=[a.point],safe=true
            for k in 1...steps {
                let t=Double(k)/Double(steps),u=1-t
                let q=Point(u*u*u*a.point.x+3*u*u*t*c1.x+3*u*t*t*c2.x+t*t*t*b.point.x,u*u*u*a.point.y+3*u*u*t*c1.y+3*u*t*t*c2.y+t*t*t*b.point.y)
                // Check the drawn segment, including narrow highlights between
                // curve vertices, without increasing export size.
                let previous=bridge.last!,checks=max(1,Int(ceil(previous.distance(q)/0.5)))
                // Inspect source pixels along the segment's small footprint,
                // too: interpolation must not hide a white pixel between
                // dark neighbors when the endpoints themselves are faint.
                let x0=Int(floor(min(previous.x,q.x)+0.5)),x1=Int(floor(max(previous.x,q.x)+0.5))
                let y0=Int(floor(min(previous.y,q.y)+0.5)),y1=Int(floor(max(previous.y,q.y)+0.5))
                for y in y0...y1 { for x in x0...x1 {
                    if weights[image.index(Point(Double(x),Double(y)))]<0.025 { safe=false }
                } }
                if !safe { break }
                for j in 1...checks {
                    let f=Double(j)/Double(checks),sample=Point(previous.x+(q.x-previous.x)*f,previous.y+(q.y-previous.y)*f)
                    if bilinear(weights,image,sample)<threshold { safe=false;break }
                }
                if !safe { break }
                bridge.append(q)
            }
            if !safe { continue }
            let length=zip(bridge,bridge.dropFirst()).reduce(0){$0+$1.0.distance($1.1)},extra=bridge.count-2
            // Bound the tonal impact and preserve the generation's vertex cap.
            if addedLength+length>originalLength*0.03 || addedVertices+extra>vertexBudget { continue }
            if sizes[ra]<sizes[rb] { parents[ra]=rb;sizes[rb]+=sizes[ra] } else { parents[rb]=ra;sizes[ra]+=sizes[rb] }
            links[edge.a]=edge.b;links[edge.b]=edge.a;bridgeIDs[edge.a]=bridges.count;bridgeIDs[edge.b]=bridges.count
            bridges.append(bridge);bridgeStarts.append(edge.a);addedLength+=length;addedVertices+=extra
        }
        var visited=Array(repeating:false,count:runs.count),output=[[Point]]()
        for start in ends.indices where links[start]<0 && !visited[start/2] {
            try Task.checkCancellation()
            var end=start,chain=[Point]()
            while !visited[end/2] {
                try Task.checkCancellation()
                let id=end/2,run=end%2==0 ? runs[id] : Array(runs[id].reversed())
                chain.append(contentsOf:chain.isEmpty ? run[...] : run.dropFirst());visited[id]=true
                let exit=end%2==0 ? end+1 : end-1,next=links[exit]
                if next<0 { break }
                let bridge=bridges[bridgeIDs[exit]],forward=bridgeStarts[bridgeIDs[exit]]==exit
                chain.append(contentsOf:forward ? bridge.dropFirst() : Array(bridge.reversed()).dropFirst());end=next
            }
            if !chain.isEmpty { output.append(chain) }
        }
        return output
    }
}
