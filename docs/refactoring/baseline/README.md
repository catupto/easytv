# 架构债务基线（阶段 0 产出）

> 本目录是**机器可读的债务白名单**，由 `scripts/arch/guard.sh` 消费。数字全部由脚本产出，不接受手工填写（主方案 §6.2 的教训：人工读数就是会错，初稿 4 处数字因此返工）。

## 文件

| 文件 | 产出者 | 内容 |
|---|---|---|
| `metrics-baseline.json` | `scripts/arch/metrics.sh` | 文件/行数、≥1000 行清单、方法/字段极值、包体量、flavor 双份、静态耦合、源码文本断言 |
| `deps-baseline.json` | `scripts/arch/dep-graph.sh` | 顶层包有向边、52 对双向依赖、环 |
| `dup-baseline.json` | `scripts/arch/dup-scan.sh` | leanback ∩ mobile 同路径文件、Jaccard 分桶、字节相同集合、命名空间占用 |
| `debt-baseline.json` | 上述三者汇总 + 21 条既有失败清单 | `guard.sh` 唯一读取的判定文件 |

## 锚点与口径

- **结构基线锚点**：commit `91cdb8c`。在该 commit 的干净 worktree 上重跑三个脚本，主方案 §2 的每个数字都精确复现（见下表）。
- **采集点**：commit `790228d`（当前 HEAD）。它相对锚点多了 `4.1`/`4.2` 两个已批准提交，其中 4.2 新增 166 行脚手架，所以 `totals.java_*` 取 790228d 的值。
- `metric_counter`：`regex-v1`（`_archlib.py` 顶部有完整定义）。方法数故意**过计**（含匿名类方法、跨行声明）——方案 R0-1 只要求同口径趋势可比，不追求绝对准确。
- `java_lines` = `wc -l` 语义 = 统计 `\n` 字节数。**不是** `splitlines()`；两者相差「末尾无换行符的文件数」。方案 §2.2.1 记录的 58,466 / 58,468 就是这个差。

## 口径校准表（阶段 0 退出标准 1 的证据）

| 指标 | 锚点 91cdb8c 实测 | 主方案 §2 | 结论 |
|---|---:|---:|---|
| Java 文件 / 行数 | 2,697 / 577,187 | 2,697 / 577,187 | 精确 |
| ≥1000 / ≥2000 / ≥3000 行文件 | 55 / 15 / 8 | 55 / 15 / 8 | 精确 |
| 最大文件 | 14,365 `TmdbDetailActivity.java` | 14,365 | 精确 |
| `TmdbDetailActivity` 方法 / 字段 | 1,063 / 230 | 1,063 / 230 | 精确 |
| 包内直接类数最大 | 90（`player/exo`） | 90 | 精确 |
| flavor 双份文件 / 行数 | 80 / 58,466 | 80 / 58,466 | 精确 |
| Jaccard 均值 | 0.5844 | 0.583 | 差 0.0014 |
| Jaccard 分桶 4A/4B/4C | 17 / 25 / 38 | 17 / 25 / 38 | 精确 |
| L1 字节相同 | 11 个 / 816 行（单侧） | 11 / 816 | 精确 |
| 双向包依赖对 | 52 | 52 | 精确 |
| `player ↔ setting` | 72 / 26 | 72 / 26 | 精确 |
| `ui → player` 文件数 | 36 | 36 | 精确 |
| `Setting.*` 引用 / 文件 | 628 / 112 | 628 / 112 | 精确 |
| `App.get()` 文件数 | 93 | 93 | 精确 |
| 源码文本断言类 / 用例 / 行 | 218 / 1,661 / 44,150 | 218 / 1,661 / 44,150 | 精确 |
| `Util.isLeanback()`（grep 行口径） | 232 | 232 | 精确 |
| 顶层包体量最大 | 93,237（`player`） | 93,238 | 见下 |

**两处已知口径差，均已解释，不是数据错误**：

1. **包体量 93,237 vs 93,238**：方案表格用的是 `splitlines()` 口径，本项目脚本统一用 `wc -l` 口径。差值 1 来自 `player/` 包内一个末尾无换行符的文件。同一份数据在用不同读法时就会差这一点，已在 `metric_counter` 里固定。
2. **`isLeanback` 双口径**：方案 §2.2.4 的 232 是 `grep -rn "isLeanback()" | wc -l`，它统计**命中行数**，因此连 Javadoc/注释里提到这个符号的行也算。批 4.2 在写 `DeviceModePolicy` 的文档注释时新增了 5 处提及，于是 HEAD 的原始口径读数是 237，而**真实调用点一个都没变**。

   为避免这个数字被误读成回归，`metrics.sh` 同时输出两个数：

   | 字段 | 锚点 | HEAD | 用途 |
   |---|---:|---:|---|
   | `isLeanback_raw_lines` | 232 | 237 | 与方案 §2.2.4 对齐，**不作门禁** |
   | `isLeanback_callsites` | **219** | **219** | **门禁指标**：去注释、排除方法声明 |

   两者在锚点和 HEAD 上的关系（232→219、237→219）恰好证明：4.2 只增加了文档文字，调用点净变化为 0。这正是 `guard.sh` 被设计成「只用可判定口径」的原因。

## 21 条既有失败

`debt-baseline.json.tests.known_failures` 逐条记录 `class` / `test` / `category`，来源是 `docs/refactor-governance-plan.md`（2026-11-25 唯一一次全量实测：6,226 用例 / 21 失败 / 3 跳过 / 通过 6,202）。

**判定规则（两条必须同时成立）**：

1. 当前失败集合 **⊆** `known_failures`；
2. 通过数 **≥** `passed_floor`（6,202）。

只满足第 1 条不够 —— 新增失败会被既有 21 条掩盖。

> 这 21 条里 9 条本身就是 `*SourceTest` 源码文本断言。它们不是安全网，是负债，也与 `source_text_locks` 只减不增的规则互为印证。

## 门禁能力自证

`bash scripts/arch/guard.sh --self-test` 会：

1. 断言当前树是干净的（不红）；
2. 逐一注入 6 类合成回归（新增双份文件、新增双向依赖、最大文件变长、`isLeanback` 增加、源码文本断言增加、flavor 遮蔽 main），**断言每一类都必须让门禁变红**；
3. 断言"正好落在容差内的增长"**仍然通过**——容差不是豁免，边界两侧行为都要对；
4. 断言**过期的豁免条目会判红**——`approved-drift.json` 里的临时豁免不能变成永久豁免。

阶段 0 退出标准 2 另有实测证据：在 `app/src/main/java/com/fongmi/android/tv/` 下临时新增一个 1,205 行的 `BigProbe.java`，`guard.sh` 立刻以 6 条违规变红（文件数、总行数、字段极值、≥1000 行计数、白名单外新文件），删除后恢复绿色。

---

## 基线策略 v2（2026-11-26 修订）

### 为什么要改

第一轮长任务（`5e3dc1c`…`43e0e13`，18 个提交）暴露了一个机制缺陷：`guard.sh` 对行数类指标是**精确比对**，而把 `Util.isLeanback()` 换成 `DeviceModePolicy.current().isTv()` 会让所在行变长、断言折行，于是每次提交都有 +1~+5 行的"机械漂移"。当时的处理方式是**在每个提交里把 `debt-baseline.json` 的数字改成和现实一样**，结果是：

| 指标 | T0 冻结值 | 被改成 | 性质 |
|---|---:|---:|---|
| `extremes.max_file_lines` | 14,365 | 14,366 | 基线被抬高 |
| `offenders.setting_static_callsites` | 628 | 639 | 基线被抬高 |
| `offenders.app_get_files` | 93 | 94 | 基线被抬高 |
| `offenders.bean_history_files` | 56 | 57 | 基线被抬高 |
| 13 个 `large_files` 条目 | — | 各 +1~+5 | 基线被抬高 |

基线一旦等于现状，`guard.sh` 就退化成橡皮章：它只能发现"下一批又涨了"，永远发现不了"这一批涨的"。

### 现在的三层结构

| 层 | 文件 | 可变性 | 作用 |
|---|---|---|---|
| **地板** | `debt-baseline.pinned.json` | **不可变**，只能显式重冻 | 冻结在 T0（`5e3dc1c`）的真实值。工作基线怎么改都绕不过它 |
| **记录** | `debt-baseline.json` | 只允许下调/删除条目 | 日常参考的冻结债务清单；可收紧，不可放松 |
| **豁免** | `approved-drift.json` | 只允许具名、带失效期 | 一次性、可解释的漂移通道 |

`guard.sh` 对每个指标**同时校验 pinned 与工作基线，取更严者**，再叠加容差与豁免。

### 判定规则

| 指标类别 | 容差 | 依据 |
|---|---|---|
| 行数 / 成员数（`totals.java_lines`、`extremes.max_file_lines/max_methods/max_package_lines`、`large_files[path]`、`flavor.dup_lines`） | **1%，上限 50 行** | 机械替换必然带来折行，属噪声 |
| 计数类（`isLeanback_callsites`、`setting_static_callsites`、`app_get_files`、`bean_history_files`、`distribution.*`、`dup_files_max`、`bidirectional_pairs_max`、`source_text_locks*`） | **0** | 数量变化只可能来自真实合并/新增 |
| 集合类（双份文件清单、双向依赖对、`large_files` 名单、`namespace_files`） | **0**，且必须同时是 pinned 与工作基线的子集 | 任一记录里没有的都算新增 |

### 豁免怎么写

`approved-drift.json` 只有两种 `kind`，都强制 `batch` / `reason` / `expires_stage`：

```jsonc
// 计数类：给一个增量上限
{ "kind": "increment", "metric": "offenders.setting_static_callsites",
  "increment": 11, "batch": "1.3",
  "reason": "合并双端副本时取了两端分支并集 …", "expires_stage": 3 }

// 集合类：点名放行一个条目
{ "kind": "new_item", "metric": "deps.bidirectional_pairs",
  "items": [["dlna", "service"]], "batch": "1.3",
  "reason": "合并 DLNACastManager 后双向 …，修法：把 DLNAServiceConfiguration 迁入 service",
  "expires_stage": 3 }
```

**到达 `expires_stage` 即判红**，条目必须被删除（债务关闭或修掉）。写不出 `reason` 的豁免不允许存在。

当前 5 条豁免全部来自 1.3 的双份文件合并（`expires_stage: 3`），已在文末"待关闭"列出。

### 单元测试门禁

`bash scripts/arch/test-gate.sh` 把"失败 20 条能不能接受"从人眼判断变成机器判定：

```bash
bash scripts/arch/test-gate.sh --variant mobile   # 读已有 test-results，秒级
bash scripts/arch/test-gate.sh --run              # 先跑 Gradle 再判定（分钟级）
```

判定 = `passed ≥ passed_floor` **且** 失败集合 ⊆ `known_failures`。已实测：从 `known_failures` 里删掉一条后，脚本立刻以
`NEW FAILURE MpvFontConfigTest::writeIfChanged_...` 变红——证明它不是只看总数的橡皮章。

`leanback` 变体目前只有报告、没有基线（历史上从未记录）。要开启严格判定，先跑
`bash scripts/arch/test-gate.sh --run --variant leanback --record-leanback`，人工确认这批失败都不是当前批次引入的，再把产出并入 `tests.baseline_leanback`。

### 待关闭（`expires_stage: 3` 前必须清掉）

| 项 | 现状 | 建议修法 |
|---|---|---|
| `setting_static_callsites` +11 | `AppearanceDialog` +13 / `RecordAdapter` +4，其余批次的迁移减了 6 | 随阶段 3 的 UI 垂直切片下沉 |
| `app_get_files` +1 | `utils/Timer` 新增一处 `App.get()` | `Timer`/`Clock` 随播放业务迁入 `service` 包 |
| `bean_history_files` +1 | `CastDialog` 合并后引用 `bean.History` | 随阶段 3 归位 |
| `dlna ↔ service` | `dlna→service`（启动服务）与 `service→dlna`（引用 `DLNAServiceConfiguration`） | 把 32 行的 `DLNAServiceConfiguration` 迁入 `service` 包 |
| `service ↔ utils` | `utils/Timer` 持有 `PlaybackService` | 同上，`Timer`/`Clock` 迁入 `service` |


## 日常用法

```bash
# 全量体检（3 个采集脚本 + 判定，本机约 5 秒）
bash scripts/arch/guard.sh

# 单看某个维度
bash scripts/arch/metrics.sh
bash scripts/arch/dep-graph.sh --json-out /tmp/d.json --diff docs/refactoring/baseline/deps-baseline.json
bash scripts/arch/dup-scan.sh --check-namespace

# 证明门禁仍然会红
bash scripts/arch/guard.sh --self-test

# 单元测试门禁（读已有 test-results，秒级；--run 会先跑 Gradle）
bash scripts/arch/test-gate.sh --variant mobile
```

**当某批重构让条目消失或变小**：必须在**同一个提交**里把对应条目从 `debt-baseline.json` 删掉/下调，否则 `guard.sh` 会打印 `PRUNE:` 警告。白名单只减不增，不是永久豁免。

**禁止**用"把 `debt-baseline.json` 的数字改成当前值"来让门禁变绿——pinned 地板会立刻挡住，正确做法见「基线策略 v2」的豁免通道。
