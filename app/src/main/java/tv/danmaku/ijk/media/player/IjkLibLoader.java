package tv.danmaku.ijk.media.player;

import android.util.Log;
import java.util.Arrays;

/* loaded from: classes3.dex */
public abstract class IjkLibLoader {
    private static final String TAG = "IjkLibLoader";
    private boolean isAvailable;
    private final String[] nativeLibraries;

    public IjkLibLoader(String... strArr) {
        this.nativeLibraries = strArr;
    }

    /**
     * 只缓存「成功」状态：一旦加载成功就永久复用（native so 进程内只需 load 一次）。
     * 失败不缓存——外置内核包可能是在 App 启动之后才放进去的，用户放好后必须能重试成功。
     * 原实现用 loadAttempted 把失败也永久化，导致首次失败后再也用不了 IJK。
     */
    public synchronized boolean isAvailable() {
        if (this.isAvailable) return true;
        try {
            for (String str : this.nativeLibraries) {
                loadLibrary(str);
            }
            this.isAvailable = true;
        } catch (Throwable e) {
            Log.w(TAG, "Failed to load " + Arrays.toString(this.nativeLibraries), e);
        }
        return this.isAvailable;
    }

    public abstract void loadLibrary(String str);
}
