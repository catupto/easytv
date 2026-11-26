# 架构决策记录（ADR）

> 本文件是 ADR 目录的编号规则与索引。**ADR 编号一经分配不复用**：被取代时不删旧编号，而是新建一份并标注 `Supersedes: ADR-NNNN`（主方案 §6.6、§6.11）。

## 什么情况必须写 ADR

以下决策必须有 ADR，不能只写在提交信息或聊天里（主方案 §6.6）：

- 新建 / 合并 / 拆分 Gradle 模块
- flavor 判定规则变更
- 跨层类型移动（例如把 `ui` 的类型下沉到 `core`）
- `proguard-rules.pro` 的 keep 变更
- `catvod` 的 `Spider` 接口变更
- 引入新依赖
- **放弃某个批次**
- **改变某个门禁指标的口径**（例如把一个指标的判定口径从 A 换成 B）

## 命名与结构

```
docs/adr/ADR-NNNN-<kebab-slug>.md
```

最小模板：

```markdown
# ADR-NNNN: <标题>

- 状态：提议 / 已定稿 / 已取代（Supersedes: ADR-XXXX）
- 日期：YYYY-MM-DD

## Context
为什么需要做这个决策，约束是什么。

## Decision
做了什么决定。

## Alternatives
还有哪些选项，为什么没选。

## Consequences
代价、收益、引入的风险。

## Rollback
怎么撤回，粒度是什么。
```

## 权威编号表

权威编号与状态以 **`docs/refactoring/ARCHITECTURE_REFACTOR_MASTER_PLAN.md` §6.11** 为准。本目录只落地对应的 ADR 文件，不重新排定编号。

| ADR | 标题 | 状态 | 依据 | 一句话决策 |
|---|---|---|---|---|
| ADR-0001 | 先立机制，再动代码 | 已定稿 | 主方案 §1.2、§5 阶段 0、§6 | 任何代码移动前，`metrics.sh` + `guard.sh` + CI required check 必须先能变红 |
| ADR-0002 | 单包化：单 APK + 运行期设备形态自适应 | 已定稿（D2） | 主方案 §4.8、§9 D2 | 一个 APK，`DeviceModePolicy` 按形态选 UI；终态双份文件 80→0 |
| ADR-0003 | 设备形态判定谓词：三维，禁止用朝向代替形态 | 已定稿 | 主方案 §4.8.1–4.8.2 | 形态 = `FEATURE_LEANBACK ∨ UI_MODE_TYPE_TELEVISION`；朝向只决定布局方向 |
| ADR-0004 | flavor 收敛先于模块抽取 | 已定稿 | 主方案 §4.3、§5 阶段 4→5 | library 模块不继承 `:app` 的 `mode` 维度，故先收敛 flavor 再抽模块 |
| ADR-0005 | 拒绝纯 Delegate 横切，采用垂直切片 + 状态下沉 | 已定稿 | 主方案 §4.6.1–4.6.2 | 上帝类按 feature 切，状态对象搬出 |
| ADR-0006 | library 模块不声明 `mode` 维度 | 已定稿 | 主方案 §4.3、§4.8.2 | 模块保持 mode 无关，差异由运行期策略承载 |
| ADR-0007 | `androidx.media3.mpvplayer` 迁出自有命名空间 | 已定稿 | 主方案 §2.5、§5 阶段 2.5 | 48 文件 / 14,962 行迁到 `com.fongmi.android.tv.player.mpv.core` |
| ADR-0008 | `Setting` 门面化 + `SettingSource` 接口化 | 已定稿 | 主方案 §2.8、§5 阶段 2.1 | 先接口吸收 628 处存量，再按包注入；禁止一次性改 628 处 |
| ADR-0009 | 禁止静态服务定位器（`App.get()` 过渡期豁免） | 已定稿 | 主方案 §2.8、§5 阶段 2.2、§6.9 | 下层包改注入 `AppContext`；`ui/**` 过渡期豁免但**不是永久许可** |

## 待办

上表 9 条 ADR 目前只有主方案里的摘要（`Context / Decision / Alternatives / Consequences / Rollback` 已在该处给出），**独立文件尚未落地**。按主方案 §6.11「前四条是本轮必须落地的核心 ADR」，后续批次在**首次触及对应决策时**落地独立文件，不集中补写（避免一次性产出大量无引用的文档）。
