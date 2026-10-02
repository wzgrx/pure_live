# A07.n 名称：任务书

> 交给执行者（维护者、Claude 或其他 AI）的全部要求。不依赖聊天记录；读完这一页和下面列的文件就能开工。

## 背景

- 为什么做：用户的原话、问题现象、相关决定 D-xxx。
- 已经做过的：相关任务和提交。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（尤其第 5 节分阶段、第 8 节合并审查）。
2. 规范：`docs/specs/ENGINEERING.md`、`docs/specs/UI.md`（界面任务）。
3. 设计或说明：本文件夹的 `README.md`（已确认的逐条照做）。
4. 3.x 代码（标签 `v3.2.11`：`git show v3.2.11:lib/...`）：列文件。
5. 现在的代码：列文件。

## 可以改 / 不能改

- 可以改：列目录。
- 不能改：其他组的界面；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 阶段和要做的

| 阶段 | 要做的（逐条，对应 README 的 c 编号） | 怎么算做完 |
|---|---|---|
| 1 | c1 ……；c2 …… | 测试……通过 |
| 2 | c3 …… | …… |

## 测试

- 修 bug 先写一个改之前会失败的测试。
- 界面：竖屏、横屏、宽屏至少各一个布局测试，固定控件顺序、图标、位置。
- 测试里的定时器至少 1 秒；测试不访问真实平台。

## 环境

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支：`ai/<任务编号>` 或本机工作区；提交信息以 `[<任务编号>]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 真机上要看的（维护者做）

- 步骤和期望结果。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条做到没有；根因；测试数量；改了哪些文件；新设置和翻译键；要在真机上看的；需要维护者决定的；可能冲突的文件。
