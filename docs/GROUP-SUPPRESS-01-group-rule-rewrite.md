# GROUP-SUPPRESS-01：群抑制重构设计文档

- 状态：**设计阶段（待批准）**
- 创建日期：2026-11-25
- 目标版本：1.1.0
- 关联任务族：`C*`（公共能力）

---

## 一、问题与需求

### 用户诉求（原话）

> 「把群抑制的功能删掉重写」

### 对"群抑制"的界定

经代码盘点，本仓库当前**没有**名为"群抑制"的独立模块。与之最接近、且语义唯一匹配的是**站点分组规则系统（Group Rule）**：

它把站点名（如 `[豆瓣] 某某影视`、`某某影视 | 4K`）用正则提取出一个"分组名"，用于：

- 站点列表按分组归类展示
- 分组在 UI 中的排序（`SiteGroupOrderStore`）
- 搜索时按分组过滤

**确认需求歧义前，本设计以"站点分组规则"为实现对象。** 若用户所指是其他功能（如弹幕屏蔽、评论过滤），需重新界定——见第七节「待确认」。

---

## 二、现有实现盘点（重写前必须理解的资产）

### 2.1 代码规模

| 文件 | 行数 | 职责 |
|---|---:|---|
| `bean/GroupRule.java` | 301 | 规则模型：id/name/regex/enabled/source/wrapBracket，正则校验 |
| `setting/GroupRuleConfig.java` | 126 | 规则聚合：内置+接口+AI+用户四源合并、启用过滤、缓存、extract |
| `setting/GroupRuleStore.java` | 131 | 用户规则持久化（SharedPreferences）+ 禁用名单 |
| `setting/AiGroupRuleStore.java` | 138 | AI 生成规则的存储 |
| `setting/SiteNameRules.java` | 40 | 站点名生效名/分组提取/搜索匹配 |
| `setting/SiteNameStore.java` | 117 | 站点自定义名持久化 |
| `setting/SiteGroupOrderStore.java` | 104 | 分组排序持久化 |
| `service/AiGroupRuleService.java` | 624 | AI 生成分组规则（含提示词、超时、校验） |
| `ui/dialog/GroupRuleDialog.java` | 678 | 规则管理界面（增删改、预览） |
| `ui/dialog/AiGroupRulePreviewSizing.java` | 28 | AI 规则预览尺寸计算 |
| **生产代码合计** | **2,287** | |
| 测试（6 个文件） | 576 | |
| **总计** | **2,863** | |

### 2.2 四类规则来源

| 来源 | 常量 | 存储位置 | 说明 |
|---|---|---|---|
| 内置 | `SOURCE_BUILTIN` | 代码硬编码 | 4 条：方括号标签、竖线后缀、框线分隔、圆点后缀 |
| 接口 | `SOURCE_INTERFACE` | 运行时注入（来自配置接口） | `setInterfaceRules()` 外部下发 |
| AI | `SOURCE_AI` | `AiGroupRuleStore` | AI 分析站点名后生成 |
| 用户 | `SOURCE_USER` | `GroupRuleStore` | 用户手写 |

### 2.3 内置规则（当前行为，重写必须保留）

```java
BUILTIN_BRACKET = "方括号标签"  // \[([^\]]+)\]
BUILTIN_PIPE    = "竖线后缀"    // (?i)(?:[|｜])\s*([^||｜]+?)\s*$
BUILTIN_BOX     = "框线分隔"    // (?i)┆\s*([^┆]+)\s*$
BUILTIN_BULLET  = "圆点后缀"    // (?i)(?:[•·])\s*([^•·]+?)\s*$
```

都是"取第 1 个捕获组作为分组名"。

### 2.4 关键数据流

```
站点 JSON 配置
   └─> Site.name (原始名)
        └─> SiteNameRules.effectiveName(rawName, customName)
             └─> GroupRuleConfig.extract(name)
                  └─> activeRules() = entries() 里 enabled && isValid
                       └─> 依次跑每条 rule.extract(text)
                            └─> LinkedHashSet<String> groups
                                 └─> Site.getGroups() -> UI 按组展示 / SiteGroupOrderStore 排序
```

### 2.5 现有测试覆盖

| 测试 | 守护什么 |
|---|---|
| `GroupRuleTest` | 规则校验、正则提取 |
| `GroupRuleStoreLockingTest` | 并发锁 |
| `SiteNameRulesTest` | 生效名、分组、搜索 |
| `SiteGroupOrderStoreTest` | 分组排序持久化 |
| `AiGroupRuleServiceTest` | AI 生成逻辑 |
| `AiGroupRuleTimeoutTest` | AI 超时 |
| `GroupRuleDialogLayoutTest` | 弹窗布局 |
| `AiGroupRulePreviewSizingTest` | 预览尺寸 |

**注意**：其中可能有源码文本断言（`*SourceTest` 模式），重写时会红，需要连同测试一起重写。

---

## 三、现有实现的问题（为什么要重写）

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| 1 | **职责分散在 9 个文件** | 见 2.1 | 改一个行为要在 4-5 个类之间跳转 |
| 2 | **四源合并逻辑复杂** | `GroupRuleConfig.entries()` 三重循环 + 双缓存 | 新增规则来源成本高 |
| 3 | **正则无复杂度约束（除 AI 路径）** | 只有 AI 规则有 `MAX_AI_NESTING_DEPTH` 等限制 | 用户手写灾难性回溯正则会卡 UI |
| 4 | **`SiteNameStore` 与规则系统耦合** | `Site.getGroups()` → `SiteNameStore.getGroups()` → `SiteNameRules` → `GroupRuleConfig` | 调用链 4 层 |
| 5 | **AI 服务 624 行单类** | `AiGroupRuleService` | 提示词、HTTP、校验、超时全塞一起 |
| 6 | **弹窗 678 行** | `GroupRuleDialog` | 列表+编辑+预览+AI 交互全在一个类 |
| 7 | **分组名同时是多个语义的键** | `Group.name` 既是显示名又是 keep 键又是树 id（见 Group.java 注释） | 改名即破坏持久化 |

---

## 四、重写方案

### 4.1 设计目标

1. **行为等价**：现有四类规则、4 条内置规则、排序、搜索全部保留。
2. **收敛到一个领域包**：`setting/grouprule/`，对外只暴露 1 个门面。
3. **正则安全**：所有规则（含用户手写）统一走复杂度校验，防 ReDoS。
4. **可测试**：核心为纯函数，UI 与 AI 单独分层。

### 4.2 目标结构

```
app/src/main/java/com/fongmi/android/tv/grouprule/
├── GroupRules.java          // 唯一门面：extract(name) / entries() / active()
├── GroupRule.java           // 模型（迁移现有，去掉多余 setter）
├── GroupRuleSet.java        // 四源合并 + 缓存（替代 GroupRuleConfig）
├── RuleMatcher.java         // 正则执行 + 安全校验（防 ReDoS）
├── RuleRepository.java      // 统一持久化（替代 GroupRuleStore + AiGroupRuleStore）
├── RuleSource.java          // enum: BUILTIN/INTERFACE/AI/USER
├── BuiltinRules.java        // 4 条内置规则（从 GroupRuleConfig 抽出）
└── SiteNameService.java     // 站点名/分组/搜索（合并 SiteNameRules + SiteNameStore）
```

AI 与 UI 分离：

```
service/AiGroupRuleService.java → 保留但瘦身（只留 HTTP + 提示词）
ui/dialog/GroupRuleDialog.java  → 拆成 GroupRuleListAdapter + GroupRuleEditor
```

### 4.3 兼容策略

- **对外 API 保持**：`Site.getGroups()`、`SiteNameStore.getGroups()` 签名不变，内部改调 `GroupRules.extract()`。
- **持久化键不变**：`user_group_rules`、`disabled_group_rule_ids`、AI 规则键、`site_group_order` 全部沿用，避免用户升级丢配置。
- **内置规则 id 不变**：`builtin_bracket_tag` 等 4 个 id 必须原样保留，否则用户的"禁用某内置规则"状态失效。

### 4.4 分阶段实施

| 阶段 | 内容 | 验收 |
|---|---|---|
| **G1** | 建 `grouprule/` 包骨架 + 迁移 `GroupRule` 模型 + `BuiltinRules` | 现有 `GroupRuleTest` 全绿 |
| **G2** | `RuleMatcher`（含 ReDoS 校验）+ `RuleRepository` + `GroupRuleSet` | `GroupRuleStoreLockingTest`、`SiteGroupOrderStoreTest` 全绿 |
| **G3** | `GroupRules` 门面替换所有调用点，删除旧类 | `SiteNameRulesTest` 全绿，全局 `grep` 无旧类引用 |
| **G4** | `SiteNameService` 合并，`Site` 调用链从 4 层降到 2 层 | `Site.getGroups()` 行为不变 |
| **G5** | AI 服务瘦身 + 弹窗拆分 | UI 测试全绿，AI 测试全绿 |
| **G6** | 删除旧文件 + 更新测试 | 全量测试通过，行数对比 |

每阶段独立提交 + recovery tag。

### 4.5 预期收益

| 指标 | 现状 | 目标 |
|---|---:|---:|
| 生产代码行数 | 2,287 | ~1,500（-34%） |
| 涉及文件数 | 9 | 8（但职责单一） |
| 调用链深度（Site→分组） | 4 层 | 2 层 |
| 用户规则 ReDoS 防护 | ❌ 无 | ✅ 有 |
| 最大单文件 | 678 行 | ≤ 300 行 |

---

## 五、风险与回滚

| 风险 | 等级 | 缓解 |
|---|---|---|
| 用户配置键变更导致升级丢数据 | **高** | 所有持久化键与内置 id 保持不变，写迁移测试 |
| 分组结果与原实现不一致 | **高** | G1-G3 每步跑现有测试；保留"新旧实现并行比对"的临时测试 |
| ReDoS 校验过严误杀合法规则 | 中 | 只拦截已知危险模式（嵌套量词、超长输入），不限制普通正则 |
| AI 规则生成回归 | 中 | G5 前先固化 AI 服务的输入输出特征测试 |
| 源码文本断言测试大面积变红 | 中 | 已知问题，随实现一起重写断言为行为测试 |

**回滚**：每阶段一个 recovery tag，`git reset --hard <tag>` 可回到任一阶段。

---

## 六、验证计划

```bash
# 每阶段
bash gradlew :app:testMobileArm64_v8aDebugUnitTest --tests 'com.fongmi.android.tv.grouprule.*'
bash gradlew :app:testMobileArm64_v8aDebugUnitTest --tests '*GroupRule*' --tests '*SiteName*'

# 最终
bash gradlew :app:testMobileArm64_v8aDebugUnitTest
bash gradlew :app:testLeanbackArm64_v8aDebugUnitTest
bash gradlew :app:assembleMobileArm64_v8aRelease
```

行为等价验证：用真实站点 json 跑新旧实现，比对 `extract()` 输出集合完全一致。

---

## 七、待确认（阻塞项）

**"群抑制"到底指哪个功能？** 现有代码里语义最接近的是"站点分组规则"，但名称不匹配。可能的情况：

1. **站点分组规则**（本设计假设）——把站点按规则归类。
2. **弹幕屏蔽词/弹幕过滤**——若指这个，实现对象完全不同。
3. **某个已被删除的功能**——需要用户提供旧版截图或描述。

**在用户确认前，不进入 G1 实施。** 若确认是分组规则，本设计可直接作为实施依据。
