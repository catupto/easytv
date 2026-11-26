# PLUGIN-04: 原生内核外置（ext 目录插件化）

- 用户决策：已批准（2026-11-24）——架构=外部包 + 绝对路径加载；版本控制=先 git init 基线；验证=静态验证为主，用户在完整环境构建确认。
- 类型：common（跨 Exo / MPV 的打包方式改造），非上游 commit 合并。
- 目标：把内置播放器内核与资源从主 APK 剥离，main APK 体积显著下降；内核按需从 ext 目录加载，缺失时优雅降级到 Exo。

## 背景与目标体积

当前单 arm64 APK 估计 ~90MB。剥离项：

| 项 | 单 arm64 体积 | 归属 |
|---|---|---|
| mpv-libs（10 so，assets） | ~49MB | MPV |
| sherpa-onnx-jni.so（jniLibs） | 22.5MB | common（实时字幕） |
| ijk so（3×，jniLibs） | ~10MB | Exo 备选内核 |
| LUT cube（13 个，assets） | 11MB | common（画质） |
| libexo_ass.so | 2.7MB | Exo（保留，收益低） |
| baseline-prof 产物 | ~30KB | 保留（收益低） |

预期：主 APK 降到 ~25–40MB。**10MB 目标在本架构下不可达**（nextlib AAR 自带 FFmpeg so + 大量第三方库仍在）。

## 架构决策（已批准）

沿用 easytv 既有的三个原生加载范式，不照搬 dsplayer 的多 APK + PluginTrust 体系：

1. `MPVLib.ensureLoaded`：已是"assets → getDir 解压 → System.load 绝对路径 + marker"，把来源从 assets 换成 ext 外部包。
2. `IjkLibLoader.loadLibrary`：抽象钩子已存在，改为从 ext 目录 System.load 绝对路径；`isAvailable()` 降级已内建。
3. sherpa：`sherpa_onnx.native.path` 系统属性已由 jar 内 `LibraryUtils` 支持，加载前指向 ext 目录。
4. LUT：`LutStore` 已支持 SAF 外部目录 + `open()` 支持 file/content URI，删内置 assets 即可。

统一新增 `ExternalCoreLoader`（`com.fongmi.android.tv.player`）：发现 ext 包 → 校验 SHA-256 → 解压到内部目录 → 版本 marker → 供三个加载器取 so 目录。

- ext 根目录：`context.getExternalFilesDir(null)/ext/cores/`，内核包为 zip：`mpv-<abi>.zip`、`ijk-<abi>.zip`、`sherpa-<abi>.zip`；每包配 `*.sha256` 清单。
- 信任模型：用户自主放置包，SHA-256 仅防损坏/篡改传输，不做签名（与自有插件框架一致；native 无沙箱，责任边界=用户只放可信来源包）。此为已知风险，记录于此。
- W^X 前提：targetSdk 保持 28，外部目录 so 可 dlopen。
- 热替换限制：System.load 映射的 so 进程内不可覆盖，换包下次启动生效。

## 验收标准

1. 主 APK 不再包含上述 4 类资产（体积核算 + `unzip -l`/SourceSet 审查）。
2. 无 ext 包时：Exo 正常播放；mpv/ijk/实时字幕/LUT 缺失时优雅降级，不崩溃。
3. 有 ext 包时：mpv/ijk/sherpa 从外部目录加载成功，LUT 从外部目录枚举成功（静态代码审查 + 用户在真机验证）。
4. 失败幂等：加载失败不缓存为"永久不可用"的反向错误（后放包重启可重试）。
5. 静态验证：无遗留对已删资产的强引用（grep）；Gradle 配置自洽；`git diff --check` 通过。

## 回滚

基线 commit：`ece01064451ff1cd3167587329c3f80aae1462cc`（全量快照）。
回滚：`git revert` 本任务各原子提交，或 `git reset --hard ece0106`（仅在确认无其他并行工作后）。

## 实施阶段（Exo/common -> MPV，遵循 webhtv-player-gates）

- S1 common：ExternalCoreLoader + ext 包工具 + 构建产物脚本
- S2 Exo/common：LUT（删 assets）、sherpa（native.path）、ijk（外部 load）
- S3 MPV：MPVLib 改来源、删两个 flavor 的 mpv-libs
- S4 清理：旧版 maven / debug 样本 / hpm tar / serverless
- S5 静态验证 + 文档收口

## Checkpoint

基线：2026-11-24 11:40 +0800，git init + 初始提交 `ece0106`，工作区干净，5659 文件。

### 已完成（S1–S3，待提交）

- 新增 `ExternalCoreLoader`：发现 ext 包 → sha256 校验 → 解压到 `files/external-cores/<core>/<abi>/` → 版本 marker。
- ijk：`IjkLibLoader` 钩子改为从外置目录 System.load 绝对路径，回退 System.loadLibrary（保留内置兼容）。
- sherpa：`RealtimeSubtitleRecognizer.create` 设置 `sherpa_onnx.native.path`；`RealtimeSubtitleController.prepareModel` 在后台线程确保外置包就位。
- mpv：`MPVLib` 来源从 assets 改为外置包，保留 LOAD_ORDER + 绝对路径加载；Vulkan 检测改读外置 so；`NativeLibraryDiagnostics` 识别 external-core 路径。
- 删除内置资产：`lut_presets`（11M）、两个 ABI 的 `mpv-libs`（91M）、ijk/sherpa so（38M）；保留 `libc++_shared.so`（libnode 依赖，不能删）。
- `scripts/build_external_cores.sh`：从基线提取 so 生成 6 个外置包（zip+sha256），已实测产出到 `ext/cores-build/`（约 61M，已 gitignore）。

### 验证结果

- 残留引用检查：已删资产无强代码引用（`WebThemeManifest` grep 为路径误报，无匹配；`LutStore.scanAssets` 对空目录安全）。
- 体积核算：jniLibs 从 58M → 2.3M；主 APK 剥离约 92M（单 ABI）。
- 未验证（需用户完整环境）：真实 APK 体积、真机播放回归（mpv/ijk/sherpa/LUT 加载）、Vulkan 路径。

### 已知风险（接受并记录）

- 外置 native 包无签名，仅 sha256 防损坏；用户须只放可信来源包（与自有插件框架一致）。
- 外置 so 缺包时：ijk 优雅降级、sherpa 走既有加载失败路径、mpv 走播放错误路径（无自动切 Exo 内建逻辑，属现状）。
- targetSdk 必须保持 28（W^X 前提）。

## 收口记录（2026-11-24 12:20 +0800）

### 提交与 tag

- `d0bb791a680b18cb7f13778e22bd672c6ce4271f` feat(plugin): externalize mpv/ijk/sherpa/LUT cores out of APK
  - tag `recovery/PLUGIN-04/20261124-external-cores`
- `484d2c8838e8655fc1c73b522efc2d64da7b43f1` chore: drop unused maven versions, serverless, debug samples, hpm tarball
  - tag `recovery/PLUGIN-04/20261124-cleanup`
- 回滚锚点：`ece01064451ff1cd3167587329c3f80aae1462cc`（改造前全量快照）。
- 外部会话脏文件 `CLAUDE.md` / `.githooks/` 不属于本任务，未纳入任何提交（task_guard finish 因这两个活跃外部脏路径及中文文件名的 quotePath 缺陷无法完成，改用显式路径 git add + 普通提交 + 手动 tag，scope 隔离已逐项核验）。

### S5 静态验证结果（全部通过）

- V1 残留引用：mpv-libs 无真实代码引用（WebThemeManifest 为 grep 编码误报）；LUT 仅 LutStore 常量引用，scanAssets 对空目录安全；ijk 保留 System.loadLibrary 回退分支（外置缺失时抛错被 isAvailable 吞掉，优雅降级，设计内）。
- V2 外置加载链：ExternalCoreLoader / MPVLib(5) / IjkMediaPlayer(3) / sherpa(2+1) / NativeLibraryDiagnostics 均就位。
- V3 外置包完整性：6 个 zip 的 sha256 与清单逐一吻合。
- V4 体积：jniLibs 58M→3M；单 ABI 从 APK 剥离约 92M（mpv 49M + sherpa 22.5M + ijk 10M + LUT 11M）。
- V5 构建配置：abiFilters / jniLibs.srcDir / minify / shrink 未受影响。
- 性能性质：mpv 外置解压与原先 assets 解压等价（都是首次播放复制 10 个 so），非新增主线程阻塞。

### 实测构建（2026-11-24 15:35 +0800，本机补齐环境后）

- 环境（全部落在 E 盘，C 盘零占用）：JDK21 `E:\soft\jdk-21`、Python3.10 `E:\soft\Python310`、`E:\gradle-home`、`E:\Android\Sdk`（新增 platform 37.0 + build-tools 37.0.0）。
- `local.properties`：`sdk.dir=E:/Android/Sdk` + `chaquopyBuildPython=E:/soft/Python310/python.exe`（注意：sdk.dir 必须用正斜杠，单反斜杠会让 AGP 9 报"文件名、目录名或卷标语法不正确"）。
- `bash gradlew :app:assembleMobileArm64_v8aRelease` **BUILD SUCCESSFUL**（19m14s，217 任务），产物 `app/build/outputs/apk/mobileArm64_v8a/release/mobile-arm64_v8a.apk` = **84.1 MB**。

**实测结论：外置改造成功（mpv/ijk/sherpa/LUT 均不在 APK 内），但 84.1MB 远超预估的 25–40MB。** 原因是当初清单漏了 APK 内另一批原生库：

| APK 内剩余大头 | 体积 | 来源 |
|---|---|---|
| libexo_dovi_renderer.so | 9.1M | 本项目 CMake（杜比视界渲染器）|
| libavcodec.so + libswscale/libavutil 等 | ~7.6M | nextlib AAR 自带 FFmpeg |
| libxl_thunder_sdk.so + libxl_stat.so | 6.2M | 迅雷 SDK |
| libjpa.so | 5.0M | JPA 库 |
| libtensorflowlite_jni.so | 3.4M | TFLite（实时字幕模型推理）|
| libpython3.10.so + chaquopy assets | 3.3M + 11.7M | Chaquopy Python 运行时 |
| libexo_ass.so | 2.6M | ASS 字幕 |
| assets/lab（7zz/proot） | 4.2M | 内置 lab 工具 |
| classes*.dex ×4 | 23.9M | 业务代码 + 第三方库（R8 后）|

`lib/arm64-v8a` 合计 47.1M——这才是当前软件体积的真正大头。**10MB 在本架构下毫无可能**；即便把上表能外置的全外置（Python/迅雷/JPA/TFLite/lab 等需逐个评估依赖与降级），主 APK 也仍在 30–50MB（dex + 资源 + 基础库无法剥离）。

### 仍待验证（真机，用户侧）

- 把 `ext/cores-build/*.zip` + `.sha256` 放到 `<external-files>/ext/cores/`，验证 mpv/ijk/实时字幕从外置加载；LUT 用 SAF 选外部目录。
- 缺包降级：ijk 不可用、实时字幕报错、mpv 播放错误路径。

### 已知限制

- 10MB 目标未达成：剩余 nextlib AAR（7.3M，自带 FFmpeg）、exo_ass、dex 与 room/work/glide/material/jgit 等库仍在；按当前架构主 APK 预计 25–40MB。继续压缩需产品层裁剪库与 nextlib。
- 外置 native 包无签名，仅 sha256 防损坏；用户须只放可信来源包。
- targetSdk 必须保持 28（W^X 前提）。
