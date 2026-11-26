# ADR-0010: `ThemeDialog` 保留双 flavor 实现，暂不合并

- 状态：已定稿
- 日期：2026-11-26
- 依据：主方案 §4.5.2（flavor 判定仲裁表）、批次 1.3

## Context

批次 1.3 要求合并 6 个近重复 flavor 文件。其中 `ui/dialog/ThemeDialog.java` 的
Jaccard（L3 口径）为 **0.9553**（leanback 533 行 / mobile 520 行），按相似度本应合并。

逐行 `diff -u` 复核后发现差异**有行为语义**，不是格式或顺序：

| 行为 | leanback | mobile |
|---|---|---|
| 主题模式是否真正保存 | 是：`Setting.putThemeMode(dark ? 1 : 0)` | 否，只改本地 `dark` 并 `render()` |
| 是否应用夜间模式 | 是：`ThemeController.applyNightModeToApp()` | 否 |
| 是否有 `modeChanged` 状态机 | 是（含 `onSaveInstanceState` 持久化） | 无 |
| 点浅色/深色按钮的副作用 | `selectMode()` → 写 `ThemeProfile` + 保存 + 应用 | `dark = x; render()` 纯预览 |

进一步查证发现这是**有意设计**，并且被测试以双向断言锁定：

```java
// app/src/test/java/com/fongmi/android/tv/theme/ThemeInlinePreviewContractTest.java
String mobile = read("mobile/java/com/fongmi/android/tv/ui/dialog/ThemeDialog.java");
String tv     = read("leanback/java/com/fongmi/android/tv/ui/dialog/ThemeDialog.java");
assertTrue(tv.contains("editor.setMode(dark ? ThemeProfile.MODE_DARK : ThemeProfile.MODE_LIGHT)"));
assertTrue(tv.contains("Setting.putThemeMode(dark ? 1 : 0)"));
assertTrue(tv.contains("ThemeController.applyNightModeToApp()"));
assertFalse(mobile.contains("editor.setMode(dark ? ThemeProfile.MODE_DARK : ThemeProfile.MODE_LIGHT)"));
```

即测试要求 **TV 必须保存并应用，手机必须只预览**。

另有旁证：主题模式真正的保存入口在 `main/ui/dialog/AppearanceDialog.java:142`
（`Setting.putThemeMode(mode)`），两侧共用。`ThemeDialog` 在手机侧是「只调色不落地」的
预览器，落地由 `AppearanceDialog` 承担。

## Decision

**本批不合并 `ThemeDialog`**，保持 leanback / mobile 两份实现。

在批次 1.3 的处置中记为「**真差异**」，双份文件数因此为 **64** 而非方案预期的 63。

## Alternatives

| 方案 | 为什么不选 |
|---|---|
| 取 leanback 版（保存并应用） | 违反 `ThemeInlinePreviewContractTest` 的 `assertFalse(mobile.contains(...))`，会让手机侧在预览阶段就写盘并重启夜间模式，是用户可见的行为变化 |
| 取 mobile 版（只预览） | 会让 TV 失去主题切换的落地能力（TV 侧没有 `AppearanceDialog` 这条保存路径的等价入口），属功能回归 |
| 抽公共基类 + 策略钩子 | 差异不在"某个可参数化点"，而在"整套保存/应用流程是否存在"。抽基类会把 460 行公共渲染代码与 60 行流程代码混在一起，产出一个新上帝类，违反方案 §4.6.1 拒绝横切的纪律 |

## Consequences

- **正面**：避免了一次用户可见的行为回归；把"为什么这份文件不能按 Jaccard 合并"固化成可查证据，防止后续批次重复尝试。
- **负面**：双份文件数停在 64，Gate T1 的 63 目标差 1 个。
- **退出条件**：4.6 单包化时，这两份会随 `mode` 维度一起消失；届时差异必须改由
  `DeviceModePolicy` 承载（真 TV 上保存并应用，触屏设备只预览），并由
  `ThemeInlinePreviewContractTest` 改写为**行为断言**（当前是源码文本断言，属 1.4 的 A/B/C 分类对象）。

## Rollback

本 ADR 只记录决策，未改任何代码。若要推翻：删除本文件并在 1.3 中合并
`ThemeDialog`，同时必须改写 `ThemeInlinePreviewContractTest` 的双向断言。
