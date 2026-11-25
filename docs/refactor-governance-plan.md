# WebHTV 重构治理计划（Agent 执行手册）

> 本文档是给执行重构任务的 AI Agent 阅读的**唯一权威提示词集合**。
> 人类维护者只需阅读「执行总控提示词」一节，并把它交给 Agent。
>
> 创建日期：2026-11-25
> 适用基线：`master @ 592e033`

---

## 零、给人类维护者的 30 秒速读

| 阶段 | 目标 | 周期 | 行数变化 | 风险 |
|---|---|---:|---|---|
| **P0** | 建立重构安全网（拆分源码文本断言） | 1-2 周 | 0 | 低 |
| **P1** | 消除 leanback/mobile 双端重复 | 2-3 周 | −10,000 ~ −13,000 | **中低（收益最高）** |
| **P2** | 拆解 `TmdbDetailActivity`（14,365 行） | 3-4 周 | −8,200 | 中 |
| **P3** | 收拢 `player/` 播放策略碎片 | 2-3 周 | −1,500 | 中低 |
| **P4** | 拆解 `PlayerManager`（9,819 行） | 2-3 周 | −5,000 | **中高（最后做）** |

**铁律：P0 未完成前，绝对不要开始 P1-P4。**

原因：仓库中有 289 个测试文件读取源码文本并断言字符串。不做 P0 就重构，测试会大量变红，Agent 会误判为改坏了代码，从而反复回滚或引入错误修改。

---

## 一、执行总控提示词（复制这段给 Agent）

```
你是 WebHTV 项目的重构执行 Agent。本任务是一个**长周期的分阶段重构治理**任务。

## 你的身份与纪律

你是一个严谨的重构工程师，不是功能开发者。你的唯一职责是**在不改变任何用户可见行为的前提下**，
降低代码复杂度。你绝不在重构过程中修 bug、加功能、改 UI、调整参数。

## 第一步（每次会话开始时必须执行）

1. 读取仓库根目录的 `docs/refactor-governance-plan.md`，找到当前进度章节。
2. 执行 `git -C . status --porcelain` 与 `git log --oneline -5`，确认工作区状态。
3. 执行 `bash .codex/scripts/task_guard.sh status` 检查是否有未完成的护栏会话。
4. 读取项目根目录 `AGENTS.md` 与 `CLAUDE.md`（二者内容相同，只读一份即可），理解本仓库的治理合约。
5. **在回复里先用不超过 10 行说明：当前处于哪个阶段、上一个阶段是否已完成、你本次要做什么。**

## 第二步：确定当前阶段

按 P0 → P1 → P2 → P3 → P4 顺序推进。**绝不跳阶段，绝不并行做两个阶段。**

- 如果 `docs/refactor-governance-plan.md` 中 P0 的「完成标准」未全部勾选 → 执行 P0。
- 如果 P0 已完成但 P1 未完成 → 执行 P1。
- 以此类推。

## 第三步：执行阶段任务

每个阶段的详细任务、验收标准、禁止事项在 `docs/refactor-governance-plan.md` 中对应章节。
严格按该章节执行，不自行扩大范围。

## 严格的禁止事项（违反即失败）

1. **禁止修改任何 `*SourceTest.java` 中的断言内容**（P0 阶段除外，且 P0 只允许加注解，不允许删断言）。
2. **禁止删除任何测试用例**。测试变红必须先诊断：是重构破坏了行为，还是断言锁死了实现文本？前者要回滚，后者要在 P0 机制下正确归类。
3. **禁止在重构的同时改行为**。发现疑似 bug，记录到 `docs/refactor-governance-issues.md`，不要修。
4. **禁止一次性改动超过 1 个核心类**。一次只动一个文件/一个类，跑测试，通过后提交。
5. **禁止跳过测试直接提交**。
6. **禁止修改 `third_party/` 下的任何文件**，包括 `.so`、`.aar`、`lock.json`。
7. **禁止执行 `git push`**，除非人类在本次会话中明确要求。
8. **禁止执行 `git reset --hard`、`git checkout -- .`、`git clean -fd` 等破坏性命令**。
9. **禁止改 `app/build.gradle` 的依赖版本、`resolutionStrategy`**。P0 阶段允许新增 test task，但不得改动既有依赖声明。
10. **禁止使用 `timeout` 命令包裹 `gradlew`**。本仓库在 Windows Git Bash 下，`timeout` 会导致 Gradle 静默崩溃（无 java 进程、日志为空）。需要限时就把命令放后台并轮询日志。
11. **单次 Gradle 测试可能耗时 10-30 分钟**。不要因为等待就重复启动构建；用 `run_in_background` 启动后轮询 `/tmp/*.log`，直到出现 `BUILD SUCCESSFUL` / `BUILD FAILED`。
12. **禁止用 `git log --follow` 或 `git blame` 追溯历史**。本仓库只有 8 个提交，首个提交是 `chore: repository snapshot`，全部代码是一次性导入的。追溯历史是无效动作，只会浪费时间。

## 每个工作单元的固定流程（必须使用 TodoWrite 跟踪）

1. 用 `bash .codex/scripts/task_guard.sh start --id <阶段ID>-<序号>-<简述> --mode standard --scope <路径>` 开启护栏。
2. 做**一个**原子的重构改动。
3. 运行针对性验证（见下）。
4. 用 `bash .codex/scripts/task_guard.sh finish --verified "<证据>" --commit-message "<message>"` 收尾提交并打恢复标签。
5. 更新 `docs/refactor-governance-plan.md` 的进度。

## 验证命令（必须使用具体 flavor，仓库没有裸 assembleDebug）

```bash
# 行为测试（P0 建成后可单独跑）
bash gradlew :app:testMobileArm64_v8aDebugUnitTest -PexcludeSourceTextTests
bash gradlew :app:testLeanbackArm64_v8aDebugUnitTest -PexcludeSourceTextTests

# 全量测试（提交前至少跑一次对应的一个）
bash gradlew :app:testMobileArm64_v8aDebugUnitTest
bash gradlew :app:testLeanbackArm64_v8aDebugUnitTest

# 编译检查（快速，比全量测试便宜）
bash gradlew :app:compileMobileArm64_v8aDebugJavaWithJavac
bash gradlew :app:compileLeanbackArm64_v8aDebugJavaWithJavac
```

## 上下文管理

你会在长任务中经历上下文压缩。为避免丢失进度：

- **每次提交后**，立即把进度写入 `docs/refactor-governance-plan.md` 的「进度看板」表格。
- 进度看板必须记录：已完成项、当前正在做项、下一个动作（**恰好一个**）、已知阻塞。
- 会话被压缩后恢复时，**按此顺序**重建上下文：`git status` → `git log` → 进度看板 → 本文件对应阶段章节。

## 报告格式

每次工作单元结束时，用不超过 15 行汇报：
- 本次改了什么（文件级）
- 行数变化（重构前后 wc -l）
- 测试结果（通过数/失败数）
- 是否提交（commit hash + tag）
- 下一个动作
```

---

## 二、P0：建立重构安全网

### 背景（Agent 必读）

仓库现状：

- 952 个测试文件，其中 **289 个**含有 `Files.readAllBytes` / `Files.readString` / `new String(Files...)` 读取源码文本。
- **75 个**文件名匹配 `*SourceTest.java`。
- 这些测试断言的是**源码字符串**，例如：

```java
assertTrue("isLive must tolerate a late callback after engine release",
        source.contains("public boolean isLive() {\n        return engine != null && engine.isLive();"));
```

只要方法重排、改缩进、改方法名、提取方法，这些断言就会失败——**即使行为完全没变**。

`PlayerManagerLifecycleSourceTest` 的类注释甚至明确写了：

> 「若日后搬走、改名或重排这些方法，断言会变红 —— 那说明约定被破坏需要同步更新断言，**不是**测试坏了。」

这意味着现有设计**主动阻止重构**。P0 的唯一目标就是解除这个锁定。

### 任务清单

#### P0.1 建立测试基线 ✅ 已完成（2026-11-25 人工实测）

**决定：P0.1 已由人工完成，Agent 直接跳到 P0.2，不要重跑 mobile 基线。**

已实测：`mobileArm64_v8aDebug` = 6,226 tests，21 failed，3 skipped。
完整失败清单见「既有失败清单」章节。

**Agent 只需补做一项：测一次 leanback 基线**

```bash
bash gradlew :app:testLeanbackArm64_v8aDebugUnitTest > build/base-leanback.log 2>&1; echo "EXIT=$?" >> build/base-leanback.log
```

把数字补进「测试基线」表格。**失败用例照原样记录，不要修。**

> 注意：
> - 日志务必重定向到**仓库内路径**（如 `build/xxx.log`）。实测 `/tmp` 在部分调用下 Python 无法访问，增加排查难度。
> - 跑完记得删掉日志文件，不要提交（`build/` 已在 .gitignore 中）。

#### P0.2 建立源码文本测试分类机制

1. 新建标记接口（三处源集各一份，或只在 `main` 的 test 源集建一份并让其他引用）：

   建议放在 `app/src/test/java/com/fongmi/android/tv/testing/SourceTextTest.java`：

   ```java
   package com.fongmi.android.tv.testing;

   /**
    * 标记「断言源码文本」的测试。
    *
    * <p>这类测试锁定实现细节（方法体字符串），会阻止合法的结构重构。
    * 重构期间用 {@code -PexcludeSourceTextTests} 排除，日常 CI 仍全量运行。
    */
   public interface SourceTextTest {}
   ```

2. 给全部 75 个 `*SourceTest.java` 加上注解。**只加注解，一个字都不要改断言。**

   在类声明上方加：

   ```java
   @org.junit.experimental.categories.Category(com.fongmi.android.tv.testing.SourceTextTest.class)
   ```

   注意：`JUnit 4.13.2` 已包含 `org.junit.experimental.categories.Category`，无需新增依赖。

3. **同时**处理那 289 个读取源码但文件名不是 `*SourceTest` 的测试。做法：
   - 先按文件名筛：`grep -rl 'Files.readAllBytes\|Files.readString\|new String(Files' app/src/test* --include=*.java`
   - 逐个判断：这个测试是不是**只**断言源码文本？
     - 是 → 加 `@Category(SourceTextTest.class)`
     - 否（既断言源码又测行为）→ **不改**，记录到待观察列表
   - **不确定时不要加注解**，宁可漏掉也不能误伤行为测试。

4. 在 `app/build.gradle` **文件末尾**（`dependencies {}` 块之后、文件最外层）新增以下块：

   ```gradle
   // P0: 重构期间用 -PexcludeSourceTextTests 跳过仅断言源码文本的测试。
   // 已核实 androidx.media3 与 AGP 的单元测试任务均继承自 Test，
   // 且 Gradle 9.5.1 的 JUnitOptions 仍提供 excludeCategories(String...)。
   tasks.withType(Test).configureEach {
       if (project.hasProperty('excludeSourceTextTests')) {
           useJUnit {
               excludeCategories 'com.fongmi.android.tv.testing.SourceTextTest'
           }
       }
   }
   ```

   **注意事项（Agent 必读）：**

   - **不要**放在 `android {}` 块内部。`tasks.withType` 是项目级 API，放在顶层。
   - 当前 `app/build.gradle` **没有**任何既有的 `tasks.withType(Test)` 配置（已核实），所以是新增而非合并。
   - 该项目是 JUnit 4（`testImplementation libs.junit`，版本 `4.13.2`），**不是** JUnit 5。因此必须用 `useJUnit { }`，**不能**用 `useJUnitPlatform { }`。用错会导致所有测试静默不执行。
   - `Category` 注解来自 `org.junit.experimental.categories.Category`，JUnit 4.13.2 自带，**不需要新增任何依赖**。

5. **验证配置真的生效**（不能只靠"应该可以"）：

   ```bash
   # a) 先验证脚本语法与 API 有效（便宜，1-2 分钟）
   bash gradlew :app:help -PexcludeSourceTextTests --offline -q

   # b) 再验证排除真的跳过了测试（昂贵，首次编译 15-40 分钟）
   bash gradlew :app:testMobileArm64_v8aDebugUnitTest -PexcludeSourceTextTests
   ```

   检查测试报告 `app/build/reports/tests/testMobileArm64_v8aDebugUnitTest/index.html`。

   如果排除后测试数没有减少，说明 `@Category` 没加对或配置未生效，**必须排查到生效为止，不得跳过此步**。

   > **已验证结论（2026-11-25，可放心使用）：**
   > 上述 Gradle DSL 在本仓库 `AGP 9.2.1 + Gradle 9.5.1 + JUnit 4.13.2` 组合下配置阶段通过（`gradlew :app:help` exit=0）。
   > 该结论只验证了「脚本可被正确解析、API 存在」，**不替代 b 步的运行时验证**——Agent 首轮仍需亲自跑一次 b 步确认测试数下降。

**验收：**
- `bash gradlew :app:testMobileArm64_v8aDebugUnitTest -PexcludeSourceTextTests` 能跑通，且跳过的测试数 > 0。
- 不带参数的全量测试，结果与 P0.1 基线**完全一致**（说明加注解没有改变全量行为）。

#### P0.3 输出「实现文本耦合地图」

生成一份清单，列出哪些生产文件被多少个源码断言测试锁定。建议用脚本生成后人工整理：

```bash
cd /e/gitwork/easytv
grep -rhoE '"[^"]*\.java"' app/src/test* --include=*SourceTest.java \
  | sort | uniq -c | sort -rn > /tmp/coupling.txt
```

把结果写入 `docs/refactor-governance-plan.md` 的「实现文本耦合地图」章节，重点标注：

| 生产文件 | 被锁定的测试数 | 重构建议 |
|---|---:|---|
| `VideoActivity.java`（leanback） | 18+16 | P1 阶段需要**先**把断言改为行为测试 |
| `PlayerManager.java` | 13 | P4 阶段前需处理 |
| `TmdbDetailActivity.java` | 7+7 | P2 阶段前需处理 |

**这一步的意义**：让你在动某个文件前，知道会撞上多少个断言。

### P0 完成标准（全部满足才能进 P1）

- [x] `docs/refactor-governance-plan.md` 有 mobile 测试基线数字（6,226 / 21 failed / 3 skipped）
- [ ] leanback 测试基线已补测
- [ ] `SourceTextTest` 标记接口已创建
- [ ] 至少 75 个 `*SourceTest.java` 已加 `@Category`
- [ ] `-PexcludeSourceTextTests` 参数可用且生效
- [ ] 全量测试结果与基线一致
- [ ] 「实现文本耦合地图」已产出
- [ ] 已提交并打恢复标签

### P0 禁止事项

- 不要删除任何一个 `assertTrue(source.contains(...))`
- 不要为了「让测试更好」而重写测试
- 不要修 P0.1 中发现的既有失败测试

---

## 三、P1：消除 leanback/mobile 双端重复

### 背景（Agent 必读）

**已核实的事实：**

- `app/src/leanback/java/.../ui/activity/VideoActivity.java` = 13,255 行
- `app/src/mobile/java/.../ui/activity/VideoActivity.java` = 11,976 行
- 两者的方法名重合 **443 个**（leanback 共 709 个方法，mobile 共 851 个）
- 两者**都已经继承** `app/src/main/java/com/fongmi/android/tv/ui/activity/PlaybackActivity.java`（1,434 行）

**这意味着共享基类已经存在**，P1 不是从零建架构，而是把重复的方法上提到 `PlaybackActivity` 或新的中间基类。

另外：

- `ui/dialog/` 下 leanback 有 34 个、mobile 有 44 个同名弹窗，其中 26 个同名，合计 7,479 行。
  但**逐字节完全相同的只有 2 个（215 行）**，其余是高度相似但已分叉的实现。
  → 弹窗合并风险较高，**放在 P1 后半段，且只处理完全一致或差异极小的**。

### 任务清单

#### P1.1 抽取纯逻辑共享方法（低风险，先做）

目标：从 443 个同名方法中，挑选**不涉及任何 View / 布局 / 焦点 / 触摸**的纯数据与状态逻辑，上提到 `PlaybackActivity`。

优先候选（已在代码中确认存在）：

```
applyHistoryPlayerKernel          // 播放内核选择
applyPendingResumeSeek            // 续播定位
alignHistoryWithSelectedEpisode   // 集数对齐
applyAutoIntroSkip                // 自动跳过片头
applyIntentPlaybackSelection      // 播放选择
applyPendingPlayerKernel          // 待定内核
analyzeTmdbSeasonWithAi           // AI 季分析
applyIntentTmdbVodRemark          // TMDB 备注
```

**执行方式：**

1. 先在 leanback 和 mobile 两个文件里，逐字对比该方法的实现。
2. **只有实现完全一致（或仅有日志 TAG 差异）才上提。**
3. 若有差异，**跳过该方法**，记录到文档的「分叉方法清单」。
4. 上提后，在两个子类中删除原方法，改由继承获得。
5. 跑 `testBehavior`（P0 建的参数）+ 编译。

**单个工作单元的上限：一次提取 3-5 个方法。** 不要贪多。

**验收：** 提取的方法在两端的调用点行为不变，测试通过，行数下降。

#### P1.2 建立端差异化的抽象点

对确实需要分叉的行为，用 `protected` 钩子方法替代复制粘贴：

```java
// PlaybackActivity (main)
protected void onEpisodeSelected(Episode item) { ... 默认实现 ... }

// leanback/VideoActivity
@Override
protected void onEpisodeSelected(Episode item) { ... 遥控器焦点处理 ... }
```

**判断标准：** 同一段逻辑出现 ≥ 2 处，且差异只在「焦点/触摸/布局」→ 用钩子。

#### P1.3 弹窗合并（后半段，谨慎）

只处理这两类：

1. **逐字节完全相同**的 2 个（已确认：`AdBlockStatsDialog` 系列中的 215 行）→ 直接删一份，移到 `main`。
2. **差异 < 20 行且仅为资源引用**的 → 抽到 `main` 加参数化。

**差异较大的 24 个弹窗不动。** 它们是真实分叉，合并收益低于风险。

### P1 完成标准

- [ ] 两端 `VideoActivity` 合计行数从 25,231 降到 **≤ 16,000**
- [ ] 所有被上提的方法在两端行为一致
- [ ] 分叉方法清单已记录（明确哪些是故意保留差异）
- [ ] 两端全量测试通过
- [ ] 每个工作单元有独立提交 + 恢复标签

### P1 禁止事项

- 不要为了「统一」而改变行为。leanback 的焦点逻辑和 mobile 的触摸逻辑**必须保持原样**。
- 不要一次上提超过 5 个方法。
- 不要合并差异较大的弹窗。

---

## 四、P2：拆解 TmdbDetailActivity

### 背景（Agent 必读）

- `app/src/main/java/com/fongmi/android/tv/ui/activity/TmdbDetailActivity.java` = **14,365 行**
- 实现 **6 个接口**
- 已探测到的超长方法：`initFusionPlayer()` 221 行、`showNativeEnhancedInlineEpisodes()` 181 行
- 有 7+7 个源码文本断言测试锁定它（P0 的耦合地图会告诉你确切数字）

### 任务清单（按顺序，一次一个）

| 顺序 | 抽出目标类 | 职责 | 预计搬走行数 |
|---|---|---|---:|
| P2.1 | `TmdbDetailPresenter` | 数据加载、TMDB API 调用、缓存 | ~2,500 |
| P2.2 | `TmdbInlinePlayerController` | `initFusionPlayer()` 等内联播放控制 | ~3,000 |
| P2.3 | `TmdbEpisodeBinder` | `showNativeEnhancedInlineEpisodes()` 等剧集渲染 | ~1,500 |
| P2.4 | `TmdbRecommendationView` | 推荐位渲染 | ~1,200 |

### 每个子任务的固定流程

1. **先补特征测试**：为要搬走的逻辑写行为测试，锁定当前行为（不是源码文本）。
2. 新建目标类，把方法连同其依赖字段搬过去。
3. Activity 只保留「委托调用」，原方法体变成一行 `presenter.xxx(...)`。
4. 跑测试 + 编译。
5. 提交。

**关键约束：Activity 的公开行为（生命周期、Intent 处理、UI 回调）绝不能变。** 搬走的是实现，不是入口。

### P2 完成标准

- [ ] `TmdbDetailActivity` 从 14,365 行降到 **≤ 6,500 行**
- [ ] 抽出 4 个职责清晰的类
- [ ] 每个抽出的类有至少 1 个行为测试
- [ ] 全量测试通过

### P2 禁止事项

- 不要一次抽出多个模块。
- 不要「顺手」优化业务逻辑。
- 不要在没补特征测试的情况下搬代码。

---

## 五、P3：收拢 player 播放策略碎片

### 背景（Agent 必读）

**已核实：**

- `app/src/main/java/com/fongmi/android/tv/player/` 根层（不含子目录）= **65 个文件、24,043 行**
- 其中 **39 个是 `Playback*` 命名的类**
- **29 个不足 150 行**

这些是「每个判断条件抽一个类」的产物。行数不多，但**定位成本极高**：改一个播放行为可能要在 5 个类之间跳转。

### 合并方案

| 合并组 | 现有碎片（已确认存在） | 合并为 |
|---|---|---|
| AB 实验 | `PlaybackProfileAbPolicy`、`PlaybackProfileAbStore`、`PlaybackProfileAbCoordinator`、`PlaybackProfileAbAcceptancePolicy`、`PlaybackProfileAbIdentity` | `PlaybackAbExperiment` |
| 系统条件 | `PlaybackSystemConditionPolicy`、`PlaybackSystemConditionMonitor`、`PlaybackSystemConditionCoordinator` | `PlaybackSystemCondition` |
| 诊断遥测 | `PlaybackTelemetry`、`PlaybackTelemetryCoordinator`、`PlaybackTelemetryMapper`、`PlaybackDiagnosticCollector`、`PlaybackDiagnosticSession` | `PlaybackDiagnostics` |
| 内存 | `PlaybackMemoryPolicy`、`PlaybackMemoryMonitor`、`PlaybackMemoryCoordinator` | `PlaybackMemoryGuard` |

### 执行方式

1. 每组合并成一个类，原类改为 `@Deprecated` 的薄委托层（**先保留，不删**）。
2. 跑全量测试。
3. 确认无回归后，删除委托层，更新所有调用点。
4. 提交。

**顺序：从被引用最少的组合并起。** 用 `grep -rl 'ClassName' app/src` 统计引用数，先做引用最少的。

### P3 完成标准

- [ ] `player/` 根层 `Playback*` 类从 39 个降到 **≤ 15 个**
- [ ] 行数减少约 1,500 行
- [ ] 关键播放路径（起播、切源、跳转、切内核）行为不变
- [ ] 全量测试通过

### P3 禁止事项

- 不要合并语义不同的类（例如把「缓存策略」和「解码策略」硬合并）。
- 不要删除仍在被引用的类而不更新调用点。
- 不要改任何播放参数的默认值。

---

## 六、P4：拆解 PlayerManager

### 背景（Agent 必读）

- `app/src/main/java/com/fongmi/android/tv/player/PlayerManager.java` = **9,819 行**
- 只实现 1 个接口，但有 40+ 个 `Playback*` 相关类依赖它
- 超长方法：`applyMpvAutoInitialControl()` 221 行、`evaluateMpvAutoOutput()` 170 行
- 有 13 个源码文本断言锁定它

**这是风险最高的阶段，必须最后做，且 P1-P3 全部完成后才启动。**

### 切分建议

| 目标类 | 职责 |
|---|---|
| `PlayerEngineRouter` | 三引擎（Exo / MPV / IJK）选择与切换 |
| `PlayerStateMachine` | 状态管理、生命周期 |
| `PlayerBufferController` | 缓冲、预载、缓存 |
| `PlayerAudioVideoConfig` | 音视频参数应用 |

### 执行方式

1. **先做 P0 的耦合清理**：把 13 个源码文本断言改写成行为测试。
2. 每切一刀，跑全量测试 + 至少一次真机/模拟器起播验证（如果设备可用）。
3. 保留 `PlayerManager` 作为门面（Facade），内部委托给切出的类——**不要改变它对外的公开 API**。

### P4 完成标准

- [ ] `PlayerManager` 从 9,819 行降到 **≤ 4,500 行**
- [ ] 对外公开方法签名完全不变（门面模式）
- [ ] 三引擎起播、切换、跳转行为不变
- [ ] 全量测试通过
- [ ] 有条件时完成真机验证

### P4 禁止事项

- 不要改 `PlayerManager` 的公开方法签名（会破坏所有调用方）。
- 不要在没跑真机验证的情况下宣称完成。
- 不要同时改 PlayerManager 和 VideoActivity。

---

## 七、进度看板（Agent 每次提交后必须更新）

> 这是跨会话恢复的唯一持久状态。格式必须保持。

| 阶段 | 状态 | 已完成项 | 当前项 | 下一动作（恰好一个） |
|---|---|---|---|---|
| P0 | 🟡 进行中 | P0.1 测试基线（mobile 实测 6226/21 failed/3 skipped） | — | 补测 leanback 基线，然后开始 P0.2 |
| P1 | ⬜ 未开始 | — | — | — |
| P2 | ⬜ 未开始 | — | — | — |
| P3 | ⬜ 未开始 | — | — | — |
| P4 | ⬜ 未开始 | — | — | — |

状态图例：⬜ 未开始 / 🟡 进行中 / ✅ 已完成 / 🔴 阻塞

### 测试基线

> **已由人工在 2026-11-25 实测完成，Agent 不需要重跑 P0.1。**
> 基线一旦变化就是回归信号。

**mobileArm64_v8aDebug：6,226 tests completed, 21 failed, 3 skipped**（耗时 8 分 10 秒，暖缓存）

| Flavor | 总数 | 通过 | 失败 | 跳过 | 记录日期 |
|---|---:|---:|---:|---:|---|
| mobile（含源码断言） | 6,226 | 6,202 | **21** | 3 | 2026-11-25 |
| leanback（含源码断言） | — | — | — | — | 待测 |

### 既有失败清单（21 个，**属于基线，不是你的改动造成的**）

> Agent 铁律：**以下用例失败是已知状态，绝对不要尝试修复它们。**
> 你的重构如果让「通过数」低于 6,202，才是回归。

| # | 测试类 | 用例 | 类别 |
|---:|---|---|---|
| 1 | `CacheTotalLimitApplyContractTest` | `bothLimitEntriesShareThePlaybackApplyPath` | 源码断言 |
| 2 | `CacheTotalLimitApplyContractTest` | `totalLimitChangeAppliesAndRepaintsTheSummary` | 行为 |
| 3 | `ChaquopyRequirementsTest` | `requestsCertificateDependencyIsPackagedExplicitly` | 打包配置 |
| 4 | `FfmpegVc1SupportTest` | `bundledFfmpeg_hasVc1DecoderForEveryAbi` | 原生资产 |
| 5 | `FollowingAlistImportTest` | `serverlessNormalizersPreserveFollowOption` | 行为 |
| 6 | `LabEnvTest` | `deleteTreeUnlocksReadOnlyDirectory` | 环境/文件系统 |
| 7 | `MpvFontConfigTest` | `writeIfChanged_replacesStaleConfigurationAndCleansTemporaryFile` | 文件系统 |
| 8 | `MpvHlsCacheCoordinatorTest` | `successfulCommitPublishesCompleteFileAndReleasesReservation` | 缓存 |
| 9 | `PlaybackOwnershipSourceTest` | `staleSwitchCallbacksRecheckPageAndPlaybackContext` | **源码断言** |
| 10 | `PlaybackOwnershipSourceTest` | `staleSwitchCallbacksRecheckPageAndPlaybackContextWithApplyGuard` | **源码断言** |
| 11 | `PlayerPlaybackRegressionSourceTest` | `mobileExoStartupPassesResumePositionAndSkipsTheSecondRestoreSeek` | **源码断言** |
| 12 | `PythonSpiderDiagnosticsWiringTest` | `dependencyFailureKeepsAnUnconditionalLogcatChannel` | **源码断言** |
| 13 | `PythonSpiderDiagnosticsWiringTest` | `dependencyFailureKeepsTheBridgeCallGuarded` | **源码断言** |
| 14 | `PythonStartIdempotenceSourceTest` | `constructorStartsPythonThroughTheGuardedEntryPoint` | **源码断言** |
| 15 | `PythonStartIdempotenceSourceTest` | `theStarterIsSynchronizedAndToleratesALostRace` | **源码断言** |
| 16 | `ThemeBinderContractTest` | `nativeActivitiesOutsideBaseActivityAreExplicitlyAccountedFor` | 契约 |
| 17 | `TmdbDetailActivityLayoutTest` | `colorfulDetailDoesNotKeepPlaybackServiceBoundBetweenEpisodeLaunches` | 布局 |
| 18 | `TmdbVideoTest` | `displayTypeUsesChineseCategoryNames` | 行为 |
| 19 | `TvAppExitSourceTest` | `backgroundResumeIsDebouncedAndWorkerStopIsVisible` | **源码断言** |
| 20 | `TvFixedLightSurfaceContrastTest` | `paletteForegroundsStayReadableOnFixedLightSurfaces` | 视觉契约 |
| 21 | `VideoActivityLayoutTest` | `leanbackPlaybackLoadingIgnoresStaleReadyBeforeNewPlayerStarts` | 布局 |

**重要观察：** 21 个既有失败中有 **9 个是 `*SourceTest` / 源码文本断言**（第 1、9、10、11、12、13、14、15、19 项）。这直接证明 P0 的必要性——这些断言已经在漂移，并非稳定的安全网。

**交叉验证手段：** P0.2 加 `@Category` 后，用 `-PexcludeSourceTextTests` 跑时，失败数应从 21 降到约 12。对不上说明分类做错了。


### 已知问题清单

> 重构过程中发现但**不属于本次范围**的 bug/坏味道，记录在此，不要修。

| 发现日期 | 文件 | 描述 | 是否已另开任务 |
|---|---|---|---|
| — | — | — | — |

### 分叉方法清单（P1 填写）

> 两个 VideoActivity 中同名但实现有意/无意不同的方法，需人工确认是否保留差异。

| 方法名 | 差异描述 | 处理决定 |
|---|---|---|
| — | — | — |

### 实现文本耦合地图（P0.3 填写）

| 生产文件 | 被锁定的源码断言数 | 备注 |
|---|---:|---|
| — | — | — |

---

## 八、附录：关键路径与数据速查

Agent 可以直接引用以下已核实数据，避免重复探测：

### 代码体量

| 指标 | 数值 |
|---|---:|
| 仓库全部 tracked 文件行数 | 1,158,515 |
| 自研业务 Java（不含测试/第三方） | ~397,000 |
| `ui/` 包 | 162,524 行 / 460 文件 |
| `player/` 包 | 93,433 行 / 323 文件 |
| 测试源集（test + testMobile + testLeanback） | 106,242 行 / 952 文件 |
| `third_party/`（vendored，禁止手改） | 165,871 行 / 658 文件 |

### 前 10 大生产文件

| 行数 | 文件 | 目标阶段 |
|---:|---|---|
| 14,365 | `main/.../ui/activity/TmdbDetailActivity.java` | P2 |
| 13,255 | `leanback/.../ui/activity/VideoActivity.java` | P1 |
| 11,976 | `mobile/.../ui/activity/VideoActivity.java` | P1 |
| 9,819 | `main/.../player/PlayerManager.java` | P4 |
| 6,667 | `main/java/androidx/media3/mpvplayer/MpvPlayer.java` | 暂不处理 |
| 3,515 | `main/.../ui/dialog/RemoteTrustDialog.java` | 暂不处理 |
| 2,894 | `main/.../ui/dialog/GitCloudDialog.java` | 暂不处理 |
| 2,742 | `main/.../ui/helper/TmdbUIAdapter.java` | P2 相关 |
| 2,721 | `main/java/androidx/media3/mpvplayer/MpvHlsProxy.java` | 暂不处理 |
| 2,553 | `main/.../ui/custom/TmdbHeaderView.java` | P2 相关 |

### 源集结构（关键）

```
app/src/main/      公共代码（两个 flavor 共享）
app/src/leanback/  电视端专属（遥控器焦点、Leanback 库）
app/src/mobile/    手机端专属（触摸、手势）
app/src/test/      公共单元测试
app/src/testLeanback/
app/src/testMobile/
```

继承关系：两个 `VideoActivity` 都 `extends PlaybackActivity`（已存在于 `main`）。

### 构建命令（必须带 flavor + ABI，没有裸任务）

```bash
bash gradlew :app:assembleMobileArm64_v8aDebug
bash gradlew :app:assembleLeanbackArm64_v8aDebug
bash gradlew :app:testMobileArm64_v8aDebugUnitTest
bash gradlew :app:testLeanbackArm64_v8aDebugUnitTest
```

### 构建耗时实测（2026-11-25 冷缓存）

| 场景 | 实测耗时 | 说明 |
|---|---|---|
| `gradlew :app:help`（仅配置阶段） | 1-2 分钟 | 适合验证脚本改动 |
| 单元测试首次运行（冷缓存） | **15-40 分钟** | 需编译 2,693 个 Java 文件 + Chaquopy Python 资源 |
| 增量编译后再次测试 | 3-8 分钟 | 只重编改动文件 |

**因此：**

- 验证 Gradle 脚本改动用 `:app:help`，不要直接跑测试。
- 重构涉及 Java 代码时，用增量编译，避免 `clean`。
- 单次测试启动后用 `run_in_background` + 轮询日志，不要重复启动（会争抢锁导致更慢）。
- **绝对不要加 `--offline`**。实测：`mobileArm64_v8aDebugAnnotationProcessorClasspath` 需要 `org.xerial:sqlite-jdbc:3.41.2.2`，该依赖不在本地缓存，`--offline` 会让构建在 `:app:javaPreCompileMobileArm64_v8aDebug` 直接失败并报 `No cached version available for offline mode`。这是环境依赖缺失，**不是代码问题**，不要因此去改 `app/build.gradle`。
- 首次成功构建后 `app/build/intermediates/javac/` 会缓存约 8,000 个 class，后续增量编译只需 1-3 分钟。**第一次构建慢是正常的，不要中途放弃。**

### JUnit 版本

`4.13.2`，已含 `org.junit.experimental.categories.Category`，**不需要新增依赖**。

### 绝对不要碰的东西

- `third_party/`（vendored 上游 + 预编译 `.so`/`.aar` + lock 文件）
- `third_party/*-lock.json`（`mpv-native-lock.json`、`ijk-native-lock.json`、`media-lock.json`）
- `app/build.gradle` 的 `resolutionStrategy` 与 Media3 版本强制
- `nodejs/build.gradle` 的 `ANDROID_STL` 配置（有特殊注释说明原因）
- `webhome-devkit/`（独立子项目，与 App 运行时无关）
