# 源码文本断言分类台账（批次 1.4）

> 主方案依据：§2.9（反模式 H）、§2.9.4（A/B/C 分类）、§5 批次 1.4、§6.5 C11。
> 机器可读版本：`bash scripts/arch/source-text-tests.sh --json-out <path>`。
> 本文件是**分类结论**，不是执行记录；执行记录见 `docs/tasks/T1-stage1-docs-and-flavor-dedupe.md`。

## 总量

| 项 | 数值 |
|---|---:|
| 类 | 218 |
| `@Test` 用例 | 1661 |
| 行 | 44160 |
| `test` / `testMobile` / `testLeanback` | 144 / 48 / 26 |

## A/B/C 分布

| 分类 | 定义（§2.9.4） | 处置 | 数量 |
|---|---|---|---:|
| **A 可迁行为** | 断言「调用了什么、什么顺序、什么结果」 | 迁移为对纯对象/接口的行为断言 | **0** |
| **B 应变契约** | 断言某个不变量/结构约束 | 改为类型/接口断言（ArchUnit + 编译期） | **32** |
| **C 无法迁移** | 断言「这段字面文本必须存在」，无行为语义 | 删除，并在 ADR 记录放弃了哪项保护 | **186** |

> **A=0 是有意义的结论，不是脚本失灵**：现有 218 个类里没有一类是纯行为断言——
> 它们全部（部分或完全）依赖读取生产源码文本。这与方案 §2.9.3 的判断一致：
> 源码文本断言不是安全网，是负债。

## 4 个重灾类（方案点名，379 用例）

| 测试类 | 用例 | 行 | 锁定对象 | 自动判级 | 处置 Phase 1 |
|---|---:|---:|---|---|---|
| `VideoActivityLayoutTest` | 159 | 4182 | `VideoActivity`（两侧） | B | `@Category(SourceTextAssertion.class)` |
| `TmdbDetailActivityLayoutTest` | 132 | 3935 | `TmdbDetailActivity` | C | `@Category(SourceTextAssertion.class)` |
| `TmdbUIAdapterTest` | 61 | 1335 | `TmdbUIAdapter` | B | `@Category(SourceTextAssertion.class)` |
| `TvFocusRingContractTest` | 27 | 1499 | 布局/Activity 源码文本 + 焦点契约 | C | `@Category(SourceTextAssertion.class)` |
| **合计** | **379** | | | | |

## 用例最多的 30 个类

| 级 | 用例 | 行 | 类 | 源集 |
|---|---:|---:|---|---|
| B | 159 | 4182 | `VideoActivityLayoutTest` | testMobile |
| C | 132 | 3935 | `TmdbDetailActivityLayoutTest` | testMobile |
| B | 61 | 1335 | `TmdbUIAdapterTest` | testMobile |
| B | 36 | 840 | `VideoDanmakuOwnershipTest` | testLeanback |
| C | 32 | 413 | `GlobalHistoryResumeSourceTest` | test |
| B | 31 | 460 | `CrashRecoveryStateTest` | test |
| B | 28 | 613 | `ReaderPlaybackRoutingSourceTest` | test |
| C | 27 | 1499 | `TvFocusRingContractTest` | testLeanback |
| B | 26 | 622 | `ThemeBinderContractTest` | test |
| B | 22 | 373 | `PluginUiPresenterTest` | test |
| C | 20 | 449 | `PlaybackOwnershipSourceTest` | test |
| C | 18 | 322 | `WebThemeDetailWiringTest` | test |
| B | 16 | 598 | `AiSubtitleTranslationServiceTest` | test |
| C | 16 | 516 | `PlayerPlaybackRegressionSourceTest` | testMobile |
| B | 16 | 261 | `ThemeEditorContractTest` | test |
| C | 15 | 430 | `EpisodeAdapterTest` | testMobile |
| C | 15 | 363 | `FollowingUiSourceTest` | test |
| C | 15 | 346 | `LabTvFocusSourceTest` | test |
| B | 15 | 653 | `ThemeBaseWiringTest` | test |
| C | 15 | 262 | `TmdbEpisodeAdapterTest` | testMobile |
| C | 14 | 378 | `NativeEnhancedPlaybackStyleFocusTest` | testLeanback |
| B | 14 | 334 | `PluginPackageImporterTest` | test |
| B | 14 | 254 | `TmdbDetailCacheTest` | test |
| B | 14 | 385 | `TvErrorStateContractTest` | testLeanback |
| B | 14 | 311 | `WebThemeManifestLoaderTest` | test |
| C | 13 | 212 | `AdBlockStatsDialogLayoutTest` | testMobile |
| C | 13 | 263 | `AppBrandingContractTest` | test |
| C | 13 | 247 | `DetailModeControllerTest` | testMobile |
| C | 11 | 171 | `CrashLogWiringTest` | test |
| C | 11 | 247 | `PlaybackSelectionLocatorSourceTest` | test |

完整 218 行清单用脚本产出，不在此重复（避免两份真相源分叉）：

```bash
bash scripts/arch/source-text-tests.sh --list        # 218 行人类可读清单
bash scripts/arch/source-text-tests.sh --json-out /tmp/st.json
```
