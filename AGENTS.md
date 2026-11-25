<!-- AUTO-GENERATED: 本文件由 .githooks/pre-commit 从 CLAUDE.md 自动镜像生成，不要手动编辑；请改 CLAUDE.md -->

# WebHTV 项目协作指南

> 本文件对 Claude Code 等 AI 编程助手和人类贡献者同时生效，也是其他 Agent（如 Codex）读取的 `AGENTS.md` 的唯一来源：**只编辑本文件**。`AGENTS.md` 由 Git `pre-commit` 钩子在每次提交时自动从本文件镜像生成，直接改 `AGENTS.md` 的内容会在下一次提交时被覆盖。镜像脚本是 `.githooks/pre-commit`；因为 Git 不会把 `.git/hooks` 目录提交进仓库，新 clone 后需要手动执行一次：
>
> ```bash
> git config core.hooksPath .githooks
> ```

## 项目简介

WebHomeTV（WebHTV）是基于 [FongMi/TV](https://github.com/FongMi/TV) 和 CatVod 爬虫生态二次开发的 Android 影音应用（包名 `com.silent.android.webhtv`，Java 包 `com.fongmi.android.tv`）。保留了原有点播、直播、Spider 爬虫、解析、投屏、本地 HTTP 服务等能力，重点增强了 WebHome 自定义首页、App Native SDK、局域网管理页、远程托管、观影记录同步和 TMDB/Nostr 推荐首页。完整的中文功能说明见 `README.md`。

## 构建

不依赖任何 IDE，全部通过 Gradle Wrapper 命令行完成。需要 JDK 21、Python 3.10（Chaquopy 固定版本）、Android SDK Platform 37 / Build-Tools 37.0.0，以及根目录下写有 `sdk.dir=...` 的 `local.properties`。NDK 只有在重建 MPV/IJK/JNI 原生库时才需要（见下文）；普通打包直接复用仓库内已提交的预编译 `.so`。

```bash
# debug（本地最快的验证方式）
bash gradlew :app:assembleMobileArm64_v8aDebug
bash gradlew :app:assembleLeanbackArm64_v8aDebug

# release（完整 R8/资源压缩）；追加 -PfastRelease=true 可得到接近 debug 速度的临时 release 包
bash gradlew :app:assembleMobileArm64_v8aRelease
bash gradlew :app:assembleMobileArm64_v8aRelease -PfastRelease=true
```

两个 productFlavor 维度组合成具体的任务名：`mode`（`leanback` = 电视端 UI，`mobile` = 手机/平板 UI）× `abi`（`arm64_v8a`、`armeabi_v7a`）。必须指定具体的 flavor+ABI 组合（`:app:assemble<Mode><Abi><Debug|Release>`），没有裸的 `assembleDebug` 任务。

debug 包输出在 `app/build/outputs/apk/<flavor>/debug/`；release 包额外会被复制到 `Release/apk/`。

## 测试

单元测试分别放在 `app/src/test`（公共）、`app/src/testLeanback`、`app/src/testMobile`（按 flavor 区分），包结构与 `com.fongmi.android.tv.*` 一一对应。必须指定具体 flavor+ABI 变体运行：

```bash
bash gradlew :app:testMobileArm64_v8aDebugUnitTest
bash gradlew :app:testLeanbackArm64_v8aDebugUnitTest

# 只跑单个测试类或某个包下的用例
bash gradlew :app:testMobileArm64_v8aDebugUnitTest --tests 'com.fongmi.android.tv.player.danmaku.*'
```

Robolectric（`testLeanbackImplementation 'org.robolectric:robolectric:4.16'`）支撑依赖 Android 框架的测试；MockWebServer 只在 `testImplementation` 范围（不会打进正式 APK），用于 WebSocket/弹幕和网络层测试。

其他验证入口（详见 `README.md` “常见构建失败” 及原生相关章节、`scripts/` 目录）：
- `bash scripts/verify_mpv_native_assets.sh [--require-elf]` —— 只校验仓库内已提交的 MPV/FFmpeg/libplacebo assets 是否与 lock 文件一致，不会重新编译。
- `scripts/build_mpv_native.sh`、`scripts/build_mpv_player_jni.sh`、`scripts/build_ijk_native.sh`、`scripts/build_media_deps.sh` —— 原生重建脚本。只有当任务范围明确包含 native/JNI/Media3 fork 改动时才运行，并严格遵循对应 lock 文件（`third_party/mpv-native-lock.json`、`third_party/ijk-native-lock.json`、`third_party/media-lock.json`）。

## 架构

### Gradle 模块（见 `settings.gradle`）

- `app` —— Android 主应用（两个 flavor，见上文）。
- `catvod`（`com.github.catvod.crawler`）—— CatVod 抽象层：`Spider` 接口、`Site`/`Result` 数据类、OkHttp/网络/代理工具。所有播放源运行时最终都实现或桥接到 `Spider`。
- `quickjs` —— 基于 QuickJS 的 JavaScript Spider 运行时（依赖 `catvod`）。
- `chaquo` —— 基于 Chaquopy 的 Python Spider 运行时（固定 Python 3.10；构建期 Python 可通过 `chaquopyBuildPython` 单独配置）。
- `nodejs` —— 为插件提供 Node.js 运行时支持；`libnode.so` 是运行时下载后用 `dlopen`/`dlsym` 载入的，编译期不链接。其极小的原生 shim 静态链接所需的 C++ 运行时符号，目的是避免抢占 `libc++_shared.so` 的 soname（会导致 NDK 29 版本被挤掉，进而让 `libmpv.so` 因缺符号而加载失败）——修改该模块的 `ANDROID_STL` 前必须先重读 `nodejs/build.gradle` 里的注释。

### Spider 插件体系

站点 “Spider” 插件可以是 Java/JAR、QuickJS JavaScript、Python，或 CatSpider HTTP 协议，最终都归一到 `com.github.catvod.crawler.Spider` 这个 Java 接口（`init`、`homeContent`、`categoryContent`、`detailContent`、`searchContent`、`playerContent`、`liveContent`、`proxy`、`action`、`destroy`）。`Site` 反序列化后由 Loader 创建对应的 Spider 运行时，`init(Context, String ext)` 接收站点的 `ext` 配置（远程地址会先拉取文本），随后 UI 依次调用首页/分类/详情/搜索/播放，`proxy` 用于换源和本地代理。每种运行时完整的方法/生命周期映射见 `docs/integration/spider.md`；其余 `docs/integration/*.md` 覆盖总配置、直播/EPG、解析器、字幕、弹幕、播放结果、本地代理、点播源字段等。

### 播放引擎

`app/src/main/java/com/fongmi/android/tv/player/` 下共存三套按站点/设备选择的播放后端：Media3/Exo（`PlayerManager`，依赖 `third_party/maven` 内本地构建的 FongMi fork 版 Media3）、MPV（`is.xyz.mpv.MPVLib` JNI，原生库在 `app/src/*_v8a/assets/mpv-libs/`）、IJKPlayer（`player/engine/Ijk*`、`player/ijk/`，预编译 `.so` 在 `app/src/main/jniLibs/`）。另一个同名相近的 `playback/` 包是播放记录/进度/Webhook/远程同步的领域模型（`PlaybackRecord`、`PlaybackRemoteSyncer`、`PlaybackWebhookSender` 等），不是播放引擎本身。原生播放库只能通过上述锁定脚本重建，绝不能手改已提交的 `.so`/assets。

### `app/src/main/java/com/fongmi/android/tv/` 下其他关键包

- `api/` —— `SiteApi`/`LiveApi`/`CatSource`/`CatAction`：已配置站点/解析与 Spider 运行时之间的粘合层。
- `plugin/` —— WebHome “App Native SDK” 插件宿主：manifest/bundle 加载、能力注册表、运行时工厂（`QuickJsPluginRuntime`）、审计日志，以及暴露给被注入网页的悬浮窗/UI 呈现层。
- `server/` —— 内置的 NanoHTTPD 服务（`Server`、`Nano`、`process/*`），提供局域网管理页、VOD/Spider HTTP API、播放历史/进度 API，以及 `proxy/*`（用于播放流和资源代理的多线程分段代理）。
- `web/` —— WebView 侧桥接与 WebHome/WebTheme 体系：`HomeWebBridge`/`HomeWebController` 负责自定义首页，`WebTheme*` 负责 WebHome V2 manifest/能力/会话契约（对照 `webhome-devkit/schemas/webtheme-v2.schema.json` 校验）。
- `ui/`、`setting/` —— Activity/Fragment/Presenter，进一步按下文的 `leanback`/`mobile` flavor 源集拆分。

### flavor 拆分（`leanback` = 电视端，`mobile` = 手机/平板端）

`app/src/main/` 是公共代码；`app/src/leanback/` 与 mobile 专属等价物（以及 `app/src/debug`、`app/src/arm64_v8a`、`app/src/armeabi_v7a` 存放 ABI 专属 MPV assets）按 Android 源集合并规则叠加。`leanback` 携带电视专属资源（遥控器友好的布局/drawable/动画/焦点态、Leanback 库、autosize）及独立的 `res/values-zh-rCN`/`values-zh-rTW`；`mobile` 额外引入 `biometric` 和自己的 zxing 扫码 flavor。各自的单元测试放在 `app/src/testLeanback` 和 `app/src/testMobile`——改动电视端或手机端专属行为时，要在对应源集补充/运行测试。

### `webhome-devkit/`

一个自包含的开发套件（文档、首页/扩展示例、模板、Schema 校验器、可安装的 AI skills），用于开发 WebHome 首页和注入式站点扩展，同时面向人类开发者和 AI 助手（给定目标 URL 产出扩展脚本）。它是文档/工具集，不属于 App 运行时的 `ext` 配置。完整 Native SDK API 见 `webhome-devkit/README.md` 与 `webhome-devkit/docs/应用完整开发文档.md`。

### `.codex/`

`.codex/scripts/task_guard.sh` 实现下文“任务护栏”要求的 `start`/`check`/`finish`/`abort` 流程。`.codex/skills/upstream-integration-governor/` 是 FFmpeg/Media3/Exo/MPV/mpv-android/libplacebo/JNI/原生二进制相关工作的权威 Skill（见下文“上游与播放器依赖工作”）；`webhome-devkit/skills/upstream-integration-governor/` 只是分发镜像，不是额外的指令来源——改动权威版本后必须在同一次治理维护任务里同步镜像并校验字节级一致。

### 原生/播放相关的依赖锁定

`third_party/maven` 内有本地构建的 `androidx.media3:*:1.11.0-alpha01-fongmi`（FongMi fork），`app/build.gradle` 的 `resolutionStrategy` 会强制所有传递依赖都使用这个版本。`third_party/*-lock.json`（`mpv-native-lock.json`、`ijk-native-lock.json`、`media-lock.json`、`fongmi-repositories-lock.json`）是每一个上游 commit/ABI/工具链锁定值的唯一真相来源；改动它们的治理流程见 `README.md` “播放层依赖”“上游基线” 章节和下文“上游与播放器依赖工作”。

## 任务护栏（原 AGENTS.md 治理合约）

以下规则对本仓库的所有改动生效，目的是让工作保持正确、范围收紧、可回滚、够快。子目录里的 `AGENTS.md`/说明文件可以补充路径专属规则，但不能削弱这里的安全、范围或回滚要求。

### 1. 先划定一个最小任务圈

动手改之前，先说清楚：一句话的完成标准、允许改动的路径、需要保护的既有未提交改动（dirty paths）、当前本地时间和时区、一个现实的总耗时预估及预计完成时间，以及最省成本但能定论的验证方式。多阶段任务要给每个阶段各自的简短预估。把这些预估当作执行目标而不是硬性门槛：预估到点或明显超出时，停掉可选工作，说明原因，转向最窄的收尾路径或换一条明显更短的路线；不要让过时的预估变成反复检查、无边界调研或烂尾交接的理由。

预估的是**当前这个 AI Agent 在本工作区**实际花费的墙上时钟时间，不是人类工程师或团队需要的时间。预估要基于仓库现状、可用工具、热缓存、ABI/构建范围、设备可用性，以及不可避免的网络/构建/等待用户响应的时间；这些阶段明显不同时就分开估，并给出预计完成的本地时间。除非用户明确要求，否则不要给“人/天”这类团队排期式的估算。

#### 治理维护快速通道

当任务只涉及编辑本文件、`.codex/skills/**`、`.codex/scripts/**` 或它们的评审文档时：

- 只依据用户观察到的失败现象和当前 diff 诊断。除非用户明确要求，或有一个具体的、会卡住改动的未知事实，否则不要上网搜索、重读通用最佳实践资料、做前瞻性测试、新建临时仓库或扩大方法论范围。
- 选定一个根因，打一个有边界的补丁，然后只跑一次覆盖改动产物的组合验证。通过就立即停止并交接，不要做安心检查。
- 不要默认在每一层都重复同一条规则。决策规则放在本文件，领域细节放在对应 Skill，确定性行为放在脚本里。只有在另一层的行为会与修复相矛盾时才去改它。
- 维护护栏机制本身或其说明文件时不需要走任务护栏流程。保留无关的未提交改动，除非用户明确要求提交/打标签，或这次维护本身已经是一个独立的、任务归属明确的改动，否则不要提交/打标签。
- 正常的工具调用序列上限：一次排查、一次打补丁、一次组合验证。第四次调用需要验证失败或遇到具体阻塞，并且要先说明原因再执行。

- 一个小 bug 默认归为 `quick-fix`（快速修复）档。不要仅仅因为“还能继续深挖”就把它升级成架构工作、大范围调研或原生工作。
- 档位名称只描述风险和工作方式，不代表耗时、改动文件数、循环次数、检查点或重新规划的硬性门槛。
- 通过去掉冗余探索、重复命令、超范围预案和低价值验证来压缩总耗时；但绝不能靠砍掉必要行为、风险驱动的验证、回滚能力或既定完成目标来换速度。
- 在用户明确给出时间限制时：不要重复一次已经成功或已有结论的检查，也不要在现有证据已足够决定方案后继续扩大调研。重试需要有相关的改动或一个尚无结论的结果作支撑；扩大调研需要指出一个具体的、会改变决策的未解事实。
- 用户给出时间预算或截止时间时，把它当作本轮的执行目标，并大致预留最后四分之一的时间给验证、记录、提交、打标签和交接。选一条证据支持、最短的路线，每个代价高的构建/测试最多跑一次（除非有相关改动或结果不确定需要重试），并在预算耗尽前停掉可选的调研或清理工作。尽量把一个批准单元的代码、lock、产物、任务文档改动都放在同一个护栏会话、同一次提交里完成；只有当存在提交后才能拿到的 ID/标签需要补记时，才允许追加一次只改文档的收尾提交，且不追加任何构建或调研。这条路由规则永远不会降低正确性、回滚或完成度要求。
- 先给命令失败分类，再决定是否要升级求助：仓库内文件权限或调用方式错误，用一次正确的范围内调用就能修好（例如改用 `bash ./gradlew`）；沙箱/网络/权限类错误才是真正需要升级求助的情形。不要在分类错误的失败上浪费第二次尝试或审批回合。
- 不经用户明确批准，不扩大既定行为或路径范围。确实很大的工作可以拆成若干独立可用的单元，但要保持原定完成目标不变。
- 除上述治理维护快速通道外，代码改动前先执行 `bash .codex/scripts/task_guard.sh start --id <task-id> --mode <lane> --scope <path>...`。`check` 是可选的只读安全审计，不要求每个循环都跑；`finish` 会自己做最终的安全检查。如果一个会话没有提交就被中断（或状态损坏），`abort` 会把那次状态归档，这样后续的 `start` 不会被卡住；它绝不会丢弃工作区改动，并且会拒绝对已经提交过的会话执行（那种情况必须走 `finish` 才能拿到恢复标签）。
- 超时只能限定某一条可能卡住的命令，不能当作整个任务的硬性时限。遇到超时要先诊断原因，再换一条更安全、更窄或可恢复的命令继续。

### 2. 范围默认是封闭的

- 只改完成这句话目标所必需的声明路径和行为。不做无关的重构、清理、格式化扫荡、依赖升级、生成文件的无谓改动或超前的抽象设计。
- 一个无关的失败测试、警告或附近的缺陷不属于本次任务范围。报告它即可；除非它会阻塞当前要求的结果并且用户批准扩大范围，否则不要去修。
- 保留任务开始前就存在的所有未提交改动。除非用户明确把这部分工作也交给你并且已经安全隔离，否则绝不把任务开始前就脏着的路径纳入任务范围或任务提交。
- 如果提议的修复会跨越一个新模块、改变公开行为/API，或改变依赖/二进制的归属，就把它收窄到最小可用单元。只有当这个最小单元本身就会扩大已授权的行为或路径范围时，才需要去问用户。

### 3. 搜索和诊断要配得上它的成本

- 遇到 bug 按这个顺序走：复现或建立证据 -> 检查确切的代码路径和调用方 -> 形成一个可证伪的根因假设 -> 做最小的修复 -> 跑一次针对性的验证。
- 先用精确的符号/报错信息在本地搜索。上网查、翻上游历史、查论文、大范围 issue 搜索、通读整个仓库考古，这些是遇到瓶颈才升级用的手段，不是 `quick-fix` 档的默认动作。
- 只有当现有证据不足以决定下一步时才扩大搜索范围。快速修复最多用两次不同的搜索措辞，一个实质性的上游问题最多三次；优先看一手的代码/文档/issue，而不是重复性的帖子。
- 一条命令的完整输出只抓取一次，之后对这份已保存的结果做过滤/阅读。不要为了换个过滤条件就重跑同一个测试或构建。
- 每个最终的语法/lint/测试检查只跑一次。只有在相关改动之后，或者第一次结果没有结论时才重跑；不要为了“安心”而重复检查一个没有变化、已经成功过的结果。
- 同一个假设失败两次后就放弃它，换一条实质不同的路径。没有新证据支撑的重复尝试是被禁止的；但任务本身仍然必须完成。

### 4. 验证按风险大小来定，追求最小必要

- 从最省成本、但足以证伪改动的确定性检查开始：针对性的单元测试、编译目标、静态检查，或一个有代表性的设备场景。
- 一次有结论的通过就够了，除非改动涉及抗抖动/并发/性能波动/原生生命周期/ABI/设备专属行为这些类别。
- 不要跑完整的 Gradle 矩阵、全部 ABI、原生重建、大范围设备套件、fuzzing 或无关测试，除非改动的契约本身要求，或用户要求。
- 不要放水让一个失败的门槛通过。先把失败分类成回归、环境问题还是过时的预期；只有当修复它本身就在声明的任务范围内时，才去扩大工作范围修它。
- 质量底线：不能为了赶时间而牺牲既有行为、正确性、安全性、兼容性、明显的性能或任务完成度。时间压力只能用来去掉冗余工作，绝不能用来授权一个未经验证的捷径。

### 5. 上下文恢复

- 只有在任务确实可能跨越会话/压缩边界、即将执行有风险的长时间操作，或正在切换功能阶段/仓库时，才创建持久检查点。不要因为耗时、循环次数或改动文件数就强制要求它。
- 一个检查点要记录：目标、档位/范围、分支/HEAD、受保护的未提交路径、已完成的证据、已改动文件、验证方式/结果、未解决的风险、回滚锚点，以及恰好一个下一步动作。
- 长期任务用 `apply_patch` 更新对应的跟踪文档；任务护栏机制本身不负责也不强制推进检查点。
- 对预期会跨会话/压缩存活的任务，建一份任务专属的 `docs/<task-id>-<slug>.md`。在文件开头或结尾保留一个简短的“恢复锚点（Recovery anchor）”，包含目标和验收标准、计划状态、当前文件/符号、已完成动作及结果、尚未验证的工作区改动、未解决风险，以及恰好一个下一步动作。
- 状态发生实质变化时，或即将进行可能触发压缩/长时间操作之前，更新恢复锚点。对话里的计划是临时的，任务文档才是持久的执行状态。
- 压缩或恢复会话后，按这个顺序恢复上下文：工作区和 Git 证据（`git status`、分支/HEAD、范围内 diff）-> 最新的恢复锚点/任务文档 -> 压缩摘要 -> 更早的对话计划。核对不一致之处，并保留现有尚未验证的改动。
- 一旦恢复核对完成，就执行文档里记录的那一个下一步动作。不要重新规划、重复已完成的全仓库搜索、重读已经看过的代码路径，或丢弃部分改动，除非工作区或任务文档证明它们已经失效。绝不要凭记忆重建精确的哈希或决策内容。

### 6. 提交和恢复标签是代码完成的一部分

- 一次任务护栏会话对应一次原子性的逻辑改动。如果任务还需要另一次逻辑提交，先完成当前这个单元，再开一个新的护栏会话。
- 一次代码改动在以下条件都满足前都不算完成：记录了针对性的验证结果、任务归属的文件已经原子性提交、并且这次提交有唯一的本地带注释恢复标签。
- **明确收尾快速通道**：当用户确认测试行为可以接受（比如“没问题”“通过”等）并要求提交或打标签时，这个确认就关闭了该场景下可选的验证环节。此时应立即停止；不要再抓更多日志/截图，不要跑相邻媒体/设备场景，不要再起一次构建/测试，不要查上游，不要做安心检查,也不要在收尾前扩写文档。
- 收到明确收尾请求后，下一次工具调用就必须直接执行收尾，除非有一个具体的、尚不明确的安全事实让这不可能。正常序列最多是：仅在需要记录已知结果时对现有任务文档打一个最小补丁，然后调用一次 `task_guard.sh finish`（它会完成提交和打标签），然后汇报提交和标签。不要再单独跑一次护栏 `check`、状态/diff 复查或标签校验，因为 `finish` 本身已经强制执行范围检查和打标签。如果改动已经提交过了，就直接创建用户要求的带注释标签，不要重新打开文档流程。
- 把这当作一个对延迟敏感的执行目标：通常应在 60 秒内完成本地提交/打标签，并在第一次可能的工具往返里就启动打标签相关的命令。只有命令本身直接失败或遇到真正的安全阻塞，才允许超出这个目标；此时只报告并修复那一个直接原因。用户确认从不授权跳过一个真正失败的必需检查，但在用户已经接受观察到的行为之后，一个缺失的可选或相邻测试不构成阻塞。
- 如果同一条消息还授权了推送，收尾后只推送指定/当前分支和新建的标签。除非推送本身报告冲突或被拒绝，否则不要先去 fetch、比较或重新校验。
- 用 `bash .codex/scripts/task_guard.sh finish --verified <evidence> --commit-message <message>` 收尾。该脚本只会把任务归属的路径加入 stage，并创建 `recovery/<task-id>/<timestamp>`；绝不能手动把无关的未提交改动加入 stage。
- 提交成功后，立即用一条本地、非交互式的 `git tag -a` 命令创建对应的恢复标签，并关闭标签签名。打标签阶段通常应在 5 秒内完成；提交和打标签之间不要插入构建、测试、搜索、网络调用、重复的 diff 复查或多余的标签检查。
- 把一次成功的打标签命令视为已经足够。如果失败，先完整记录一次错误信息，修复其直接原因后再重试，且只有命令本身发生实质变化才重试；不要在命令不变的情况下循环重试。
- 如果验证失败、改动范围与既有未提交工作重叠，或无法形成一个安全的原子提交，就不要提交/打标签。必要时记录持久状态，并汇报具体卡在哪里。
- 仅做评估不等于获得生产改动的授权。标签只能指向已提交且已验证的状态。未经明确授权，绝不推送提交/标签、移动已发布的标签、改写历史，或发布产物。

### 7. 最佳实践设计调研

下面这条强制性的设计调研门槛适用于全仓库范围内的每一项重大新功能、优化、架构、兼容性、安全、依赖或跨模块需求，以及每一个上游合并候选项。存在对应领域 Skill 时要使用它。简单的文本/配置改动，以及方案已经确定、范围局限的小修复，不受此要求约束，除非用户明确要求调研。

### 8. 上游与播放器依赖工作

涉及 FFmpeg、media/Media3/nextlib、Exo、mpv、mpv-android、libplacebo、JNI、原生二进制、lock 文件、补丁或二进制打包的工作，必须阅读并遵循 `.codex/skills/upstream-integration-governor/SKILL.md`，且只使用它为当前档位标注需要的参考资料。

`.codex/skills/upstream-integration-governor/` 是本仓库的运行期权威副本。`webhome-devkit/skills/upstream-integration-governor/` 是给其他开发者使用的参考/分发镜像，不是额外的指令权威或加载路径。权威 Skill 发生变化时，必须在同一次治理维护任务里同步更新镜像，并校验镜像文件与权威版本逐字节一致；绝不能让两份拷贝各自演化。

#### 新会话下，上游合并计划的路由方式

- 用户不需要粘贴完整的启动提示词。把 “下一个任务”“继续上游播放器依赖合并计划”“梳理新的上游更新” 等简短请求，视为已经足够触发上游 Skill。本仓库该计划预期所在分支是 `fongmi-sync`；动手前先核实实际的分支/HEAD，并保留所有既有未提交改动。
- 除非用户最新一条消息明确批准实施，第一次回复必须是只读的评估性回复。完整阅读 `README.md`、本文件、当前有效的 `docs/upstream-player-dependency-merge-assessment-*.md`，以及和候选项直接相关的任务文档。结合评估台账、Git 历史和当前代码，按 `Exo -> MPV -> common` 的顺序选出下一个真正尚未完成、尚未实施的任务。
- 提出工作前，先判断是否已经有某次提交实现过、部分覆盖过、取代过，或使其已经没有意义。如果已经覆盖或已无实际产品价值，直接建议“忽略”，不要把它重新包装成一项新的实施工作。
- 用通俗语言说明这项改动对用户可见的播放能力影响。要包含所有相关仓库和完整 40 位 commit ID、跨仓库关系、收益、缺点与风险、对现有行为的影响、兼容性、性能和包体积、是否符合最佳实践、WebHTV 需要做的适配、明确的 `实施`/`暂缓`/`忽略` 建议，以及最小的分阶段实施与验证计划。
- 第一次回复使用这个结构，然后停下来等待明确批准：`任务编号和名称`、`所属分类`、`要实现的实际能力`、`当前项目已有实现`、`涉及仓库及完整 commit ID`、`收益`、`缺点与风险`、`与现有功能的关系`、`建议`、`最小实施步骤`、`预计需要的验证`。这次选型回复期间不要改动代码、lock、补丁、产物或运行时行为。
- 后续一条明确的 “开始实施” 只授权当前这一个无歧义的推荐任务。把所有既有行为、兼容性和明显性能都当作验收契约：实施不能明知会造成直接或间接回归，也不能降低现有性能。必要时可以调整或拒绝上游方案，用与风险匹配的最小验证范围，并且在还存在明显回归风险时不要宣称完成。

- 评估和实施是两个独立的授权层级。要列出范围内每一个上游 commit 的完整 40 位 ID 及其处置方式；绝不能实施一个尚未批准的阶段。
- 把相关的跨仓库行为归并成独立可回滚的 `Exo`、`MPV` 或 `common` 阶段。保持 `Exo -> MPV` 的决策/实施顺序。
- 从 `docs/upstream-player-dependency-merge-assessment-2026-08-20.md` 继续当前有效的评估；除非上游源头或实质性证据发生变化，否则不要重做已完成的分析。
- 创建或更新任务文档前，先把每一个可执行阶段落到评估索引里记录的稳定任务 ID。沿用既有的任务族：Exo 用 `E*`/`E*-*`，Exo 性能用 `E-SP*`，MPV 用 `P*`/`P*-*`，公共工作用 `C*`/`C*-*`。绝不能重新编号、回收旧号，或用一个泛化序号替换已分配的 ID。
- 一个已启动的上游任务只对应一份固定命名为 `docs/<TASK-ID>-<slug>.md` 的持久文件。这份文件承载该任务的最佳实践调研、本地代码评审、决策、实施历史、反复修复记录、验证、提交/标签、回滚方式、当前状态和下一步动作。后续工作追加到这份文件里，不要为同一个任务另建 `plan`、`assessment`、`implementation`、`fix` 或按日期命名的并行文件。
- 评估文档是唯一的例外：它始终是跨任务索引和完整的上游 commit 台账。它会链接到每个活跃任务各自的专属文档，但不会取代那份文档里的实施记录。

#### 强制性设计调研门槛

在为任何上游候选项或重大新需求改动代码、lock、构建脚本、补丁或运行时行为之前，必须完成一次可直接支撑决策的最佳实践评审。“重大需求”包括新的用户可见能力，或对架构、性能、播放行为、起播/跳转、解码器或渲染器选择、网络/代理处理、兼容性、原生/二进制打包、公开 API、安全、数据归属或跨模块契约的改动。

- 实施前,先创建或更新该任务专属的 `docs/<TASK-ID>-<slug>.md`,并在评估索引中链接它。它的最佳实践章节就是持久计划;不要另建第二份 `plans/` 文档,也不要把一次聊天回复当作记录。
- 搜索每一类适用的证据:准确的上游源码/commit/测试;官方规范和平台/项目文档;上游 PR、issue、回退和维护者讨论;成熟的相关项目代码和测试;以及相关的论文、技术文章、博客、benchmark 或实战报告。如果某一类证据确实不适用,要在计划里写明原因,而不是悄悄跳过。
- 要读实际的源码,不能只看搜索结果摘要。记录 URL 或仓库路径、revision/commit、访问日期、证据等级、支撑的结论、对 WebHTV 的适用性、注意事项,以及对决策的影响。需要联网时使用已配置的代理;如果拿不到所需的调研资料,就把这个阶段标记为未完成,不要宣称已经得出最佳实践结论。
- 在具体的文件和符号位置评审当前 WebHTV 的实现和调用/数据流。选定方案前先确认是否已有等价或部分实现、本地的防护措施、调用方、构建可达性,以及后续的本地修复。
- 计划至少要比较:`不改动`、原样的上游方案、以及一个针对 WebHTV 收窄过的适配方案(相关时再加其他可信的备选方案)。明确决定是采纳、修正、补充还是拒绝这个上游提案,并说明在正确性、兼容性、性能、质量、生命周期、ABI、安全、来源可追溯性、可维护性、验证、发布和回滚方面的权衡。
- 在计划包含明确建议、验收标准和回滚路径,并且用户明确批准该阶段之前,不要开始实施。调研要聚焦在一个决策相关的问题上:当更多资料已经不可能改变设计或决策时就停下来,把未解决的缺口记录下来,而不是无边界地继续翻找。

### 9. 执行边界

本文件是一层指令约定,不是安全边界。任务护栏机制被调用时,只强制检查声明的路径、受保护的既有未提交文件、分支/HEAD 稳定性、任务提交的原子性,以及恢复标签。它不会强制检查耗时、循环次数、改动文件数量上限、检查点或状态归档。Git 钩子不是主要的强制机制,因为普通 clone 不会可靠地启用被跟踪的钩子,客户端钩子也可以被绕过。组织级别的强制检查应该放在 CI 里。
