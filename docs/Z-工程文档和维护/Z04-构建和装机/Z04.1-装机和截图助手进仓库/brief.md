# Z04.1 装机和截图助手进仓库：任务书

## 背景

- 来源：登记时的旧编号 T00d.1。真机验证（S02、各任务的 `verify.md`）一直用维护者本机仓库外的 `~/tools/pl-adb.sh`；“每次输入前检查前台”是两次事故后定的规矩：2026-09-25 点按落到了用户的哔哩哔哩个人页和搜狗输入法的短信验证码页；2026-09-28 另一个自动化程序同时在操作手机（D-019、PROCESS 第 10 节）。
- 现象：其他执行者拿不到这个脚本；脚本默认的 `PL_APP` 还是旧测试包 `com.mystyle.purelive.next`（`~/tools/pl-adb.sh:7`），截图目录写死成某一次会话的 scratchpad（`:4`）。
- 为什么现在做：第三档；真机验证目前都由维护者做，助手放进仓库后 S02.6、S02.5 这类批量验证可以交给别人照着做。
- 已经做过的：无（脚本只在本机）。

## 目标和验收

1. `tools/device/pl-adb.sh` 存在，`source` 后提供 `pl_fg`、`pl_need`、`pl_front`、`pl_tap`、`pl_key`、`pl_text`、`pl_swipe`、`pl_shot`、`pl_ui`、`pl_tapl`、`pl_install`、`pl_check_others`。
2. 每个输入函数（点按、按键、文字、滑动、按文字点）在发命令前检查前台是 `$PL_APP`，不是就打印 `ABORT: foreground is <包名>` 并返回 1，不发任何输入。
3. 默认 `PL_APP=com.mystyle.purelive.v4dev`、`PL_DEVICE=192.168.1.2:5555`、`PL_SHOTS=./verify`；`PL_APP` 设成 `com.mystyle.purelive` 时所有函数拒绝工作。
4. `pl_install <apk>` 先读 APK 的包名（`aapt2 dump badging` 或 `aapt`），不是 `.v4dev` 结尾就拒绝。
5. `pl_shot <名字>` 存成 `<PL_SHOTS>/<名字>.jpg`，宽 540。
6. `tools/device/README.md` 写用法和规矩；`tools/gate/tests/test_device.py` 用假的 `adb` 测 2～4；门禁 `--all` 通过。

## 现状（读代码得出，写文件:行）

- `~/tools/pl-adb.sh`（16 行，仓库外）：`:3` `D=192.168.1.2:5555`；`:4` `S=<某次会话的 scratchpad>`；`:5` `fg()`（`dumpsys window | grep -m1 mCurrentFocus`，取 `u0 包名`）；`:7` `PL_APP` 默认 `.next`；`:8` `need_pl()`；`:9-12` `tap`、`key`、`text`、`swipe`；`:13` `shot`（`exec-out screencap -p`）；`:15` `ui`（`uiautomator dump` 后用正则取 `text`/`content-desc` 和 `bounds`）；`:16` `tapl`（取第一个匹配的中心点再 `tap`）。
- 测试包：`apps/pure_live/android/app/build.gradle.kts` 的 debug、profile 构建 `applicationIdSuffix = ".v4dev"`，应用名“纯粹直播 v4dev”；入口 `MainActivity`。
- 仓库里还没有 `tools/device/`；`tools/gate/tests/` 有三个检查脚本的测试可以照着写。

## 3.x 基线

- 不适用（3.x 的设备脚本是 Codex 时期的一次性脚本，没有前台检查）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 10 节真机验证、第 14 节规则）、`docs/DECISIONS.md` 的 D-019。
2. `docs/S-质量和验证/README.md` 的“风险和注意”（手机规则、其他自动化程序、K90 横屏尺寸）；`docs/S-质量和验证/S02-真机验证/CHECKLIST.md` 的开头。
3. 本文件夹的 `README.md`；`~/tools/pl-adb.sh`（如果在本机）。

## 范围

- 可以改：新建 `tools/device/`（`pl-adb.sh`、`README.md`、可选的 `resize.py`）、`tools/gate/tests/test_device.py`；本文件夹的文档。
- 不能改：`docs/PROCESS.md`、S 组的文档（引用新脚本的改动列进报告，由维护者改）；应用代码；版本号、`assets/version.json`、`assets/releases.json`；签名配置。
- 绝对不能：对 `com.mystyle.purelive` 做任何输入、安装、卸载、清数据；不在测试里连真实设备。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 脚本、c2 配置、c3 截图缩放、c5 测试 | `tools/device/pl-adb.sh`、`tools/device/resize.py`、`tools/gate/tests/test_device.py` | 测试通过；门禁 `--all` 通过 |
| 2 | c4 说明；在 K90 上试一遍（真机步骤） | `tools/device/README.md`、本文件夹 `verify.md` | 真机步骤全部按期望 |

## 测试

- `tools/gate/tests/test_device.py`（`unittest` + `subprocess` 跑 `bash -c 'source tools/device/pl-adb.sh; …'`，PATH 前面放一个假的 `adb` 脚本，记录收到的参数、按测试设定回答 `dumpsys window`）：
  - 前台是别的应用时 `pl_tap 1 2` 返回 1，假 `adb` 没收到 `input`；
  - 前台是 `.v4dev` 时收到 `shell input tap 1 2`；
  - `PL_APP=com.mystyle.purelive` 时 `pl_front`、`pl_tap` 都拒绝；
  - `pl_install` 遇到包名 `com.mystyle.purelive` 的 APK（假 `aapt2` 回答）拒绝。
- 不连真实设备、不访问网络。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. `source tools/device/pl-adb.sh; pl_check_others` | 列出最近有没有别的 adb 客户端在操作手机 |
| 2. 手机前台放桌面，`pl_tap 500 500` | 打印 `ABORT: foreground is …`，手机上没有点按 |
| 3. `pl_front`，再 `pl_tap` 首页的一张卡片 | 测试包切到前台；进了直播间 |
| 4. `pl_shot 01` | `verify/01.jpg` 宽 540 |
| 5. `pl_tapl '设置'` | 点到底部导航的“设置” |
| 6. `PL_APP=com.mystyle.purelive pl_front` | 拒绝，手机上 3.x 没有被拉起 |

## 风险和注意

- `dumpsys window` 的输出在不同 Android 版本上格式不同（`mCurrentFocus` / `mFocusedApp`），沿用现在能在 K90（Android 17）上用的写法，取不到时当成“不是测试包”（宁可拒绝）。
- `adb shell input text` 不支持中文和空格，`pl_text` 只用于英文和数字；中文输入写进 README 的限制。
- 截图缩放不要依赖必须安装的第三方库：Pillow 没有时保留 PNG 并提示。

## 环境和提交

- 需要 `adb`（`~/Android/Sdk/platform-tools`，`source ~/tools/purelive-env.sh` 会加进 PATH）、`aapt2`（build-tools 37.0.0）。
- 分支 `ai/Z04.1` 或本机工作区；提交信息以 `[Z04.1]` 开头（英文）；不推 master。
- 提交前：`python3 -m unittest discover -s tools/gate/tests`；`bash tools/gate/gate.sh --all`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；函数清单；测试数量；真机步骤的结果；需要维护者改的文档（PROCESS 第 10 节、S02 说明）；仓库外旧脚本怎么处理的建议。
