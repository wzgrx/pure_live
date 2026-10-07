# Z03.2 项目清点脚本：代码文件、功能点、设置项、平台、原生插件都归到子分类，没归的报错

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：工程
- 来源：docs v0（2026-10-02）整理成 20 组时提出：界面已经有清点脚本（Z03.1），但其他东西——4.x 的代码文件、功能点、设置项、平台、原生插件——归哪个子分类只写在登记表 `[[sub]]` 的 `code` 文字里，新加的东西可能没人管。
- 旧编号：T00c.2
- 相关：Z03.1（界面清点，规则表的写法可以照搬）；Z03.3（从登记表取新编号）；Z06（`tools/docs/docs.py`、`tasks.toml`）；Z02（第 3 阶段接进门禁）；[inventory/FEATURES.md](../../../inventory/FEATURES.md)（功能点、平台能力表、设置项核对）

## 目标

一个脚本回答“这个东西归哪个子分类管”，并在门禁里拦住没归属的：

1. 代码文件：`apps/pure_live/lib/`（283 个 Dart 文件）、`packages/*/lib/`（11 个包 315 个）、`apps/pure_live/android/` 的 Kotlin（7 个）、`apps/pure_live/windows/runner/` 的 C++（4 个 `.cpp`）、`tools/` 下的脚本，每个都按路径规则归到一个子分类。
2. 功能点：FEATURES.md 的 176 个 `F-…` 和 14 个 `F-WIN-…`，“依据”或“备注”里写的任务编号都存在。
3. 设置项：`Settings.all` 的 218 个设置各归一个子分类（按 `section` 默认、个别覆盖）。
4. 平台：`SiteIds.supported` 的 35 个来源（34 个平台 + 网络电视）各有播放（E01～E03、L01）和弹幕（D01）的子分类。
5. 原生插件：14 个方法通道（`pure_live/app`、`pure_live/recorder`……）和 7 个 Kotlin 文件各归一个子分类。

没归属的任何一项，脚本退出 1；进门禁以后，加新文件、新设置、新平台时必须同时登记归属。

## 3.x 和现状

| 方面 | 3.x | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 代码归属 | 没有（`lib/modules/` 按模块分目录，没有清单） | `docs/tasks.toml` 每个 `[[sub]]` 的 `code` 字段是文字（107 个子分类里 93 个写了路径，其余“—”），`docs.py` 原样印到子分类 README 的“代码：”一行，没人核对 | 路径表 + 脚本核对 |
| 功能点 | — | `docs/inventory/FEATURES.md`（手写，V03.3 在 2026-10-03 核对过），任务编号写在“依据”“备注”两列 | 脚本核对编号都存在 |
| 设置项 | 3.x 的 Hive 键散在各控制器 | `packages/live_store/lib/src/settings/settings.dart` 的 `Settings.all`（218 个，分 `section`）；FEATURES.md 第 15 节手工核对过 | 每个设置有子分类 |
| 平台 | `lib/core/site/` 下 34 个条目（33 个平台加共用文件） | `packages/live_core/lib/src/sites.dart:111` 的 `SiteIds.supported`（35 个）；弹幕在 `packages/live_danmaku/lib/src/sites/` | 每个来源有播放和弹幕的子分类（或写明“没有弹幕”） |
| 原生插件 | `android/app/src/main/kotlin/` 下 5 个文件（`git ls-tree -r v3.2.11 android/app/src/main/kotlin`） | `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/` 7 个文件；Dart 侧 14 个 `MethodChannel`/`EventChannel` 名 | 每个有子分类 |

## 方案

- c1 规则和路径表（第 1 阶段）：新文件 `docs/inventory/OWNERS.toml`（建议 A；B 是在 `tasks.toml` 的 `[[sub]]` 加 `paths` 字段，会让登记表变长、`docs.py` 要改，不建议）：
  - `[[path]]`：`glob` → `sub`，第一条匹配的生效（照 Z03.1 的规则表写法）；
  - `[setting_sections]`：`danmaku` → D05、`player` → G 组……，`[[setting]]` 个别覆盖；
  - `[[site]]`：`SiteIds` 的值 → 播放子分类、弹幕子分类（或 `danmaku = "无"`）；
  - `[[channel]]`：通道名 → 子分类。
  写表时以 `tasks.toml` 现有的 `code` 字段为起点，冲突的（一个文件两个子分类都写了）在 `record.md` 列出来请维护者定。
- c2 脚本（第 2 阶段）：`tools/docs/owners.py`（只用标准库，像门禁的另外三个脚本）：扫文件、用正则从 `settings.dart` 取 `Settings.all` 的键和 `section`、从 `sites.dart` 取 `SiteIds`、从 `apps/pure_live/lib` 取通道名、从 FEATURES.md 取任务编号；输出 `docs/inventory/OWNERS.md`（每个子分类管哪些文件、设置、平台、通道，生成）；`--check` 只检查不写。测试 `tools/gate/tests/test_owners.py`。
- c3 接进门禁（第 3 阶段）：`tools/gate/gate.sh` 在“docs”一步后加 `step "owners" python3 tools/docs/owners.py --check`；`docs.py` 生成子分类 README 时“代码：”一行改为从 OWNERS 取（可选，维护者定）。

## 验证

- 自动测试：`tools/gate/tests/test_owners.py`：没匹配的文件报错、第一条规则生效、设置的 `section` 默认和覆盖、平台缺弹幕归属报错、FEATURES 里的不存在编号报错、干净的仓库通过。
- 门禁：`bash tools/gate/gate.sh --all` 里有 `gate: ok   owners`。
- 真机：不适用（工程任务）。

## 留下的问题

- 还没开始。路径表第一版要逐个子分类定边界（例如 `features/live_play/danmaku/` 是 A08 界面还是 D04 数据流——A08 子分类说明已经写了按文件的分法），工作量主要在这里，脚本本身不大。
- 本地互动的数据和规则（`features/live_play/local_interaction/logic/`）A08 说明里写着“没有登记在哪个功能子分类”，写表时会碰到，按“需要维护者决定”报告。
