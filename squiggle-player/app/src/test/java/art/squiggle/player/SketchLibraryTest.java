package art.squiggle.player;
import org.junit.*;
import org.junit.rules.TemporaryFolder;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;

import static org.junit.Assert.*;
@RunWith(RobolectricTestRunner.class) @Config(sdk=34,manifest=Config.NONE) @GraphicsMode(GraphicsMode.Mode.NATIVE)
public class SketchLibraryTest {
 @Rule public TemporaryFolder folder=new TemporaryFolder();
 static final String ADDRESS="http://127.0.0.1:48765/"+"a".repeat(64)+"/",LIB="01234567-89ab-cdef-0123-456789abcdef",OTHER="01234567-89ab-cdef-0123-456789abcdee",ID="11234567-89ab-cdef-0123-456789abcdef";
 static final byte[] SVG="<svg viewBox='0 0 20 20'><path stroke='#dd3039' d='M0 0L20 20'/></svg>".getBytes(StandardCharsets.UTF_8);
 JSONObject manifest(String lib,byte[] bytes) throws Exception {return new JSONObject().put("schemaVersion",1).put("libraryID",lib).put("sketches",new JSONArray().put(new JSONObject().put("id",ID).put("title","Photo sketch").put("style","Form sketch").put("createdAt","2026-10-09T10:00:00Z").put("bytes",bytes.length).put("sha256",SketchLibrary.hex(MessageDigest.getInstance("SHA-256").digest(bytes))).put("file",ID+".svg")));}
 SketchLibrary.Fetch fetch(JSONObject m,byte[] bytes) {return url->new ByteArrayInputStream(url.getPath().endsWith("manifest.json")?m.toString().getBytes(StandardCharsets.UTF_8):bytes);}
 interface Throwing {void run() throws Exception;}
 void fails(Throwing operation) throws Exception {try {operation.run();fail("Expected rejection");} catch(IOException expected) {assertFalse(expected.getMessage().contains("a".repeat(64)));}}
 @Test public void connectedSyncPrefersCableAndFallsBackToWifiAfterTimeout() throws Exception {
  SketchLibrary lib=new SketchLibrary(folder.newFolder());String wifi=ADDRESS.replace("127.0.0.1","192.168.1.23");
  java.util.List<String> hosts=new java.util.ArrayList<>();
  SketchLibrary.Fetch fixture=fetch(manifest(LIB,SVG),SVG);
  lib.syncConnected(wifi,LIB,url->{hosts.add(url.getHost());return fixture.open(url);});
  assertTrue(hosts.stream().allMatch(h->h.equals("127.0.0.1")));hosts.clear();
  lib.syncConnected(wifi,LIB,url->{hosts.add(url.getHost());if(url.getHost().equals("127.0.0.1")) throw new java.net.SocketTimeoutException();return fixture.open(url);});
  assertEquals("127.0.0.1",hosts.get(0));assertTrue(hosts.contains("192.168.1.23"));assertEquals(LIB,lib.current().libraryID);
 }
 @Test public void connectedSyncRejectsWrongMacBeforeCommitting() throws Exception {
  SketchLibrary lib=new SketchLibrary(folder.newFolder());lib.sync(ADDRESS,fetch(manifest(LIB,SVG),SVG));
  fails(()->lib.syncConnected(ADDRESS,LIB,fetch(manifest(OTHER,SVG),SVG)));
  assertEquals(LIB,lib.current().libraryID);assertEquals(1,lib.saved().size());
 }
 @Test public void usbPairingSavesWifiWithoutTouchingOtherMacs() throws Exception {
  android.content.Context context=org.robolectric.RuntimeEnvironment.getApplication();
  android.content.SharedPreferences prefs=context.getSharedPreferences("MainActivity",0);prefs.edit().clear().putString("libraryAddress:"+OTHER,"kept").commit();
  android.content.Intent intent=new android.content.Intent("art.squiggle.player.PAIR_USB").putExtra("address",ADDRESS.replace("127.0.0.1","192.168.1.23")).putExtra("libraryId",LIB);
  PairingReceiver.savePairing(context,intent);
  assertEquals(LIB,prefs.getString("pairedLibraryID",""));assertTrue(prefs.getString("libraryAddress","").contains("192.168.1.23"));assertEquals("kept",prefs.getString("libraryAddress:"+OTHER,""));
 }
 @Test public void invalidUsbPairingDoesNotReplaceSavedAddress() throws Exception {
  android.content.Context context=org.robolectric.RuntimeEnvironment.getApplication();android.content.SharedPreferences prefs=context.getSharedPreferences("MainActivity",0);prefs.edit().clear().putString("libraryAddress","kept").commit();
  for(String bad:new String[]{ADDRESS.replace("127.0.0.1","8.8.8.8"),ADDRESS.replace("48765","9110"),"invalid"}) {
   try { PairingReceiver.savePairing(context,new android.content.Intent("art.squiggle.player.PAIR_USB").putExtra("address",bad).putExtra("libraryId",LIB));fail("Accepted invalid pairing"); } catch(Exception expected) { }
   assertEquals("kept",prefs.getString("libraryAddress",""));
  }
 }
 @Test public void persistsOfflineAndReusesVerifiedFiles() throws Exception {
  File files=folder.newFolder();SketchLibrary lib=new SketchLibrary(files);lib.sync(ADDRESS,fetch(manifest(LIB,SVG),SVG));SketchLibrary.Catalog offline=new SketchLibrary(files).current();assertEquals(LIB,offline.libraryID);assertArrayEquals(SVG,Files.readAllBytes(offline.file(offline.entries.get(0)).toPath()));
  JSONObject m=manifest(LIB,SVG);lib.sync(ADDRESS,url->{if(!url.getPath().endsWith("manifest.json")) throw new IOException("Should reuse SVG");return new ByteArrayInputStream(m.toString().getBytes(StandardCharsets.UTF_8));});
 }
 @Test public void failedDownloadsKeepExactSnapshot() throws Exception {
  SketchLibrary lib=new SketchLibrary(folder.newFolder());SketchLibrary.Catalog old=lib.sync(ADDRESS,fetch(manifest(LIB,SVG),SVG));byte[] changed="different SVG".getBytes(StandardCharsets.UTF_8);fails(()->lib.sync(ADDRESS,fetch(manifest(LIB,changed),SVG)));assertEquals(old.snapshot,lib.current().snapshot);assertArrayEquals(SVG,Files.readAllBytes(old.file(old.entries.get(0)).toPath()));
  fails(()->lib.sync(ADDRESS,url->{throw new IOException("Offline");}));assertEquals(old.snapshot,lib.current().snapshot);
  JSONObject m=manifest(LIB,SVG);m.getJSONArray("sketches").put(new JSONObject(m.getJSONArray("sketches").getJSONObject(0).toString()).put("id",OTHER).put("file",OTHER+".svg"));fails(()->lib.sync(ADDRESS,url->{if(url.getPath().endsWith(OTHER+".svg")) throw new IOException("Transfer failed");return fetch(m,SVG).open(url);}));assertEquals(old.snapshot,lib.current().snapshot);
 }
 @Test public void removalRetainsOtherMacsAndManualImports() throws Exception {
  File files=folder.newFolder();File manual=new File(files,"manual.svg");Files.write(manual.toPath(),SVG);SketchLibrary lib=new SketchLibrary(files);SketchLibrary.Catalog first=lib.sync(ADDRESS,fetch(manifest(LIB,SVG),SVG));lib.sync(ADDRESS,fetch(manifest(OTHER,SVG),SVG));assertTrue(first.file(first.entries.get(0)).exists());assertEquals(2,lib.saved().size());lib.activate(LIB);assertEquals(LIB,lib.current().libraryID);
  lib.sync(ADDRESS,fetch(manifest(LIB,SVG).put("sketches",new JSONArray()),SVG));assertTrue(lib.current().entries.isEmpty());assertFalse(first.snapshot.exists());lib.activate(OTHER);assertEquals(1,lib.current().entries.size());assertTrue(manual.exists());
 }
 @Test public void rejectsTraversalDuplicatesAndBounds() throws Exception {
  SketchLibrary lib=new SketchLibrary(folder.newFolder());JSONObject m=manifest(LIB,SVG);m.getJSONArray("sketches").getJSONObject(0).put("file","../manual.svg");fails(()->lib.sync(ADDRESS,fetch(m,SVG)));
  JSONObject dup=manifest(LIB,SVG);dup.getJSONArray("sketches").put(dup.getJSONArray("sketches").getJSONObject(0));fails(()->lib.sync(ADDRESS,fetch(dup,SVG)));
  JSONObject large=manifest(LIB,SVG);large.getJSONArray("sketches").getJSONObject(0).put("bytes",SketchLibrary.MAX_FILE+1);fails(()->lib.sync(ADDRESS,fetch(large,SVG)));
  JSONObject total=manifest(LIB,SVG);JSONArray entries=total.getJSONArray("sketches");entries.getJSONObject(0).put("bytes",SketchLibrary.MAX_FILE);for(int i=1;i<9;i++) {String id=UUID.randomUUID().toString();entries.put(new JSONObject(entries.getJSONObject(0).toString()).put("id",id).put("file",id+".svg"));}fails(()->lib.sync(ADDRESS,fetch(total,SVG)));
  JSONObject count=manifest(LIB,SVG);JSONArray many=count.getJSONArray("sketches");for(int i=1;i<65;i++) {String id=UUID.randomUUID().toString();many.put(new JSONObject(many.getJSONObject(0).toString()).put("id",id).put("file",id+".svg"));}fails(()->lib.sync(ADDRESS,fetch(count,SVG)));
  fails(()->lib.sync(ADDRESS,url->new ByteArrayInputStream(new byte[SketchLibrary.MAX_MANIFEST+1])));assertNull(lib.current());
 }
 @Test public void cancellationPreservesPreviousSnapshot() throws Exception {
  SketchLibrary lib=new SketchLibrary(folder.newFolder());SketchLibrary.Catalog old=lib.sync(ADDRESS,fetch(manifest(LIB,SVG),SVG));Thread.currentThread().interrupt();try {fails(()->lib.sync(ADDRESS,fetch(manifest(LIB,SVG),SVG)));} finally {Thread.interrupted();}assertEquals(old.snapshot,lib.current().snapshot);
 }
 @Test public void midTransferCancellationAndShortBodyKeepOldFiles() throws Exception {
  SketchLibrary lib=new SketchLibrary(folder.newFolder());SketchLibrary.Catalog old=lib.sync(ADDRESS,fetch(manifest(LIB,SVG),SVG));byte[] changed="changed sketch content".getBytes(StandardCharsets.UTF_8);JSONObject m=manifest(LIB,changed);
  fails(()->lib.sync(ADDRESS,fetch(m,new byte[0])));assertEquals(old.snapshot,lib.current().snapshot);
  try {fails(()->lib.sync(ADDRESS,url->url.getPath().endsWith("manifest.json")?fetch(m,changed).open(url):new ByteArrayInputStream(changed) {@Override public synchronized int read(byte[] b,int offset,int length) {Thread.currentThread().interrupt();return super.read(b,offset,length);}}));} finally {Thread.interrupted();}
  assertEquals(old.snapshot,lib.current().snapshot);assertArrayEquals(SVG,Files.readAllBytes(old.file(old.entries.get(0)).toPath()));
 }
 @Test public void repairsMissingFilesAndDamagedIndexWithoutLosingOtherMac() throws Exception {
  File files=folder.newFolder();SketchLibrary lib=new SketchLibrary(files);SketchLibrary.Catalog old=lib.sync(ADDRESS,fetch(manifest(LIB,SVG),SVG));SketchLibrary.Catalog other=lib.sync(ADDRESS,fetch(manifest(OTHER,SVG),SVG));lib.activate(LIB);
  assertTrue(old.file(old.entries.get(0)).delete());fails(lib::current);lib.sync(ADDRESS,fetch(manifest(LIB,SVG),SVG));assertEquals(1,lib.current().entries.size());
  File index=new File(files,"wifi-sketch-library/catalog.json");Files.write(index.toPath(),"damaged index".getBytes(StandardCharsets.UTF_8));fails(lib::current);
  byte[] damaged=Files.readAllBytes(index.toPath());fails(()->lib.sync(ADDRESS,url->{throw new IOException("Offline");}));assertArrayEquals(damaged,Files.readAllBytes(index.toPath()));assertTrue(other.file(other.entries.get(0)).exists());
  lib.sync(ADDRESS,fetch(manifest(LIB,SVG),SVG));assertEquals(2,lib.saved().size());lib.activate(OTHER);assertArrayEquals(SVG,Files.readAllBytes(lib.current().file(lib.current().entries.get(0)).toPath()));
 }
 @Test public void missingSnapshotOffersPairRecoveryControl() throws Exception {
  org.robolectric.android.controller.ActivityController<MainActivity> controller=org.robolectric.Robolectric.buildActivity(MainActivity.class).setup();android.app.Activity activity=controller.get();SketchLibrary lib=new SketchLibrary(activity.getFilesDir());SketchLibrary.Catalog saved=lib.sync(ADDRESS,fetch(manifest(LIB,SVG),SVG));assertTrue(saved.file(saved.entries.get(0)).delete());
  java.lang.reflect.Method open=MainActivity.class.getDeclaredMethod("libraryDialog");open.setAccessible(true);open.invoke(activity);
  android.widget.Button recovery=findButton(activity.getWindow().getDecorView(),"Pair and sync");assertNotNull(recovery);recovery.performClick();
  android.app.AlertDialog dialog=org.robolectric.shadows.ShadowAlertDialog.getLatestAlertDialog();assertEquals("Pair and sync",dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).getText().toString());dialog.dismiss();controller.pause().stop().destroy();
 }
 private static android.widget.Button findButton(android.view.View view,String label) {
  if(view instanceof android.widget.Button && ((android.widget.Button)view).getText().toString().equals(label)) return (android.widget.Button)view;
  if(view instanceof android.view.ViewGroup) for(int i=0;i<((android.view.ViewGroup)view).getChildCount();i++) {android.widget.Button found=findButton(((android.view.ViewGroup)view).getChildAt(i),label);if(found!=null)return found;}
  return null;
 }
 @Test public void acceptsOnlyExplicitLocalAddresses() throws Exception {
  SketchLibrary.pairingURL(ADDRESS);SketchLibrary.pairingURL(ADDRESS.replace("127.0.0.1","192.168.1.23"));for(String bad:new String[]{ADDRESS.replace("127.0.0.1","example.com"),ADDRESS.replace("127.0.0.1","8.8.8.8"),ADDRESS.replace("http:","https:"),ADDRESS+"?leak=yes",ADDRESS.replace("127.0.0.1","user@127.0.0.1"),ADDRESS.replace(":48765","")}) fails(()->SketchLibrary.pairingURL(bad));
 }
 @Test public void realHTTPTransferAndRedirectRejection() throws Exception {
  JSONObject m=manifest(LIB,SVG);ServerSocket server=new ServerSocket(0,8,InetAddress.getByName("127.0.0.1"));
  Thread responder=new Thread(()-> {while(!server.isClosed()) try(Socket client=server.accept()) {
   BufferedReader in=new BufferedReader(new InputStreamReader(client.getInputStream(),StandardCharsets.UTF_8));String request=in.readLine();String header;while((header=in.readLine())!=null && !header.isEmpty()) { }
   boolean redirect=request.contains("b".repeat(64));byte[] body=request.contains("manifest.json")?m.toString().getBytes(StandardCharsets.UTF_8):SVG;
   String head=redirect?"HTTP/1.1 302 Found\r\nLocation: http://8.8.8.8/never\r\nContent-Length: 0\r\nConnection: close\r\n\r\n":"HTTP/1.1 200 OK\r\nContent-Length: "+body.length+"\r\nConnection: close\r\n\r\n";
   client.getOutputStream().write(head.getBytes(StandardCharsets.UTF_8));if(!redirect) client.getOutputStream().write(body);
  } catch(IOException ignored) { }});responder.setDaemon(true);responder.start();
  try {String base="http://127.0.0.1:"+server.getLocalPort()+"/"+"a".repeat(64)+"/";SketchLibrary lib=new SketchLibrary(folder.newFolder());lib.sync(base,SketchLibrary.HTTP);assertEquals(1,lib.current().entries.size());fails(()->lib.sync(base.replace("a".repeat(64),"b".repeat(64)),SketchLibrary.HTTP));assertEquals(1,lib.current().entries.size());} finally {server.close();responder.join(1000);}

 }
 /** The fixture URL is read privately and never printed. */
 @Test public void liveMacInteroperabilityFixture() throws Exception {
  String path=System.getenv("SQUIGGLE_LIBRARY_URL_FILE");Assume.assumeTrue("Live Mac fixture configured",path!=null);String base=new String(Files.readAllBytes(new File(path).toPath()),StandardCharsets.UTF_8).trim();File files=folder.newFolder();SketchLibrary lib=new SketchLibrary(files);SketchLibrary.Catalog catalog=lib.sync(base,SketchLibrary.HTTP);
  String expected=System.getenv("SQUIGGLE_LIBRARY_EXPECTED_COUNT");assertEquals(expected==null?1:Integer.parseInt(expected),catalog.entries.size());
  for(SketchLibrary.Entry entry:catalog.entries) try(InputStream input=new FileInputStream(catalog.file(entry))) {assertFalse(SvgDrawing.read(input,entry.title).paths.isEmpty());}assertEquals(catalog.entries.size(),new SketchLibrary(files).current().entries.size());System.out.println("Live Mac library imported and reopened offline: "+catalog.entries.size()+" sketches");
 }
}
