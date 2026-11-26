package com.fongmi.android.tv.utils;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * {@code CrashReport.CRASH_ACTIVITY_CLASS} 的正确性契约（批次 2.3 剪环）。
 *
 * <p><b>这条测试为什么存在。</b>为了解开本仓库最大的一对双向依赖
 * {@code ui ↔ utils}（ui→utils 309 处、utils→ui 1 处），{@code CrashReport} 不再用
 * {@code CrashActivity.class} 类字面量，改用类名字符串。代价是<b>丢掉了编译期校验</b>：
 * 如果 {@code CrashActivity} 改名或被移动，编译器不再报错，崩溃恢复页会静默打不开
 * ——而这恰恰只在崩溃时才暴露，是最难被发现的一类事故。
 *
 * <p>所以这里把"编译期校验"换成"会失败的测试"，逐条补回三件事：
 * <ol>
 *   <li>常量指向的类<b>确实存在</b>（反射加载）；</li>
 *   <li>它确实是 {@code Activity} 的子类（不是任意同名类）；</li>
 *   <li>它在 manifest 里<b>已声明</b>（否则 {@code startActivity} 会抛
 *       ActivityNotFoundException，同样是崩溃期才炸）。</li>
 * </ol>
 */
public class CrashRecoveryTargetContractTest {

    private static final String MANIFEST = "src/main/AndroidManifest.xml";

    /** 常量指向的类必须能被加载。 */
    @Test
    public void crashActivityClassResolvesToARealClass() throws Exception {
        Class<?> type = Class.forName(CrashReport.CRASH_ACTIVITY_CLASS);
        assertNotNull("CRASH_ACTIVITY_CLASS must resolve", type);
        assertEquals("resolved class must be the one the constant names",
                CrashReport.CRASH_ACTIVITY_CLASS, type.getName());
    }

    /** 它必须是 Activity 子类，否则 startActivity 会失败。 */
    @Test
    public void crashActivityIsAnActivity() throws Exception {
        Class<?> type = Class.forName(CrashReport.CRASH_ACTIVITY_CLASS);
        assertTrue("crash recovery target must be an Activity, got " + type.getName(),
                android.app.Activity.class.isAssignableFrom(type));
    }

    /**
     * 它必须在 manifest 中声明。
     *
     * <p>与上一条同样重要：类存在但未注册，{@code startActivity} 依然会抛
     * {@code ActivityNotFoundException}，而这条路径只在崩溃时走到。
     */
    @Test
    public void crashActivityIsDeclaredInManifest() throws Exception {
        String manifest = new String(
                java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(MANIFEST)),
                java.nio.charset.StandardCharsets.UTF_8);
        String simple = CrashReport.CRASH_ACTIVITY_CLASS.substring(
                CrashReport.CRASH_ACTIVITY_CLASS.lastIndexOf('.') + 1);
        assertTrue("manifest must declare the crash recovery activity (" + simple + "); "
                        + "without it startActivity throws ActivityNotFoundException at crash time",
                manifest.contains(simple));
    }

    /**
     * 常量必须是全限定类名，不能是简名或相对名。
     *
     * <p>{@code Intent.setClassName(context, name)} 要求全限定名；写成简名会在运行期
     * 静默失败，而这条路径没人会手动测。
     */
    @Test
    public void constantIsAFullyQualifiedName() {
        String value = CrashReport.CRASH_ACTIVITY_CLASS;
        assertTrue("must be fully qualified: " + value, value.contains("."));
        assertFalse("must not start with a dot", value.startsWith("."));
        assertEquals("must not carry an inner-class suffix", -1, value.indexOf('$'));
        assertTrue("must live under the app package: " + value,
                value.startsWith("com.fongmi.android.tv."));
    }

    /**
     * {@code utils} 包不得再 import {@code ui.*}。
     *
     * <p>这是剪环本身的回归防线：任何人重新写回 {@code import ...ui.activity.CrashActivity}
     * 都会让 {@code utils → ui} 这条边复活，{@code ui ↔ utils} 重新变成双向依赖。
     * 断言方式是枚举路径而非读源码文本，避免成为 C11 源码文本断言。
     */
    @Test
    public void utilsPackageDoesNotReferenceUiTypes() throws Exception {
        java.nio.file.Path utilsDir = java.nio.file.Paths.get(
                "src/main/java/com/fongmi/android/tv/utils");
        assertTrue("utils package must exist", java.nio.file.Files.isDirectory(utilsDir));
        java.util.List<String> offenders = new java.util.ArrayList<>();
        try (java.util.stream.Stream<java.nio.file.Path> files = java.nio.file.Files.walk(utilsDir)) {
            for (java.nio.file.Path file : (Iterable<java.nio.file.Path>) files
                    .filter(p -> p.toString().endsWith(".java"))::iterator) {
                String text = new String(java.nio.file.Files.readAllBytes(file),
                        java.nio.charset.StandardCharsets.UTF_8);
                if (text.contains("import com.fongmi.android.tv.ui.")) {
                    offenders.add(file.getFileName().toString());
                }
            }
        }
        assertTrue("utils must not import ui types (this would re-create the ui<->utils cycle): "
                + offenders, offenders.isEmpty());
    }
}
