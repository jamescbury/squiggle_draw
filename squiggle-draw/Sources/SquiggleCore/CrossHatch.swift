import Foundation

extension Engine {
    // Long, gently curved hatch families cross at distinct angles. Each additional
    // family supplies optical density in shadows; fractional family coverage is
    // distributed by a low-discrepancy line rank, retaining continuous tone.
    static func hatchLevel(_ weight:Double,_ dose:Double,_ p:Parameters)->Double {
        if !p.matchTones { return weight*Double(p.hatchPasses) }
        // The displayed black ink is charcoal, so compensate for its gray floor.
        let floor=p.color ? 0.0 : Pixel(32.0/255,34.0/255,31.0/255).luminance
        let transmission=max(0.008,1-weight/(1-floor))
        let complete=Foundation.floor(-log(transmission)/dose)
        let remaining=transmission/exp(-complete*dose)
        return complete+(1-remaining)/(1-exp(-dose))
    }
    /// Residual-density streamlines follow surface structure in the first pass;
    /// rotated families deepen only the parts that still need pigment.
    static func crossHatch(_ source:Raster,_ p:Parameters,_ progress:@Sendable(String)->Void) throws -> Drawing {
        progress("Studying contours and surface directions…")
        let field=try PhotoAnalysis(source)
        let prepared=try field.preparedSource(source,background:p.sketchBackground)
        let shaded=try shadedSource(prepared,depth:p.sketchShading)
        let image=field.image,w=image.width,h=image.height,n=w*h
        var pixels=[Pixel]();pixels.reserveCapacity(n)
        for y in 0..<h {
            try Task.checkCancellation()
            for x in 0..<w { pixels.append(shaded.pixels[shaded.index(field.output(Point(Double(x),Double(y))))]) }
        }
        let tonalImage=try Raster(width:w,height:h,pixels:pixels)
        let pen=p.penWidth/sqrt(field.sx*field.sy)
        let long=Double(max(w,h)),short=Double(min(w,h))
        let minimum=max(2,Int(short*0.0125))
        let traceStep=min(2.0,max(0.25,short/4))
        var layers=[Layer](),totalVertices=0
        let angles=[0.0,0.0,0.95,-0.95,0.0,0.95,-0.95,0.0]
        for ink in (p.color ? Ink.allCases : [.black]) {
            let weights=try inkWeights(tonalImage,ink,p,(0...255).map{Double($0)/255})
            if (weights.max() ?? 0)<0.012 { continue }
            let soft=try PhotoAnalysis.blur(weights,w,h,1)
            let maximum=min(3.6,Double(p.hatchPasses)*0.5)
            let target=soft.map { weight in
                let optical = -log(max(0.018,1-weight/0.875))
                return min(maximum,optical)*(p.matchTones ? 0.68 : 0.55)
            }
            var deposited=[Double](repeating:0,count:n),strokes=[[Point]](),centers=[Point]()
            var random=Random(state:p.seed &+ UInt64(ink.index)*7919)
            let mass=target.reduce(0,+)
            let sourceWeights=try inkWeights(shaded,ink,p,(0...255).map{Double($0)/255})
            let gap=max(0.8,p.hatchSpacing*Double(max(source.width,source.height))/1600/sqrt(field.sx*field.sy))
            let spacingFactor=min(1.6,max(0.35,2.2/gap))
            let detailFactor=0.65+0.7*p.sketchDetail
            func paint(_ line:[Point]) {
                for (a,b) in zip(line,line.dropFirst()) {
                    let distance=a.distance(b),steps=max(1,Int(ceil(distance)))
                    for k in 0..<steps {
                        let t=(Double(k)+0.5)/Double(steps),q=Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
                        let x=Int(q.x.rounded()),y=Int(q.y.rounded()),dose=pen*distance/Double(steps)/6.1689
                        for oy in -2...2 { for ox in -2...2 {
                            if x+ox>=0 && x+ox<w && y+oy>=0 && y+oy<h { deposited[(y+oy)*w+x+ox]+=dose*exp(-Double(ox*ox+oy*oy)/2) }
                        } }
                    }
                }
            }
            for pass in 0..<p.hatchPasses {
                try Task.checkCancellation()
                progress("Following \(ink.rawValue) surfaces · layer \(pass+1) of \(p.hatchPasses)…")
                let fraction=Double(pass+1)/Double(p.hatchPasses)
                let stageStart=strokes.count
                let ceiling=0.16+3.44*pow(fraction,2)
                let averageLength=max(4,long*(0.14-0.055*Double(pass)/Double(p.hatchPasses))*detailFactor)
                let attempts=min(10000,max(24,Int(mass/max(0.08,pen*averageLength)/Double(p.hatchPasses)*spacingFactor*1.8)))
                for attempt in 0..<attempts {
                    if attempt%32==0 { try Task.checkCancellation() }
                    var seed:Point?,score=0.015
                    for _ in 0..<32 {
                        let q=Point(random.unit()*Double(w-1),random.unit()*Double(h-1)),i=image.index(q)
                        let residual=min(ceiling,target[i]*fraction)-deposited[i]
                        let feature=pass==0 ? 0.8+min(0.7,field.edge[i]*16)*p.sketchDetail : 1
                        let candidate=residual*feature*(0.8+random.unit()*0.4)
                        if weights[i]>=0.025 && candidate>score { score=candidate;seed=q }
                    }
                    guard let seed else { continue }
                    let rotation=angles[pass]+(random.unit()-0.5)*0.1
                    let startAngle=0.5*atan2(bilinear(field.ty,image,seed),bilinear(field.tx,image,seed))+rotation
                    let length=averageLength*(0.55+random.unit()*0.9),phase=random.unit()*2*Double.pi
                    var line=[seed]
                    for sign in [-1.0,1.0] {
                        var q=seed,branch=[Point](),previous=Point(cos(startAngle)*sign,sin(startAngle)*sign)
                        for step in 0..<max(2,Int(length/(2*traceStep))) {
                            let tangent=0.5*atan2(bilinear(field.ty,image,q),bilinear(field.tx,image,q))+rotation
                            let angle=tangent+0.025*sin(Double(step)*0.14+phase)
                            var direction=Point(cos(angle)*sign,sin(angle)*sign)
                            if direction.x*previous.x+direction.y*previous.y<0 { direction=Point(-direction.x,-direction.y) }
                            let bend=min(0.32,p.hatchCurve/30)
                            direction=Point((1-bend)*previous.x+bend*direction.x,(1-bend)*previous.y+bend*direction.y)
                            let norm=max(1e-9,hypot(direction.x,direction.y));direction=Point(direction.x/norm,direction.y/norm)
                            let next=Point(q.x+direction.x*traceStep,q.y+direction.y*traceStep)
                            let midpoint=Point((q.x+next.x)/2,(q.y+next.y)/2)
                            if next.x<0 || next.x>Double(w-1) || next.y<0 || next.y>Double(h-1) { break }
                            let desired=min(ceiling,bilinear(target,image,next)*fraction),done=bilinear(deposited,image,next)
                            if bilinear(weights,image,next)<0.025 || bilinear(weights,image,midpoint)<0.025 || desired<0.015 || (step>3 && done>desired*1.1) { break }
                            // A hard tone discontinuity indicates a feature boundary,
                            // where continuing the hatch would flatten the form.
                            if p.protectEdges && abs(bilinear(soft,image,next)-bilinear(soft,image,q))>0.1 { break }
                            branch.append(next);q=next;previous=direction
                        }
                        if sign<0 { line=branch.reversed()+line } else { line.append(contentsOf:branch) }
                    }
                    if line.count>=minimum {
                        totalVertices+=line.count;guard totalVertices<=8000000 else { throw DrawError.tooDetailed }
                        paint(line)
                        let output=line.map(field.output)
                        strokes.append(output);centers.append(output[0]);centers.append(output.last!)
                    }
                }
                // Keep each layer's light-to-dark sequence while reducing pen lifts locally.
                if p.connectHatches && strokes.count>stageStart+1 {
                    let runs=Array(strokes[stageStart...]),before=runs.reduce(0){$0+$1.count}
                    let reach=p.hatchJoinReach*Double(max(source.width,source.height))/1600
                    let joined=try joinHatchStrokes(runs,shaded,sourceWeights,reach:reach,vertexBudget:max(0,8000000-totalVertices))
                    totalVertices+=joined.reduce(0){$0+$1.count}-before
                    strokes.replaceSubrange(stageStart...,with:joined)
                }
            }
            // Even a two-pixel image receives a valid tonal mark.
            if strokes.isEmpty,let index=weights.indices.max(by:{weights[$0]<weights[$1]}),weights[index]>=0.012 {
                let q=Point(Double(index%w),Double(index/w))
                let a=field.output(q),b=field.output(Point(min(Double(w-1),q.x+0.5),max(0,q.y-0.5)))
                let fallback=a.distance(b)>0 ? [a,b] : [Point(0,0),Point(Double(source.width-1),Double(source.height-1))]
                strokes=[fallback];centers=fallback;totalVertices+=2
            }
            if !strokes.isEmpty { layers.append(Layer(ink:ink,centers:centers,points:strokes.flatMap{$0},strokes:strokes)) }
        }
        return Drawing(width:source.width,height:source.height,layers:layers,parameters:p)
    }
}
