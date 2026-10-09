package art.squiggle.player;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import java.net.URL;
import java.util.UUID;

/** Bootstrap from the already-authorized ADB cable. The manifest requires the
 * system DUMP permission, which the ADB shell holds but ordinary apps do not. */
public final class PairingReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context,Intent intent) {
        try {
            savePairing(context,intent);
            setResultCode(0);setResultData("Squiggle paired");
        } catch(Exception failure) {setResultCode(1);setResultData("Pairing failed; install the current Squiggle player and try again");}
    }
    static void savePairing(Context context,Intent intent) throws Exception {
            if(!"art.squiggle.player.PAIR_USB".equals(intent.getAction())) throw new IllegalArgumentException();
            String address=intent.getStringExtra("address"),id=intent.getStringExtra("libraryId");
            URL url=SketchLibrary.pairingURL(address);
            if(id==null || !UUID.fromString(id).toString().equals(id) || url.getPort()!=48765) throw new IllegalArgumentException();
            SharedPreferences prefs=context.getSharedPreferences("MainActivity",Context.MODE_PRIVATE);
            // Preserve every other library and its pairing. The network address
            // remains separate from the temporary cable route.
            if(!prefs.edit().putString("libraryAddress",url.toString()).putString("pairedLibraryID",id)
                    .putString("libraryAddress:"+id,url.toString()).commit()) throw new IllegalStateException();
    }
}
