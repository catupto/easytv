package com.fongmi.android.tv;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import com.fongmi.android.tv.bean.Style;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;

/**
 * {@code Product} 合并（批次 4.2b）的行为契约 —— TV 侧，带真实 {@code Context}。
 *
 * <p>与 {@code testMobile} 下的同名类配对存在：Gate T2 要求 device 契约测试
 * <b>两侧都跑</b>，而两侧能用的测试设施不同。本仓库的 Robolectric 只在
 * {@code testLeanback}（{@code testLeanbackImplementation 'org.robolectric:robolectric:4.16'}），
 * 所以只有这里能构造 {@code Context} 去验证触屏路径的列数/spec 计算；
 * {@code testMobile} 侧用纯 JVM 反射验签名与 0/1 映射。
 *
 * <p>核心不变量同 {@code testMobile}：
 * <ul>
 *   <li>{@code getDeviceType()} TV 必须是 <b>0</b>（会写进持久化观看历史）；</li>
 *   <li>两侧原有重载必须全部存活；</li>
 *   <li>spec 宽高必须为正且由宽高比推出。</li>
 * </ul>
 */
@RunWith(RobolectricTestRunner.class)
public class ProductContractTest {

    private Context context() {
        // RuntimeEnvironment is the Robolectric-native way to obtain the application
        // context here; androidx.test.core is not on this source set's classpath.
        return RuntimeEnvironment.getApplication();
    }

    /** TV -> 0。这是 {@code bean/Device.java:79} 写进历史记录的值。 */
    @Test
    public void deviceTypeIsZeroOnTvBuilds() {
        assertEquals("TV builds must keep the persisted deviceType=0",
                0, Product.getDeviceType());
    }

    @Test
    public void deviceTypeMappingIsStable() {
        int actual = Product.getDeviceType();
        assertTrue("getDeviceType must only ever return the persisted 0/1 values, got " + actual,
                actual == 0 || actual == 1);
    }

    /** 合并后两侧的全部重载都必须还在；缺一个就会在另一个变体里编译失败。 */
    @Test
    public void bothFlavoursOverloadsSurvive() throws Exception {
        Class<?> c = Product.class;
        c.getMethod("getColumn");
        c.getMethod("getColumn", Style.class);
        c.getMethod("getSpec", Style.class);
        c.getMethod("getSpec", int.class, int.class, Style.class);
        c.getMethod("getEms");
        c.getMethod("getColumn", Context.class);
        c.getMethod("getColumn", Context.class, Style.class);
        c.getMethod("getSpec", Context.class);
        c.getMethod("getSpec", Context.class, int.class);
        c.getMethod("getSpec", Context.class, Style.class);
        c.getMethod("getDeviceType");
        c.getMethod("registerReaderFallback");
    }

    /** TV 路径的列数只由用户设置决定：{@code |size - 7|}，与窗口形状无关。 */
    @Test
    public void tvColumnCountDependsOnlyOnUserSetting() {
        int expected = Math.abs(com.fongmi.android.tv.setting.PlayerSetting.getSize() - 7);
        assertEquals("TV column count must stay |PlayerSetting.getSize() - 7|",
                expected, Product.getColumn());
        assertTrue("TV must always have at least one column", Product.getColumn() >= 1);
    }

    /** 触屏路径用 Context 取窗口宽度，spec 必须为正。 */
    @Test
    public void touchSpecIsPositiveWithRealContext() {
        int[] rect = Product.getSpec(context(), Style.rect());
        assertTrue("width must be positive", rect[0] > 0);
        assertTrue("height must be positive", rect[1] > 0);
    }

    /** 高度必须由宽高比推出，不能是随意常数。 */
    @Test
    public void touchSpecHeightDerivesFromRatio() {
        int[] rect = Product.getSpec(context(), Style.rect());
        int expected = (int) (rect[0] / Style.rect().getRatio());
        assertEquals("height must derive from the style ratio", expected, rect[1]);
    }

    /** 同一次调用必须稳定：policy 判定不允许受光标/时序影响。 */
    @Test
    public void columnCountIsIdempotent() {
        assertEquals("getColumn(Context) must be deterministic",
                Product.getColumn(context()), Product.getColumn(context()));
    }
}
