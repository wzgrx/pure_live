# 仓库说明

纯粹直播 v4：在 v3 代码上逐模块重构。方案和进度见 [docs/PLAN.md](docs/PLAN.md)，每个模块的审查记录在 [docs/modules/](docs/modules/)。

## 目录

- `tools/gate/`：门禁（格式、依赖方向、分析、测试）。
- `tools/brotli/`：Brotli 字典和测试向量的生成脚本（M1.1）。
- `tools/timeshift/`：把系统时间往后推再跑测试，找出拿样本里的过期时间和“现在”比较的测试（时间炸弹）。
- `tools/check_latest/`：对照官方渠道检查工具链和依赖是否最新。
- `tools/ffmpeg_kit/`：录制用的 FFmpeg 原生包（`fetch.sh`，Windows 用 `fetch.ps1`）：缓存到 `~/.cache/pure_live/ffmpeg_kit/` 并链接到 `.ffmpeg_kit/`，克隆或新建工作树后先跑一次，之后离线也能构建和测试（M8.1）。
- `packages/`、`apps/pure_live`：按 docs/PLAN.md 第 6 节逐模块加入，分层见第 4 节。
- `assets/version.json`、`assets/releases.json`：已安装的 3.x 检查更新时从 master 读取。只在发布新版本时修改，不能删。

## 工作规则

- **界面、布局、操作逻辑以 v3 为准。** v3 源码在归档分支 `archive/v4` 的 `legacy/` 下，本机只读副本在 `~/ref/pure_live_archive/legacy`。改变外观或操作习惯的改动，先征得用户同意。用户已批准的升级（2026-09-28 全部采用）记录在 [docs/UPGRADES.md](docs/UPGRADES.md)，照表执行，不必再问；表外的新改动仍要先问。
- **一个模块一次上传**：走完 docs/PLAN.md 第 7 节的流程（读、审查、重构、测试、门禁）后推送。只用 `master`，不强推。
- **工具链和依赖用最新稳定版**，固定在 `toolchain.env` 和根目录的 `pubspec.lock`。检查命令：`GITHUB_TOKEN=$(gh auth token) dart run tools/check_latest/bin/check_latest.dart`。
- **代码规范**：very_good_analysis，行宽 120，公开接口写文档注释，Dart 主构造函数写 `const new(...)`。纯 Dart 包不引用 Flutter；依赖方向由 `tools/gate/check_deps.py` 强制。
- **门禁**：开发中跑 `bash tools/gate/gate.sh`，推送前必须跑 `bash tools/gate/gate.sh --all`，日志里出现 `gate: passed` 才算通过。
- **时间炸弹**：发布前跑 `tools/timeshift/run.sh`（默认 +30 天、+1 年、+5 年），必须全部 ok（2026-10-01 起为加速，模块收尾时不再跑）。测试里凡是用到样本时间（Cookie、签名地址、租期、开播时间）的，都要把“现在”固定成录制时间，被测代码要能注入时间（`now:` 参数）。
- **构建只在本机**：Android 在 WSL，Windows 在主机，不用 GitHub Actions。同一时间只跑一个重任务。
- **安全**：签名文件和密钥不进 Git；Cookie 加密存储，不写进日志。
- **版本号**只在发布时改。
- **测试设备**：
  - 测试包用 `.next` 包名，和用户手机上的 3.x 并存，不碰 `com.mystyle.purelive` 和它的数据；
  - 不碰 Windows 上 `D:\Soft` 下的安装；
  - 每次向手机发送输入前，先确认前台应用。
- **提交和沟通**：提交信息用英文，文档和给用户的说明用中文。
- **参考仓库**：本机副本在 `~/ref/`，见 docs/PLAN.md 第 8 节。做相关模块前先 `git pull`。

## 加速（2026-10-01 起）

用户要求“先加速完成项目，以后再慢慢测试”：
- 平台和功能任务的测试只写主要路径，不做变异检查、不连跑多次；录制和真实环境检查每个任务合计不超过 10 分钟。
- 任务分支提交前只跑改动相关的格式、分析和测试；完整门禁 `gate.sh --all` 由合并的人在推送前跑。多个分支可以一起合并后跑一次门禁、一起推送。
