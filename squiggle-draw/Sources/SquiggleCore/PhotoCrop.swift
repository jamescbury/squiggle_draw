import CoreGraphics
import Foundation

extension Raster {
    /// Normalized, top-left image coordinates. Copies pixels without resampling.
    public func cropped(to rect:CGRect) throws ->Raster {
        guard [rect.origin.x,rect.origin.y,rect.width,rect.height].allSatisfy(\.isFinite),
              rect.width>0,rect.height>0 else { throw DrawError.invalidImage }
        let clipped=rect.intersection(CGRect(x:0,y:0,width:1,height:1))
        guard !clipped.isNull,!clipped.isEmpty else { throw DrawError.invalidImage }
        let left=max(0,Int(floor(clipped.minX*Double(width))))
        let top=max(0,Int(floor(clipped.minY*Double(height))))
        let right=min(width,Int(ceil(clipped.maxX*Double(width))))
        let bottom=min(height,Int(ceil(clipped.maxY*Double(height))))
        guard right-left>=2,bottom-top>=2 else { throw DrawError.invalidImage }
        var result=[Pixel]();result.reserveCapacity((right-left)*(bottom-top))
        for y in top..<bottom { result.append(contentsOf:pixels[(y*width+left)..<(y*width+right)]) }
        return try Raster(width:right-left,height:bottom-top,pixels:result)
    }
}
