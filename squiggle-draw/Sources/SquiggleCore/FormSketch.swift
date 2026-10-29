import Foundation

extension Engine {
    static func formSketch(_ source:Raster,_ p:Parameters,_ progress:@Sendable(String)->Void) throws ->Drawing {
        progress("Studying contours and surface directions…")
        let field=try PhotoAnalysis(source),image=field.image,w=image.width,h=image.height,n=w*h
        let pen=p.penWidth/sqrt(field.sx*field.sy)
        var layers=[Layer](),totalVertices=0
        for ink in (p.color ? Ink.allCases : [.black]) {
            try Task.checkCancellation()
            let raw=try inkWeights(image,ink,p,(0...255).map{Double($0)/255})
            var weights=raw
            for i in 0..<n { weights[i]*=(1-field.background[i]*(1-p.sketchBackground))*p.sketchShading }
            if (weights.max() ?? 0)<0.015 { continue }
            let soft=try PhotoAnalysis.blur(weights,w,h,1)
            let target=soft.map{0.7*min(3.6,-log(max(0.027,1-$0/0.875)))}
            var deposited=[Double](repeating:0,count:n),strokes=[[Point]](),centers=[Point]()
            var random=Random(state:p.seed &+ UInt64(ink.index)*7919)
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
            func append(_ line:[Point]) throws {
                guard line.count>2 else { return }
                totalVertices+=line.count;guard totalVertices<=4000000 else { throw DrawError.tooDetailed }
                strokes.append(line);centers.append(field.output(line[0]));centers.append(field.output(line.last!));paint(line)
            }
            // Sparse, thinned feature contours establish recognizable structures first.
            func contours(_ threshold:Double,_ minimum:Int,_ detail:Bool) throws {
                var eligible=[Bool](repeating:false,count:n),visited=eligible
                for y in 1..<h-1 { for x in 1..<w-1 {
                    let i=y*w+x,g=field.edge[i]
                    if g<threshold*0.45 || raw[i]<0.015 || (field.background[i]>0.95 && p.sketchBackground<0.2) { continue }
                    let dx=field.gx[i]/max(g,1e-9),dy=field.gy[i]/max(g,1e-9),q=Point(Double(x),Double(y))
                    let a=bilinear(field.edge,image,Point(q.x+dx,q.y+dy)),b=bilinear(field.edge,image,Point(q.x-dx,q.y-dy))
                    eligible[i]=g>=a && g>=b
                } }
                let seeds=(0..<n).filter{eligible[$0] && field.edge[$0]>=threshold}.sorted{field.edge[$0]==field.edge[$1] ? $0<$1 : field.edge[$0]>field.edge[$1]}
                for (number,seed) in seeds.enumerated() where !visited[seed] {
                    if number%128==0 { try Task.checkCancellation() }
                    var line=[Point(Double(seed%w),Double(seed/w))];visited[seed]=true
                    for side in 0...1 {
                        var current=seed,direction=Point(-field.gy[seed],field.gx[seed])
                        if side==1 { direction=Point(-direction.x,-direction.y) }
                        var branch=[Point]()
                        for _ in 0..<220 {
                            let x=current%w,y=current/w;var best:Int?,score = -Double.infinity
                            for oy in -1...1 { for ox in -1...1 where ox != 0 || oy != 0 {
                                if x+ox<1 || x+ox>=w-1 || y+oy<1 || y+oy>=h-1 { continue }
                                let j=(y+oy)*w+x+ox
                                if !eligible[j] || visited[j] { continue }
                                let length=hypot(Double(ox),Double(oy)),alignment=(direction.x*Double(ox)+direction.y*Double(oy))/max(1e-9,hypot(direction.x,direction.y)*length)
                                if alignment<0.15 { continue }
                                let value=alignment+field.edge[j]*2
                                if value>score { score=value;best=j }
                            } }
                            guard let next=best else { break }
                            direction=Point(Double(next%w-x),Double(next/w-y));current=next;visited[next]=true;branch.append(Point(Double(next%w),Double(next/w)))
                        }
                        if side==0 { line.append(contentsOf:branch) } else { line=branch.reversed()+line }
                    }
                    if line.count>=minimum {
                        if detail && bilinear(deposited,image,line[line.count/2])>bilinear(target,image,line[line.count/2])*1.25 { continue }
                        // Gentle smoothing retains the feature while removing pixel stair steps.
                        var smoothed=line
                        for i in 1..<line.count-1 { smoothed[i]=Point((line[i-1].x+2*line[i].x+line[i+1].x)/4,(line[i-1].y+2*line[i].y+line[i+1].y)/4) }
                        try append(smoothed)
                    }
                }
            }
            progress("Establishing \(ink.rawValue) contours…")
            try contours(0.045,10,false)
            let mass=target.reduce(0,+),longSide=Double(max(w,h))
            var focus=Point(Double(w)/2,Double(h)/2)
            let fractions=[0.18,0.42,0.72,1.0]
            for (stage,fraction) in fractions.enumerated() {
                progress(["Laying in broad forms","Following curved surfaces","Deepening shadows","Finishing tonal detail"][stage]+" — \(ink.rawValue)…")
                let stageStart=strokes.count
                let increment=fraction-(stage==0 ? 0 : fractions[stage-1])
                let ceiling=[0.22,0.55,1.2,3.6][stage]
                func wanted(_ q:Point)->Double { min(ceiling,bilinear(target,image,q)*fraction) }
                let averageLength=longSide*(stage<2 ? 0.11 : 0.065)
                let attempts=min(8500,max(80,Int(mass*increment/max(0.1,pen*averageLength)*1.8)))
                for attempt in 0..<attempts {
                    if attempt%32==0 { try Task.checkCancellation() }
                    var seed:Point?,best=0.045
                    let local=attempt%12 != 0
                    for trial in 0..<28 {
                        let q:Point
                        if local && trial<20 { q=Point(focus.x+(random.unit()-0.5)*longSide*0.22,focus.y+(random.unit()-0.5)*longSide*0.22) }
                        else { q=Point(random.unit()*Double(w-1),random.unit()*Double(h-1)) }
                        if q.x<1 || q.x>=Double(w-2) || q.y<1 || q.y>=Double(h-2) { continue }
                        let i=image.index(q),residual=wanted(q)-deposited[i]
                        let feature=stage<2 ? 0.35+min(1,field.edge[i]*30) : 1+min(0.5,field.edge[i]*4)
                        let score=residual*(0.75+random.unit()*0.5)*feature
                        if score>best { best=score;seed=q }
                    }
                    guard let seed else { continue };focus=seed
                    let cross=stage>=2 && random.unit()<0.3 ? (random.unit()<0.5 ? 0.85 : -0.85) : 0
                    let length=averageLength*(0.55+random.unit()*1.1),phase=random.unit()*6.283
                    var line=[seed]
                    for sign in [-1.0,1.0] {
                        var q=seed,branch=[Point](),previous=Point(0,0)
                        for step in 0..<max(2,Int(length/2)) {
                            let angle=0.5*atan2(bilinear(field.ty,image,q),bilinear(field.tx,image,q))+cross+0.035*sin(Double(step)*0.13+phase)
                            var direction=Point(cos(angle)*sign,sin(angle)*sign)
                            if step>0 && direction.x*previous.x+direction.y*previous.y<0 { direction=Point(-direction.x,-direction.y) }
                            if step>0 { direction=Point(0.7*previous.x+0.3*direction.x,0.7*previous.y+0.3*direction.y);let d=max(1e-9,hypot(direction.x,direction.y));direction=Point(direction.x/d,direction.y/d) }
                            let next=Point(q.x+direction.x,q.y+direction.y)
                            if next.x<0 || next.x>Double(w-1) || next.y<0 || next.y>Double(h-1) { break }
                            let required=wanted(next),done=bilinear(deposited,image,next)
                            if required<0.035 || (step>3 && done>required*1.15) { break }
                            // Keep the pen inside the tone region; a lift is preferable
                            // to a connector that cuts through a highlight or boundary.
                            if abs(bilinear(soft,image,next)-bilinear(soft,image,q))>0.075 { break }
                            branch.append(next);q=next;previous=direction
                        }
                        if sign<0 { line=branch.reversed()+line } else { line.append(contentsOf:branch) }
                    }
                    if line.count>=6 { try append(line) }
                }
                if p.connectHatches && strokes.count>stageStart+1 {
                    let runs=Array(strokes[stageStart...]),before=runs.reduce(0){$0+$1.count}
                    let joined=try joinHatchStrokes(runs,image,weights,reach:3*longSide/720,vertexBudget:4000000-totalVertices)
                    totalVertices+=joined.reduce(0){$0+$1.count}-before
                    strokes.replaceSubrange(stageStart...,with:joined)
                }
            }
            progress("Adding \(ink.rawValue) feature accents…")
            try contours(0.055-0.035*p.sketchDetail,Int(12-7*p.sketchDetail),true)
            if !strokes.isEmpty {
                let output=strokes.map{$0.map{field.output($0)}}
                layers.append(Layer(ink:ink,centers:centers,points:output.flatMap{$0},strokes:output))
            }
        }
        return Drawing(width:source.width,height:source.height,layers:layers,parameters:p)
    }
}
