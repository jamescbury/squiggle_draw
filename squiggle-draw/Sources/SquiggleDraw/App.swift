import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import SquiggleCore

private enum AppVersion {
    static let label: String = {
        guard let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String else { return "Development build" }
        let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String
        return "v\(version)" + (build.map { " · build \($0)" } ?? "")
    }()
}

@main
struct SquiggleDrawApp: App {
    @StateObject private var model=Studio()
    var body: some Scene {
        WindowGroup("Squiggle Draw") { StudioView(model:model).frame(minWidth:980,minHeight:720).preferredColorScheme(.light) }
        .defaultSize(width:1200,height:850)
        .commands {
            CommandGroup(replacing:.newItem) { Button("Open Image…") { model.open() }.keyboardShortcut("o") }
        }
    }
}
@MainActor
final class Studio: ObservableObject {
    @Published var parameters:Parameters = { var p=Parameters();p.style = .formSketch;return (DisplayMedium(rawValue:UserDefaults.standard.string(forKey:"displayMedium") ?? "") ?? .eInk).applying(to:p) }()
    @Published var medium:DisplayMedium = DisplayMedium(rawValue:UserDefaults.standard.string(forKey:"displayMedium") ?? "") ?? .eInk
    @Published var artFinish="Pen drawing"
    func selectMedium(_ value:DisplayMedium) {
        cancel();invalidateDrawTest();medium=value;UserDefaults.standard.set(value.rawValue,forKey:"displayMedium");parameters=value.applying(to:parameters);enabled=Set(Ink.allCases)
        testCanvasWidth=value.isEInk ? 800 : 1920;testCanvasHeight=value.isEInk ? 1100 : 1080
        optimizationSummary="";status="Preset applied · regenerate to use these settings"
    }
    @Published var raster: Raster?
    @Published var cropSource: Raster?
    @Published var cropRect=CGRect(x:0,y:0,width:1,height:1)
    var hasCrop:Bool { cropRect != CGRect(x:0,y:0,width:1,height:1) }
    @Published var original: NSImage?
    @Published var drawing: Drawing?
    @Published var busy=false
    @Published var status="Open a photograph to begin"
    @Published var error: String?
    @Published var name="Untitled"
    @Published var mode="Scribble"
    @Published var zoom=1.0
    @Published var enabled=Set(Ink.allCases)
    @Published var autoOptimize=true
    @Published var optimizationSummary=""
    @Published var testPlan:DrawTestPlan?
    @Published var testState=DrawTestState()
    @Published var testPlaying=false
    @Published var testPreparing=false
    @Published var testNote=""
    @Published var testSpeed=70.0
    @Published var testPenWidth=1.0
    @Published var testAcceleration=500.0
    @Published var testCanvasWidth=800.0
    @Published var testCanvasHeight=1100.0
    var testWork:Task<Void,Never>?
    var testClock:Task<Void,Never>?
    var testToken=0
    var lastTestTick=Date()
    var work: Task<Void,Never>?
    var token=0
    var outdated: Bool { drawing.map { $0.parameters != parameters } ?? false }
    func cancel() { pauseDrawTest();token+=1;work?.cancel();work=nil;busy=false;status="Cancelled · previous drawing kept" }
    func open() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.png,.jpeg,.tiff,.heic];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else { return }
        open(url)
    }
    func openSample(_ filename:String) {
        let resources=Bundle.main.resourceURL?.appendingPathComponent("SquiggleDraw_SquiggleDraw.bundle")
        let samples=resources.flatMap { Bundle(url:$0) } ?? Bundle.module
        guard let url=samples.url(forResource:filename,withExtension:"png",subdirectory:"Samples") else { error="The sample images are missing. Reinstall this app build.";return }
        open(url)
    }
    func open(_ url:URL) {
        cancel();busy=true;status="Opening image…";error=nil
        let request=token
        work=Task { [weak self] in
            do {
                let image=try await Task.detached(priority:.userInitiated) { try Self.decode(url) }.value
                guard let self,self.token==request,!Task.isCancelled else { return }
                self.cropSource=image;self.cropRect=CGRect(x:0,y:0,width:1,height:1);self.zoom=1
                self.raster=image
                self.original=Self.image(image)
                self.invalidateDrawTest();self.drawing=nil;self.optimizationSummary="";self.name=url.deletingPathExtension().lastPathComponent
                self.busy=false;self.status="\(image.width) × \(image.height) · ready to generate";self.mode="Original"
                if self.autoOptimize { self.optimize() }
            } catch {
                guard let self,self.token==request else { return }
                self.busy=false;self.error=error.localizedDescription;self.status="Could not open image"
            }
        }
    }
    func applyCrop(_ rect:CGRect) {
        guard let source=cropSource else { return }
        do {
            let cropped=try source.cropped(to:rect)
            cancel();invalidateDrawTest();drawing=nil;optimizationSummary="";error=nil
            cropRect=rect;raster=cropped;original=Self.image(cropped);zoom=1;mode="Original"
            status="\(cropped.width) × \(cropped.height) · ready to generate"
            if autoOptimize { optimize() }
        } catch { self.error="Choose a larger crop area." }
    }
    nonisolated static func decode(_ url: URL) throws -> Raster {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let metadata=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let w=metadata[kCGImagePropertyPixelWidth] as? Int,let h=metadata[kCGImagePropertyPixelHeight] as? Int,w>=2,h>=2,w<=50000,h<=50000,
              let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1600,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { throw DrawError.invalidImage }
        let width=cg.width,height=cg.height
        var bytes=[UInt8](repeating:255,count:width*height*4)
        let good=bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx=CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            ctx.setFillColor(NSColor.white.cgColor);ctx.fill(CGRect(x:0,y:0,width:width,height:height))
            ctx.draw(cg,in:CGRect(x:0,y:0,width:width,height:height));return true
        }
        guard good else { throw DrawError.invalidImage }
        let pixels=stride(from:0,to:bytes.count,by:4).map { Pixel(Double(bytes[$0])/255,Double(bytes[$0+1])/255,Double(bytes[$0+2])/255) }
        return try Raster(width:width,height:height,pixels:pixels)
    }
    static func image(_ raster: Raster) -> NSImage {
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:raster.width,pixelsHigh:raster.height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:raster.width*4,bitsPerPixel:32)!
        for (i,p) in raster.pixels.enumerated() {
            rep.bitmapData![4*i]=UInt8(p.r*255);rep.bitmapData![4*i+1]=UInt8(p.g*255);rep.bitmapData![4*i+2]=UInt8(p.b*255);rep.bitmapData![4*i+3]=255
        }
        let image=NSImage(size:NSSize(width:raster.width,height:raster.height));image.addRepresentation(rep);return image
    }
    func optimize() {
        guard let raster else { return }
        cancel();error=nil;busy=true;status="Optimizing for this photo…"
        let request=token,settings=parameters
        work=Task { [weak self] in
            let task=Task.detached(priority:.userInitiated) { try Engine.optimize(raster,parameters:settings) }
            do {
                let result=try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
                guard let self,self.token==request,!Task.isCancelled else { return }
                guard self.parameters==settings else { self.busy=false;self.status="Settings changed · choose Optimize photo again";return }
                self.parameters=result.parameters;self.optimizationSummary=result.summary
                self.busy=false;self.generate()
            } catch {
                guard let self,self.token==request else { return }
                self.busy=false;self.error=error.localizedDescription;self.status="Optimization could not finish"
            }
        }
    }
    func generate() {
        guard let raster else { return }
        cancel();error=nil;busy=true;status="Preparing drawing…";let request=token,settings=parameters
        work=Task { [weak self] in
            let studio=self
            let task=Task.detached(priority:.userInitiated) {
                try Engine.generate(raster,parameters:settings) { stage in
                    Task { @MainActor in if let studio,studio.token==request { studio.status=stage } }
                }
            }
            do {
                let result=try await withTaskCancellationHandler(operation: { try await task.value },onCancel: { task.cancel() })
                guard let self,self.token==request,!Task.isCancelled else { return }
                self.invalidateDrawTest();self.drawing=result;self.busy=false;self.mode="Scribble";self.zoom=1
                let count=result.drawingLayers(inks:Set(Ink.allCases)).reduce(0) { sum,layer in
                    let strokes=layer.strokes.filter { !$0.isEmpty }
                    let gestures=strokes.indices.filter { i in layer.widthFactors.isEmpty || i==0 || strokes[i-1].last != strokes[i].first }.count
                    return sum+gestures+layer.dots.count+layer.facets.count
                }
                let unit=settings.style == .stipple ? "dots" : settings.style == .poly ? "facets" : "paths"
                self.status=result.layers.isEmpty ? "No ink needed · image is white" : "Ready · \(count.formatted()) \(unit)"
            } catch {
                guard let self,self.token==request else { return }
                self.busy=false;self.error=error.localizedDescription;self.status="Drawing could not be generated"
            }
        }
    }
    func exportSVG(only: Ink? = nil) {
        guard let drawing else { return }
        let inks=drawing.parameters.style == .poly ? Set([Ink.black]) : only.map { Set([$0]) } ?? enabled
        guard drawing.layers.contains(where:{ inks.contains($0.ink) && $0.hasArtwork }) else { error="Enable an ink layer containing strokes before exporting.";return }
        let panel=NSSavePanel();panel.allowedContentTypes=[.svg];panel.nameFieldStringValue="\(name)-\(only?.rawValue ?? "squiggle").svg"
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do { try drawing.svg(inks:inks).write(to:url,atomically:true,encoding:.utf8);status="Saved \(url.lastPathComponent)" } catch { self.error=error.localizedDescription }
    }
    func exportPNG() {
        guard let drawing else { return }
        let panel=NSSavePanel();panel.allowedContentTypes=[.png];panel.nameFieldStringValue="\(name)-squiggle.png"
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do {
            let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:drawing.width,pixelsHigh:drawing.height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:drawing.width*4,bitsPerPixel:32)!
            guard let context=NSGraphicsContext(bitmapImageRep:rep) else { throw DrawError.invalidImage }
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
            let ctx=context.cgContext
            ctx.setFillColor(NSColor.white.cgColor);ctx.fill(CGRect(x:0,y:0,width:drawing.width,height:drawing.height))
            ctx.translateBy(x:0,y:CGFloat(drawing.height));ctx.scaleBy(x:1,y:-1)
            render(drawing,in:ctx,inks:enabled,tracing:false)
            NSGraphicsContext.restoreGraphicsState()
            guard let data=rep.representation(using:.png,properties:[:]) else { throw DrawError.invalidImage }
            try data.write(to:url,options:.atomic);status="Saved \(url.lastPathComponent)"
        } catch { self.error=error.localizedDescription }
    }
}
func inkColor(_ ink: Ink) -> NSColor {
    switch ink { case .red: NSColor(srgbRed:221/255,green:48/255,blue:57/255,alpha:1)
    case .green: NSColor(srgbRed:33/255,green:139/255,blue:76/255,alpha:1)
    case .blue: NSColor(srgbRed:40/255,green:91/255,blue:215/255,alpha:1)
    case .black: NSColor(srgbRed:32/255,green:34/255,blue:31/255,alpha:1) }
}
func cgPath(_ points:[Point],closed:Bool=false) -> CGPath {
    let path=CGMutablePath();if let first=points.first { path.move(to:CGPoint(x:first.x,y:first.y));for p in points.dropFirst() { path.addLine(to:CGPoint(x:p.x,y:p.y)) };if closed { path.closeSubpath() } };return path
}
struct CachedLayer {
    let ink: Ink; let path: CGPath; let guide: CGPath; let dots: CGPath
    let facets: [(CGPath,Pixel)]
    let widths: [(CGPath,Double,Pixel?)]
    let coloredDots:[(CGPath,Pixel)]
    init(_ layer:Layer,style:DrawingStyle,spread:Bool=false) {
        widths=layer.widthFactors.isEmpty && layer.strokeColors.isEmpty ? [] : layer.strokes.enumerated().map { (cgPath($0.element),layer.widthFactor(at:$0.offset),layer.strokeColor(at:$0.offset)) }
        coloredDots=layer.dotColors.isEmpty ? [] : layer.dots.enumerated().map { i,dot in
            (CGPath(ellipseIn:CGRect(x:dot.center.x-dot.radius,y:dot.center.y-dot.radius,width:2*dot.radius,height:2*dot.radius),transform:nil),layer.dotColors[i])
        }
        ink=layer.ink;path=layerPath(layer,tracing:false,style:style);guide=layerPath(layer,tracing:true,style:style,spread:spread)
        let disks=CGMutablePath()
        for dot in layer.dots { disks.addEllipse(in:CGRect(x:dot.center.x-dot.radius,y:dot.center.y-dot.radius,width:2*dot.radius,height:2*dot.radius)) }
        dots=disks;facets=layer.facets.map { (cgPath($0.vertices,closed:true),$0.color) }
    }
}
func paint(_ layer:CachedLayer,in ctx:CGContext,parameters:Parameters,tracing:Bool) {
    ctx.setStrokeColor(inkColor(layer.ink).cgColor);ctx.setLineWidth(tracing ? 0.5 : parameters.penWidth)
    if !tracing && !layer.widths.isEmpty {
        for (path,factor,color) in layer.widths {
            ctx.setStrokeColor(color.map{CGColor(srgbRed:$0.r,green:$0.g,blue:$0.b,alpha:1)} ?? inkColor(layer.ink).cgColor)
            ctx.setLineWidth(parameters.penWidth*factor);ctx.addPath(path);ctx.strokePath()
        }
    } else { ctx.addPath(tracing ? layer.guide : layer.path);ctx.strokePath() }
    ctx.addPath(layer.dots)
    if tracing { ctx.strokePath() } else { ctx.setFillColor(inkColor(layer.ink).cgColor);
        if layer.coloredDots.isEmpty { ctx.fillPath() } else {
            ctx.beginPath()
            for (path,color) in layer.coloredDots { ctx.setFillColor(CGColor(srgbRed:color.r,green:color.g,blue:color.b,alpha:1));ctx.addPath(path);ctx.fillPath() }
        }
    }
    for (path,color) in layer.facets {
        ctx.addPath(path)
        if tracing || parameters.polyWireframe { ctx.setStrokeColor(inkColor(layer.ink).cgColor);ctx.setLineWidth(tracing ? 0.5 : parameters.penWidth);ctx.strokePath() }
        else {
            let fill=CGColor(srgbRed:color.r,green:color.g,blue:color.b,alpha:1)
            ctx.setFillColor(fill);ctx.setStrokeColor(fill);ctx.setLineWidth(0.25);ctx.drawPath(using:.fillStroke)
        }
    }
}
func render(_ drawing:Drawing,in ctx:CGContext,inks:Set<Ink>,tracing:Bool) {
    ctx.setLineCap(.round);ctx.setLineJoin(.round)
    let visible=drawing.parameters.style == .poly ? Set([Ink.black]) : inks
    let layers=tracing ? drawing.layers.filter{visible.contains($0.ink)} : drawing.drawingLayers(inks:visible)
    for layer in layers {
        paint(CachedLayer(layer,style:drawing.parameters.style,spread:drawing.parameters.spreadAcrossCanvas),in:ctx,parameters:drawing.parameters,tracing:tracing)
    }
}
func layerPath(_ layer:Layer,tracing:Bool,style:DrawingStyle,spread:Bool=false) -> CGPath {
    if tracing && (style == .formSketch || (spread && (style == .waves || style == .crossHatch))) && !layer.strokes.isEmpty {
        let guide=CGMutablePath()
        for stroke in layer.strokes { if let first=stroke.first,let last=stroke.last { guide.addPath(cgPath([first,last])) } }
        return guide
    }
    if tracing && (style == .circular || style == .flowing || style == .singleLine) { return cgPath(layer.centers,closed:true) }
    let path=CGMutablePath()
    if tracing && (style == .waves || style == .crossHatch) && layer.centers.count>=2 {
        for i in stride(from:0,to:layer.centers.count-1,by:2) { path.addPath(cgPath([layer.centers[i],layer.centers[i+1]])) }
    } else if !tracing { for stroke in layer.strokes { path.addPath(cgPath(stroke)) } }
    return path
}
struct StudioView: View {
    @ObservedObject var model: Studio
    @StateObject var library=BooxLibraryModel()
    @StateObject private var sequence=SequentialDrawingsModel()
    @State var tab="Draw"
    @State var cropping=false
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Image(systemName:"scribble.variable").font(.title).foregroundStyle(.green)
                Text("Squiggle Draw").font(.title2.weight(.semibold))
                Text(AppVersion.label).font(.caption).foregroundStyle(.secondary)
                    .help("Running app: " + Bundle.main.bundleURL.path)
                    .accessibilityLabel("Version " + AppVersion.label)
                Spacer();Text(model.name).foregroundStyle(.secondary).lineLimit(1)
            }.padding(22).background(.background)
            Divider()
            Picker("Workspace",selection:$tab) {
                Label("Draw",systemImage:"scribble.variable").tag("Draw")
                Label("Gallery",systemImage:"square.grid.2x2").tag("BOOX Library")
                Label("Sequential drawings",systemImage:"play.rectangle.on.rectangle").tag("Sequential drawings")
            }.pickerStyle(.segmented).frame(width:560).padding(12)
            Divider()
            if tab=="Draw" { drawingWorkspace }
            else if tab=="BOOX Library" { BooxLibraryView(library:library,studio:model) }
            else { SequentialDrawingsView(model:sequence,library:library) }

        }
        .sheet(isPresented:$cropping) {
            if let source=model.cropSource {
                PhotoCropView(source:source,selection:model.cropRect) { rect in
                    cropping=false
                    if let rect { model.applyCrop(rect) }
                }
            }
        }
        .onChange(of:tab) { if tab != "Draw" { model.pauseDrawTest() } }
        .onDisappear { model.cancel();model.invalidateDrawTest() }
        .onChange(of:model.enabled) { model.invalidateDrawTest();if model.mode=="Test the draw" { model.startDrawTest() } }
        .onChange(of:model.mode) { if model.mode=="Test the draw" && model.testPlan==nil && !model.testPreparing { model.startDrawTest() };if model.mode != "Test the draw" { model.pauseDrawTest() } }
        .onChange(of:model.parameters.style) { model.optimizationSummary="" }
        .onChange(of:model.parameters.colorMode) { model.enabled=Set(Ink.allCases);model.invalidateDrawTest() }
        .onChange(of:model.parameters.minRadius) { if model.parameters.maxRadius<model.parameters.minRadius { model.parameters.maxRadius=model.parameters.minRadius } }
        .onChange(of:model.parameters.maxRadius) { if model.parameters.minRadius>model.parameters.maxRadius { model.parameters.minRadius=model.parameters.maxRadius } }
    }
    private var drawingWorkspace: some View {
        VStack(spacing:0) {
            HStack(spacing:0) {
                drawingInspector
                Divider()
                VStack(spacing:0) {
                    HStack {
                        Picker("Preview",selection:$model.mode) { ForEach(["Original","Scribble","Tracing path","Test the draw"],id:\.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(width:410)
                        Spacer();Button("Fit") { model.zoom=1 };Button("−") { model.zoom=max(0.5,model.zoom/1.3) };Button("＋") { model.zoom=min(5,model.zoom*1.3) }
                    }.padding(18)
                    if model.mode=="Test the draw" { DrawTestControls(model:model) }
                    GeometryReader { geo in
                        ScrollView([.horizontal,.vertical]) {
                            let w=CGFloat(model.raster?.width ?? 800),h=CGFloat(model.raster?.height ?? 1000)
                            let factor=min((geo.size.width-50)/w,(geo.size.height-40)/h)*model.zoom
                            ZStack {
                                Color.white
                                if model.mode=="Original",let original=model.original { Image(nsImage:original).resizable().aspectRatio(contentMode:.fit) }
                                else if model.mode=="Test the draw",let plan=model.testPlan { DrawTestPreview(plan:plan,state:model.testState,penWidth:model.medium.isEInk ? model.testPenWidth/plan.fitScale(canvasWidth:model.testCanvasWidth,canvasHeight:model.testCanvasHeight) : model.drawing?.parameters.penWidth ?? 0.7) }
                                else if model.mode=="Test the draw" { ProgressView(model.testPreparing ? "Preparing playback…" : "Choose Test the draw to prepare playback") }
                                else if let drawing=model.drawing { DrawingPreview(drawing:drawing,inks:model.enabled,tracing:model.mode=="Tracing path") }
                                else { VStack(spacing:14) { Image(systemName:"scribble.variable").font(.system(size:48));Text("Your next drawing starts here");Text("Open a photograph and choose Generate drawing.").font(.caption).foregroundStyle(.secondary) }.foregroundStyle(.secondary) }
                            }.frame(width:max(1,w*factor),height:max(1,h*factor)).shadow(color:.black.opacity(0.1),radius:12,y:4).padding(20).frame(minWidth:geo.size.width,minHeight:geo.size.height)
                        }
                    }
                }.background(Color(nsColor:NSColor(srgbRed:0.9,green:0.91,blue:0.88,alpha:1)))
            }
            Divider()
            HStack(spacing:12) {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.caption).lineLimit(2)
                Spacer()
                if model.outdated { Text("Settings changed · regenerate to apply").font(.caption).foregroundStyle(.orange) }
            }.padding(.horizontal,22).padding(.vertical,12)
            if let error=model.error { HStack { Text(error).font(.callout);Spacer();Button("Dismiss") { model.error=nil } }.padding().background(.red.opacity(0.08)) }
        }
    }
    func slider(_ title:String,value:Binding<Double>,range:ClosedRange<Double>,format:String) -> some View {
        VStack(spacing:7) { HStack { Text(title);Spacer();Text(String(format:format,value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit() };Slider(value:value,in:range) }
    }
}
struct DrawingPreview: NSViewRepresentable {
    let drawing: Drawing;let inks:Set<Ink>;let tracing:Bool
    func makeNSView(context:Context) -> PaperView { PaperView() }
    func updateNSView(_ view:PaperView,context:Context) {
        if view.drawingID != drawing.id || view.inks != inks || view.tracing != tracing {
            let visible=drawing.parameters.style == .poly ? Set([Ink.black]) : inks
            let layers=tracing ? drawing.layers.filter{visible.contains($0.ink)} : drawing.drawingLayers(inks:visible)
            view.paths=layers.map { CachedLayer($0,style:drawing.parameters.style,spread:drawing.parameters.spreadAcrossCanvas) }
        }
        view.drawingID=drawing.id;view.settings=drawing.parameters
        view.drawingWidth=drawing.width;view.drawingHeight=drawing.height;view.inks=inks;view.tracing=tracing;view.needsDisplay=true
    }
}
final class PaperView: NSView {
    var paths=[CachedLayer](),inks=Set(Ink.allCases),tracing=false
    var drawingWidth=1,drawingHeight=1,drawingID:UUID?,settings=Parameters()
    override var isFlipped:Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        guard let ctx=NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState();ctx.scaleBy(x:bounds.width/CGFloat(drawingWidth),y:bounds.height/CGFloat(drawingHeight));ctx.setLineCap(.round);ctx.setLineJoin(.round)
        for layer in paths where settings.style == .poly || inks.contains(layer.ink) { paint(layer,in:ctx,parameters:settings,tracing:tracing) }
        ctx.restoreGState()
    }
}
