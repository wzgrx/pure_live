# 0002 media_kit 使用 Predidit 分支的自维护副本

- 状态：已接受
- 日期：2026-09-27

## 背景

pub.dev 上的 media_kit 最新版是 1.2.6（2025-12-13），media_kit_video 是 2.0.1（2025-12-02），此后没有发版。官方仓库 `media-kit/media-kit` 的 main 到 2026-08-30 仍有修复但未发布。`Predidit/media-kit`（Kazumi 的播放底层）与官方分叉（领先 137、落后 146 个提交），改用 Native Assets 分发原生库，并加入 Windows 三缓冲渲染、ARM64、Android SurfaceTexture 回退等改进，2026-09-26 仍在提交。

本仓库在 Predidit 分支之上还有补丁（记录在 `third_party/media_kit_video/PURELIVE_PATCH.md`）：Android 三个架构和 Linux 使用自编 mpv 0.41.0 + FFmpeg 9.0.2；`setVideoOutputEnabled`；Windows `frameRevision` 画面进度信号；`setSize(force:)`；Windows 退出时的渲染释放顺序；去掉 `hls_ad_filter`。应用代码有 6 处以上调用这些接口。

## 决定

- 继续使用 `third_party/media_kit` 和 `third_party/media_kit_video` 的自维护副本，上游为 `Predidit/media-kit`。
- 对这个依赖，宪法中的“官方最新稳定版”解释为“所选活跃上游的最新提交”，而不是 pub.dev 的版本号。
- 2026-09-27 已同步到 Predidit HEAD `803c4a27`（提交 `4802611a`）：与本地补丁重叠的两个文件三方合并，无冲突，补丁逐行不变。
- 每次同步按 `PURELIVE_PATCH.md` 的步骤三方合并，并登记在 `docs/DEPENDENCY_AUDIT.md`；`tool/check_latest` 对比上游仓库的提交而不是 pub.dev 版本。

## 备选方案与放弃理由

- 改用 pub.dev 1.2.6：代码反而更旧；缺少上述接口导致编译失败；失去自编 FFmpeg 9、Windows 画面停住检测和 Android Surface 修复。
- 跟踪官方仓库 main：没有 Native Assets 分发，无法按平台替换自编 libmpv；需要重新移植全部补丁。

## 影响

- 维护成本：每次同步需要重放 3～4 个文件的补丁。
- 依赖单一维护者的分支；若 Predidit 停止维护，重新评估迁回官方仓库。
