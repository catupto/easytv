# docs/ 索引

> 本目录是 WebHTV 的文档根。**根目录只允许本索引 + 三个被程序读取的文件**，其余一律进子目录（主方案 §6.7）。历史流水账只读，禁止在其上追加内容。

## 目录结构

| 路径 | 用途 | 写入规则 |
|---|---|---|
| `docs/integration/` | **对外契约**：Spider 插件、代理、直播/EPG、解析、字幕、弹幕、播放结果、点播源字段等。这些是真正的参考文档，保持现状 | 可维护 |
| `docs/refactoring/` | 架构重构主方案 + 机器可读基线 | 主方案可修订；`baseline/` 只增不改（用时间戳文件） |
| `docs/refactoring/archive/` | 已被取代的治理计划 | **只读**，禁止追加 |
| `docs/adr/` | 架构决策记录，`ADR-NNNN-<slug>.md` | **只增不改**，被取代时新 ADR 标注 `Supersedes:` |
| `docs/tasks/` | 任务过程文档，`<TASK-ID>-<slug>.md`。**一个任务只允许一份** | 持续追加 |
| `docs/archive/2026/` | 2026 年的过程流水账（原根目录散落文档 + 历史设计/评审记录） | **只读** |
| `docs/superpowers/` | 历史 plan/spec 归档（在本仓约定之前产生） | 只读 |

## 根目录保留的三个文件（不要移动）

这三个文件被**测试或脚本按字面相对路径读取**，移动到子目录会让对应测试直接失败：

| 文件 | 读取者 |
|---|---|
| `docs/ui-token-allowlist.txt` | `scripts/check_ui_tokens.sh:20`、`scripts/check_ui_tokens.py:358` |
| `docs/webhtv-unified-visual-design-system-20260920.md` | `UiTokenGatePortabilityContractTest`、`DialogInputCornerContractTest` |
| `docs/webtheme-compatibility-matrix.md` | `WebThemeCompatibilityMatrixTest`（内容必须与 `WebThemeCompatibilityMatrix.markdown()` 完全一致） |

## 当前有效的重构文档

| 文档 | 说明 |
|---|---|
| [`refactoring/ARCHITECTURE_REFACTOR_MASTER_PLAN.md`](refactoring/ARCHITECTURE_REFACTOR_MASTER_PLAN.md) | **唯一真相源**：病灶诊断、目标架构、批次表、门禁、红线 |
| [`refactoring/baseline/README.md`](refactoring/baseline/README.md) | 债务基线口径说明 + 21 条既有失败 + 门禁自证 |
| [`refactoring/baseline/debt-baseline.json`](refactoring/baseline/debt-baseline.json) | 机器可读债务白名单，由 `scripts/arch/guard.sh` 消费 |
| [`adr/README.md`](adr/README.md) | ADR 编号规则与权威清单入口 |

## 已归档（只读，不要再改）

| 文档 | 归档原因 |
|---|---|
| [`refactoring/archive/refactor-governance-plan-2026-11-25.md`](refactoring/archive/refactor-governance-plan-2026-11-25.md) | 旧 P0–P4 治理计划。其 21 条既有失败基线与 6,226/21/3 测试基线已继承进 `refactoring/baseline/debt-baseline.json`（主方案 §1.6.3 资产 1、2），故可安全归档 |
| [`refactoring/TMDB_DETAIL_ACTIVITY_REFACTORING_ROADMAP.md`](refactoring/TMDB_DETAIL_ACTIVITY_REFACTORING_ROADMAP.md) | 旧 8 周 Delegate 拆分计划。已被主方案 §4.6.2 的垂直切片蓝图取代，作为失败复盘证据保留 |
| `archive/2026/` | 根目录散落的过程日志、设计稿与评审记录（原 17 个根文档 + 177 个 `C<数字>-*` 编号文档 + 其余历史设计文档） |
## 归档现状（批次 1.1 结果）

| 分类 | 数量 |
|---|---:|
| 原根目录过程文档（`CODE_REVIEW_REPORT` / `TMDB_FIX_*` / `智能去广-设计文档` 等） | 17 |
| `C<数字>-*` 编号任务文档（含 123 个 `beta-merge-review`） | 177 |
| 其余历史设计/评估文档 | 298 |
| **`docs/archive/2026/` 合计** | **492** |
| 直接删除的过程产物（`stacktrace.txt`、`fix-episode-gap-numbering.patch`；`build-p7.log` 本就未跟踪且被 `.gitignore:27` 的 `*.log` 覆盖） | 2 + 1 |

`docs/` 根的**直接文件数：479 → 4**（索引 `README.md` + 3 个被程序读取的文件），达标 ≤30。

> 归档是**移动，不是删除**：`docs/` 递归总数因此没有下降（529）。方案 §6.7 对 `docs/` 根的要求是「只允许 `README.md` + 上述子目录」，已在本次满足；`≈330` 这个阶段 1 总量目标属于 1.5「归档细化与索引」的范畴，且依赖后续批次的 1.2–1.4 不新增文档。

## 命名禁令

禁止新增 `xxx-beta-merge-review-dev3-20261023.md` 这类「日期 + 分支 + 序号」的并行文件（主方案 §6.7）。同一个任务只允许一份任务文档，写在 `docs/tasks/<TASK-ID>-<slug>.md`。
