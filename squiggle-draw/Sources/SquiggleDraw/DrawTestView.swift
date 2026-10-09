import SwiftUI
import AppKit
import SquiggleCore

@MainActor extension Studio {
    func pauseDrawTest() { testClock?.cancel();testClock=nil;testPlaying=false }
    func invalidateDrawTest() { pauseDrawTest();testToken+=1;testWork?.cancel();testWork=nil;testPlan=nil;testState=DrawTestState();testPreparing=false;testNote="" }
    func startDrawTest() {
        guard let drawing,!busy else { return }
        mode="Test the draw"
        if testPlan != nil { playDrawTest();return }
        testToken+=1;let request=testToken,inks=enabled
        testPreparing=true;testNote="Preparing stroke order…"
        testWork=Task { [weak self] in
            let task=Task.detached(priority:.userInitiated) { () throws -> (DrawTestPlan,String) in
                let plan=try DrawTestPlan(drawing,inks:inks)
                var warnings=[String]()
                if plan.strokes.count>20000 { warnings.append("This exceeds the current BOOX player's 20,000-stroke limit. Increase spacing or export fewer ink layers before tablet playback.") }
                let size=try drawing.svgSize(inks:drawing.parameters.style == .poly ? [.black] : inks)
                if size.elements>20000 && plan.strokes.count<=20000 { warnings.append("This SVG exceeds the current BOOX element limit. Increase spacing or export one ink layer.") }
                if size.fileBytes>32*1024*1024 || size.pathDataBytes>28000000 { warnings.append("This SVG exceeds the current BOOX file-size limit. Reduce detail or increase spacing.") }
                if drawing.parameters.style == .stipple { warnings.append("BOOX plays dot outlines; it does not fill them.") }
                if drawing.parameters.style == .poly && !drawing.parameters.polyWireframe { warnings.append("Polygon fills require BOOX Squiggle 0.13 or later. Each outline completes before its fill appears.") }
                return (plan,warnings.joined(separator:" "))
            }
            do {
                let (plan,note)=try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
                guard let self,self.testToken==request,self.drawing?.id==drawing.id else { return }
                self.testPlan=plan;self.testState=DrawTestState();self.testPreparing=false;self.testNote=note
                self.playDrawTest()
            } catch {
                guard let self,self.testToken==request else { return }
                self.testPreparing=false;self.testNote=error.localizedDescription
            }
        }
    }
    func playDrawTest() {
        guard mode=="Test the draw",!busy,let plan=testPlan,!testPlaying,!plan.strokes.isEmpty else { return }
        if testState.done(plan) { try? testState.restore(0,plan:plan) }
        testPlaying=true;lastTestTick=Date()
        testClock=Task { [weak self] in
            while !Task.isCancelled {
                self?.tickDrawTest()
                do { try await Task.sleep(for:.milliseconds(33)) } catch { break }
            }
        }
    }
    func tickDrawTest() {
        guard testPlaying,let plan=testPlan else { return }
        let now=Date(),dt=min(0.1,max(0,now.timeIntervalSince(lastTestTick)));lastTestTick=now
        guard testCanvasWidth.isFinite,testCanvasHeight.isFinite,testCanvasWidth>=50,testCanvasHeight>=50 else { pauseDrawTest();testNote="Enter a tablet drawing area of at least 50 × 50.";return }
        do {
            try testState.advance(seconds:dt*testAcceleration,speed:testSpeed/plan.fitScale(canvasWidth:testCanvasWidth,canvasHeight:testCanvasHeight),plan:plan)
            if testState.done(plan) { pauseDrawTest() }
        } catch { pauseDrawTest();testNote=error.localizedDescription }
    }
    func seekDrawTest(_ progress:Double) { pauseDrawTest();if let plan=testPlan { try? testState.restore(progress,plan:plan) } }
}
struct DrawTestControls:View {
    @ObservedObject var model:Studio
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Button(model.testPlaying ? "Pause" : "Play") { model.testPlaying ? model.pauseDrawTest() : model.playDrawTest() }.disabled(model.testPlan==nil)
                Button("Restart") { model.seekDrawTest(0);model.playDrawTest() }.disabled(model.testPlan==nil)
                Slider(value:Binding(get:{model.testPlan.map{model.testState.fraction($0)} ?? 0},set:{model.seekDrawTest($0)}),in:0...1).disabled(model.testPlan==nil)
                Text("\(Int((model.testPlan.map{model.testState.fraction($0)} ?? 0)*100))%").monospacedDigit().frame(width:42)
                Picker("Preview speed",selection:$model.testAcceleration) {
                    Text("1×").tag(1.0);Text("100×").tag(100.0);Text("500×").tag(500.0);Text("1,000×").tag(1000.0)
                }.frame(width:190)
            }
            DisclosureGroup("BOOX playback settings") {
                VStack(alignment:.leading,spacing:8) {
                    HStack { Text("Speed \(Int(model.testSpeed))").frame(width:110,alignment:.leading);Slider(value:$model.testSpeed,in:1...500,step:1) }
                    HStack { Text(String(format:"Pen width %.2f",model.testPenWidth)).frame(width:110,alignment:.leading);Slider(value:$model.testPenWidth,in:0.25...4) }
                    HStack {
                        Text("Drawing area (dp)")
                        TextField("Width",value:$model.testCanvasWidth,format:.number).frame(width:80)
                        Text("×")
                        TextField("Height",value:$model.testCanvasHeight,format:.number).frame(width:80)
                    }.textFieldStyle(.roundedBorder)
                    Text("Matches SVG order, BOOX pen width and shadow thickness, polygon fills after each outline, and 0.2-second pen lifts. Set the drawing area to your tablet's logical canvas size. E-ink refresh effects and device delays are not simulated.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top,6)
            }
            if let plan=model.testPlan {
                let seconds=plan.estimatedSeconds(speed:model.testSpeed,canvasWidth:model.testCanvasWidth,canvasHeight:model.testCanvasHeight)
                Text("\((plan.penLifts + (plan.strokes.isEmpty ? 0 : 1)).formatted()) pen strokes · estimated tablet drawing time \(duration(seconds))").font(.caption).foregroundStyle(.secondary)
            }
            if !model.testNote.isEmpty { Text(model.testNote).font(.caption).foregroundStyle(.orange) }
        }.padding(.horizontal,18).padding(.bottom,12)
    }
    func duration(_ seconds:Double)->String {
        guard seconds.isFinite,seconds>=0,seconds<1e9 else { return "—" }
        let n=Int(seconds);return n>=3600 ? "\(n/3600)h \(n%3600/60)m" : "\(n/60)m \(n%60)s"
    }
}
struct DrawTestPreview:NSViewRepresentable {
    let plan:DrawTestPlan,state:DrawTestState,penWidth:Double
    func makeNSView(context:Context)->DrawTestPaper { DrawTestPaper() }
    func updateNSView(_ view:DrawTestPaper,context:Context) { view.update(plan:plan,state:state,penWidth:penWidth) }
}
final class DrawTestPaper:NSView {
    var planID:UUID?,bitmap:CGContext?,drawn=0.0,penWidth=0.0,pen:Point?,lifting=false
    var imageWidth=1,imageHeight=1
    override var isFlipped:Bool { true }
    func update(plan:DrawTestPlan,state:DrawTestState,penWidth width:Double) {
        guard width.isFinite,width>0 else { return }
        if planID != plan.id || width != penWidth || state.drawn<drawn {
            bitmap=CGContext(data:nil,width:plan.width,height:plan.height,bitsPerComponent:8,bytesPerRow:plan.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)
            guard let ctx=bitmap else { return }
            ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:plan.width,height:plan.height))
            ctx.translateBy(x:0,y:CGFloat(plan.height));ctx.scaleBy(x:1,y:-1);ctx.setLineCap(.round);ctx.setLineJoin(.round)
            planID=plan.id;drawn=0;penWidth=width;imageWidth=plan.width;imageHeight=plan.height
        }
        if let ctx=bitmap,state.drawn>drawn {
            var position=plan.location(at:drawn),remaining=state.drawn-drawn
            ctx.setLineWidth(width)
            while remaining>1e-8 && position.index<plan.strokes.count {
                let stroke=plan.strokes[position.index],take=min(remaining,stroke.length-position.distance)
                ctx.setLineWidth(width*stroke.widthFactor)
                ctx.setStrokeColor(CGColor(srgbRed:stroke.color.r,green:stroke.color.g,blue:stroke.color.b,alpha:1));ctx.addPath(cgPath(stroke.portion(from:position.distance,to:position.distance+take)));ctx.strokePath()
                if let fill=stroke.fill,position.distance+take>=stroke.length-1e-7 {
                    ctx.setFillColor(CGColor(srgbRed:fill.r,green:fill.g,blue:fill.b,alpha:1))
                    ctx.addPath(cgPath(stroke.points,closed:true));ctx.fillPath()
                }
                remaining-=take;position=(position.index+1,0)
            }
        }
        drawn=state.drawn;pen=state.done(plan) ? nil : state.pen(plan);lifting=state.liftRemaining>0;needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect) {
        if let image=bitmap?.makeImage() {
            NSImage(cgImage:image,size:NSSize(width:imageWidth,height:imageHeight)).draw(in:bounds,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
        }
        if let pen {
            let q=CGPoint(x:pen.x*bounds.width/CGFloat(imageWidth),y:pen.y*bounds.height/CGFloat(imageHeight))
            let circle=NSBezierPath(ovalIn:CGRect(x:q.x-4,y:q.y-4,width:8,height:8))
            (lifting ? NSColor.gray : NSColor.systemOrange).setStroke();circle.lineWidth=1.5;circle.stroke()
        }
    }
}
