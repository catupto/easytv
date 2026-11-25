package com.fongmi.android.tv.player.exo.ass;

import android.view.Surface;

/** Loaded only by the ASS worker after eligible, selected subtitle data arrives. */
final class AssNative {
    // HDR/wide-gamut video keeps ASS colors in the independent SDR RGB layer.
    // Zero is outside Media3's BT.601/BT.709 values; exo_ass.cpp must match it.
    static final int COLOR_SPACE_SDR_RGB = 0;
    private static boolean loaded;

    static synchronized void ensureLoaded() {
        if (loaded) return;
        // PLUGIN-05: ASS renderer shipped as external core, not inside the APK.
        android.content.Context app = com.fongmi.android.tv.App.get();
        for (String abi : android.os.Build.SUPPORTED_ABIS) {
            com.fongmi.android.tv.player.ExternalCoreLoader.ensure(app, "ass", abi);
            java.io.File dir = com.fongmi.android.tv.player.ExternalCoreLoader.installedDir(app, "ass", abi);
            if (dir == null) continue;
            java.io.File so = new java.io.File(dir, System.mapLibraryName("exo_ass"));
            if (so.isFile()) {
                System.load(so.getAbsolutePath());
                loaded = true;
                return;
            }
        }
        throw new UnsatisfiedLinkError("exo_ass external core not installed (PLUGIN-05)");
    }

    static native long create(String fontConfig, String[] fontNames, byte[][] fonts);
    static native boolean load(long handle, byte[] utf8);
    static native boolean loadHeader(long handle, byte[] utf8);
    static native boolean chunk(long handle, byte[] utf8, long startMs, long durationMs);
    static native boolean setSurface(long handle, Surface surface);
    static native int render(long handle, long timeMs, int width, int height,
                             int storageWidth, int storageHeight, double pixelAspect,
                             int colorSpace, int colorRange, boolean force, long[] stats);
    static native void destroy(long handle);
    static native boolean testSurface(long handle, int width, int height);
    static native long createTestFonts(String[] names, byte[][] fonts);
    static native byte[] readPixels(long handle);

    private AssNative() { }
}
