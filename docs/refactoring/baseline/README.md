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
2. 逐一注入 6 类合成回归（新增双份文件、新增双向依赖、最大文件变长、`isLeanback` 增加、源码文本断言增加、flavor 遮蔽 main），**断言每一类都必须让门禁变红**。

阶段 0 退出标准 2 另有实测证据：在 `app/src/main/java/com/fongmi/android/tv/` 下临时新增一个 1,205 行的 `BigProbe.java`，`guard.sh` 立刻以 6 条违规变红（文件数、总行数、字段极值、≥1000 行计数、白名单外新文件），删除后恢复绿色。

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
```

**当某批重构让条目消失或变小**：必须在**同一个提交**里把对应条目从 `debt-baseline.json` 删掉/下调，否则 `guard.sh` 会打印 `PRUNE:` 警告。白名单只减不增，不是永久豁免。
