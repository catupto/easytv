package com.fongmi.android.tv.device;

/**
 * 设备形态。由 {@link DeviceModePolicy} 判定，禁止在调用方另行推断。
 *
 * <p>判定依据（逻辑本身不放在枚举里，枚举只承载形态标签）：
 * <ul>
 *   <li>{@link #TV}：{@code PackageManager.FEATURE_LEANBACK} 特性 + {@code UiModeManager}
 *       的 {@code UI_MODE_TYPE_TELEVISION}；编译期等价物为 flavor {@code leanback}。</li>
 *   <li>{@link #PHONE} / {@link #TABLET}：同一套触屏范式下，由
 *       {@code Configuration.smallestScreenWidthDp} 以 600dp 为界区分。</li>
 * </ul>
 */
public enum DeviceMode {
    TV, PHONE, TABLET
}
