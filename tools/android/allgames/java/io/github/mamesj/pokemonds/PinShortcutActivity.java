// Asks Android's launcher to pin a shortcut that starts one game straight away (GameActivity reads the "game"
// extra). Started with extras: game (the four-letter code, "IREO"), label (the shortcut's name) and icon (the path
// of a picture, optional). Android shows its own "add to home screen" prompt; the player confirms it.
package io.github.mamesj.pokemonds;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;

public class PinShortcutActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        try {
            pin();
        } catch (Exception e) {
            Log.e("PokemonDS", "pinning the shortcut", e);
        }
        finish();
    }

    private void pin() {
        String game = getIntent().getStringExtra("game");
        String label = getIntent().getStringExtra("label");
        String icon = getIntent().getStringExtra("icon");
        if (game == null || !game.matches("[A-Za-z0-9]{4}") || Build.VERSION.SDK_INT < 26) return;
        ShortcutManager sm = getSystemService(ShortcutManager.class);
        if (sm == null || !sm.isRequestPinShortcutSupported()) return;
        Intent start = new Intent(this, GameActivity.class)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .putExtra("game", game.toUpperCase());
        ShortcutInfo.Builder b = new ShortcutInfo.Builder(this, "game-" + game.toUpperCase())
                .setShortLabel(label == null || label.isEmpty() ? game : label)
                .setIntent(start);
        Bitmap bmp = icon == null ? null : BitmapFactory.decodeFile(icon);
        // Adaptive: the picture fills the launcher's tile (a plain bitmap is shrunk onto a white one).
        if (bmp != null) b.setIcon(Icon.createWithAdaptiveBitmap(bmp));
        else b.setIcon(Icon.createWithResource(this, getApplicationInfo().icon));
        ShortcutInfo info = b.build();
        // Already on the home screen with this id: Android would show the old name and picture again, so the
        // pinned one is updated in place (no prompt).
        for (ShortcutInfo p : sm.getPinnedShortcuts())
            if (p.getId().equals(info.getId())) {
                sm.updateShortcuts(java.util.Collections.singletonList(info));
                return;
            }
        sm.requestPinShortcut(info, null);
    }
}
