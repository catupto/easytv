package com.fongmi.android.tv;

import android.content.Context;
import android.os.Build;
import android.view.DisplayCutout;

import com.fongmi.android.tv.bean.Style;
import com.fongmi.android.tv.device.DeviceModePolicy;
import com.fongmi.android.tv.setting.PlayerSetting;
import com.fongmi.android.tv.utils.MobileWindow;
import com.fongmi.android.tv.utils.ResUtil;

/**
 * 网格列数与卡片尺寸的唯一计算入口。
 *
 * <p><b>为什么现在是 main 里的一份实现（批次 4.2b）。</b>此前 leanback 与 mobile 各有一份
 * 同名类，API 有一半不相同（TV 侧 {@code getColumn()} 无参、触屏侧 {@code getColumn(Context)}），
 * 于是「TV 与触屏的列数差异」被写了两遍，改一次要记住两个文件。现在两份合为一份：
 *
 * <ul>
 *   <li>两侧原有的每个签名都保留为**重载**，调用点零改动；</li>
 *   <li>差异不再靠「哪份文件被编进 APK」决定，而是靠 {@link DeviceModePolicy} 在运行期判定。</li>
 * </ul>
 *
 * <p><b>4.2b 阶段的行为等价承诺</b>：当前 {@code DeviceModePolicy} 的实现是
 * {@code FlavorDeviceModePolicy}（按 {@code BuildConfig.FLAVOR_mode} 判定），与旧的
 * "两份文件各编各的" 逐字节等价。因此本批次只改代码归属，不改任何数值输出。
 *
 * <p><b>重载的取舍规则</b>（后续 4.3/4.6 单包化时按此收缩）：
 * <ul>
 *   <li>无 {@code Context} 的重载 = TV 路径，宽度取全屏 {@link ResUtil#getScreenWidth()}；</li>
 *   <li>带 {@code Context} 的重载 = 触屏路径，宽度取窗口 {@link MobileWindow#getWidth(Context)}
 *       并叠加刘海 {@code getCutout}，因为它可能在分屏/小窗里运行。</li>
 * </ul>
 * 同一设备形态下两条路径不会混用：调用方本来就是按源集分文件存在的。
 */
public class Product {

    /** 触屏基线的卡片紧凑间距（dp）。TV 用 {@link #TV_ITEM_SPACING_DP}。 */
    private static final int TOUCH_BASE_SPACING_DP = 32;
    /** TV 基线的卡片紧凑间距（dp）：TV 的卡片更大，左右留白也更大。 */
    private static final int TV_BASE_SPACING_DP = 48;
    /** 相邻卡片之间的固定间隙（dp），两侧一致。 */
    private static final int ITEM_GAP_DP = 16;
    /** 触屏横屏时的列数基准 / 竖屏时的列数基准。 */
    private static final int TOUCH_WIDE_COLUMNS = 7;
    private static final int TOUCH_TALL_COLUMNS = 5;

    /**
     * 设备类型，供 {@code bean.Device} 把设备身份写入历史记录。
     *
     * <p><b>返回值语义必须保持等价</b>：旧 leanback 恒为 {@code 0}、旧 mobile 恒为 {@code 1}。
     * 这两个数字会被写进持久化的历史记录并与既有数据比较，所以 {@code TV -> 0}、
     * 触屏 -> {@code 1} 的映射不能改（{@code Device.java:79} 是唯一调用点）。
     */
    public static int getDeviceType() {
        return DeviceModePolicy.current().isTv() ? 0 : 1;
    }

    /**
     * 阅读器判定内容不归自己管时，回退到播放流程。
     *
     * <p><b>为什么这里能只有一份实现。</b>原先两侧的
     * {@code VideoActivity.startSkippingDispatch(...)} 参数列表不同（TV 侧多
     * {@code boolean cast} 与 {@code long launch}），导致这段注册逻辑必须两个 flavor 各写一遍。
     * 批次 4.2b 给 leanback 补了一个与触屏侧同签名的重载（内部转发到 12 参数版，
     * {@code cast=false}、{@code launch=now}，与旧行为逐字等价），两侧签名因此对齐，
     * 本方法得以回到 {@code main} 只有一份。
     */
    public static void registerReaderFallback() {
        com.fongmi.android.tv.ui.novel.NovelRouter.fallbackLauncher = (activity, key, id, name, pic, mark) ->
                com.fongmi.android.tv.ui.activity.VideoActivity.startSkippingDispatch(
                        activity, key, id, name, pic, mark, false, null, null, null);
    }

    // ------------------------------------------------------------------ TV 路径

    /** TV 列数：只由用户设置的分组大小决定。 */
    public static int getColumn() {
        return Math.abs(PlayerSetting.getSize() - 7);
    }

    public static int getColumn(Style style) {
        return style.isLand() ? getColumn() - 1 : getColumn();
    }

    public static int[] getSpec(Style style) {
        int column = getColumn(style);
        int space = ResUtil.dp2px(TV_BASE_SPACING_DP) + ResUtil.dp2px(ITEM_GAP_DP * (column - 1));
        if (style.isOval()) space += ResUtil.dp2px(column * ITEM_GAP_DP);
        return getSpec(space, column, style);
    }

    public static int[] getSpec(int space, int column, Style style) {
        int base = ResUtil.getScreenWidth() - space;
        int width = base / column;
        int height = (int) (width / style.getRatio());
        return new int[]{width, height};
    }

    /**
     * TV 的 em 宽度上限。
     *
     * <p>当前无调用方（合并前的 leanback 副本里就已如此）。保留而不删除，是因为它属于
     * 公开静态 API，删除属行为面收缩，应在 4.6 单包化的 API 盘点里统一处理，而不是
     * 藏进一次「合并两份文件」的提交里。
     */
    public static int getEms() {
        return Math.min(Math.round((float) ResUtil.getScreenWidth() / ResUtil.sp2px(24)), 35);
    }

    // --------------------------------------------------------------- 触屏路径

    /** 触屏列数：横屏 7 / 竖屏 5，平板 +1。 */
    public static int getColumn(Context context) {
        int count = MobileWindow.isWide(context) ? TOUCH_WIDE_COLUMNS : TOUCH_TALL_COLUMNS;
        count = count + (ResUtil.isPad() ? 1 : 0);
        return Math.abs(PlayerSetting.getSize() - count);
    }

    public static int getColumn(Context context, Style style) {
        return style.isLand() ? getColumn(context) - 1 : getColumn(context);
    }

    // ------------------------------------------------------------ 列数（具名入口）
    //
    // 「网格列数」原先只有 getColumn 系列这一个名字，而它同时被用来算列数、算 item 间距、
    // 传进 FocusRestorer。4.3 迁移 isLeanback() 时需要一个语义明确的名字来承接
    // 「TV 与触屏列数不同」这件事，因此补两个具名入口。
    //
    // 它们是 getColumn 的**别名而非新逻辑**：实现直接转发，避免出现第二套计算。

    /**
     * 当前设备形态下的网格列数（自动选择 TV / 触屏算法）。
     *
     * <p>与 {@link #getColumn()}（TV 专用）和 {@link #getColumn(Context)}（触屏专用）的区别：
     * 本方法接受 {@code null} 并在 null 时回落到 TV 算法，因为 4.3 的迁移点里有相当一部分
     * 拿不到可靠的 {@code Context}（构造期、静态初始化、被回收的 View）。**不要**用它替代
     * 已知形态的调用点——那会把编译期可判定的分支变成运行期查询。
     */
    public static int gridColumnCount(Context context) {
        if (context == null) return getColumn();
        return DeviceModePolicy.current().isTv() ? getColumn() : getColumn(context);
    }

    /** {@link #gridColumnCount(Context)} 的样式重载：横屏少一列。 */
    public static int gridColumnCount(Context context, Style style) {
        return style.isLand() ? gridColumnCount(context) - 1 : gridColumnCount(context);
    }

    public static int[] getSpec(Context context) {
        return getSpec(context, Style.rect());
    }

    public static int[] getSpec(Context context, int column) {
        Style style = Style.rect();
        int space = ResUtil.dp2px(TOUCH_BASE_SPACING_DP)
                + ResUtil.dp2px(ITEM_GAP_DP * (column - 1)) + getCutout(context);
        return getSpec(context, space, column, style);
    }

    public static int[] getSpec(Context context, Style style) {
        int column = getColumn(context, style);
        int space = ResUtil.dp2px(TOUCH_BASE_SPACING_DP)
                + ResUtil.dp2px(ITEM_GAP_DP * (column - 1)) + getCutout(context);
        if (style.isOval()) space += ResUtil.dp2px(column * ITEM_GAP_DP);
        return getSpec(context, space, column, style);
    }

    private static int[] getSpec(Context context, int space, int column, Style style) {
        int base = MobileWindow.getWidth(context) - space;
        int width = base / column;
        int height = (int) (width / style.getRatio());
        return new int[]{width, height};
    }

    /** 刘海占用的水平宽度；低于 Q 或没有刘海时返回 0。 */
    private static int getCutout(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return 0;
        DisplayCutout cutout = ResUtil.getDisplay(context).getCutout();
        if (cutout == null) return 0;
        int left = cutout.getSafeInsetLeft();
        int right = cutout.getSafeInsetRight();
        return left | right;
    }
}
