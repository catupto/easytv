package com.fongmi.android.tv.device;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertSame;

import com.fongmi.android.tv.BuildConfig;

import org.junit.Test;

/**
 * {@link DeviceModePolicy} 的契约测试：纯 JUnit，不依赖 Robolectric / Mockito，
 * 也不引用 {@code Util} / {@code App} 等带 Android 静态初始化的类。
 */
public class DeviceModePolicyContractTest {

    @Test
    public void currentReturnsStableSingleton() {
        DeviceModePolicy first = DeviceModePolicy.current();
        assertNotNull(first);
        assertSame(first, DeviceModePolicy.current());
    }

    @Test
    public void modeIsNeverNull() {
        assertNotNull(DeviceModePolicy.current().mode());
    }

    /**
     * 迁移期最关键的一条：新抽象与旧 {@code Util.isLeanback()} 必须给出同一个答案。
     * {@code Util.isLeanback()} 的实现即为 {@code "leanback".equals(BuildConfig.FLAVOR_mode)}，
     * 这里直接把该表达式写进断言，任何一侧漂移都会立刻失败。
     */
    @Test
    public void isTvMatchesLegacyIsLeanback() {
        assertEquals("leanback".equals(BuildConfig.FLAVOR_mode), DeviceModePolicy.current().isTv());
    }

    @Test
    public void interactionParadigmsFollowDeviceMode() {
        DeviceModePolicy policy = DeviceModePolicy.current();
        assertEquals(policy.isTv(), policy.wantsFocusNavigation());
        assertEquals(!policy.isTv(), policy.wantsTouchScroll());
    }

    @Test
    public void isWideScreenToleratesNullContext() {
        assertFalse(DeviceModePolicy.current().isWideScreen(null));
    }

    @Test
    public void deviceModeFlagsAreMutuallyExclusiveAndComplete() {
        DeviceModePolicy policy = DeviceModePolicy.current();
        int truthy = 0;
        if (policy.isTv()) truthy++;
        if (policy.isPhone()) truthy++;
        if (policy.isTablet()) truthy++;
        assertEquals(1, truthy);
    }
}
