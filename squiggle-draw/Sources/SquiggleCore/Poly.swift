import Foundation

extension Engine {
    /// A conforming Delaunay mesh, colored from the photograph and shaded from a
    /// luminance height field. This is a two-dimensional illustration, not depth recovery.
    static func poly(_ source: Raster, _ p: Parameters, _ progress: @Sendable (String) -> Void) throws -> Drawing {
        try Task.checkCancellation()
        progress("Measuring local photo detail…")
        let analysis=try PhotoAnalysis(source)
        let image=try analysis.preparedSource(source,background:p.sketchBackground)
        let w=Double(image.width),h=Double(image.height)
        let vertices=try adaptivePolyVertices(image,p,analysis:analysis)
        progress("Triangulating the photograph…")
        let mesh=try polyTriangulate(vertices,width:w,height:h)
        progress("Coloring and lighting facets…")
        var facets=[Facet]();facets.reserveCapacity(mesh.count)
        for (index,triangle) in mesh.enumerated() {
            if index%32==0 { try Task.checkCancellation() }
            let face=[vertices[triangle.a],vertices[triangle.b],vertices[triangle.c]]
            let average=try polyAverage(image,face)
            let shade=polyShade(image,face,relief:p.relief)
            func tone(_ value: Double) -> Double { 1-pow(1-value,1/p.gamma) }
            let color=p.color ? Pixel(tone(average.r),tone(average.g),tone(average.b)) : Pixel(tone(average.luminance),tone(average.luminance),tone(average.luminance))
            facets.append(Facet(vertices:face,color:Pixel(min(1,max(0,color.r*shade)),min(1,max(0,color.g*shade)),min(1,max(0,color.b*shade)))))
        }
        return Drawing(width:image.width,height:image.height,layers:[Layer(ink:.black,centers:vertices,points:[],strokes:[],facets:facets)],parameters:p)
    }

    // Adaptive rectangular regions contribute corners and centers to a single
    // conforming triangulation. RGB variance and shared boundary energy measure detail; splitting
    // the highest-error region allocates small facets where they matter most.
    static func adaptivePolyVertices(_ image:Raster,_ p:Parameters,analysis supplied:PhotoAnalysis?=nil) throws -> [Point] {
        let analysis=try supplied ?? PhotoAnalysis(image)
        let fw=analysis.image.width,fh=analysis.image.height,fs=fw+1
        var features=[Double](repeating:0,count:(fw+1)*(fh+1))
        for y in 0..<fh {
            try Task.checkCancellation()
            var row=0.0
            for x in 0..<fw {
                row+=analysis.featureEnergy[y*fw+x]
                features[(y+1)*fs+x+1]=features[y*fs+x+1]+row
            }
        }
        func featureMean(_ x0:Int,_ y0:Int,_ x1:Int,_ y1:Int)->Double {
            let a=max(0,min(fw-1,Int(Double(x0)/analysis.sx))),b=max(0,min(fh-1,Int(Double(y0)/analysis.sy)))
            let c=max(a+1,min(fw,Int(ceil(Double(x1)/analysis.sx)))),d=max(b+1,min(fh,Int(ceil(Double(y1)/analysis.sy))))
            return (features[d*fs+c]-features[b*fs+c]-features[d*fs+a]+features[b*fs+a])/Double((c-a)*(d-b))
        }
        let width=image.width,height=image.height,stride=width+1,count=(width+1)*(height+1)
        var red=Array(repeating:0.0,count:count),green=red,blue=red,square=red
        for y in 0..<height {
            try Task.checkCancellation()
            var r=0.0,g=0.0,b=0.0,s=0.0
            for x in 0..<width {
                let pixel=image.pixels[y*width+x];r+=pixel.r;g+=pixel.g;b+=pixel.b;s+=pixel.r*pixel.r+pixel.g*pixel.g+pixel.b*pixel.b
                let i=(y+1)*stride+x+1,above=y*stride+x+1
                red[i]=red[above]+r;green[i]=green[above]+g;blue[i]=blue[above]+b;square[i]=square[above]+s
            }
        }
        struct Cell { let x0:Int,y0:Int,x1:Int,y1:Int;var priority:Double }
        func sum(_ field:[Double],_ x0:Int,_ y0:Int,_ x1:Int,_ y1:Int)->Double {
            field[y1*stride+x1]-field[y0*stride+x1]-field[y1*stride+x0]+field[y0*stride+x0]
        }
        func cell(_ x0:Int,_ y0:Int,_ x1:Int,_ y1:Int)->Cell {
            let area=Double((x1-x0)*(y1-y0))
            let r=sum(red,x0,y0,x1,y1)/area,g=sum(green,x0,y0,x1,y1)/area,b=sum(blue,x0,y0,x1,y1)/area
            let variance=max(0,(sum(square,x0,y0,x1,y1)/area-r*r-g*g-b*b)/3)
            let detail=p.polyAdaptation==0 ? 1 : pow(variance+0.6*featureMean(x0,y0,x1,y1),p.polyAdaptation*1.5)
            return Cell(x0:x0,y0:y0,x1:x1,y1:y1,priority:area*(detail+0.00004))
        }
        var cells=[cell(0,0,width,height)]
        let budget=Int(48+1800*p.polyDetail)
        while cells.count<budget {
            try Task.checkCancellation()
            guard let i=cells.indices.max(by:{cells[$0].priority<cells[$1].priority}),cells[i].priority>=0 else { break }
            let parent=cells[i],dx=parent.x1-parent.x0,dy=parent.y1-parent.y0
            if dx<2 && dy<2 { cells[i].priority = -1;continue }
            let xs=dx>=2 ? [parent.x0,(parent.x0+parent.x1)/2,parent.x1] : [parent.x0,parent.x1]
            let ys=dy>=2 ? [parent.y0,(parent.y0+parent.y1)/2,parent.y1] : [parent.y0,parent.y1]
            let children=(xs.count-1)*(ys.count-1)
            if cells.count+children-1>budget { break }
            cells.remove(at:i)
            for y in 0..<ys.count-1 { for x in 0..<xs.count-1 { cells.append(cell(xs[x],ys[y],xs[x+1],ys[y+1])) } }
        }
        var vertices=[Point](),seen=Set<Int>()
        func insert(_ x:Double,_ y:Double) {
            let key=Int(x*2)+Int(y*2)*(width*2+1)
            if seen.insert(key).inserted { vertices.append(Point(x,y)) }
        }
        for c in cells {
            insert(Double(c.x0),Double(c.y0));insert(Double(c.x1),Double(c.y0));insert(Double(c.x1),Double(c.y1));insert(Double(c.x0),Double(c.y1))
            insert(Double(c.x0+c.x1)/2,Double(c.y0+c.y1)/2)
        }
        return vertices
    }

    private struct PolyTriangle { let a: Int;let b: Int;let c: Int }
    private struct PolyEdge: Hashable { let a: Int;let b: Int; init(_ x: Int,_ y: Int) { a=min(x,y);b=max(x,y) } }
    private static func polyCross(_ a: Point,_ b: Point,_ c: Point) -> Double { (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x) }
    private static func polyTriangulate(_ input: [Point],width: Double,height: Double) throws -> [PolyTriangle] {
        let span=max(width,height)*8,n=input.count
        let points=input+[Point(-span,-span),Point(span*3,-span),Point(-span,span*3)]
        var triangles=[PolyTriangle(a:n,b:n+1,c:n+2)]
        for index in input.indices {
            try Task.checkCancellation()
            let p=points[index]
            var boundary=[PolyEdge:Int](),kept=[PolyTriangle]()
            for (j,t) in triangles.enumerated() {
                if j%512==0 { try Task.checkCancellation() }
                let a=points[t.a],b=points[t.b],c=points[t.c]
                let ax=a.x-p.x,ay=a.y-p.y,bx=b.x-p.x,by=b.y-p.y,cx=c.x-p.x,cy=c.y-p.y
                let determinant=(ax*ax+ay*ay)*(bx*cy-by*cx)-(bx*bx+by*by)*(ax*cy-ay*cx)+(cx*cx+cy*cy)*(ax*by-ay*bx)
                if determinant>0 {
                    for edge in [PolyEdge(t.a,t.b),PolyEdge(t.b,t.c),PolyEdge(t.c,t.a)] { boundary[edge,default:0]+=1 }
                } else { kept.append(t) }
            }
            // Dictionary traversal is deliberately sorted for repeatable topology and exports.
            for edge in boundary.keys.sorted(by:{ $0.a == $1.a ? $0.b<$1.b : $0.a<$1.a }) where boundary[edge]==1 {
                let cross=polyCross(points[edge.a],points[edge.b],p)
                if abs(cross)>1e-10 { kept.append(cross>0 ? PolyTriangle(a:edge.a,b:edge.b,c:index) : PolyTriangle(a:edge.b,b:edge.a,c:index)) }
            }
            triangles=kept
        }
        return triangles.filter { $0.a<n && $0.b<n && $0.c<n }
    }
    private static func polyAverage(_ image: Raster,_ face: [Point]) throws -> Pixel {
        let a=face[0],b=face[1],c=face[2]
        let x0=max(0,Int(floor(min(a.x,b.x,c.x)))),x1=min(image.width-1,Int(ceil(max(a.x,b.x,c.x))))
        let y0=max(0,Int(floor(min(a.y,b.y,c.y)))),y1=min(image.height-1,Int(ceil(max(a.y,b.y,c.y))))
        var r=0.0,g=0.0,blue=0.0,count=0.0
        if x0<=x1 && y0<=y1 {
            for y in y0...y1 {
                if y%32==0 { try Task.checkCancellation() }
                for x in x0...x1 {
                    let q=Point(Double(x)+0.5,Double(y)+0.5)
                    if polyCross(a,b,q)>=0 && polyCross(b,c,q)>=0 && polyCross(c,a,q)>=0 {
                        let pixel=image.pixels[y*image.width+x];r+=pixel.r;g+=pixel.g;blue+=pixel.b;count+=1
                    }
                }
            }
        }
        return count>0 ? Pixel(r/count,g/count,blue/count) : image.pixels[image.index(Point((a.x+b.x+c.x)/3,(a.y+b.y+c.y)/3))]
    }
    private static func polyShade(_ image: Raster,_ face: [Point],relief: Double) -> Double {
        if relief==0 { return 1 }
        let a=face[0],b=face[1],c=face[2],height=Double(min(image.width,image.height))*0.18
        let za=image.pixels[image.index(a)].luminance*height,zb=image.pixels[image.index(b)].luminance*height,zc=image.pixels[image.index(c)].luminance*height
        let ux=b.x-a.x,uy=b.y-a.y,uz=zb-za,vx=c.x-a.x,vy=c.y-a.y,vz=zc-za
        let nx=uy*vz-uz*vy,ny=uz*vx-ux*vz,nz=ux*vy-uy*vx
        let length=sqrt(nx*nx+ny*ny+nz*nz)
        guard length>0 else { return 1 }
        let illumination=max(0,(-0.35*nx-0.45*ny+0.82*nz)/length)/sqrt(0.35*0.35+0.45*0.45+0.82*0.82)
        let flat=0.82/sqrt(0.35*0.35+0.45*0.45+0.82*0.82)
        let factor=max(0.45,min(1.3,(0.35+0.65*illumination)/(0.35+0.65*flat)))
        return 1+relief*(factor-1)
    }
}
