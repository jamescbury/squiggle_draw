package art.squiggle.player;

import android.util.AtomicFile;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.Instant;
import java.util.*;

/** Private offline snapshots. A single atomic pointer is the only sync commit. */
final class SketchLibrary {
    static final long MAX_FILE=32L*1024*1024, MAX_TOTAL=256L*1024*1024;
    static final int MAX_MANIFEST=1024*1024, MAX_ENTRIES=64;
    interface Fetch { InputStream open(URL url) throws IOException; }
    static final Fetch HTTP=url -> {
        HttpURLConnection connection=(HttpURLConnection)url.openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(8000);connection.setReadTimeout(12000);
        connection.setRequestProperty("Accept-Encoding","identity");
        try {
            if(connection.getResponseCode()!=200) throw new IOException("The Mac did not return the requested library file. Check sharing and pair again.");
            long length=connection.getContentLengthLong();
            if(length>MAX_FILE) throw new IOException("A library file exceeds the 32 MB limit.");
            InputStream input=connection.getInputStream();
            return new FilterInputStream(input) { @Override public void close() throws IOException { try {super.close();} finally {connection.disconnect();} } };
        } catch(IOException failure) {connection.disconnect();throw new IOException("Could not reach the Mac library. Keep both devices on the same Wi-Fi and try again.");}
    };
    static final class Entry {
        final String id,title,style,createdAt,sha256,file;
        final long bytes;
        Entry(JSONObject value) throws Exception {
            id=uuid(value.getString("id"));title=text(value,"title",512);style=text(value,"style",128);
            createdAt=text(value,"createdAt",128);Instant.parse(createdAt);
            Object size=value.get("bytes");
            if(!(size instanceof Number) || ((Number)size).doubleValue()!=((Number)size).longValue()) throw invalid();
            bytes=((Number)size).longValue();
            if(bytes<1 || bytes>MAX_FILE) throw new IOException("Each sketch must be between 1 byte and 32 MB.");
            sha256=value.getString("sha256");file=value.getString("file");
            if(!sha256.matches("[a-f0-9]{64}") || !file.equals(id+".svg")) throw invalid();
        }
        JSONObject json() throws JSONException {
            return new JSONObject().put("id",id).put("title",title).put("style",style).put("createdAt",createdAt).put("bytes",bytes).put("sha256",sha256).put("file",file);
        }
    }
    static final class Catalog {
        final String libraryID;final List<Entry> entries;final File snapshot;
        Catalog(String id,List<Entry> entries,File snapshot) {libraryID=id;this.entries=Collections.unmodifiableList(entries);this.snapshot=snapshot;}
        File file(Entry entry) {return new File(snapshot,entry.file);}
    }
    private static final Object INDEX_LOCK=new Object();
    private final File directory;
    SketchLibrary(File files) {directory=new File(files,"wifi-sketch-library");}
    static URL pairingURL(String value) throws IOException {
        try {
            URI uri=new URI(value.trim());String host=uri.getHost();
            if(!"http".equals(uri.getScheme()) || host==null || uri.getUserInfo()!=null || uri.getQuery()!=null || uri.getFragment()!=null || uri.getPort()<1 || uri.getPort()>65535 || !uri.getRawPath().matches("/[a-f0-9]{64}/")) throw invalid();
            String[] parts=host.split("\\.");if(parts.length!=4) throw invalid();int[] octets=new int[4];
            for(int i=0;i<4;i++) {if(!parts[i].matches("0|[1-9][0-9]{0,2}")) throw invalid();octets[i]=Integer.parseInt(parts[i]);if(octets[i]>255) throw invalid();}
            boolean local=octets[0]==10 || octets[0]==127 || (octets[0]==172 && octets[1]>=16 && octets[1]<=31) || (octets[0]==192 && octets[1]==168) || (octets[0]==169 && octets[1]==254);
            if(!local) throw invalid();return uri.toURL();
        } catch(Exception failure) {throw new IOException("Use the complete private Wi-Fi pairing address shown by Squiggle Draw on your Mac.");}
    }
    private JSONObject index() throws Exception {
        synchronized(INDEX_LOCK) {
        AtomicFile file=new AtomicFile(new File(directory,"catalog.json"));
        if(!file.getBaseFile().exists() && !new File(file.getBaseFile()+".bak").exists()) return new JSONObject().put("libraries",new JSONObject());
        return readJSON(file);
        }
    }
    Catalog current() throws IOException {
        try {JSONObject state=index();String id=state.optString("activeLibraryID","");return id.isEmpty()?null:catalog(uuid(id),state.getJSONObject("libraries").getString(id));}
        catch(Exception failure) {throw new IOException("The saved library could not be read. Pair and sync again.");}
    }
    List<Catalog> saved() throws IOException {
        try {JSONObject libraries=index().getJSONObject("libraries");List<Catalog> result=new ArrayList<>();Iterator<String> ids=libraries.keys();while(ids.hasNext()) {String id=uuid(ids.next());result.add(catalog(id,libraries.getString(id)));}return result;}
        catch(Exception failure) {throw new IOException("The saved libraries could not be read. Pair and sync again.");}
    }
    void activate(String id) throws IOException {
        synchronized(SketchLibrary.class) {try {check();JSONObject state=index();catalog(uuid(id),state.getJSONObject("libraries").getString(id));state.put("activeLibraryID",id);check();commitIndex(state);} catch(Exception failure) {throw new IOException("Could not select the saved library.");}}
    }
    private Catalog catalog(String id,String snapshot) throws Exception {
        if(!snapshot.matches("snapshot-[a-f0-9-]{36}")) throw invalid();
        File folder=new File(new File(directory,id),snapshot);JSONObject manifest=readJSON(new AtomicFile(new File(folder,"manifest.json")));
        Catalog catalog=manifest(manifest,folder);if(!catalog.libraryID.equals(id)) throw invalid();
        for(Entry entry:catalog.entries) if(!catalog.file(entry).isFile()) throw new IOException("A saved sketch is missing. Sync again to restore it.");
        return catalog;
    }
    static String cableAddress(String address) throws IOException {
        URL url=pairingURL(address);
        return "http://127.0.0.1:48765"+url.getPath();
    }
    Catalog syncConnected(String address,String expectedID,Fetch fetch) throws IOException {
        String cable=cableAddress(address);
        try { return sync(cable,fetch,expectedID); }
        catch(IOException unplugged) {
            if(Thread.currentThread().isInterrupted()) throw unplugged;
            if(cable.equals(address)) throw unplugged;
            return sync(address,fetch,expectedID);
        }
    }
    Catalog sync(String address,Fetch fetch) throws IOException { return sync(address,fetch,null); }
    Catalog sync(String address,Fetch fetch,String expectedID) throws IOException {
        // Also serialize old/new Activity instances in this process.
        synchronized(SketchLibrary.class) {
            File stage=null;boolean committed=false;
            try {
                check();URL base=pairingURL(address);
                JSONObject document;
                try(InputStream input=fetch.open(new URL(base,"manifest.json"))) {document=new JSONObject(new String(read(input,MAX_MANIFEST),StandardCharsets.UTF_8));}
                Catalog incoming=manifest(document,null);check();
                if(expectedID!=null && !expectedID.isEmpty() && !incoming.libraryID.equals(expectedID)) throw new IOException("This connection belongs to a different Mac library. Pair your Mac again.");
                File home=new File(directory,incoming.libraryID);if(!home.exists() && !home.mkdirs()) throw new IOException("Could not create library storage.");
                JSONObject state=syncIndex();JSONObject libraries=state.getJSONObject("libraries");
                Catalog previous=null;try {previous=catalog(incoming.libraryID,libraries.getString(incoming.libraryID));} catch(Exception ignored) { }
                stage=new File(home,"snapshot-"+UUID.randomUUID());if(!stage.mkdir()) throw new IOException("Could not prepare library storage.");
                for(Entry entry:incoming.entries) {
                    check();Entry prior=null;
                    if(previous!=null) for(Entry old:previous.entries) if(old.id.equals(entry.id) && old.sha256.equals(entry.sha256) && old.bytes==entry.bytes) {prior=old;break;}
                    File destination=new File(stage,entry.file);
                    try(InputStream input=prior==null ? fetch.open(new URL(base,entry.file)) : new FileInputStream(previous.file(prior));FileOutputStream output=new FileOutputStream(destination)) {
                        MessageDigest hash=MessageDigest.getInstance("SHA-256");byte[] buffer=new byte[32768];long count=0;int n;
                        while((n=input.read(buffer))!=-1) {check();if(n==0) continue;count+=n;if(count>entry.bytes || count>MAX_FILE) throw new IOException("A sketch download has an unexpected size.");hash.update(buffer,0,n);output.write(buffer,0,n);}
                        if(count!=entry.bytes || !hex(hash.digest()).equals(entry.sha256)) throw new IOException("A sketch download failed its integrity check. Previous sketches were kept.");
                        output.getFD().sync();
                    }
                }
                check();writeJSON(new AtomicFile(new File(stage,"manifest.json")),document);
                libraries.put(incoming.libraryID,stage.getName());state.put("activeLibraryID",incoming.libraryID);
                check();commitIndex(state);
                committed=true;
                for(File old:list(home)) if(old.isDirectory() && old.getName().startsWith("snapshot-") && !old.equals(stage)) remove(old);
                return new Catalog(incoming.libraryID,incoming.entries,stage);
            } catch(Exception failure) {
                if(failure instanceof InterruptedIOException) throw (InterruptedIOException)failure;
                if(failure instanceof IOException) throw (IOException)failure;
                throw new IOException("The Mac library is invalid. Previous sketches were kept.");
            } finally {if(stage!=null && !committed) remove(stage);}
        }
    }
    // Recovery is worker-only and remains uncommitted until the new sync succeeds.
    // Keep every other Mac's valid snapshot mapping instead of resetting its cache.
    private JSONObject syncIndex() throws Exception {
        try {JSONObject state=index();state.getJSONObject("libraries");return state;}
        catch(Exception damaged) {
            JSONObject libraries=new JSONObject();
            for(File home:list(directory)) {
                check();String id;try {id=uuid(home.getName());} catch(IOException ignored) {continue;}
                if(!home.isDirectory()) continue;
                File newest=null;
                for(File snapshot:list(home)) {
                    check();if(!snapshot.isDirectory() || !snapshot.getName().matches("snapshot-[a-f0-9-]{36}")) continue;
                    try {catalog(id,snapshot.getName());if(newest==null || snapshot.lastModified()>newest.lastModified()) newest=snapshot;} catch(Exception ignored) { }
                }
                if(newest!=null) libraries.put(id,newest.getName());
            }
            return new JSONObject().put("libraries",libraries);
        }
    }
    private void commitIndex(JSONObject state) throws Exception {synchronized(INDEX_LOCK) {writeJSON(new AtomicFile(new File(directory,"catalog.json")),state);}}
    private static Catalog manifest(JSONObject value,File snapshot) throws Exception {
        Object version=value.get("schemaVersion");if(!(version instanceof Number) || ((Number)version).doubleValue()!=1) throw invalid();
        String id=uuid(value.getString("libraryID"));JSONArray items=value.getJSONArray("sketches");
        if(items.length()>MAX_ENTRIES) throw new IOException("The library can contain up to 64 sketches.");
        List<Entry> entries=new ArrayList<>();Set<String> ids=new HashSet<>();long total=0;
        for(int i=0;i<items.length();i++) {check();Entry entry=new Entry(items.getJSONObject(i));if(!ids.add(entry.id)) throw invalid();total+=entry.bytes;if(total>MAX_TOTAL) throw new IOException("Selected sketches exceed the 256 MB library limit.");entries.add(entry);}
        return new Catalog(id,entries,snapshot);
    }
    private static String uuid(String value) throws IOException {try {String result=UUID.fromString(value).toString();if(!result.equals(value)) throw invalid();return result;} catch(IllegalArgumentException failure) {throw invalid();}}
    private static String text(JSONObject value,String key,int limit) throws Exception {Object v=value.get(key);if(!(v instanceof String) || ((String)v).length()>limit || ((String)v).isEmpty()) throw invalid();return (String)v;}
    private static IOException invalid() {return new IOException("The Mac library manifest is invalid. Previous sketches were kept.");}
    private static void check() throws InterruptedIOException {if(Thread.currentThread().isInterrupted()) throw new InterruptedIOException("Library sync cancelled.");}
    private static byte[] read(InputStream input,int limit) throws IOException {ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] buffer=new byte[8192];int n;while((n=input.read(buffer))!=-1) {check();if(bytes.size()+n>limit) throw new IOException("The library manifest exceeds 1 MB.");bytes.write(buffer,0,n);}return bytes.toByteArray();}
    private static JSONObject readJSON(AtomicFile file) throws Exception {try(InputStream input=file.openRead()) {return new JSONObject(new String(read(input,MAX_MANIFEST),StandardCharsets.UTF_8));}}
    private static void writeJSON(AtomicFile file,JSONObject value) throws Exception {FileOutputStream output=null;try {output=file.startWrite();output.write(value.toString().getBytes(StandardCharsets.UTF_8));file.finishWrite(output);} catch(Exception failure) {if(output!=null) file.failWrite(output);throw failure;}}
    static String hex(byte[] bytes) {StringBuilder result=new StringBuilder();for(byte b:bytes) result.append(String.format(Locale.ROOT,"%02x",b&255));return result.toString();}
    private static File[] list(File file) {File[] files=file.listFiles();return files==null ? new File[0] : files;}
    private static void remove(File file) {for(File child:list(file)) remove(child);if(!file.delete() && file.exists()) { /* A stale snapshot can be collected at the next successful sync. */ }}
}
