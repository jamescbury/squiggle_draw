import SwiftUI
import SquiggleCore

extension StudioView {
    var drawingInspector:some View {
        VStack(spacing:0) {
            ScrollView {
                VStack(spacing:14) {
                    inspectorCard("Display",icon:"display") {
                        Picker("Destination",selection:Binding(get:{model.medium},set:{model.selectMedium($0)})) {
                            ForEach(DisplayMedium.allCases,id:\.self) { Label($0.rawValue,systemImage:$0.symbol).tag($0) }
                        }
                        Text(model.medium.detail).font(.caption).foregroundStyle(.secondary)
                        Text("Changing the display applies a preset. You can adjust it below.").font(.caption2).foregroundStyle(.secondary)
                    }
                    inspectorCard("Source photo",icon:"photo") {
                        HStack {
                            Button("Import…",systemImage:"plus",action:model.open)
                            Menu("Samples") {
                                ForEach(StudioSample.all) { sample in Button(sample.title) { model.openSample(sample.id) } }
                            }
                        }.controlSize(.large)
                        if model.raster != nil {
                            HStack {
                                Button("Crop…",systemImage:"crop") { model.pauseDrawTest();cropping=true }.disabled(model.busy)
                                if model.hasCrop { Button("Reset crop") { model.applyCrop(CGRect(x:0,y:0,width:1,height:1)) }.disabled(model.busy) }
                                Spacer()
                                Text("\(model.raster!.width) × \(model.raster!.height)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    inspectorCard("Art style",icon:"paintbrush.pointed") {
                        Picker("Medium",selection:$model.artFinish) {
                            Text("Pen drawing").tag("Pen drawing")
                            Text("Oil painting · coming soon").tag("Oil painting").disabled(true)
                            Text("Watercolor · coming soon").tag("Watercolor").disabled(true)
                        }
                        Picker("Technique",selection:$model.parameters.style) {
                            ForEach(DrawingStyle.studioStyles,id:\.self) { Text($0.displayName).tag($0) }
                        }
                        Text("Oil and watercolor are planned painting modes.").font(.caption2).foregroundStyle(.secondary)
                    }
                    inspectorCard("Color",icon:"paintpalette") {
                        Picker("Color mode",selection:$model.parameters.colorMode) {
                            ForEach(DrawingColorMode.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                        }
                        if model.parameters.colorMode == .photoPalette {
                            Picker("Palette",selection:$model.parameters.paletteSize) { Text("12 colors").tag(12);Text("24 colors").tag(24) }.pickerStyle(.segmented)
                            Text("A compact palette chosen from your photo.").font(.caption).foregroundStyle(.secondary)
                        } else if model.parameters.colorMode == .fullColor {
                            Text("Strokes pick up local colors as they follow the photograph.").font(.caption).foregroundStyle(.secondary)
                        }
                        if model.parameters.colorMode == .rgb && model.parameters.style != .poly {
                            HStack { ForEach(Ink.allCases,id:\.self) { ink in
                                Toggle(isOn:Binding(get:{model.enabled.contains(ink)},set:{on in if on { model.enabled.insert(ink) } else { model.enabled.remove(ink) }})) {
                                    Circle().fill(Color(nsColor:inkColor(ink))).frame(width:9,height:9)
                                }.toggleStyle(.checkbox).help(ink.rawValue.capitalized).accessibilityLabel(ink.rawValue.capitalized)
                            } }
                            Toggle("Alternate colors",isOn:$model.parameters.alternateColors)
                            if model.parameters.alternateColors {
                                Picker("Switch frequency",selection:$model.parameters.colorRounds) {
                                    Text("Occasional").tag(8);Text("Regular").tag(20);Text("Frequent").tag(50);Text("Very frequent").tag(100)
                                }
                            }
                        }
                        if model.medium == .plotter && model.parameters.colorMode.usesPhotoColors {
                            Text("Photo colors need many pens. Choose black or RGB + black for separate pen exports.").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    inspectorCard("Photo tuning",icon:"slider.horizontal.3") {
                        Button("Optimize for this photo",systemImage:"wand.and.stars",action:model.optimize).disabled(model.raster==nil || model.busy)
                        Toggle("Optimize on import",isOn:$model.autoOptimize)
                        if !model.optimizationSummary.isEmpty { Text(model.optimizationSummary).font(.caption).foregroundStyle(.secondary) }
                        DisclosureGroup("Fine-tune strokes") { VStack(alignment:.leading,spacing:14) { strokeControls }.padding(.top,12) }
                    }
                    if model.drawing != nil {
                        inspectorCard("Save & share",icon:"square.and.arrow.up") {
                            HStack { Button("SVG…") { model.exportSVG() };Button("PNG…",action:model.exportPNG) }.disabled(model.busy)
                            Button("Save to gallery",systemImage:"square.grid.2x2") { library.add(studio:model);tab="BOOX Library" }.disabled(model.busy || model.outdated || library.busy)
                            if model.parameters.colorMode == .rgb {
                                Menu("Export one pen…") { ForEach(Ink.allCases,id:\.self) { ink in Button(ink.rawValue.capitalized) { model.exportSVG(only:ink) } } }.disabled(model.busy)
                            }
                        }
                    }
                    Text("Photo processing stays on your Mac.").font(.caption2).foregroundStyle(.secondary)
                }.padding(16)
            }
            VStack(spacing:8) {
                Button(action:{model.busy ? model.cancel() : model.generate()}) {
                    Label(model.busy ? "Cancel generation" : "Generate drawing",systemImage:model.busy ? "stop" : "scribble.variable").frame(maxWidth:.infinity)
                }.buttonStyle(.borderedProminent).tint(.init(red:0.22,green:0.36,blue:0.32)).controlSize(.large).disabled(model.raster==nil)
                Button("Test the draw",systemImage:"play.circle",action:model.startDrawTest).disabled(model.drawing==nil || model.busy || model.outdated || model.testPreparing)
            }.padding(16).background(.regularMaterial)
        }.frame(width:340).background(Color(nsColor:.windowBackgroundColor))
    }
    func inspectorCard<Content:View>(_ title:String,icon:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:12) {
            Label(title,systemImage:icon).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            content()
        }.frame(maxWidth:.infinity,alignment:.leading).padding(14)
            .background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:14))
            .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(.primary.opacity(0.06)))
    }
    @ViewBuilder var strokeControls:some View {
                        if model.parameters.style == .formSketch {
                            slider("Feature detail",value:$model.parameters.sketchDetail,range:0...1,format:"%.2f")
                            Toggle("Join nearby shading strokes",isOn:$model.parameters.connectHatches)
                            Text("Builds contours first, follows surface directions, then deepens shadows and adds fine accents. Pen lifts preserve highlights. Background shading controls smooth areas connected to the image border.").font(.caption).foregroundStyle(.secondary)
                        } else if model.parameters.style == .waves {
                            VStack(spacing:7) {
                                HStack { Text("Number of lines");Spacer();Text("\(model.parameters.lines)").foregroundStyle(.secondary) }
                                Slider(value:Binding(get:{Double(model.parameters.lines)},set:{model.parameters.lines=Int($0)}),in:20...300,step:1)
                            }
                            slider("Wave height",value:$model.parameters.waveHeight,range:0.1...1.5,format:"%.2f")
                            slider("Wave frequency",value:$model.parameters.waveFrequency,range:0.3...3,format:"%.2f")
                        } else if model.parameters.style == .circular {
                        slider("Detail",value:$model.parameters.detail,range:0...1,format:"%.2f")
                        slider("Smallest loop",value:$model.parameters.minRadius,range:4...60,format:"%.1f px")
                        slider("Largest loop",value:$model.parameters.maxRadius,range:30...160,format:"%.1f px")
                        slider("Loop spacing",value:$model.parameters.spacing,range:0.3...3,format:"%.2f")
                        Toggle("Thicker lines in shadows",isOn:$model.parameters.toneWidth)
                        if model.parameters.toneWidth { slider("Shadow thickness",value:$model.parameters.shadowWidth,range:1...6,format:"%.1f×") }
                        Text("Broad loops follow contours. Shadow thickness varies the stroke width.").font(.caption).foregroundStyle(.secondary)
                        } else if model.parameters.style == .crossHatch {
                            slider("Feature detail",value:$model.parameters.sketchDetail,range:0...1,format:"%.2f")
                            slider("Hatch spacing",value:$model.parameters.hatchSpacing,range:1...8,format:"%.2f px")
                            slider("Curve bend",value:$model.parameters.hatchCurve,range:0...20,format:"%.1f px")
                            VStack(spacing:7) {
                                HStack { Text("Shading layers");Spacer();Text("\(model.parameters.hatchPasses)").foregroundStyle(.secondary) }
                                Slider(value:Binding(get:{Double(model.parameters.hatchPasses)},set:{model.parameters.hatchPasses=Int($0)}),in:2...8,step:1)
                            }
                            Toggle("Connect hatch ends",isOn:$model.parameters.connectHatches)
                            if model.parameters.connectHatches { slider("Connection reach",value:$model.parameters.hatchJoinReach,range:1...40,format:"%.1f px") }
                            Text("Nearby ends join within each shading stage. Increase Connection reach for fewer pen lifts.").font(.caption).foregroundStyle(.secondary)
                            Text("Curved strokes cross in layers, deepening the shadows while preserving highlights.").font(.caption).foregroundStyle(.secondary)
                        } else if model.parameters.style == .flowing {
                            slider("Detail",value:$model.parameters.detail,range:0...1,format:"%.2f")
                            slider("Smallest sweep",value:$model.parameters.minRadius,range:0.3...60,format:"%.1f px")
                            slider("Largest sweep",value:$model.parameters.maxRadius,range:30...160,format:"%.1f px")
                            slider("Curve length",value:$model.parameters.curveStretch,range:1...4,format:"%.2f")
                            slider("Wandering",value:$model.parameters.curveWander,range:0...1,format:"%.2f")
                            slider("Stroke spacing",value:$model.parameters.spacing,range:0.3...3,format:"%.2f")
                            Text("Long, crossing curves follow the photo’s forms. Lifts across blank areas protect highlights.").font(.caption).foregroundStyle(.secondary)
                        } else if model.parameters.style == .stipple || model.parameters.style == .singleLine {
                            VStack(spacing:7) {
                                HStack { Text(model.parameters.style == .singleLine ? "Path points" : "Dot count");Spacer();Text(model.parameters.stippleCount.formatted()).foregroundStyle(.secondary) }
                                Slider(value:Binding(get:{Double(model.parameters.stippleCount)},set:{model.parameters.stippleCount=Int($0)}),in:500...50000,step:100)
                            }
                            if model.parameters.style == .stipple { slider("Dot size",value:$model.parameters.dotSize,range:0.3...8,format:"%.2f") }
                            else {
                                slider("Corner rounding",value:$model.parameters.cornerRounding,range:0...1,format:"%.2f")
                                Text("A rounded route connecting stipple points.").font(.caption).foregroundStyle(.secondary)
                            }
                            VStack(spacing:7) {
                                HStack { Text("Relaxation passes");Spacer();Text("\(model.parameters.relaxation)").foregroundStyle(.secondary) }
                                Slider(value:Binding(get:{Double(model.parameters.relaxation)},set:{model.parameters.relaxation=Int($0)}),in:4...60,step:1)
                            }
                        } else {
                            slider("Facet detail",value:$model.parameters.polyDetail,range:0...1,format:"%.2f")
                            slider("Shape size variation",value:$model.parameters.polyAdaptation,range:0...1,format:"%.2f")
                            slider("Depth shading",value:$model.parameters.relief,range:0...1,format:"%.2f")
                            Toggle("Wireframe for pen drawing",isOn:$model.parameters.polyWireframe)
                            Text("Smaller shapes preserve detailed regions; larger shapes cover smooth areas. Filled faces use photo colors; wireframe exports triangle outlines.").font(.caption).foregroundStyle(.secondary)
                        }
                        if [.formSketch,.circular,.flowing,.crossHatch].contains(model.parameters.style) { slider("Shading depth",value:$model.parameters.sketchShading,range:0.2...1.2,format:"%.2f") }
                        slider("Background shading",value:$model.parameters.sketchBackground,range:0...1,format:"%.2f")
                        Text("Leave smooth backgrounds as paper, or increase to restore them. Increase this if the background estimate removes part of your subject.").font(.caption).foregroundStyle(.secondary)
                        slider("Tone",value:$model.parameters.gamma,range:0.3...3,format:"%.2f")
                        if model.parameters.style != .stipple && (model.parameters.style != .poly || model.parameters.polyWireframe) { slider("Pen width",value:$model.parameters.penWidth,range:0.1...2,format:"%.2f px") }
                        if model.parameters.style == .waves || model.parameters.style == .circular || model.parameters.style == .flowing || model.parameters.style == .crossHatch { Toggle("Match photo tones",isOn:$model.parameters.matchTones) }
                        if model.parameters.style == .circular || model.parameters.style == .flowing { Toggle(model.parameters.style == .circular ? "Bend loops along edges" : "Protect edges",isOn:$model.parameters.protectEdges) }
                        if model.parameters.style != .waves {
                            HStack { Text("Seed");TextField("Seed",value:$model.parameters.seed,format:.number).textFieldStyle(.roundedBorder).frame(width:100);Spacer() }
                        }
                        if ![.formSketch,.crossHatch].contains(model.parameters.style) { Toggle("Encourage canvas coverage",isOn:$model.parameters.spreadAcrossCanvas)
                        Text("Movement gently favors underdrawn areas while keeping long strokes and local crossings.").font(.caption).foregroundStyle(.secondary) }
    }
}
struct StudioSample:Identifiable {
    let id:String,title:String
    static let all:[StudioSample] = [
        .init(id:"shell",title:"Shell"),.init(id:"apple",title:"Apple"),.init(id:"pear_and_pitcher",title:"Pear and pitcher"),.init(id:"mountain_lake",title:"Mountain lake"),
        .init(id:"coffee",title:"Coffee"),.init(id:"eyeglasses",title:"Eyeglasses"),.init(id:"watch",title:"Watch"),.init(id:"flower",title:"Sunflower"),.init(id:"butterfly",title:"Butterfly"),.init(id:"fish",title:"Goldfish"),.init(id:"eyeball",title:"Eye study"),.init(id:"padlock",title:"Brass padlock"),.init(id:"lemon",title:"Lemon"),.init(id:"feather",title:"Feather"),.init(id:"chess_knight",title:"Chess knight"),.init(id:"mushroom",title:"Mushroom")
    ]
}
