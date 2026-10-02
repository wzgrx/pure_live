# 仓库说明

纯粹直播（Pure Live）4.x：在 3.x（`v3.2.11`）的代码上重构的第三方直播聚合应用。4.0.0（Android）已发布。

**文档入口：[docs/README.md](docs/README.md)。** 进度看 [docs/STATUS.md](docs/STATUS.md)，做法看 [docs/PROCESS.md](docs/PROCESS.md)，决定看 [docs/DECISIONS.md](docs/DECISIONS.md)。全部任务登记在 [docs/tasks.toml](docs/tasks.toml)，分成 20 组（字母 A～Z，界面设计 A 排第一）。

## 接到一个任务时

1. 在 [docs/STATUS.md](docs/STATUS.md) 或 [docs/TASKS.md](docs/TASKS.md) 找到任务编号（例如 `A07.13`），读它文件夹里的 `brief.md`（任务书）、`README.md`（设计或说明）、`record.md`（记录）。
2. 读 [docs/PROCESS.md](docs/PROCESS.md)：分阶段做（第 5 节）、新功能（第 6 节）、合并审查（第 8 节）、规则汇总（第 14 节）。
3. 读规范：[docs/specs/ENGINEERING.md](docs/specs/ENGINEERING.md)，界面任务再读 [docs/specs/UI.md](docs/specs/UI.md)。
4. 在自己的分支上做（`ai/<任务编号>` 或本机工作区），提交信息以 `[<任务编号>]` 开头；不推 master。
5. 做不完时按 PROCESS 第 5.2 节停下：提交、在 `record.md` 写“停在哪”、更新登记表。

## 目录

- `apps/pure_live`：应用（Android、Windows、Linux、电视模式）。
- `packages/`：`live_core`（平台）、`live_net`（网络）、`live_danmaku`（弹幕）、`live_media`、`live_player`（播放）、`live_record`（录制）、`live_store`（存储和迁移）、`live_ui`（设计系统）、`live_iptv`、`live_cast`、`live_vod`。分层和依赖方向见 [docs/specs/ENGINEERING.md](docs/specs/ENGINEERING.md) 第 4 节。
- `tools/gate/`：门禁；`tools/docs/`：文档生成和检查；`tools/ui/`：清点和效果图工具；`tools/check_latest/`：工具链检查；`tools/ffmpeg_kit/`：录制用的 FFmpeg 包；`tools/timeshift/`：时间炸弹检查；`tools/brotli/`：Brotli 测试向量生成。
- `assets/version.json`、`assets/releases.json`：已安装的 3.x 从 master 读取检查更新，只在发布时修改，不能删。

## 必须遵守

- 3.x 是功能和操作习惯的基线；先找根因再改；各处一致（同一个功能各布局是同一个组件）。
- 用户看得到的文字一律中文（`apps/pure_live/assets/translations/zh.json` 和 `en.json` 都加，按键名排序，4 空格缩进）；代码、注释、提交信息用英文。
- 推送前 `bash tools/gate/gate.sh --all` 必须通过（日志里有 `gate: passed`）；不强推；版本号只在发布时改。
- 只在本机构建；签名文件和密钥不进 git；不把真实 Cookie、账号、客户端地址写进仓库。
- 不碰用户的 3.x 安装和数据（手机上的 `com.mystyle.purelive`、Windows 上 `D:\Soft` 下的安装）；测试包是 `com.mystyle.purelive.v4dev`。
- 测试里的定时器至少 1 秒；测试不访问真实平台。
- 改了任务状态就改 [docs/tasks.toml](docs/tasks.toml) 并运行 `python3 tools/docs/docs.py`。
