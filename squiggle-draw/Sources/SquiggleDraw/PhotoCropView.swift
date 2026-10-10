import SwiftUI
import SquiggleCore

/// Selection is stored in image coordinates, independent of the fitted preview size.
struct PhotoCropView:View {
    let source:Raster
    let image:NSImage
    let finish:(CGRect?)->Void
    @State private var selection:CGRect
    init(source:Raster,selection:CGRect,finish:@escaping (CGRect?)->Void) {
        self.source=source;self.image=Studio.image(source);self.finish=finish
        _selection=State(initialValue:selection)
    }
    private var dimensions:(Int,Int) {
        (Int(ceil(selection.maxX*Double(source.width)))-Int(floor(selection.minX*Double(source.width))),
         Int(ceil(selection.maxY*Double(source.height)))-Int(floor(selection.minY*Double(source.height))))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Crop photo").font(.title2.bold())
            Text("Drag a box around the area to keep. Drag again to change it. The workspace will fit your crop.").foregroundStyle(.secondary)
            GeometryReader { geo in
                let fit=min(geo.size.width/Double(source.width),geo.size.height/Double(source.height))
                let size=CGSize(width:Double(source.width)*fit,height:Double(source.height)*fit)
                let box=CGRect(x:selection.minX*size.width,y:selection.minY*size.height,width:selection.width*size.width,height:selection.height*size.height)
                ZStack(alignment:.topLeading) {
                    Image(nsImage:image).resizable().frame(width:size.width,height:size.height)
                    Path { path in path.addRect(CGRect(origin:.zero,size:size));path.addRect(box) }
                        .fill(.black.opacity(0.5),style:FillStyle(eoFill:true))
                    Rectangle().stroke(.white,lineWidth:2).frame(width:box.width,height:box.height).offset(x:box.minX,y:box.minY)
                    Path { path in
                        for fraction in [1.0/3,2.0/3] {
                            path.move(to:CGPoint(x:box.minX+box.width*fraction,y:box.minY));path.addLine(to:CGPoint(x:box.minX+box.width*fraction,y:box.maxY))
                            path.move(to:CGPoint(x:box.minX,y:box.minY+box.height*fraction));path.addLine(to:CGPoint(x:box.maxX,y:box.minY+box.height*fraction))
                        }
                    }.stroke(.white.opacity(0.5),lineWidth:1)
                }
                .frame(width:size.width,height:size.height).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:2).onChanged { value in
                    let a=clamp(value.startLocation,size:size),b=clamp(value.location,size:size)
                    selection=CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(b.x-a.x),height:abs(b.y-a.y))
                })
                .accessibilityLabel("Photo crop area")
                .frame(maxWidth:.infinity,maxHeight:.infinity)
            }.frame(height:460).background(Color.black.opacity(0.07))
            HStack {
                Button("Use full photo") {selection=CGRect(x:0,y:0,width:1,height:1)}
                Text("\(dimensions.0) × \(dimensions.1) pixels").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Cancel") {finish(nil)}.keyboardShortcut(.cancelAction)
                Button("Apply crop") {finish(selection)}.keyboardShortcut(.defaultAction)
                    .disabled(dimensions.0<2 || dimensions.1<2 || selection.width<=0 || selection.height<=0)
            }
        }.padding(24).frame(width:720)
    }
    private func clamp(_ point:CGPoint,size:CGSize)->CGPoint {
        CGPoint(x:min(1,max(0,point.x/size.width)),y:min(1,max(0,point.y/size.height)))
    }
}
