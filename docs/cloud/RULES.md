# 云端任务的共同规则

每个云端会话开始时先读完这一页，再读自己的任务单 `docs/cloud/tasks/<编号>.md`。任务单和这一页冲突时，以任务单为准。

## 这一轮的目标

只做 **Android**（手机、平板）。4.0.0 已经发布，这一轮是 4.0.x：修 bug、改进界面和功能、提升流畅度，并适配各种刷新率和分辨率。Windows、Linux、电视、苹果平台都不做。

## 开始前

1. 从最新的 `master` 新建分支 `cloud/<编号>`（例如 `cloud/B01`）。只在这个分支上提交，**不要推送到 master，也不要合并 PR**，合并由维护者在本地做。
2. 读：`AGENTS.md`；`docs/ui/UI_PLAN.md` 第 3 节（原则）、第 5 节（尺寸）、第 7 节（弹窗）、第 8 节（设计系统）、第 9 节（性能）、附录 A（必须保留的旧操作习惯）；`docs/features/PROCESS.md`；你的任务单里列出的文件和记录。
3. 环境：
   - Flutter 版本见 `toolchain.env`。`flutter --version` 不对或没有 Flutter 时，按这个版本安装（`git clone https://github.com/flutter/flutter.git -b <版本> --depth 1`，加进 PATH）。
   - 在仓库根目录先运行 `bash tools/ffmpeg_kit/fetch.sh linux`（录制用的 FFmpeg 包；只建链接或下载到缓存，不进 git），再运行 `flutter pub get`。
   - 需要出效果图的任务（任务单会写明）：`pip install playwright && python3 -m playwright install chromium-headless-shell`，然后 `bash tools/ui/mock/fetch.sh`，用法见 `tools/ui/mock/README.md`。

## 做的时候

- **先找根因再改。** 修 bug 时先写一个改之前会失败的测试，再改代码；任务单里写的位置和原因是线索，要自己核对。
- **v3（标签 `v3.2.11`，代码在同一个仓库里：`git show v3.2.11:lib/...`）是功能基线**，功能一个不少；界面以已确认的新设计（`docs/ui/compare/<任务>/README.md`）为准。
- **各处一致**：同一个功能在竖屏、横屏、平板上是同一个组件、同样的操作，屏幕大小只决定放在哪。
- **用户看得到的文字一律中文**，走 i18n：`apps/pure_live/assets/translations/zh.json` 和 `en.json` 都要加，按键名排序，4 空格缩进。代码、注释、提交信息用英文。
- 颜色和图标从 `packages/live_ui` 取（`AppIcons`、颜色角色），不在功能目录里直接写颜色和图标；`tools/gate/check_ui_structure.py` 会检查，数量只能减少。
- 功能目录（`apps/pure_live/lib/features/<模块>/`）之间不互相引用；共用的放 `apps/pure_live/lib/shared/` 或 `packages/live_ui`。
- 3.x 的设置键名和含义不变；新设置只加不改，写清默认值。
- 测试里的定时器至少 1 秒；不访问真实的直播平台（用仓库里的样本和假数据）。
- 不改版本号，不动 `assets/version.json` 和 `assets/releases.json`，不改 `docs/PLAN.md`。不把任何密钥、Cookie、真实账号写进仓库。

## 改了 Android 原生代码或资源时

改了 `apps/pure_live/android/` 下的 Kotlin、清单或资源（P01、B04 的通知图标等）：云端有 Android SDK 和 JDK 时跑一次 `flutter build apk --debug --target-platform android-arm64` 确认能编译；没有就不装，在记录里写明“原生部分没有编译”，维护者在本地构建。不要改签名、`key.properties`、版本号。

## 提交前（都要通过）

在仓库根目录：

```bash
bash tools/gate/gate.sh --all
```

跑不了完整门禁时，至少：每个改过的包 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`（或 `dart analyze`）和测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`。在报告里写清跑了哪些。

## 交付

1. 按任务单分几次提交；提交信息英文，说清改了什么和为什么。
2. 写记录 `docs/cloud/records/<编号>.md`（中文）：逐条对照任务单（做了没有、偏差和原因）、根因、改了哪些文件、新设置、测试数量、**要在真机（Redmi K90 Pro Max，Android 17，120 Hz）上看的地方和步骤**。
3. 推送分支 `cloud/<编号>`，开一个**草稿 PR** 到 master，PR 描述用中文，写记录的摘要。
4. 会话最后回复：分支名、PR 链接、每条做到没有、测试结果、需要维护者决定的事。
