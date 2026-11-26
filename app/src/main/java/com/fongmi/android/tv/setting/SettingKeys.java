package com.fongmi.android.tv.setting;

/**
 * 设置键名常量表（批次 2.1，主方案 §2.1 的 {@code SettingKeys}）。
 *
 * <p><b>为什么需要它。</b>{@link SettingSource} 只认"键名 + 默认值"这一对参数，它不知道
 * 也不应该知道某个键属于哪个功能。下层包（`player`/`utils`/`server`/...）要用
 * {@code SettingSource} 读设置，就必须知道键名——把键名裸露成调用方各自的字符串字面量，
 * 就会出现"同一个键在两处拼错"，而这种错误在运行期只表现为"设置不生效"，不报错。
 *
 * <p>所以键名在这里集中一次，{@code Setting} 与下层包都从本类取。
 *
 * <p><b>红线（§8.1）：这里的字符串一个字都不能改。</b>键名是用户数据的持久化标识，
 * 改键名 = 静默丢弃存量用户配置。本类只做"把已有字面量提取成常量"这一件事，
 * 不新增、不删除、不改写任何键。
 *
 * <p>当前只登记 {@code player} 包正在迁移的那批键（批次 2.1 范围）。其余键随各自包的
 * 迁移批次逐步登记，不一次性搬运——一次性搬运会让本类的 diff 大到无法逐字核对，
 * 而"逐字核对"正是这条红线唯一可靠的验证方式。
 */
public final class SettingKeys {

    // ---------------------------------------------------------------- player 包

    /** 跳过片头片尾的模式：0=关闭 / 1=自动 / 2=询问。默认 {@code INTRO_SKIP_OFF}。 */
    public static final String INTRO_SKIP_MODE = "intro_skip_mode";
    /** 启用的片段类型位掩码。默认 {@code INTRO_SKIP_KIND_DEFAULT}（回顾+片头+片尾）。 */
    public static final String INTRO_SKIP_KINDS = "intro_skip_kinds";
    /** 自定义 User-Agent；空表示不覆盖。 */
    public static final String UA = "ua";
    /** 广告拦截开关。默认 true。 */
    public static final String ADBLOCK = "adblock";
    /** 首选字幕语言。默认 {@code "zh"}。 */
    public static final String SUBTITLE_PREFERRED_LANGUAGE = "subtitle_preferred_language";
    /** 字幕自动匹配开关。默认 false。 */
    public static final String SUBTITLE_AUTO_MATCH = "subtitle_auto_match";

    private SettingKeys() {
    }
}
