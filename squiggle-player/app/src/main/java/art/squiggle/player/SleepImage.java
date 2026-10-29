package art.squiggle.player;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.graphics.*;
import android.net.Uri;
import android.os.Environment;
import android.provider.MediaStore;
import java.io.*;

/** A complete artwork export independent of the live playback bitmap. */
final class SleepImage {
    static Bitmap render(SvgDrawing drawing,int width,int height,float penWidth) {
        Bitmap bitmap=Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888);
        bitmap.eraseColor(Color.WHITE);Canvas canvas=new Canvas(bitmap);
        float margin=Math.min(width,height)*0.045f;
        float scale=Math.min((width-2*margin)/drawing.bounds.width(),(height-2*margin)/drawing.bounds.height());
        Matrix fit=new Matrix();fit.setValues(new float[]{scale,0,(width-drawing.bounds.width()*scale)/2-drawing.bounds.left*scale,
            0,scale,(height-drawing.bounds.height()*scale)/2-drawing.bounds.top*scale,0,0,1});
        Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);paint.setStrokeCap(Paint.Cap.ROUND);paint.setStrokeJoin(Paint.Join.ROUND);
        for(int i=0;i<drawing.paths.size();i++) {
            Path path=new Path(drawing.paths.get(i));path.transform(fit);
            paint.setStyle(Paint.Style.STROKE);paint.setColor(drawing.colors.get(i));
            float factor=drawing.widthFactors.get(i);paint.setStrokeWidth(penWidth*(factor==0?1:factor));canvas.drawPath(path,paint);
            if(Color.alpha(drawing.fills.get(i))>0) {paint.setStyle(Paint.Style.FILL);paint.setColor(drawing.fills.get(i));canvas.drawPath(path,paint);}
        }
        return bitmap;
    }
    static File publish(Context context,Bitmap bitmap) throws IOException {
        ContentValues values=new ContentValues();values.put(MediaStore.Images.Media.DISPLAY_NAME,"Squiggle-sleep-"+System.currentTimeMillis()+".png");
        values.put(MediaStore.Images.Media.MIME_TYPE,"image/png");values.put(MediaStore.Images.Media.RELATIVE_PATH,Environment.DIRECTORY_PICTURES+"/Squiggle");values.put(MediaStore.Images.Media.IS_PENDING,1);
        Uri uri=context.getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,values);
        if(uri==null) throw new IOException("Could not save sleep image");
        try {
            try(OutputStream output=context.getContentResolver().openOutputStream(uri)) {
                if(output==null || !bitmap.compress(Bitmap.CompressFormat.PNG,100,output)) throw new IOException("Could not write sleep image");
            }
            values.clear();values.put(MediaStore.Images.Media.IS_PENDING,0);context.getContentResolver().update(uri,values,null,null);
            String path=null;
            // BOOX's documented screensaver API accepts an on-device filesystem path.
            try(Cursor c=context.getContentResolver().query(uri,new String[]{MediaStore.Images.Media.DATA},null,null,null)) {if(c!=null && c.moveToFirst()) path=c.getString(0);}
            if(path==null) throw new IOException("The image was saved but its BOOX path is unavailable");
            File file=new File(path);if(file.length()>10L*1024*1024) throw new IOException("Sleep image exceeds BOOX’s 10 MB limit");
            return file;
        } catch(Exception e) {context.getContentResolver().delete(uri,null,null);if(e instanceof IOException) throw (IOException)e;throw new IOException("Could not save sleep image",e);}
    }
}
