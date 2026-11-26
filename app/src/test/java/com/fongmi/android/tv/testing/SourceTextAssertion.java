package com.fongmi.android.tv.testing;

/**
 * JUnit4 category marking a test class that asserts against the <b>text</b> of a
 * {@code .java} source file instead of behaviour (master plan §2.9 / C11).
 *
 * <p>Why this exists: 218 test classes (44,150 lines / 1,661 cases) read production
 * sources and do {@code contains(...)} on the resulting string. They are why the
 * previous refactor roadmap could not move: extracting a method or reordering fields
 * turns them red even when behaviour is identical. The plan (§5 batch 1.4) requires a
 * transition switch so a slice batch can be verified without the text locks drowning
 * out real regressions.
 *
 * <p>This is a <b>transition</b> device, not a permanent exemption. The exit path is
 * §2.9.4's A/B/C classification: A migrates to behaviour assertions, B becomes a
 * type/interface contract (ArchUnit), C is deleted with an ADR recording the
 * protection given up. The count of classes carrying this category may only go down
 * (baseline frozen in {@code docs/refactoring/baseline/debt-baseline.json}).
 *
 * <p>Usage on a class that locks a god class about to be split:
 * <pre>{@code
 * @Category(SourceTextAssertion.class)
 * public class TmdbDetailActivityLayoutTest { ... }
 * }</pre>
 *
 * <p>Then run the behavioural suite without them:
 * {@code bash gradlew :app:testMobileArm64_v8aDebugUnitTest -PexcludeSourceTextTests}
 *
 * <p>Note: this marker lives in {@code app/src/test} so it is visible to
 * {@code test}, {@code testMobile} and {@code testLeanback} alike. It must never be
 * referenced from {@code main} — it is test-only and must not ship in the APK.
 */
public interface SourceTextAssertion {
}
