package com.fongmi.android.tv.device;

import android.content.Context;

import com.fongmi.android.tv.BuildConfig;

/**
 * 阶段 3 使用：仍按 flavor 编译期常量判定，行为与 {@code Util.isLeanback()} 逐字节等价。
 * 阶段 4 单包化后替换为 RuntimeDeviceModePolicy，本类随之删除。
 */
public final class FlavorDeviceModePolicy implements DeviceModePolicy {

    private static final int WIDE_SCREEN_DP = 600;

    @Override
    public DeviceMode mode() {
        // 与 Util.isLeanback() 完全一致："leanback".equals(BuildConfig.FLAVOR_mode)
        return "leanback".equals(BuildConfig.FLAVOR_mode) ? DeviceMode.TV : DeviceMode.PHONE;
    }

    @Override
    public boolean wantsFocusNavigation() {
        return isTv();
    }

    @Override
    public boolean wantsTouchScroll() {
        return !isTv();
    }

    @Override
    public boolean isWideScreen(Context context) {
        // null 刻意返回 false：本方法会被布局初始化路径调用，那里 context 可能尚未就绪。
        return context != null && context.getResources().getConfiguration().smallestScreenWidthDp >= WIDE_SCREEN_DP;
    }
}
