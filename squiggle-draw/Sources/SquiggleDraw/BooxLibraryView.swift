import SwiftUI
import AppKit
import ImageIO
import SquiggleCore

@MainActor
final class BooxLibraryModel: ObservableObject {
    @Published var catalog: LibraryCatalog?
    @Published var busy=false
    @Published var message="Save artwork here for your displays and drawing sequences."
    @Published var error:String?
    let store:LibraryStore
    let server=LibraryServer()

    init() {
        let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "art.squiggle.draw",isDirectory:true).appendingPathComponent("BOOX Library",isDirectory:true)
        store=LibraryStore(rootURL:root)
        perform(success:"Library ready",restoreSharing:true) { try $0.load() }
    }
    func perform(success:String,restoreSharing:Bool=false,operation:@escaping @Sendable (LibraryStore) throws ->LibraryCatalog) {
        guard !busy else { return }
        busy=true;error=nil
        let store=store
        Task {
            do {
                let result=try await Task.detached(priority:.userInitiated) { try operation(store) }.value
                catalog=result;server.update(catalog:result);message=success
                if restoreSharing { server.restoreSharing(store:store,catalog:result) }
            } catch { self.error=error.localizedDescription }
            busy=false
        }
    }
    func add(studio:Studio) {
        guard let drawing=studio.drawing,!studio.busy else { return }
        guard !studio.outdated else { error="Regenerate the drawing to apply your changed settings before saving it to the library.";return }
        let inks=drawing.parameters.style == .poly ? Set([Ink.black]) : studio.enabled
        guard drawing.layers.contains(where:{inks.contains($0.ink) && $0.hasArtwork}) else { error="Enable an ink layer containing artwork first.";return }
        let title=studio.name,style=drawing.parameters.style.rawValue,tablet=studio.medium.isEInk
        perform(success:tablet ? "Saved \(title). Choose Sync now on your tablet to download it." : "Saved \(title) to your gallery for display and sequences.") { store in
            let size=try drawing.svgSize(inks:inks)
            guard (!tablet || (size.elements<=20000 && size.pathDataBytes<=28000000)),size.fileBytes<=32*1024*1024 else {
                throw tablet ? LibraryUIError.limit : LibraryUIError.galleryLimit
            }
            let svg=Data(drawing.svg(inks:inks).utf8)
            let thumbnail=try Self.thumbnail(drawing,inks:inks)
            return try store.add(svg:svg,thumbnail:thumbnail,title:title,style:style,available:tablet)
        }
    }
    func update(_ entry:LibraryEntry,title:String?=nil,available:Bool?=nil) {
        perform(success:"Gallery updated.") { store in
            if available == true {
                let data=try store.verifiedSVG(entry)
                guard data.count<=28000000,try SequenceArtwork(svg:data).strokes.count<=19990 else { throw LibraryUIError.limit }
            }
            return try store.update(id:entry.id,title:title,available:available)
        }
    }
    func remove(_ entry:LibraryEntry) {
        perform(success:"Removed from the gallery.") { try $0.remove(id:entry.id) }
    }
    nonisolated private static func thumbnail(_ drawing:Drawing,inks:Set<Ink>) throws ->Data {
        let scale=min(1,420/Double(max(drawing.width,drawing.height)))
        let width=max(1,Int(Double(drawing.width)*scale)),height=max(1,Int(Double(drawing.height)*scale))
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DrawError.invalidImage }
        context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
        context.translateBy(x:0,y:CGFloat(height));context.scaleBy(x:CGFloat(width)/CGFloat(drawing.width),y: -CGFloat(height)/CGFloat(drawing.height))
        render(drawing,in:context,inks:inks,tracing:false)
        guard let image=context.makeImage() else { throw DrawError.invalidImage }
        let data=NSMutableData()
        guard let destination=CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil) else { throw DrawError.invalidImage }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else { throw DrawError.invalidImage }
        return data as Data
    }
}
private enum LibraryUIError:LocalizedError {
    case limit,galleryLimit
    var errorDescription:String? {
        if self == .galleryLimit { return "This drawing exceeds the gallery’s 32 MB limit. Reduce detail or export it as an SVG instead." }
        return "This drawing exceeds the BOOX player's limits. Reduce detail, increase spacing, or select fewer inks, then regenerate. The library accepts up to 20,000 SVG elements and 32 MB per sketch." }
}

struct BooxLibraryView:View {
    @ObservedObject var library:BooxLibraryModel
    @ObservedObject var studio:Studio
    @State private var deleting:LibraryEntry?
    var body:some View {
        HStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Label("Gallery",systemImage:"square.grid.2x2").font(.title2.weight(.semibold))
                    Text("Save artwork for your displays and drawing sequences.").foregroundStyle(.secondary)
                    Button { library.add(studio:studio) } label: { Label("Add current drawing",systemImage:"plus").frame(maxWidth:.infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(studio.drawing==nil || studio.busy || library.busy || library.catalog==nil)
                    Text("Saves the generated drawing with its selected inks and color order. Each save creates a separate sketch.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    if studio.medium.isEInk {
                    LibrarySharingView(server:library.server,store:library.store,catalog:library.catalog)
                    Divider()
                    Text("Available on BOOX").font(.headline)
                    Text("Checked sketches are ready to transfer. With sharing on, choose Library → Sync now on your BOOX to download them. Unchecking removes the tablet copy on its next sync and keeps the sketch here.").font(.caption).foregroundStyle(.secondary)
                    Text("Downloaded sketches work offline. Your photographs stay on this Mac.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(22)
            }.frame(width:310).background(Color(nsColor:.windowBackgroundColor))
            Divider()
            VStack(alignment:.leading,spacing:16) {
                HStack {
                    Text("Saved sketches").font(.title2.weight(.semibold))
                    Spacer()
                    if let catalog=library.catalog {
                        Text(studio.medium.isEInk ? "\(catalog.entries.filter(\.available).count) selected for BOOX · \(catalog.entries.count) saved on Mac" : "\(catalog.entries.count) saved on Mac").foregroundStyle(.secondary)
                    }
                    if library.busy { ProgressView().controlSize(.small) }
                }
                if let catalog=library.catalog,catalog.entries.isEmpty {
                    ContentUnavailableView("Your library starts here",systemImage:"books.vertical",description:Text("Generate a sketch in the Draw tab, then choose Add current drawing. Your saved sketches will appear here."))
                        .frame(maxWidth:.infinity,maxHeight:.infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:230,maximum:330))],spacing:18) {
                            ForEach(library.catalog?.entries ?? []) { entry in
                                LibrarySketchCard(entry:entry,thumbnailURL:library.store.thumbnailURL(id:entry.id),busy:library.busy,showBOOX:studio.medium.isEInk,
                                    update:{ title,available in library.update(entry,title:title,available:available) },remove:{deleting=entry})
                            }
                        }.padding(2)
                    }
                }
                if let error=library.error {
                    HStack(alignment:.top) { Image(systemName:"exclamationmark.triangle");Text(error);Spacer();Button("Dismiss") {library.error=nil} }.foregroundStyle(.red)
                }
                Text(library.message).font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
        }
        .alert("Remove sketch from library?",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}})) {
            Button("Cancel",role:.cancel) {deleting=nil}
            Button("Remove",role:.destructive) {if let entry=deleting {library.remove(entry)};deleting=nil}
        } message: {Text("This removes the saved library copy and removes it from the BOOX on its next successful sync. Your source photo and exported files are kept.")}
    }
}
private struct LibrarySharingView:View {
    @ObservedObject var server:LibraryServer
    let store:LibraryStore
    let catalog:LibraryCatalog?
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Label("USB and Wi-Fi sync",systemImage:"wifi").font(.headline)
            Toggle("Share library with BOOX",isOn:Binding(get:{server.running},set:{ enabled in
                if let catalog {server.setSharing(enabled,store:store,catalog:catalog)}
            })).disabled(catalog==nil)
            Text(server.status).font(.caption).foregroundStyle(.secondary)
            Text("This setting is remembered when you reopen the app. Keep Squiggle Draw open while syncing.").font(.caption).foregroundStyle(.secondary)
            if server.running,let catalog {
                USBPairingView(usb:server.usb,address:server.connectionAddress,libraryID:catalog.libraryID)
            }
            if server.running && !server.address.isEmpty {
                DisclosureGroup("Manual Wi-Fi pairing") {
                Text("Pairing address").font(.caption.weight(.semibold))
                Text(server.address).font(.system(.caption,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                Button("Copy pairing address") {NSPasteboard.general.clearContents();NSPasteboard.general.setString(server.address,forType:.string)}
                Text("Use Pair connected BOOX above to avoid typing. For manual pairing, enter this address in the tablet’s Library → Pair Mac. Keep this app open for syncing.").font(.caption).foregroundStyle(.secondary)
            }
                }
        }
    }
}
private struct USBPairingView:View {
    @ObservedObject var usb:USBConnection
    let address:String
    let libraryID:UUID
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Button("Pair connected BOOX") { usb.pair(address:address,libraryID:libraryID) }.disabled(usb.busy)
            Text(usb.status).font(.caption).foregroundStyle(.secondary)
            Text("Connect the USB cable once to save the Wi-Fi address automatically. Squiggle uses USB while connected and Wi-Fi when unplugged. Then choose Sync now on the BOOX to download your sketches. Sharing automatically restores the cable connection after replugging.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
private struct LibrarySketchCard:View {
    let entry:LibraryEntry
    let thumbnailURL:URL
    let busy:Bool
    let showBOOX:Bool
    let update:(String?,Bool?)->Void
    let remove:()->Void
    @State private var title=""
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Group {
                if let image=NSImage(contentsOf:thumbnailURL) { Image(nsImage:image).resizable().scaledToFit() }
                else { Image(systemName:"scribble.variable").font(.largeTitle).foregroundStyle(.secondary) }
            }.frame(maxWidth:.infinity).frame(height:180).background(.white).clipShape(RoundedRectangle(cornerRadius:8))
            HStack {
                TextField("Sketch name",text:$title).textFieldStyle(.roundedBorder).onSubmit {update(title,nil)}
                Button {update(title,nil)} label:{Image(systemName:"checkmark")}.help("Save name").disabled(title==entry.title || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            Text(entry.style).font(.caption).foregroundStyle(.secondary)
            HStack {
                if showBOOX { Toggle("Available on BOOX",isOn:Binding(get:{entry.available},set:{update(nil,$0)})).toggleStyle(.checkbox) }
                Spacer()
                Button(role:.destructive,action:remove) {Image(systemName:"trash")}.buttonStyle(.borderless).help("Remove from library")
            }
            Text(ByteCountFormatter.string(fromByteCount:Int64(entry.bytes),countStyle:.file)).font(.caption2).foregroundStyle(.secondary)
        }.padding(14).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
            .disabled(busy).onAppear {title=entry.title}.onChange(of:entry.title) {title=entry.title}
    }
}
