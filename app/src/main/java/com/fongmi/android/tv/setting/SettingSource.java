package com.fongmi.android.tv.setting;

/**
 * 设置存储的读写契约（批次 2.1，主方案 §2.1 / §4.7）。
 *
 * <p><b>存在的理由：把上下颠倒的依赖边翻正。</b>现在 7 个下层包（`player`/`utils`/
 * `server`/`bean`/`api`/`web`/`playback`）对 {@code Setting} 有 168 处静态调用，而
 * {@code Setting} 的实现又反向依赖播放器能力（{@code setting→player} 26 次）。这两条边
 * 互为上下层，构成一个包级环，是模块化的物理障碍。
 *
 * <p>本接口把「读一个键、写一个键」这件事从 {@code Setting} 这个**具体门面**上剥下来。
 * 下层包依赖本接口（一个只讲键值存取的抽象），而不是依赖那个碰播放器的门面，
 * 环就被切断了。{@code Setting} 退化为唯一职责的转发器，存量 645 处静态调用零改动。
 *
 * <p><b>为什么先建接口、而不是直接批量改成注入。</b>方案 §2.1 的原文结论：
 * 「用接口吸收存量，而不是用批量改写承担风险」。一次改 186 处会让单个提交无法评审、
 * 无法回滚；先建接口再按包注入，每包一个可独立回滚的提交。
 *
 * <p><b>红线（§8.1）：键字符串与默认值语义不得改变。</b>键名是用户数据的持久化标识，
 * 改键名 = 静默丢弃存量用户配置；改默认值 = 改变"未设置"时的行为。本接口的实现
 * 必须逐字复用现有键名与默认值，且 {@code guard.sh} 之外还要有一致性测试兜底
 * （见 {@code SettingSourceContractTest}）。
 *
 * <p><b>过渡期用法</b>：{@link SettingSource#current()} 是 ADR-0006（禁止静态服务定位器）
 * 的临时例外，与 {@code DeviceModePolicy.current()} 同一性质。等各包完成构造注入后，
 * 本方法必须删除。
 */
public interface SettingSource {

    String getString(String key, String defaultValue);

    int getInt(String key, int defaultValue);

    long getLong(String key, long defaultValue);

    float getFloat(String key, float defaultValue);

    boolean getBoolean(String key, boolean defaultValue);

    boolean contains(String key);

    void put(String key, Object value);

    void remove(String key);

    /**
     * 过渡期取用入口。
     *
     * <p>与 {@code DeviceModePolicy.current()} 同属 ADR-0006 的过渡例外：2.1–2.3 期间
     * 下层包无法一次性改为构造注入，故保留；各包注入完成后必须删除。
     */
    static SettingSource current() {
        return Holder.SOURCE;
    }

    /** 延迟初始化：类加载时不触碰 Android 的 SharedPreferences。 */
    final class Holder {
        private static final SettingSource SOURCE = new SharedPrefsSettingSource();

        private Holder() {
        }
    }
}
