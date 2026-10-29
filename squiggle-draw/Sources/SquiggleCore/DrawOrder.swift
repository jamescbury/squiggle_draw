import Foundation

extension Engine {
    /// Interleave complete independent marks. Continuous styles stay intact;
    /// their page-spanning route is established before curve synthesis.
    static func spreadOrder(_ drawing:Drawing) throws -> Drawing {
        // Form and hatching establish light structure before deepening shadows.
        if drawing.parameters.style == .formSketch || drawing.parameters.style == .crossHatch { return drawing }
        var layers=[Layer]()
        for layer in drawing.layers {
            try Task.checkCancellation()
            if !layer.widthFactors.isEmpty { layers.append(layer);continue }
            var strokes=[[Point]]()
            strokes=layer.strokes
            let ordered=try spatialOrder(strokes,width:drawing.width,height:drawing.height,seed:drawing.parameters.seed) { stroke in
                guard !stroke.isEmpty else { return Point(0,0) }
                // Bounding-box center avoids a circular line's repeated turns
                // over-weighting one end of a stroke.
                var x0=stroke[0].x,x1=x0,y0=stroke[0].y,y1=y0
                for q in stroke { x0=min(x0,q.x);x1=max(x1,q.x);y0=min(y0,q.y);y1=max(y1,q.y) }
                return Point((x0+x1)/2,(y0+y1)/2)
            }
            let dots=try spatialOrder(layer.dots,width:drawing.width,height:drawing.height,seed:drawing.parameters.seed){$0.center}
            let facets=try spatialOrder(layer.facets,width:drawing.width,height:drawing.height,seed:drawing.parameters.seed) { f in
                let n=Double(max(1,f.vertices.count));return Point(f.vertices.reduce(0){$0+$1.x}/n,f.vertices.reduce(0){$0+$1.y}/n)
            }
            layers.append(Layer(ink:layer.ink,centers:layer.centers,points:ordered.flatMap{$0},strokes:ordered,dots:dots,facets:facets))
        }
        return Drawing(width:drawing.width,height:drawing.height,layers:layers,parameters:drawing.parameters)
    }
    static func spatialOrder<T>(_ values:[T],width:Int,height:Int,seed:UInt64,position:(T)->Point) throws -> [T] {
        guard values.count>1 else { return values }
        let side=8
        var buckets=Array(repeating:[Int](),count:side*side)
        for (i,value) in values.enumerated() {
            if i%512==0 { try Task.checkCancellation() }
            let p=position(value),x=max(0,min(side-1,Int(p.x/Double(width)*Double(side)))),y=max(0,min(side-1,Int(p.y/Double(height)*Double(side))))
            buckets[y*side+x].append(i)
        }
        var random=Random(state:seed),ranked=[(index:Int,priority:Double)]()
        ranked.reserveCapacity(values.count)
        // Random order with a gentle regional balance. No fixed cell cycle or
        // top-to-bottom sweep survives into drawing order.
        for var bucket in buckets where !bucket.isEmpty {
            try Task.checkCancellation()
            if bucket.count>1 { for i in stride(from:bucket.count-1,through:1,by:-1) { if i%512==0 { try Task.checkCancellation() };bucket.swapAt(i,Int(random.unit()*Double(i+1))) } }
            for (k,id) in bucket.enumerated() {
                if k%512==0 { try Task.checkCancellation() }
                let priority=(Double(k)+random.unit())/Double(bucket.count)+random.unit()*0.2
                ranked.append((id,priority))
            }
        }
        ranked.sort{$0.priority==$1.priority ? $0.index<$1.index : $0.priority<$1.priority}
        return ranked.map{values[$0.index]}
    }
}
