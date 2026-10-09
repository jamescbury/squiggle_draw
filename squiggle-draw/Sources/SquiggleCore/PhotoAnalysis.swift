import Foundation

/// Bounded shared image structure and source-coordinate transforms.
struct PhotoAnalysis: Sendable {
    let image:Raster
    let sx:Double,sy:Double
    let luminance:[Double],smooth:[Double],gx:[Double],gy:[Double],edge:[Double]
    let tx:[Double],ty:[Double],background:[Double]
    let featureEnergy:[Double]
    private let preparedBackground:[Double]
    init(_ source:Raster) throws {
        let scale=min(1,720/Double(max(source.width,source.height)))
        let w=max(2,Int(Double(source.width)*scale)),h=max(2,Int(Double(source.height)*scale))
        sx=Double(source.width-1)/Double(w-1);sy=Double(source.height-1)/Double(h-1)
        var pixels=[Pixel]();pixels.reserveCapacity(w*h)
        for y in 0..<h {
            try Task.checkCancellation()
            for x in 0..<w { pixels.append(source.pixels[source.index(Point(Double(x)*sx,Double(y)*sy))]) }
        }
        image=try Raster(width:w,height:h,pixels:pixels)
        luminance=pixels.map(\.luminance)
        smooth=try Self.blur(luminance,w,h,2)
        let fine=try Self.blur(luminance,w,h,1)
        var dx=[Double](repeating:0,count:w*h),dy=dx,magnitude=dx
        for y in 1..<h-1 { for x in 1..<w-1 {
            let i=y*w+x;dx[i]=(fine[i+1]-fine[i-1])*0.5;dy[i]=(fine[i+w]-fine[i-w])*0.5;magnitude[i]=hypot(dx[i],dy[i])
        } }
        gx=dx;gy=dy;edge=magnitude
        // Color boundaries can be invisible in luminance (for example red/green).
        var features=magnitude
        for channel in [pixels.map(\.r),pixels.map(\.g),pixels.map(\.b)] {
            let color=try Self.blur(channel,w,h,1)
            for y in 1..<h-1 {
                try Task.checkCancellation()
                for x in 1..<w-1 {
                    let i=y*w+x
                    features[i]=max(features[i],hypot((color[i+1]-color[i-1])*0.5,(color[i+w]-color[i-w])*0.5))
                }
            }
        }
        featureEnergy=features
        let xx=try Self.blur(dx.map{$0*$0},w,h,5),yy=try Self.blur(dy.map{$0*$0},w,h,5)
        let xy=try Self.blur(zip(dx,dy).map{$0*$1},w,h,5)
        var fx=dx,fy=dy
        for i in fx.indices {
            let difference=xx[i]-yy[i],cross=2*xy[i],strength=hypot(difference,cross)
            let coherence=strength/max(1e-8,xx[i]+yy[i])
            let confidence=coherence*min(1,strength/0.00008)
            let base = -Double.pi/4+0.14*sin(Double(i%w)/110)+0.12*sin(Double(i/w)/150)
            // Double-angle representation makes the line field insensitive to sign.
            fx[i] = -difference/max(1e-9,strength)*confidence+cos(2*base)*(1-confidence)
            fy[i] = -cross/max(1e-9,strength)*confidence+sin(2*base)*(1-confidence)
        }
        tx=fx;ty=fy
        // Find the dominant border color, then retain only connected matching areas.
        var bins=[Int:[Int]]()
        for y in 0..<h { for x in 0..<w where x==0 || y==0 || x==w-1 || y==h-1 {
            let i=y*w+x,p=pixels[i],key=Int(p.r*7)*64+Int(p.g*7)*8+Int(p.b*7)
            bins[key,default:[]].append(i)
        } }
        let dominant=bins.keys.sorted().max{ a,b in bins[a]!.count<bins[b]!.count }!
        let sites=bins[dominant]!,n=Double(sites.count)
        let mean=Pixel(sites.reduce(0){$0+pixels[$1].r}/n,sites.reduce(0){$0+pixels[$1].g}/n,sites.reduce(0){$0+pixels[$1].b}/n)
        var mask=[Double](repeating:0,count:w*h),queue=[Int]()
        func matches(_ i:Int)->Bool { let p=pixels[i];return magnitude[i]<0.012 && sqrt(pow(p.r-mean.r,2)+pow(p.g-mean.g,2)+pow(p.b-mean.b,2))<0.22 }
        for y in 0..<h { for x in 0..<w where x==0 || y==0 || x==w-1 || y==h-1 {
            let i=y*w+x;if matches(i) { mask[i]=1;queue.append(i) }
        } }
        var head=0
        while head<queue.count {
            if head%4096==0 { try Task.checkCancellation() }
            let i=queue[head];head+=1
            for j in [i%w>0 ? i-1 : i,i%w<w-1 ? i+1 : i,i>=w ? i-w : i,i<(h-1)*w ? i+w : i] where mask[j]==0 && matches(j) { mask[j]=1;queue.append(j) }
        }
        background=try Self.blur(mask,w,h,3)
        // Keep the original field for Form's established geometry, but protect
        // chromatic edges as well when preparing the other styles' photographs.
        mask=Array(repeating:0,count:w*h);queue.removeAll(keepingCapacity:true)
        func colorMatches(_ i:Int)->Bool { matches(i) && features[i]<0.012 }
        for y in 0..<h { for x in 0..<w where x==0 || y==0 || x==w-1 || y==h-1 {
            let i=y*w+x;if colorMatches(i) { mask[i]=1;queue.append(i) }
        } }
        head=0
        while head<queue.count {
            if head%4096==0 { try Task.checkCancellation() }
            let i=queue[head];head+=1
            for j in [i%w>0 ? i-1 : i,i%w<w-1 ? i+1 : i,i>=w ? i-w : i,i<(h-1)*w ? i+w : i] where mask[j]==0 && colorMatches(j) { mask[j]=1;queue.append(j) }
        }
        preparedBackground=try Self.blur(mask,w,h,3)
    }
    static func blur(_ source:[Double],_ w:Int,_ h:Int,_ radius:Int) throws ->[Double] {
        var horizontal=source,result=source
        for y in 0..<h {
            if y%32==0 { try Task.checkCancellation() }
            var sum=0.0
            for x in 0..<w {
                if x==0 { for k in 0...min(w-1,radius) { sum+=source[y*w+k] } }
                else { if x+radius<w { sum+=source[y*w+x+radius] };if x-radius-1>=0 { sum-=source[y*w+x-radius-1] } }
                horizontal[y*w+x]=sum/Double(min(w-1,x+radius)-max(0,x-radius)+1)
            }
        }
        for x in 0..<w {
            if x%32==0 { try Task.checkCancellation() }
            var sum=0.0
            for y in 0..<h {
                if y==0 { for k in 0...min(h-1,radius) { sum+=horizontal[k*w+x] } }
                else { if y+radius<h { sum+=horizontal[(y+radius)*w+x] };if y-radius-1>=0 { sum-=horizontal[(y-radius-1)*w+x] } }
                result[y*w+x]=sum/Double(min(h-1,y+radius)-max(0,y-radius)+1)
            }
        }
        return result
    }
    func output(_ q:Point)->Point { Point(q.x*sx,q.y*sy) }
    func sourcePoint(_ q:Point)->Point { output(q) }
    func fieldPoint(_ q:Point)->Point { Point(q.x/sx,q.y/sy) }

    /// Fade connected background toward paper without changing ink proportions.
    /// Flat swatches remain useful tone inputs rather than disappearing entirely.
    func preparedSource(_ source:Raster,background:Double) throws ->Raster {
        try Task.checkCancellation()
        guard background.isFinite && (0...1).contains(background) else { throw DrawError.invalidParameters }
        if background==1 { return source }
        var low=Pixel(1,1,1),high=Pixel(0,0,0)
        for (i,p) in source.pixels.enumerated() {
            if i%4096==0 { try Task.checkCancellation() }
            low=Pixel(min(low.r,p.r),min(low.g,p.g),min(low.b,p.b))
            high=Pixel(max(high.r,p.r),max(high.g,p.g),max(high.b,p.b))
        }
        if max(high.r-low.r,high.g-low.g,high.b-low.b)<0.04 { return source }
        var pixels=source.pixels
        for i in pixels.indices {
            if i%4096==0 { try Task.checkCancellation() }
            let q=fieldPoint(Point(Double(i%source.width),Double(i/source.width)))
            let mask=min(1,max(0,Engine.bilinear(preparedBackground,image,q)))
            let retained=1-mask*(1-background),p=pixels[i]
            pixels[i]=Pixel(min(1,max(0,1-(1-p.r)*retained)),min(1,max(0,1-(1-p.g)*retained)),min(1,max(0,1-(1-p.b)*retained)))
        }
        return try Raster(width:source.width,height:source.height,pixels:pixels)
    }
}
