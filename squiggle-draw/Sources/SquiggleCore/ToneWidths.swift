import Foundation

extension Engine {
    /// Width follows pigment under the actual pen, rather than just the loop's
    /// center. Adjacent width runs share their exact endpoint and remain one
    /// gesture in playback. Standard SVG stroke widths also render in browsers.
    static func toneWidths(_ drawing:Drawing,_ image:Raster) throws ->Drawing {
        let p=drawing.parameters
        let prepared=try PhotoAnalysis(image).preparedSource(image,background:p.sketchBackground)
        let source=try shadedSource(prepared,depth:p.sketchShading)
        let scale=Double(max(image.width,image.height))/1600
        let baseCount=drawing.layers.reduce(0) { $0+$1.strokes.count }
        // Leave space for color-round boundaries and SVG groups in BOOX's
        // element budget. This bound does not discard or reorder geometry.
        let budget=max(1,14000-baseCount)
        let length=drawing.layers.reduce(0) { $0+$1.length }
        let minimumRun=max(6*scale,length/Double(budget))
        var layers=[Layer]()
        for layer in drawing.layers {
            let pigment=try inkWeights(source,layer.ink,p,(0...255).map { Double($0)/255 })
            let runs=try widthRuns(layer.strokes,minimumRun:minimumRun,minimum:0.35,maximum:p.shadowWidth) { q in
                0.35+(p.shadowWidth-0.35)*pow(bilinear(pigment,image,q),1.6)
            }
            layers.append(Layer(ink:layer.ink,centers:layer.centers,points:runs.strokes.flatMap{$0},strokes:runs.strokes,widthFactors:runs.factors))
        }
        return Drawing(width:drawing.width,height:drawing.height,layers:layers,parameters:p)
    }

    static func widthRuns(_ strokes:[[Point]],minimumRun:Double,minimum:Double=1,maximum:Double,width:(Point)->Double) throws ->(strokes:[[Point]],factors:[Double]) {
        var output=[[Point]](),factors=[Double]()
        let step=max(0.001,(maximum-minimum)/8)
        func quantize(_ value:Double)->Double { min(maximum,max(minimum,minimum+((value-minimum)/step).rounded()*step)) }
        for stroke in strokes {
            guard let first=stroke.first,stroke.count>1 else { continue }
            var part=[first],previous=first,smooth=width(first),factor=quantize(smooth),length=0.0
            for (i,q) in stroke.dropFirst().enumerated() {
                if i%1024==0 { try Task.checkCancellation() }
                let distance=previous.distance(q)
                smooth += (width(q)-smooth)*(1-exp(-distance/max(1,minimumRun*0.3)))
                part.append(q);length+=distance
                // Hysteresis prevents flicker around bin boundaries.
                if length>=minimumRun && abs(smooth-factor)>step*0.75 {
                    output.append(part);factors.append(factor)
                    part=[q];length=0;factor=quantize(smooth)
                }
                previous=q
            }
            if part.count>1 { output.append(part);factors.append(factor) }
        }
        return (output,factors)
    }
}
