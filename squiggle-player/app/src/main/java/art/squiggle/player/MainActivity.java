package art.squiggle.player;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.database.Cursor;
import android.view.View;
import android.view.WindowInsets;
import android.widget.*;
import java.io.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private InkView ink;
    private DrawingAwake drawingAwake;
    private Button play, importButton, sampleButton, libraryButton;
    private SketchLibrary library;
    private final ExecutorService syncWorker=Executors.newSingleThreadExecutor();
    private int syncGeneration;
    private boolean syncing;
    private TextView title,status,speedLabel,refreshNote;
    private LinearLayout controls, canvasPage, libraryPage;
    private SvgDrawing currentDrawing;
    private File currentFile;
    private boolean inLibrary, settingSleep;
    private final BooxRefresh refresh=new BooxRefresh();
    private final ExecutorService loader=Executors.newSingleThreadExecutor();
    private String refreshChoice="Fast";
    private int generation;
    private boolean importing;

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        drawingAwake=new DrawingAwake(this);
        library=new SketchLibrary(getFilesDir());
        LinearLayout root=new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setBackgroundColor(Color.WHITE);
        root.setOnApplyWindowInsetsListener((v,insets)-> {
            android.graphics.Insets bars=insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            v.setPadding(bars.left,bars.top,bars.right,bars.bottom); return insets;
        });
        setContentView(root);
        LinearLayout navigation=row(); navigation.setPadding(dp(16),dp(8),dp(16),dp(8)); root.addView(navigation);
        navigation.addView(button("Back to canvas",this::showCanvas),new LinearLayout.LayoutParams(0,dp(56),1));
        libraryButton=button("Library",this::libraryDialog); navigation.addView(libraryButton,new LinearLayout.LayoutParams(0,dp(56),1));
        FrameLayout pages=new FrameLayout(this); root.addView(pages,new LinearLayout.LayoutParams(-1,0,1));
        canvasPage=new LinearLayout(this); canvasPage.setOrientation(LinearLayout.VERTICAL); pages.addView(canvasPage,new FrameLayout.LayoutParams(-1,-1));
        title=text("SQUIGGLE",22); title.setTypeface(null,android.graphics.Typeface.BOLD); title.setPadding(dp(20),0,dp(20),dp(6)); title.setMaxLines(1); title.setEllipsize(android.text.TextUtils.TruncateAt.END); canvasPage.addView(title);
        ink=new InkView(this); canvasPage.addView(ink,new LinearLayout.LayoutParams(-1,0,1));
        controls=new LinearLayout(this); controls.setOrientation(LinearLayout.VERTICAL); controls.setPadding(dp(16),0,dp(16),dp(10)); canvasPage.addView(controls);
        status=text("Ready",16); status.setPadding(dp(4),dp(4),0,dp(8)); controls.addView(status);
        LinearLayout buttons=row(); controls.addView(buttons);
        play=button("Draw",()->{ if(ink.isRunning()) ink.pause(); else ink.play(); }); buttons.addView(play,new LinearLayout.LayoutParams(0,dp(60),1));
        buttons.addView(button("Redraw",()->{ ink.restart(); ink.play(); }),new LinearLayout.LayoutParams(0,dp(60),1));
        buttons.addView(button("Sleep image",this::sleepDialog),new LinearLayout.LayoutParams(0,dp(60),1));
        LinearLayout speedRow=row(); speedRow.setPadding(0,dp(8),0,dp(8)); controls.addView(speedRow);
        speedLabel=text("Speed · 70",18); speedRow.addView(speedLabel,new LinearLayout.LayoutParams(dp(140),dp(48)));
        SeekBar speed=new SeekBar(this); speed.setMax(100); speed.setProgress(68); speed.setContentDescription("Drawing speed"); speedRow.addView(speed,new LinearLayout.LayoutParams(0,dp(48),1));
        speed.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            public void onProgressChanged(SeekBar s,int p,boolean user) { float value=(float)(Math.pow(500,p/100.0)); ink.setSpeed(value); speedLabel.setText("Speed · "+Math.round(value)); }
            public void onStartTrackingTouch(SeekBar s) {} public void onStopTrackingTouch(SeekBar s) {}
        });
        LinearLayout extras=row(); controls.addView(extras);
        extras.addView(button("Options",this::options),new LinearLayout.LayoutParams(0,dp(52),1));
        extras.addView(button("Clean screen",()->{ ink.pause(); refresh.clean(ink); }),new LinearLayout.LayoutParams(0,dp(52),1));
        refreshNote=text("",14); refreshNote.setPadding(dp(4),dp(8),0,0); controls.addView(refreshNote);
        libraryPage=new LinearLayout(this); libraryPage.setOrientation(LinearLayout.VERTICAL); libraryPage.setBackgroundColor(Color.WHITE); libraryPage.setPadding(dp(20),dp(8),dp(20),dp(16)); libraryPage.setVisibility(View.GONE); pages.addView(libraryPage,new FrameLayout.LayoutParams(-1,-1));
        importButton=button("Import SVG",this::openSvg); sampleButton=button("Spirograph sample",()->{loadSample();showCanvas();});
        ink.listener=(running,finished,fraction)-> {
            drawingAwake.setDrawing(running);
            play.setText(running?"Pause":finished?"Replay":"Draw");
            refreshNote.setText(ink.rendererStatus());
            status.setText(syncing?"Syncing library…":importing?"Opening drawing…":finished?"Complete":running?"Drawing…":fraction>0?"Paused · "+(int)(fraction*100)+"%":"Ready · choose Draw to begin");
        };
        ink.post(()->refreshNote.setText(refresh.apply(ink,refreshChoice)));
        loadSample();
        File sleepFile=new File(getFilesDir(),"sleep-drawing.svg");
        if(sleepFile.isFile() && getPreferences(MODE_PRIVATE).getBoolean("sleepIsDrawing",false))
            load(()->new FileInputStream(sleepFile),getPreferences(MODE_PRIVATE).getString("sleepName","Sleep drawing"));
    }
    private int dp(float n) { return Math.round(n*getResources().getDisplayMetrics().density); }
    private TextView text(String s,int size) { TextView t=new TextView(this); t.setText(s); t.setTextSize(size); t.setTextColor(Color.BLACK); return t; }
    private LinearLayout row() { LinearLayout r=new LinearLayout(this); r.setOrientation(LinearLayout.HORIZONTAL); r.setGravity(android.view.Gravity.CENTER_VERTICAL); return r; }
    private Button button(String name,Runnable action) {
        Button b=new Button(this); b.setText(name); b.setTextSize(18); b.setTypeface(null,android.graphics.Typeface.BOLD); b.setAllCaps(false);
        b.setTextColor(new android.content.res.ColorStateList(new int[][]{new int[]{-android.R.attr.state_enabled},new int[]{}},new int[]{0xff444444,Color.BLACK}));
        android.graphics.drawable.StateListDrawable states=new android.graphics.drawable.StateListDrawable();
        states.addState(new int[]{android.R.attr.state_pressed},buttonBackground(0xffdddddd)); states.addState(new int[]{},buttonBackground(Color.WHITE));
        b.setBackground(states); b.setBackgroundTintList(null); b.setMinHeight(dp(56)); b.setMinimumHeight(dp(56)); b.setPadding(dp(12),dp(8),dp(12),dp(8));
        b.setOnClickListener(v->action.run()); return b;
    }
    private android.graphics.drawable.Drawable buttonBackground(int color) {
        android.graphics.drawable.GradientDrawable d=new android.graphics.drawable.GradientDrawable(); d.setColor(color); d.setStroke(dp(2),Color.BLACK); d.setCornerRadius(dp(5));
        return new android.graphics.drawable.InsetDrawable(d,dp(4));
    }
    private void showCanvas() { inLibrary=false; libraryPage.setVisibility(View.GONE); canvasPage.setVisibility(View.VISIBLE); }
    @Override public void onBackPressed() { if(inLibrary) showCanvas(); else super.onBackPressed(); }
    private void openSvg() {
        if(settingSleep) return;
        ink.pause();
        Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT); intent.setType("*/*"); intent.addCategory(Intent.CATEGORY_OPENABLE);
        startActivityForResult(intent,1);
    }
    @Override protected void onActivityResult(int request,int result,Intent data) {
        super.onActivityResult(request,result,data);
        if(result!=RESULT_OK || data==null || data.getData()==null) return;
        if(request==2) {setSleepPhoto(data.getData());return;}
        if(request!=1) return;
        Uri uri=data.getData();
        String name="Imported drawing";
        try(Cursor c=getContentResolver().query(uri,new String[]{OpenableColumns.DISPLAY_NAME},null,null,null)) {
            if(c!=null && c.moveToFirst()) name=c.getString(0);
        } catch(RuntimeException ignored) {}
        final String drawingName=name;
        load(()->getContentResolver().openInputStream(uri),drawingName);
    }
    interface Source { InputStream open() throws Exception; }
    private void loadSample() {
        if(settingSleep) return;
        generation++;
        importing=false;
        play.setEnabled(true); importButton.setEnabled(true); sampleButton.setEnabled(true);
        SvgDrawing drawing=GenerativeDrawing.spirograph();
        if(currentFile!=null) currentFile.delete();
        currentDrawing=drawing; currentFile=null; ink.setDrawing(drawing); title.setText(drawing.name);
    }
    private void load(Source source,String name) {
        showCanvas();
        ink.pause(); importing=true; status.setText("Opening drawing…"); play.setEnabled(false); importButton.setEnabled(false); sampleButton.setEnabled(false);
        int token=++generation;
        loader.submit(()-> {
            SvgDrawing drawing=null; String error=null;
            File staged=null;
            try(InputStream input=source.open()) {
                if(input==null) throw new IOException("Could not open the file");
                staged=File.createTempFile("drawing-",".svg",getCacheDir());
                try(OutputStream out=new FileOutputStream(staged)) {copyBounded(input,out);}
                try(InputStream savedInput=new FileInputStream(staged)) { drawing=SvgDrawing.read(savedInput,name); }
            } catch(Exception e) { error=e.getMessage()==null?"The SVG could not be read":e.getMessage(); }
            File savedFile=staged;
            SvgDrawing ready=drawing; String failure=error;
            runOnUiThread(()-> {
                if(isDestroyed() || token!=generation) {if(savedFile!=null) savedFile.delete();return;}
                importing=false; play.setEnabled(true); importButton.setEnabled(true); sampleButton.setEnabled(true);
                if(ready!=null) {
                    try {
                        ink.setDrawing(ready); title.setText(ready.name);
                        if(currentFile!=null) currentFile.delete(); currentFile=savedFile; currentDrawing=ready; showCanvas();
                        if(ready.hasColor()) {
                            refreshChoice="Quality";
                            refresh.apply(ink,refreshChoice);
                            refreshNote.setText(ink.rendererStatus());
                        }
                    }
                    catch(RuntimeException e) { showError(e.getMessage()); loadSample(); }
                } else { if(savedFile!=null) savedFile.delete(); status.setText("Could not open SVG"); showError(failure); }
            });
        });
    }
    private String pairingAddress() {return getPreferences(MODE_PRIVATE).getString("libraryAddress","");}
    private void libraryError(String message) {new AlertDialog.Builder(this).setTitle("Library").setMessage(message).setPositiveButton("OK",null).show();}
    private void libraryDialog() {
        ink.pause(); inLibrary=true; canvasPage.setVisibility(View.INVISIBLE); libraryPage.setVisibility(View.VISIBLE); libraryPage.removeAllViews();
        TextView heading=text("Your library",26); heading.setTypeface(null,android.graphics.Typeface.BOLD); heading.setPadding(dp(4),dp(8),0,dp(12)); libraryPage.addView(heading);
        LinearLayout actions=row(); libraryPage.addView(actions);
        if(importButton.getParent()!=null) ((android.view.ViewGroup)importButton.getParent()).removeView(importButton);
        actions.addView(importButton,new LinearLayout.LayoutParams(0,dp(60),1));
        actions.addView(button(syncing?"Syncing…":"Sync now",()->{if(pairingAddress().isEmpty()) pairDialog();else syncLibrary();}),new LinearLayout.LayoutParams(0,dp(60),1));
        libraryPage.addView(button("Pair / saved Macs",this::libraryConnections));
        TextView hint=text("Select a sketch to open it on the canvas. Downloaded sketches work offline.",18); hint.setPadding(dp(4),dp(16),dp(4),dp(16)); libraryPage.addView(hint);
        ScrollView scroll=new ScrollView(this); libraryPage.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout list=new LinearLayout(this); list.setOrientation(LinearLayout.VERTICAL); scroll.addView(list);
        try {
            SketchLibrary.Catalog catalog=library.current();
            if(catalog==null || catalog.entries.isEmpty()) list.addView(text("No sketches yet. Import an SVG, or pair your Mac and sync its library.",20));
            else for(SketchLibrary.Entry entry:catalog.entries) {
                Button sketch=button(entry.title,()->{if(settingSleep) return;showCanvas();load(()->new FileInputStream(catalog.file(entry)),entry.title);});
                sketch.setGravity(android.view.Gravity.CENTER_VERTICAL|android.view.Gravity.START); list.addView(sketch,new LinearLayout.LayoutParams(-1,dp(76)));
            }
        } catch(IOException failure) {list.addView(text("Could not read saved library. Pair and sync again to recover it.",20));list.addView(button("Pair and sync",this::pairDialog));}
        if(sampleButton.getParent()!=null) ((android.view.ViewGroup)sampleButton.getParent()).removeView(sampleButton);
        File sleepFile=new File(getFilesDir(),"sleep-drawing.svg");
        if(sleepFile.isFile() && getPreferences(MODE_PRIVATE).getBoolean("sleepIsDrawing",false))
            libraryPage.addView(button("Open sleep drawing",()->{if(settingSleep)return;showCanvas();load(()->new FileInputStream(sleepFile),getPreferences(MODE_PRIVATE).getString("sleepName","Sleep drawing"));}),new LinearLayout.LayoutParams(-1,dp(60)));
        libraryPage.addView(sampleButton,new LinearLayout.LayoutParams(-1,dp(60)));
    }
    private void libraryConnections() {
        try {
            java.util.List<SketchLibrary.Catalog> saved=library.saved();
            String[] labels=new String[saved.size()+1];labels[0]="Pair a Mac";
            for(int i=0;i<saved.size();i++) labels[i+1]=(saved.get(i).entries.isEmpty()?"Empty library":saved.get(i).entries.get(0).title)+" · "+saved.get(i).entries.size()+" sketches";
            new AlertDialog.Builder(this).setTitle("Mac libraries").setItems(labels,(d,which)-> {
                if(which==0) pairDialog();else activateLibrary(saved.get(which-1).libraryID);
            }).setNegativeButton("Cancel",null).show();
        } catch(IOException failure) {pairDialog();}
    }
    private void activateLibrary(String id) {
        if(syncing) return;
        syncing=true;libraryButton.setEnabled(false);status.setText("Opening saved library…");int token=++syncGeneration;
        syncWorker.submit(()-> {
            String error=null;try {library.activate(id);} catch(IOException failure) {error=failure.getMessage();}String failure=error;
            runOnUiThread(()-> {
                if(isDestroyed() || token!=syncGeneration) return;
                syncing=false;libraryButton.setEnabled(true);
                if(failure!=null) {libraryError(failure);return;}
                String address=getPreferences(MODE_PRIVATE).getString("libraryAddress:"+id,"");getPreferences(MODE_PRIVATE).edit().putString("libraryAddress",address).putString("pairedLibraryID",id).apply();libraryDialog();
            });
        });
    }
    private void pairDialog() {
        EditText address=new EditText(this);address.setSingleLine(false);address.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_VARIATION_URI);address.setText(pairingAddress());address.setHint("Optional manual pairing address");
        LinearLayout panel=new LinearLayout(this);panel.setOrientation(LinearLayout.VERTICAL);panel.setPadding(dp(24),dp(12),dp(24),dp(12));
        panel.addView(text("Connect your BOOX to the Mac by USB. In the Mac’s BOOX Library, enable sharing and click Pair connected BOOX. Then close this dialog and choose Sync now. The cable is preferred; Wi-Fi works when unplugged. You can still enter an address below for manual pairing.",14));panel.addView(address);
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle("Pair Mac").setView(panel).setPositiveButton("Pair and sync",null).setNegativeButton("Cancel",null).create();
        dialog.setOnShowListener(d->dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v-> {
            String value=address.getText().toString().trim();
            try {SketchLibrary.pairingURL(value);getPreferences(MODE_PRIVATE).edit().putString("libraryAddress",value).remove("pairedLibraryID").apply();dialog.dismiss();syncLibrary();}
            catch(IOException failure) {address.setError(failure.getMessage());}
        }));dialog.show();
    }
    private void syncLibrary() {
        if(syncing) return;
        ink.pause();syncing=true;libraryButton.setEnabled(false);status.setText("Syncing library…");if(inLibrary) libraryDialog();int token=++syncGeneration;String address=pairingAddress(),expectedID=getPreferences(MODE_PRIVATE).getString("pairedLibraryID","");
        syncWorker.submit(()-> {
            String error=null;SketchLibrary.Catalog result=null;
            try {result=library.syncConnected(address,expectedID,SketchLibrary.HTTP);} catch(IOException failure) {error=failure.getMessage();}
            String failure=error;SketchLibrary.Catalog ready=result;
            runOnUiThread(()-> {if(isDestroyed() || token!=syncGeneration) return;syncing=false;libraryButton.setEnabled(true);status.setText(failure==null?"Library synced · available offline":"Sync failed · saved sketches kept");if(failure==null) {getPreferences(MODE_PRIVATE).edit().putString("libraryAddress:"+ready.libraryID,address).putString("pairedLibraryID",ready.libraryID).apply();libraryDialog();}else libraryError(failure);});
        });
    }
    private static void copyBounded(InputStream input,OutputStream output) throws IOException {
        byte[] buffer=new byte[65536]; long total=0; int n;
        while((n=input.read(buffer))!=-1) {if((total+=n)>32L*1024*1024) throw new IOException("Choose a file smaller than 32 MB");output.write(buffer,0,n);}
    }
    private void sleepDialog() {
        ink.pause(); if(settingSleep || importing) return;
        new AlertDialog.Builder(this).setTitle("Sleep image").setMessage("Use the complete drawing as your BOOX sleep image, or choose a photo. To watch a drawing again, wake the BOOX and tap Redraw. The sleep image itself cannot respond to taps.")
            .setPositiveButton("Use this drawing",(d,w)->setSleepDrawing())
            .setNeutralButton("Choose photo",(d,w)->{Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE);startActivityForResult(pick,2);})
            .setNegativeButton("Cancel",null).show();
    }
    private void setSleepDrawing() {
        if(currentDrawing==null || settingSleep) return;
        ink.pause();settingSleep=true;status.setText("Preparing sleep image…");
        SvgDrawing selected=currentDrawing;File source=currentFile;
        android.graphics.Rect screen=getWindowManager().getCurrentWindowMetrics().getBounds();float pen=ink.penWidthPixels();
        loader.submit(()-> {
            String error=null;File image=null;
            try {
                android.graphics.Bitmap bitmap=SleepImage.render(selected,screen.width(),screen.height(),pen);
                try {image=SleepImage.publish(this,bitmap);} finally {bitmap.recycle();}
                File stable=new File(getFilesDir(),"sleep-drawing.svg");
                if(source!=null) {File staged=new File(getFilesDir(),"sleep-drawing.tmp");try(InputStream in=new FileInputStream(source);OutputStream out=new FileOutputStream(staged)) {copyBounded(in,out);}if(!staged.renameTo(stable)) throw new IOException("Could not save the sleep drawing");}
                else {stable.delete();}
            } catch(Exception e) {error=e.getMessage();}
            File ready=image;String failure=error;
            runOnUiThread(()-> {if(isDestroyed()) return;settingSleep=false;
                if(ready==null || failure!=null) {status.setText("Sleep image failed");showError(failure==null?"Could not create the image":failure);return;}
                requestSleepImage(ready,selected.name,source!=null);
            });
        });
    }
    private void setSleepPhoto(Uri uri) {
        ink.pause();settingSleep=true;status.setText("Preparing sleep photo…");
        loader.submit(()-> {
            File image=null;String error=null;
            try {android.graphics.Rect screen=getWindowManager().getCurrentWindowMetrics().getBounds();
                android.graphics.ImageDecoder.Source source=android.graphics.ImageDecoder.createSource(getContentResolver(),uri);
                android.graphics.Bitmap bitmap=android.graphics.ImageDecoder.decodeBitmap(source,(decoder,info,s)-> {
                    decoder.setAllocator(android.graphics.ImageDecoder.ALLOCATOR_SOFTWARE);
                    int w=info.getSize().getWidth(),h=info.getSize().getHeight();float scale=Math.min(1f,Math.min(screen.width()/(float)w,screen.height()/(float)h));decoder.setTargetSize(Math.max(1,Math.round(w*scale)),Math.max(1,Math.round(h*scale)));
                });
                try {image=SleepImage.publish(this,bitmap);} finally {bitmap.recycle();}
            } catch(Exception e) {error=e.getMessage();}
            File ready=image;String failure=error;
            runOnUiThread(()-> {if(isDestroyed()) return;settingSleep=false;if(ready==null) {showError(failure==null?"Could not open photo":failure);return;}requestSleepImage(ready,"Photo",false);});
        });
    }
    private void requestSleepImage(File image,String name,boolean drawing) {
        try {
            if(!com.onyx.android.sdk.api.device.screensaver.ScreenResourceManager.setScreensaver(this,image.getAbsolutePath(),true)) throw new IOException("BOOX could not accept this image");
            getPreferences(MODE_PRIVATE).edit().putBoolean("sleepIsDrawing",drawing).putString("sleepName",name).apply();
            status.setText(name.equals("Photo")?"Sleep photo sent to BOOX":"Sleep image sent to BOOX · wake and tap Redraw");
        } catch(Exception | LinkageError e) {new AlertDialog.Builder(this).setTitle("Sleep image saved").setMessage("Open BOOX Screensaver settings and select the image in Pictures / Squiggle. This firmware did not accept automatic setup.").setPositiveButton("OK",null).show();}
    }
    private void showError(String message) { new AlertDialog.Builder(this).setTitle("Could not open drawing").setMessage(message).setPositiveButton("OK",null).show(); }
    private void options() {
        ink.pause();
        LinearLayout panel=new LinearLayout(this); panel.setOrientation(LinearLayout.VERTICAL); panel.setPadding(dp(24),dp(12),dp(24),dp(12));
        panel.addView(text("Drawing method",14));
        Spinner renderer=spinner(new String[]{"Direct pen","Canvas"}); renderer.setSelection(rendererIndex); panel.addView(renderer);
        panel.addView(text("Canvas refresh mode",14));
        Spinner modes=spinner(new String[]{"System","Fast","Animation","Quality"}); panel.addView(modes);
        modes.setSelection(java.util.Arrays.asList("System","Fast","Animation","Quality").indexOf(refreshChoice));
        panel.addView(text("Updates per second",14)); Spinner cadence=spinner(new String[]{"10","20","30","60"}); cadence.setSelection(cadenceIndex); panel.addView(cadence);
        panel.addView(text("Line width",14)); Spinner width=spinner(new String[]{"Fine","Medium","Bold"}); width.setSelection(widthIndex); panel.addView(width);
        TextView hint=text("Try Direct pen at 60 updates/second first. Speed is measured in screen distance per second. Each pen lift pauses for 0.2 seconds.",14); hint.setPadding(0,dp(12),0,0); panel.addView(hint);
        new AlertDialog.Builder(this).setTitle("Drawing options").setView(panel).setNegativeButton("Cancel",null).setPositiveButton("Apply",(d,w)-> {
            rendererIndex=renderer.getSelectedItemPosition(); ink.setDirectEnabled(rendererIndex==0);
            refreshChoice=modes.getSelectedItem().toString(); cadenceIndex=cadence.getSelectedItemPosition(); widthIndex=width.getSelectedItemPosition();
            ink.setFps(Integer.parseInt(cadence.getSelectedItem().toString())); ink.setWidth(new float[]{0.6f,1f,1.8f}[widthIndex]);
            refreshNote.setText(refresh.apply(ink,refreshChoice));
        }).show();
    }
    private int cadenceIndex=3,widthIndex=1,rendererIndex=0;
    private Spinner spinner(String[] values) { Spinner s=new Spinner(this); ArrayAdapter<String> adapter=new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,values); s.setAdapter(adapter); return s; }
    @Override protected void onPause() { ink.pause(); refresh.release(ink); super.onPause(); }
    @Override protected void onResume() { super.onResume(); if(ink!=null) ink.post(()->refreshNote.setText(refresh.apply(ink,refreshChoice))); }
    @Override protected void onDestroy() { drawingAwake.setDrawing(false); generation++; syncGeneration++; syncWorker.shutdownNow(); loader.shutdownNow(); super.onDestroy(); }
}
