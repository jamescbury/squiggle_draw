import SwiftUI
import AppKit
import SquiggleCore

private actor SequenceWorker {
    private var renderer:SequenceRenderer?
    func prepare(store:LibraryStore,source:LibraryEntry,target:LibraryEntry) throws {
        let a=try SequenceArtwork(svg:store.verifiedSVG(source)),b=try SequenceArtwork(svg:store.verifiedSVG(target))
        renderer=try SequenceRenderer(transition:SequenceTransition(source:a,target:b))
    }
    func frame(_ fraction:Double)->CGImage? { renderer?.frame(at:fraction) }
}

@MainActor final class SequentialDrawingsModel:ObservableObject {
    @Published var items=[SequenceItem]()
    @Published var index=0
    @Published var progress=0.0
    @Published var playing=false
    @Published var preparing=false
    @Published var image:CGImage?
    @Published var error:String?
    @Published var acceleration=1.0
    private var presentationWindow:NSWindow?
    private let worker=SequenceWorker()
    private var clock:Task<Void,Never>?,preparation:Task<Void,Never>?
    private var generation=0,ready=false,lastTick=ProcessInfo.processInfo.systemUptime
    private var displayedProgress = -1.0
    private let settings:URL
    init() {
        settings=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "art.squiggle.draw")
            .appendingPathComponent("sequential-drawings.json")
        if FileManager.default.fileExists(atPath:settings.path) {
            do {
                let saved=try JSONDecoder().decode([SequenceItem].self,from:Data(contentsOf:settings))
                guard saved.count<=64,Set(saved.map(\.id)).count==saved.count,saved.allSatisfy({$0.minutes.isFinite && (1...1440).contains($0.minutes)}) else { throw SequenceError.unsupported }
                items=saved
            } catch { self.error="Could not read the saved sequence: \(error.localizedDescription)" }
        }
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at:settings.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(items).write(to:settings,options:.atomic)
        } catch { self.error="Could not save the sequence: \(error.localizedDescription)" }
    }
    func add(_ entry:LibraryEntry,library:BooxLibraryModel) {
        guard items.count<64 else { return }
        items.append(SequenceItem(sketchID:entry.id));changed(library)
    }
    func remove(_ id:UUID,library:BooxLibraryModel) { items.removeAll{$0.id==id};changed(library) }
    func move(_ offset:Int,by distance:Int,library:BooxLibraryModel) {
        let next=offset+distance;guard items.indices.contains(next) else { return }
        items.swapAt(offset,next);changed(library)
    }
    func time(_ id:UUID,minutes:Double) {
        guard minutes.isFinite,let i=items.firstIndex(where:{$0.id==id}) else { return }
        items[i].minutes=max(1,min(1440,minutes));lastTick=ProcessInfo.processInfo.systemUptime;save()
    }
    private func changed(_ library:BooxLibraryModel) { playing=false;index=0;progress=0;save();prepare(library) }
    func prepare(_ library:BooxLibraryModel) {
        generation+=1;let request=generation
        preparation?.cancel();ready=false;preparing=false;displayedProgress = -1
        guard items.count>=2,items.indices.contains(index),let entries=library.catalog?.entries else { image=nil;return }
        guard let source=entries.first(where:{$0.id==items[index].sketchID}),
              let target=entries.first(where:{$0.id==items[(index+1)%items.count].sketchID}) else {
            playing=false;image=nil;error="A drawing in this sequence is missing from the gallery. Remove it or choose another drawing.";return
        }
        preparing=true;error=nil
        let store=library.store
        preparation=Task { [weak self] in
            guard let self else { return }
            do {
                try await worker.prepare(store:store,source:source,target:target)
                guard generation==request,!Task.isCancelled else { return }
                ready=true;preparing=false;lastTick=ProcessInfo.processInfo.systemUptime
            } catch {
                guard generation==request else { return }
                self.error=error.localizedDescription;preparing=false;playing=false;image=nil
            }
        }
    }
    func activate(_ library:BooxLibraryModel) {
        guard clock==nil else { return }
        if !ready { prepare(library) }
        lastTick=ProcessInfo.processInfo.systemUptime
        clock=Task { [weak self,weak library] in
            while !Task.isCancelled {
                guard let self,let library else { return }
                await self.tick(library)
                do { try await Task.sleep(for:.milliseconds(100)) } catch { return }
            }
        }
    }
    func deactivate() { playing=false;clock?.cancel();clock=nil;closePresentation() }
    func present() {
        if presentationWindow==nil {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title="Sequential drawings";window.isReleasedWhenClosed=false
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.contentView=NSHostingView(rootView:SequencePresentation(model:self))
            window.center();presentationWindow=window
        }
        presentationWindow?.makeKeyAndOrderFront(nil)
    }
    func closePresentation() { presentationWindow?.close() }
    func toggle() { guard ready else { return };playing.toggle();lastTick=ProcessInfo.processInfo.systemUptime }
    func seek(_ value:Double) { playing=false;progress=max(0,min(1,value)) }
    func restart(_ library:BooxLibraryModel) { playing=false;index=0;progress=0;prepare(library) }
    func select(_ i:Int,library:BooxLibraryModel) { playing=false;index=i;progress=0;prepare(library) }
    func next(_ library:BooxLibraryModel) { guard items.count>=2 else { return };index=(index+1)%items.count;progress=0;prepare(library) }
    private func tick(_ library:BooxLibraryModel) async {
        let now=ProcessInfo.processInfo.systemUptime,elapsed=now-lastTick;lastTick=now
        guard ready,!preparing else { return }
        if playing { progress=min(1,progress+elapsed*acceleration/(items[index].minutes*60)) }
        if displayedProgress != progress {
            let request=generation,fraction=progress
            let frame=await worker.frame(fraction)
            guard request==generation,!Task.isCancelled else { return }
            image=frame;displayedProgress=fraction
        }
        if playing,progress>=1 { next(library) }
    }
    func title(_ library:BooxLibraryModel,offset:Int=0)->String {
        guard !items.isEmpty else { return "Choose drawings from the gallery" }
        return library.catalog?.entries.first(where:{$0.id==items[(index+offset)%items.count].sketchID})?.title ?? "Missing drawing"
    }
}

struct SequentialDrawingsView:View {
    @ObservedObject var model:SequentialDrawingsModel
    @ObservedObject var library:BooxLibraryModel
    @State private var thumbnails=[UUID:NSImage]()
    private func loadThumbnails() {
        thumbnails=Dictionary(uniqueKeysWithValues:(library.catalog?.entries ?? []).compactMap { entry in
            NSImage(contentsOf:library.store.thumbnailURL(id:entry.id)).map { (entry.id,$0) }
        })
    }
    var body:some View {
        HStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    Text("Gallery").font(.title3.weight(.semibold))
                    Text("Add saved drawings to your loop. Save new sketches to the Gallery first.").font(.caption).foregroundStyle(.secondary)
                    if library.catalog?.entries.isEmpty != false { Text("No saved drawings yet.").foregroundStyle(.secondary) }
                    ForEach(library.catalog?.entries ?? []) { entry in
                        HStack {
                            if let thumbnail=thumbnails[entry.id] {
                                Image(nsImage:thumbnail).resizable().scaledToFit().frame(width:54,height:54).background(.white)
                            }
                            VStack(alignment:.leading) { Text(entry.title).lineLimit(2);Text(entry.style).font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                            Button { model.add(entry,library:library) } label: { Image(systemName:"plus") }
                                .help("Add \(entry.title) to sequence").accessibilityLabel("Add \(entry.title) to sequence").disabled(model.items.count>=64)
                        }
                    }
                    Divider()
                    HStack { Text("Drawing order").font(.title3.weight(.semibold));Spacer();Text("\(model.items.count) / 64").font(.caption).foregroundStyle(.secondary) }
                    Text("Minutes to change into the next drawing. The last returns to the first.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(model.items.enumerated()),id:\.element.id) { i,item in
                        VStack(alignment:.leading,spacing:7) {
                            HStack {
                                Text("\(i+1).").foregroundStyle(.secondary)
                                Button { model.select(i,library:library) } label: {
                                    Text(library.catalog?.entries.first(where:{$0.id==item.sketchID})?.title ?? "Missing drawing").lineLimit(1)
                                }.buttonStyle(.plain).fontWeight(i==model.index ? .semibold : .regular)
                                Spacer()
                                Button { model.move(i,by:-1,library:library) } label: {Image(systemName:"arrow.up")}.disabled(i==0).accessibilityLabel("Move drawing \(i+1) up")
                                Button { model.move(i,by:1,library:library) } label: {Image(systemName:"arrow.down")}.disabled(i==model.items.count-1).accessibilityLabel("Move drawing \(i+1) down")
                                Button { model.remove(item.id,library:library) } label: {Image(systemName:"minus.circle")}.accessibilityLabel("Remove drawing \(i+1) from sequence")
                            }
                            HStack {
                                TextField("Minutes for drawing \(i+1)",value:Binding(get:{item.minutes},set:{model.time(item.id,minutes:$0)}),format:.number.precision(.fractionLength(0...1))).frame(width:64).textFieldStyle(.roundedBorder)
                                Text("minutes to next").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(10).background(i==model.index ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
                    }
                    if !model.items.isEmpty {
                        Text("Full loop: \(model.items.reduce(0){$0+$1.minutes}.formatted()) minutes at actual speed. Order and timing save automatically.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(16)
            }.frame(width:330)
            Divider()
            VStack(spacing:14) {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        Text(model.items.count>=2 ? "\(model.title(library)) → \(model.title(library,offset:1))" : "Sequential drawings").font(.title3.weight(.semibold))
                        Text("Old strokes erase along their paths as new strokes draw. Shared ink stays.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Present",systemImage:"arrow.up.left.and.arrow.down.right") { model.present() }.disabled(model.image==nil)
                }
                SequencePaper(image:model.image).overlay {
                    if model.preparing { ProgressView("Preparing transition…").padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)) }
                    else if model.items.count<2 { Text("Add at least two drawings to begin.").foregroundStyle(.secondary) }
                }
                HStack {
                    Button(model.playing ? "Pause" : "Play",systemImage:model.playing ? "pause.fill" : "play.fill") { model.toggle() }.disabled(model.preparing || model.image==nil)
                    Button("Restart") { model.restart(library) }.disabled(model.items.count<2)
                    Button("Next") { model.next(library) }.disabled(model.items.count<2)
                    Spacer()
                    Picker("Speed",selection:$model.acceleration) {
                        Text("Actual timing").tag(1.0)
                        Text("Preview · 60×").tag(60.0)
                        Text("Preview · 120×").tag(120.0)
                    }.frame(width:220)
                }
                HStack {
                    Slider(value:Binding(get:{model.progress},set:{model.seek($0)}),in:0...1).disabled(model.image==nil || model.preparing).accessibilityLabel("Transition progress")
                    Text("\(Int(model.progress*100))%").monospacedDigit().frame(width:40)
                }
                if let error=model.error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
                Text("Landscape display · 16:9 · continuous loop").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .onAppear { loadThumbnails();model.activate(library) }
        .onDisappear { model.deactivate() }
        .onChange(of:library.catalog?.entries.map(\.id)) { loadThumbnails();model.prepare(library) }
    }
}

private struct SequencePaper:View {
    let image:CGImage?
    var body:some View {
        GeometryReader { area in
            let width=min(area.size.width,area.size.height*16/9),height=width*9/16
            ZStack {
                Color.white
                if let image { Image(decorative:image,scale:1).resizable().interpolation(.high).scaledToFit() }
            }.frame(width:width,height:height).position(x:area.size.width/2,y:area.size.height/2)
        }.background(Color(white:0.92))
    }
}
private struct SequencePresentation:View {
    @ObservedObject var model:SequentialDrawingsModel
    var body:some View {
        VStack(spacing:0) {
            SequencePaper(image:model.image)
            HStack {
                Button(model.playing ? "Pause" : "Play") { model.toggle() }
                Spacer();Text("Use the window’s green button for full screen.").font(.caption).foregroundStyle(.secondary);Spacer()
                Button("Done") { model.closePresentation() }.keyboardShortcut(.cancelAction)
            }.padding(12)
        }.frame(minWidth:960,minHeight:600)
    }
}
