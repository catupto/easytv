package com.fongmi.android.tv.device;

import android.content.Context;

/**
 * 设备形态策略：把「当前是 TV 还是触屏」以及由此派生的交互范式收敛到一个抽象后面。
 *
 * <p>存在意义：迁移期把散落的 {@code Util.isLeanback()} 调用点改为依赖本接口，
 * 从而在单包化（TV/触屏合包）之后可以按运行时信息判定，而不是按编译期 flavor 常量。
 */
public interface DeviceModePolicy {

    DeviceMode mode();

    default boolean isTv() {
        return mode() == DeviceMode.TV;
    }

    default boolean isPhone() {
        return mode() == DeviceMode.PHONE;
    }

    default boolean isTablet() {
        return mode() == DeviceMode.TABLET;
    }

    /** true = TV 交互范式：D-pad / requestFocus / androidx.leanback 控件。 */
    boolean wantsFocusNavigation();

    /** true = 触屏交互范式：RecyclerView / NestedScrollView 滚动。 */
    boolean wantsTouchScroll();

    /** 窗口尺寸等级：smallestScreenWidthDp >= 600。与设备形态正交，TV 亦可能为 true。 */
    boolean isWideScreen(Context context);

    /**
     * 过渡期唯一取用入口。
     *
     * <p>这是 ADR-0006（禁止静态服务定位器）的临时例外：4.2–4.3 期间调用点无法一次性
     * 改为构造注入，故保留此入口；4.4 调用点全部注入后必须删除本方法。
     */
    static DeviceModePolicy current() {
        return Holder.POLICY;
    }

    /** 延迟初始化持有者：类加载时只做一次实例化，接口静态方法则不触碰任何 Android 类。 */
    final class Holder {
        private static final DeviceModePolicy POLICY = new FlavorDeviceModePolicy();

        private Holder() {
        }
    }
}
