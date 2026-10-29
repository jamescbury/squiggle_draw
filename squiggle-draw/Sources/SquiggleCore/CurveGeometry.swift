import Foundation

extension Engine {
    /// Drop subpixel sampling redundancy without moving endpoints or erasing turns.
    /// Bounded windows keep simplification linear even for million-point scribbles.
    static func compactCurve(_ points:[Point],tolerance:Double) throws ->[Point] {
        guard points.count>2,tolerance>0 else { return points }
        var result=[points[0]],start=0
        let squared=tolerance*tolerance
        while start<points.count-1 {
            if start%4096==0 { try Task.checkCancellation() }
            let end=min(points.count-1,start+64)
            var retained=[Bool](repeating:false,count:end-start+1)
            retained[0]=true;retained[end-start]=true
            var ranges=[(start,end)]
            while let (lo,hi)=ranges.popLast() {
                if hi-lo<2 { continue }
                let a=points[lo],b=points[hi],dx=b.x-a.x,dy=b.y-a.y,length=dx*dx+dy*dy
                var furthest=0,maximum=squared
                for index in lo+1..<hi {
                    let q=points[index]
                    let t=length>0 ? min(1,max(0,((q.x-a.x)*dx+(q.y-a.y)*dy)/length)) : 0
                    let ex=q.x-a.x-t*dx,ey=q.y-a.y-t*dy,distance=ex*ex+ey*ey
                    if distance>maximum { maximum=distance;furthest=index }
                }
                if furthest>0 {
                    retained[furthest-start]=true
                    ranges.append((lo,furthest));ranges.append((furthest,hi))
                }
            }
            for index in start+1...end where retained[index-start] { result.append(points[index]) }
            start=end
        }
        return result
    }
}
