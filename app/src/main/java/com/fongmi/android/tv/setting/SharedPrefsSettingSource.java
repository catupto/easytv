package com.fongmi.android.tv.setting;

import com.github.catvod.utils.Prefers;

/**
 * {@link SettingSource} 的生产实现：委托给既有的 {@link Prefers}（SharedPreferences）。
 *
 * <p><b>为什么是纯转发、一行逻辑都不加。</b>批次 2.1 是"语义搬运"，最容易静默改坏默认值
 * （方案 R2-4）：628 处调用点里有相当一部分依赖 {@code Setting} 内部对"未设置"的兜底。
 * 如果本实现在转发时顺手加一个默认值、或把 {@code getInt} 换成 {@code getLong}，
 * 编译完全不报错，但行为变了。所以这里每个方法都只是同名转发，默认值参数原样透传。
 *
 * <p>{@link Prefers} 的默认值重载已存在（{@code getString(key, def)} 等），
 * 无需在此重新实现一遍兜底逻辑。
 */
final class SharedPrefsSettingSource implements SettingSource {

    @Override
    public String getString(String key, String defaultValue) {
        return Prefers.getString(key, defaultValue);
    }

    @Override
    public int getInt(String key, int defaultValue) {
        return Prefers.getInt(key, defaultValue);
    }

    @Override
    public long getLong(String key, long defaultValue) {
        return Prefers.getLong(key, defaultValue);
    }

    @Override
    public float getFloat(String key, float defaultValue) {
        return Prefers.getFloat(key, defaultValue);
    }

    @Override
    public boolean getBoolean(String key, boolean defaultValue) {
        return Prefers.getBoolean(key, defaultValue);
    }

    @Override
    public boolean contains(String key) {
        return Prefers.contains(key);
    }

    @Override
    public void put(String key, Object value) {
        Prefers.put(key, value);
    }

    @Override
    public void remove(String key) {
        Prefers.remove(key);
    }
}
