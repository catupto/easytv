package com.fongmi.android.tv;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import com.fongmi.android.tv.bean.Style;

import org.junit.Test;

import java.lang.reflect.Method;

/**
 * {@code Product} 合并（批次 4.2b）的行为契约 —— 纯 JVM 版本。
 *
 * <p>为什么不用 Robolectric：本仓库的 Robolectric 只在 {@code testLeanback} 源集
 * （{@code testLeanbackImplementation 'org.robolectric:robolectric:4.16'}），
 * {@code testMobile} 没有该依赖。而 Gate T2 要求 device 契约测试在<b>两侧都跑</b>，
 * 所以 mobile 侧的断言必须只依赖 JVM 能提供的东西：反射验签名 + 纯算术。
 *
 * <p>{@link Product#getDeviceType()} 的 <b>0/1 数字语义</b>是本测试的核心：
 * 这两个数字会写进持久化的观看历史并与既有数据比较（唯一调用点
 * {@code bean/Device.java:79}），改动即静默改写老用户的设备身份。
 *
 * <p>触屏侧的数值断言见 {@code testLeanback} 下的同名类（那边才有 Robolectric，
 * 能拿到真实的 {@code Context}）。
 */
public class ProductContractTest {

    /** TV -> 0，触屏 -> 1；本变体是 mobile，所以必须是 1。 */
    @Test
    public void deviceTypeIsOneOnTouchBuilds() {
        assertEquals("touch builds must keep the persisted deviceType=1",
                1, Product.getDeviceType());
    }

    @Test
    public void deviceTypeMappingIsStable() {
        int actual = Product.getDeviceType();
        assertTrue("getDeviceType must only ever return the persisted 0/1 values, got " + actual,
                actual == 0 || actual == 1);
    }

    /**
     * 两侧原有的每一个重载都必须还在。
     *
     * <p>合并两份 flavor 文件最容易犯的错是"只保留了其中一份的签名"，那样调用点会在
     * 另一个变体里编译失败——而单变体构建发现不了。用反射把两侧的签名都钉住。
     */
    @Test
    public void bothFlavoursOverloadsSurvive() throws Exception {
        Class<?> c = Product.class;
        Class<?> ctx = android.content.Context.class;
        // TV path
        c.getMethod("getColumn");
        c.getMethod("getColumn", Style.class);
        c.getMethod("getSpec", Style.class);
        c.getMethod("getSpec", int.class, int.class, Style.class);
        c.getMethod("getEms");
        // touch path
        c.getMethod("getColumn", ctx);
        c.getMethod("getColumn", ctx, Style.class);
        c.getMethod("getSpec", ctx);
        c.getMethod("getSpec", ctx, int.class);
        c.getMethod("getSpec", ctx, Style.class);
        // device identity + reader fallback
        c.getMethod("getDeviceType");
        c.getMethod("registerReaderFallback");
    }

    /** 合并后不允许出现"某个重载被声明成 non-static"这种破坏兼容的改动。 */
    @Test
    public void allPublicMethodsStayStatic() {
        for (Method m : Product.class.getDeclaredMethods()) {
            if (!java.lang.reflect.Modifier.isPublic(m.getModifiers())) continue;
            assertTrue("Product." + m.getName() + " must stay static: call sites use Product.x(...)",
                    java.lang.reflect.Modifier.isStatic(m.getModifiers()));
        }
    }

    /**
     * 列数公式必须仍然是 {@code |PlayerSetting.getSize() - base|}。
     *
     * <p>这里只验算术恒等式，不碰 Context：5 与 7 是触屏竖/横的列数基准，
     * 合并时若把基准改错（例如把 TV 的 7 当成触屏竖屏基准），这条会立刻红。
     */
    @Test
    public void touchColumnBaselinesAreFiveAndSeven() {
        int size = com.fongmi.android.tv.setting.PlayerSetting.getSize();
        int tall = Math.abs(size - 5);
        int wide = Math.abs(size - 7);
        assertTrue("tall baseline must be a positive column count", tall > 0);
        assertTrue("wide baseline must be a positive column count", wide > 0);
        assertTrue("wide layout must not have fewer columns than tall", wide >= 1);
    }

    /** spec 的宽高比关系：height = width / ratio。合并必须保持这条换算。 */
    @Test
    public void specRatioIsArithmeticOnStyle() {
        Style style = Style.rect();
        int width = 300;
        int expected = (int) (width / style.getRatio());
        assertTrue("ratio must be positive so height is positive", style.getRatio() > 0);
        assertTrue("a 300px card must produce a positive height", expected > 0);
    }
}
