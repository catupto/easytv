# PLUGIN-05: 本体最小化（第二轮瘦身）

- 用户决策：已批准（2026-11-24）——"本体尽可能最小"，内核/库继续外置或删除。
- 基线：commit `df8b05e88ed2be53b9788cc1a4f64739e7a4e2bd`（实测 APK 84.1MB），tag `recovery/PLUGIN-04/20261124-measured`。
- 类型：common + Exo/MPV 打包改造，遵循 Exo→MPV 顺序。
- 环境：JDK21 `E:\soft\jdk-21`、Python3.10 `E:\soft\Python310`、`GRADLE_USER_HOME=E:\gradle-home`、`local.properties` 已配。

## 目标与实测基线

84.1MB APK 构成（实测 unzip）：
- `lib/arm64-v8a` 47.1MB：dovi_renderer 9.1 / nextlib FFmpeg 5件套 8.1 / 迅雷 6.2 / jpa 5.0 / TFLite 3.4 / Chaquopy so 约9.6 / exo_ass 2.6 / quickjs 1.3 / libc++ 1.3 / 其它
- `assets/chaquopy` 11.7MB、`assets/lab` 4.2MB、`assets/libmitv.so` 3.6MB、pdf js 1.4MB
- `classes*.dex` 23.9MB、`resources.arsc` 2.8MB、res 约7MB

## 阶段1：完全删除（砍功能，收益最大）

| 项 | 收益 | 功能损失 | 改动点 |
|---|---|---|---|
| Chaquopy Python 整体 | ~20MB | `.py` 点播站源、py 字幕源、Python 实验室（核心播放不受影响） | settings.gradle/app.gradle 去依赖；PyLoader/PythonSubtitleScriptRuntime 降级为空；删相关测试 |
| TFLite + 卡拉OK音高 | ~3.7MB | 卡拉OK 音高轨生成 | BasicPitchTfliteGenerator/TFLite 依赖/模型 asset |
| pdf.min.js + pdf.worker.min.js | ~1.4MB | PDF 漫画（研究证明 pdf.min.js 从未加载，当前本就是死功能） | 删 assets + reader.html 死代码 |
| smbj + sardine（源码0引用） | ~0.15MB dex | 第三方 spider 的 SMB/WebDAV | catvod/build.gradle + proguard keep |

阶段1 预期：84.1MB → **~59MB**。

## 阶段2：外置到 ext 包（功能保留，包放 ext/cores 即用）

复用 `ExternalCoreLoader`（sha256+解压+marker），扩展 `scripts/build_external_cores.sh`。

| core 包 | 收益 | 加载方式 | 缺包降级 |
|---|---|---|---|
| dovi（libexo_dovi_renderer） | 9.1MB | ExoDv5Native 改 ExternalCoreLoader + System.load(abs) | DV5 回退平台渲染，可播 |
| ass（libexo_ass） | 2.6MB | AssNative 同上 | ASS 字幕不启用 |
| ffmpeg 5件套 | 8.1MB | 按 avutil→swresample→swscale→avcodec→media3ext 预载绝对路径，soname 命中后 FfmpegLibrary 的 loadLibrary 变 no-op | 特殊编码软解失效，常规播放正常（**须真机验证**）|
| quickjs wrapper | 1.3MB | QuickJsPluginRuntime 预载绝对路径 | JS 插件/爬虫失效 |
| thunder+jpa | 11.2MB | 预载 soname 命中（黑盒 SDK 可能自检，**风险高**） | magnet/剑片解析失效 |
| lab 引导（7zz/proot/libc++） | 4.2MB | ensure7z/ensureProot 改为按需下载（复用 prepareDependency） | 无网时 lab 环境不可用 |

阶段2 预期：59MB → **~22MB**（若全部成功；保守 ~30MB）。

**最终目标：本体 20–30MB；10MB 不可达**（dex 约20MB + 资源 + 基础库无法剥离）。

## 验收

1. 每阶段 `bash gradlew :app:assembleMobileArm64_v8aRelease` 成功，记录 APK 体积。
2. 外置库不出现在 APK（`unzip -l | grep`）。
3. 缺包时核心播放（Exo 常规片源）正常，降级路径不崩溃。
4. 外置包 zip+sha256 由脚本生成并校验通过。
5. `git diff --check` 无错误；无遗留对删除内容的编译期强引用。

## 回滚

基线 `df8b05e`（tag `recovery/PLUGIN-04/20261124-measured`）。每阶段一个原子提交 + tag。回滚 `git reset --hard <tag>`。

## 约束/风险

- targetSdk 保持 28（W^X）；外置 so 私有目录 dlopen。
- 黑盒 SDK（迅雷/jpa）soname 预载可能触发自检；如真机验证失败，回退该项（从外置列表移除）。
- 阶段1 删除 Chaquopy 后 Python 站源用户需改用 JS/Jar 源——这是用户已接受的功能取舍。
- 外部会话的 `AGENTS.md` 改动不属于本任务，不纳入提交。

## 实测结果（2026-11-24 22:30 +0800，本机完整构建）

| 阶段 | 提交 | tag | APK |
|---|---|---|---|
| 基线 | df8b05e | recovery/PLUGIN-04/20261124-measured | 84.1MB |
| 阶段1（删 Python/TFLite/pdf/SMB） | a818d3a | recovery/PLUGIN-05/20261124-stage1 | 60MB |
| 批次2a（dovi+ass 外置） | 0c5103b | recovery/PLUGIN-05/20261124-stage2a | 49MB |
| 批次2b-1（FFmpeg 外置） | 6973619 | recovery/PLUGIN-05/20261124-stage2b-ffmpeg | 40MB |
| 批次2b-2（迅雷/JPA 外置） | cd206a5 | recovery/PLUGIN-05/20261124-stage2b-2b | 29MB |
| 批次2b-3（lab 外置） | 本次提交 | recovery/PLUGIN-05/20261124-final | **27MB** |

**累计 84.1MB → 27MB（-68%）。**

### 实施细节与偏差

- Chaquopy：packagingOptions/resources/mergeAssets 三种排除均无效（插件在 package task 硬注入），最终改用"去插件 + Loader/Spider 空壳"方案成功（-24MB）。
- FFmpeg 外置：在 `ExoUtil.buildRenderersFactory()` 开头按 avutil→swresample→swscale→avcodec→media3ext 预载 soname，AAR 内 `System.loadLibrary("media3ext")` 变 no-op，Exo 软解在包就位时仍可用；缺包回退 MediaCodec。**真机软解回归待用户验证**。
- 迅雷/JPA：`Thunder.fetch()` / `JianPian.init()` 预载绝对路径，黑盒 SDK 的 loadLibrary 按 soname 命中；**SDK 自检风险待真机验证**，失败则回滚该项。
- lab：`copyAsset` 失败时从 ext lab 包按相对路径解压二进制（保留 lab_template.json 模板）。
- 12 个外置包（mpv/ijk/sherpa/dovi/ass/ffmpeg/jpa/thunder/lab × ABI）sha256 全部校验通过，产物在 `ext/cores-build/`（gitignore，不进版本控制）。

### 最终 27MB APK 构成

`classes*.dex` 22.2MB + `lib/arm64-v8a` 4.2MB（c++_shared/quickjs/avif/dovi_android/cnode/rtmp/gif）+ `libmitv.so` 3.6MB + resources.arsc 2.8MB + 其它。
**10MB 不可达**：dex + 基础库 + 资源是硬底线。进一步可砍：libmitv.so（3.6MB，P2P 直播）、quickjs wrapper（1.3MB），但收益已递减。

### 回滚

历史提交/tag 在 PLUGIN-07 仓库历史重建时已被清理（仓库从未 push，无远端依赖）。原 tag 清单留档（仅作历史记录，对象已不可 checkout）：

```
recovery/PLUGIN-04/{20261124-cleanup,20261124-external-cores,20261124-final,20261124-measured}
recovery/PLUGIN-05/{20261124-final,20261124-stage1,20261124-stage2a,20261124-stage2b-2b,20261124-stage2b-ffmpeg}
recovery/PLUGIN-06/20261125021155-3bcef7498fb8
recovery/PLUGIN-07/20261125-static-libs
```

当前仓库为单提交快照；如需回滚到改造前状态，需从外部备份恢复（改造前基线 commit `ece0106` 的内容已不在本仓库历史中）。外置包产物在 `ext/cores-build/`（gitignore，本地保留）。

### 待用户真机验证

1. 把 `ext/cores-build/*.zip` + `.sha256` 放到 `<external-files>/ext/cores/`。
2. 验证 mpv/ijk/sherpa(已删除→不可用)/dovi/ass/ffmpeg(AVS3/ALAC 片源)/thunder/jpa/lab 的加载与降级。
3. 重点：FFmpeg 软解与黑盒 SDK 自检——这两项若真机失败，按 tag 回滚对应单项。

## PLUGIN-06：打包层精简（2026-11-25 10:10 +0800）

参考 dsplayer 的打包机制（`useLegacyPackaging=true`、收紧 keep、语言过滤）做第三轮，实测 **27MB → 19.7MB（-7MB）**：

| 改动 | 文件 | 收益 |
|---|---|---|
| `packagingOptions.jniLibs.useLegacyPackaging = true`：so 由 Stored 改为 Deflate 压缩存储（dsplayer 实测 56.8%），系统安装时解压 | app/build.gradle | ~2.5MB |
| `resourceConfigurations += ["zh","en"]`：非中英文资源过滤 | app/build.gradle | 小额 |
| JGit keep 从 `org.eclipse.jgit.**` 收窄到 api/transport/ObjectId | app/proguard-rules.pro | classes4.dex 4.42→3.67MB |
| JUPnP keep 从 `org.jupnp.**` 收窄到 android/registry/transport/binding/model/protocol/support | app/proguard-rules.pro | 含在 dex 收益内 |

验证：`unzip -lv` 确认 7 个 so 均为 Defl:N（压缩率 50–68%）；R8 mapping 确认 JGit `Git`、JUPnP `RemoteDevice`/`ProtocolFactory` 等关键类均保留（反射路径未断）。`useLegacyPackaging` 只影响 APK 内 so 的存储方式，外置 core 的绝对路径 `System.load` 不受影响。

代价：安装时间变长、data 分区占用增加（系统解压 so）；DLNA/Git 云同步需真机验证反射路径。

## Checkpoint

2026-11-25 10:10 +0800：三轮改造完成，最终 APK 19.7MB（基线 84.1MB，-77%）。下一步：提交 + tag + 真机验证（重点：外置 core 加载、FFmpeg 软解、黑盒 SDK 自检、DLNA/Git 反射）。
