package com.fongmi.android.tv.setting;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;

import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.List;

/**
 * {@code SettingSource} 接口化（批次 2.1）的契约测试。
 *
 * <p><b>这个测试要防的是什么。</b>方案 §2.1 风险 R2-4：2.1 是"语义搬运"，最容易静默改坏默认值。
 * 628 处调用点里很多依赖 {@code Setting} 内部对"未设置"的兜底；如果某个默认值从
 * "实现内兜底"变成"接口默认"，**编译不报错，行为却变了**。§8.1 更把键名/默认值列为红线。
 *
 * <p><b>为什么用行为断言而不是读源码文本。</b>方案 §6.5 的 C11 规则明确禁止新增读取
 * {@code .java} 源码文本的测试（基线 218 只减不增）——那种测试在重构期会大面积误红，
 * 正是上一轮路线图失败的机制性原因。所以本测试用真实 {@code SharedPreferences}
 * 走一遍读写，断言值确实落盘、确实读回，而不是断言"某行源码长什么样"。
 *
 * <p>三条断言：
 * <ol>
 *   <li><b>接口面完整</b>：{@link SettingSource} 必须覆盖全部读写能力，否则某个包迁移到
 *       一半会因为没有对应 getter 而被迫退回静态门面。</li>
 *   <li><b>默认值原样透传</b>：未写入任何值时，{@code getXxx(key, default)} 必须返回调用方
 *       传入的那个默认值——不是实现自己另定的值。</li>
 *   <li><b>写入后读回一致</b>：{@code put} 之后 {@code get} 必须返回同一个值，且
 *       {@code contains} 为 true，{@code remove} 之后回到默认值。</li>
 * </ol>
 */
@RunWith(RobolectricTestRunner.class)
public class SettingSourceContractTest {

    private SettingSource source() {
        // Reset shared prefs state so assertions do not depend on other tests.
        RuntimeEnvironment.getApplication()
                .getSharedPreferences("CONFIG", android.content.Context.MODE_PRIVATE)
                .edit().clear().commit();
        return SettingSource.current();
    }

    /** 接口必须提供的全部能力，与 Prefers 一一对应。 */
    @Test
    public void interfaceCoversEveryReadWriteCapability() throws Exception {
        Class<?> c = SettingSource.class;
        c.getMethod("getString", String.class, String.class);
        c.getMethod("getInt", String.class, int.class);
        c.getMethod("getLong", String.class, long.class);
        c.getMethod("getFloat", String.class, float.class);
        c.getMethod("getBoolean", String.class, boolean.class);
        c.getMethod("contains", String.class);
        c.getMethod("put", String.class, Object.class);
        c.getMethod("remove", String.class);
    }

    /** 生产实现必须真的实现接口，且是 final（不允许子类偷换语义）。 */
    @Test
    public void sharedPrefsImplementationIsTheOnlyOne() {
        assertTrue("SettingSource must be an interface", SettingSource.class.isInterface());
        assertTrue("SharedPrefsSettingSource must implement SettingSource",
                SettingSource.class.isAssignableFrom(SharedPrefsSettingSource.class));
        assertTrue("implementation must be final",
                Modifier.isFinal(SharedPrefsSettingSource.class.getModifiers()));
        // The only public static entry point on the interface must be current().
        List<String> statics = new ArrayList<>();
        for (Method m : SettingSource.class.getDeclaredMethods()) {
            if (Modifier.isStatic(m.getModifiers()) && Modifier.isPublic(m.getModifiers())) {
                statics.add(m.getName());
            }
        }
        assertEquals("SettingSource must expose exactly one static entry point (current)",
                List.of("current"), statics);
    }

    /**
     * 未写入任何值时，接口必须把调用方给的默认值原样返回。
     *
     * <p>这是 R2-4 的直接防线：如果实现里自作主张换了默认值（例如把 30 写成 60、
     * 把 true 写成 false），这里立刻红。
     */
    @Test
    public void absentKeysReturnTheCallersDefaultVerbatim() {
        SettingSource s = source();
        assertEquals("string default must pass through", "fallback", s.getString("no_such_key_str", "fallback"));
        assertEquals("empty string default must pass through", "", s.getString("no_such_key_str2", ""));
        assertEquals("int default must pass through", 42, s.getInt("no_such_key_int", 42));
        assertEquals("int 0 default must pass through", 0, s.getInt("no_such_key_int2", 0));
        assertEquals("long default must pass through", 123L, s.getLong("no_such_key_long", 123L));
        assertEquals("float default must pass through", 1.5f, s.getFloat("no_such_key_float", 1.5f), 0.0f);
        assertTrue("boolean true default must pass through", s.getBoolean("no_such_key_bool", true));
        assertFalse("boolean false default must pass through", s.getBoolean("no_such_key_bool2", false));
        assertFalse("absent key must not report contains", s.contains("no_such_key_absent"));
    }

    /** 写入后必须读回同一个值，remove 后回到调用方默认值。 */
    @Test
    public void writtenValuesRoundTripAndRemoveRestoresDefault() {
        SettingSource s = source();
        s.put("rt_int", 7);
        assertEquals("int must round-trip", 7, s.getInt("rt_int", 0));
        assertTrue("written key must report contains", s.contains("rt_int"));
        s.remove("rt_int");
        assertFalse("removed key must not report contains", s.contains("rt_int"));
        assertEquals("removed key must fall back to caller default", 99, s.getInt("rt_int", 99));

        s.put("rt_bool", true);
        assertTrue("boolean must round-trip", s.getBoolean("rt_bool", false));
        s.put("rt_str", "hello");
        assertEquals("string must round-trip", "hello", s.getString("rt_str", ""));
        s.put("rt_long", 8_000_000_000L);
        assertEquals("long must round-trip", 8_000_000_000L, s.getLong("rt_long", 0L));
        s.put("rt_float", 2.25f);
        assertEquals("float must round-trip", 2.25f, s.getFloat("rt_float", 0f), 0.0f);
    }

    /**
     * 同一实例必须每次都返回同一对象（延迟初始化的单例），否则不同包各自拿到
     * 不同实现，会出现"一个包读到的设置另一个包看不到"。
     */
    @Test
    public void currentReturnsAStableSingleton() {
        assertNotNull(SettingSource.current());
        assertTrue("current() must return the same instance",
                SettingSource.current() == SettingSource.current());
    }

    /**
     * {@code Setting} 的既有键名必须仍然可用。
     *
     * <p>这不读源码：它通过真实读写验证批次 2.1 改动过的两个键语义未变。
     * {@code isIncognito} 的默认值必须是 false（未设置 = 非隐身），这与
     * {@code Prefers.getBoolean("incognito")} 的旧行为一致。
     */
    @Test
    public void incognitoKeyKeepsItsDefaultAndRoundTrips() {
        source();
        assertFalse("incognito must default to false (not in incognito until the user turns it on)",
                Setting.isIncognito());
        Setting.putIncognito(true);
        assertTrue("putIncognito(true) must be observed by isIncognito()", Setting.isIncognito());
        Setting.putIncognito(false);
        assertFalse("putIncognito(false) must be observed by isIncognito()", Setting.isIncognito());
    }
}
