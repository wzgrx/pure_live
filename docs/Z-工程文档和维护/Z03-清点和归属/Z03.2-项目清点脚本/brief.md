# Z03.2 项目清点脚本：任务书

## 背景

- 来源：docs v0（2026-10-02，`c613b73f9`）整理成 20 组时登记（旧编号 T00c.2）。界面有 Z03.1 的清点脚本，但 4.x 的代码文件、功能点、设置项、平台、原生插件归哪个子分类，只写在 `docs/tasks.toml` 每个 `[[sub]]` 的 `code` 文字里，没有脚本核对。
- 现象：例如 A08 子分类说明里写着“本地互动的数据和规则（`features/live_play/local_interaction/logic/`）没有登记在哪个功能子分类”；`tools/live_cli` 写在 E07 的 `code` 里但仓库里没有；新加一个设置或平台时没人检查它有没有子分类管。
- 为什么现在做：第二档；子分类说明（docs v2）已经逐个写了“代码地图”，正好把它们变成一张能被脚本核对的表。
- 已经做过的：Z03.1（`tools/ui/inventory.py`，规则表写法可以照搬）；V03.3 手工核对了 FEATURES.md 的功能点和 218 个设置项。

## 目标和验收

1. `docs/inventory/OWNERS.toml`（手写）：代码路径规则、设置分节默认值和覆盖、平台、通道各归一个子分类；子分类编号都在 `tasks.toml` 里。
2. `tools/docs/owners.py`：没归属的代码文件、设置、平台、通道，以及 FEATURES.md 里写了却不存在的任务编号，逐条打印并退出 1；归属齐全时退出 0。
3. 生成 `docs/inventory/OWNERS.md`（每个子分类管的文件、设置、平台、通道），文件开头写“生成，不要手改”。
4. `tools/gate/tests/test_owners.py` 覆盖规则的各种情况；门禁加一步 `owners`，`--all` 通过。
5. `docs/inventory/README.md` 加 OWNERS 两个文件的说明；路径表和 `tasks.toml` 的 `code` 字段冲突的地方列进 `record.md`，由维护者定。

## 现状（读代码得出，写文件:行）

- 代码：`apps/pure_live/lib/` 283 个 Dart 文件（`app/`、`features/` 25 个目录、`shared/`、`platform/`、`routes/`、`tv/`、`i18n/`）；`packages/*/lib/` 共 315 个（`live_core` 91、`live_ui` 56、`live_danmaku` 46、`live_net` 21、`live_record` 17、`live_vod` 17、`live_media` 16、`live_store` 16、`live_iptv` 14、`live_player` 12、`live_cast` 9）；Kotlin 7 个（`apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/`：`AppChannelsPlugin.kt`、`MainActivity.kt`、`PermissionsPlugin.kt`、`RecorderForegroundService.kt`、`RecorderPlugin.kt`、`ShareIntakePlugin.kt`、`SystemAccessPlugin.kt`）；Windows 运行器 4 个 `.cpp`。
- 设置：`packages/live_store/lib/src/settings/settings.dart` 的 `static const xxx = …Setting('键', section: '…')`，`Settings.all` 列全部（FEATURES.md 第 15 节：218 个，10 个 `SettingScope.internal`）。
- 平台：`packages/live_core/lib/src/sites.dart:111` 的 `SiteIds.supported`（35 个，含 `iptv`）；弹幕实现 `packages/live_danmaku/lib/src/sites/`（29 个文件）。
- 通道：`apps/pure_live/lib` 里 14 个名字：`pure_live/app`、`background_playback`、`device_controls`、`display_mode`、`multicast_lock`、`native_http`、`permissions`、`pip`、`predictive_back`、`recorder`、`secret_cipher`、`share_intake`、`system_access`、`text_codec`（都带 `pure_live/` 前缀）。
- 功能点：`docs/inventory/FEATURES.md` 每行“依据”“备注”列里括号中的任务编号（例如 F-APP-01 的 `J02.1`、`I01.1`、`J06.1`、`S04.1`）。
- 现有的归属文字：`docs/tasks.toml` 每个 `[[sub]]` 的 `code`（93 个写了路径）；`tools/docs/docs.py` 的 `sub_md`（`:438`）原样输出。
- 可以照搬的写法：`tools/ui/inventory.py:97` 的 `assign`（前缀规则，第一条匹配的生效）；`tools/gate/check_*.py` 都只用标准库、在钩子里能直接跑。

## 3.x 基线

- 3.x 没有归属清点，`lib/modules/<模块>/` 的目录就是唯一的归属线索；不适用。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 1 节编号、第 8 节合并审查、第 13 节文档规范）。
2. `docs/specs/ENGINEERING.md`（第 4 节分层、第 7 节代码规则）。
3. 本文件夹的 `README.md`；`docs/Z-工程文档和维护/Z03-清点和归属/README.md`；`tools/ui/inventory.py`；`tools/gate/check_ui_structure.py`（标准库脚本的写法和测试）；`docs/inventory/FEATURES.md` 第 14、15 节；各组子分类 README 的“代码地图”（例如 `docs/A-界面设计/A08-弹幕界面/README.md`）。

## 范围

- 可以改：新建 `docs/inventory/OWNERS.toml`、`docs/inventory/OWNERS.md`（生成）、`tools/docs/owners.py`、`tools/gate/tests/test_owners.py`；`tools/gate/gate.sh`（只加一步）；`docs/inventory/README.md`；本文件夹的文档。
- 不能改：`docs/tasks.toml`（`code` 字段要不要改由维护者定，冲突写进报告）；任何应用和包的代码；其他组的文档；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 定规则和路径表 | c1：写 `OWNERS.toml`，以各子分类 README 的代码地图和 `tasks.toml` 的 `code` 为起点；设置按 `section` 给默认子分类再列例外；35 个来源、14 个通道逐个写 | `docs/inventory/OWNERS.toml`、`record.md` | 每条规则指向存在的子分类；冲突和拿不准的列进 `record.md` |
| 2 写脚本 | c2：`owners.py`（扫描、匹配、报告、生成 OWNERS.md、`--check`），测试 | `tools/docs/owners.py`、`tools/gate/tests/test_owners.py`、`docs/inventory/OWNERS.md` | 在当前 master 上 `--check` 退出 0；测试全过 |
| 3 接进门禁 | c3：`gate.sh` 加 `step "owners" python3 tools/docs/owners.py --check`；`docs/inventory/README.md` 写说明 | `tools/gate/gate.sh`、`docs/inventory/README.md` | `bash tools/gate/gate.sh --all` 通过，日志有 `gate: ok   owners` |

每个阶段都要能单独合并（门禁通过、不留半截功能）。第 1 阶段只有文档。

## 测试

- `tools/gate/tests/test_owners.py`（`unittest`，用临时目录造文件树）：
  - 一个文件不匹配任何规则 → 报 `unowned: <路径>`；
  - 两条规则都匹配时第一条生效；
  - 设置按 `section` 归属，个别设置覆盖；新加一个 `section` 没写默认值 → 报错；
  - `SiteIds.supported` 里有、`[[site]]` 里没有 → 报错；弹幕写“无”时不报；
  - FEATURES.md 一行写了不存在的任务编号 → 报错；
  - 规则指向不存在的子分类 → 报错；
  - 干净的树通过。
- 不访问网络；只用标准库（和另外三个检查脚本一样）。

## 真机验证

不适用（工程任务，没有用户看得到的变化）。

## 风险和注意

- 边界最难定的地方：同一目录里界面和逻辑分属 A 组和功能组（例如 `features/live_play/danmaku/chat_feed.dart` 归 D04、`chat_list.dart` 归 A08）。规则允许精确到文件，写不清的列为“需要维护者决定”，不要硬分。
- 规则写得太细会让每个新文件都要改表；优先按目录写，例外才写到文件。
- 门禁一步只能用标准库：解析 TOML 用 `tomllib`（Python 3.11+，`docs.py` 已经在用）。
- 可能冲突的文件：`tools/gate/gate.sh`（Z02 的其他改动）；`docs/inventory/README.md`（Z03.3 也改）。先做 Z03.3 再做本任务第 3 阶段，或两边都保留。

## 环境和提交

- 只需要 Python 3.11+；不需要 Flutter。门禁需要 `source ~/tools/purelive-env.sh`。
- 分支 `ai/Z03.2` 或本机工作区；提交信息以 `[Z03.2]` 开头（英文）；不推 master。
- 提交前：`python3 -m unittest discover -s tools/gate/tests`；`python3 tools/docs/owners.py --check`；`python3 tools/docs/docs.py --check`；第 3 阶段再跑 `bash tools/gate/gate.sh --all`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（路径表写到哪个组、脚本做到哪）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

规则条数（路径、设置、平台、通道）；没归属的项目一开始有多少、怎么处理的；和 `tasks.toml` `code` 字段冲突的地方；需要维护者决定的归属；测试数量；门禁结果。
