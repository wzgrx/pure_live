# Z04.1 装机和截图助手进仓库：K90 截图、带前台检查的点按

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：工程
- 来源：真机验证一直用维护者本机的 `~/tools/pl-adb.sh`（仓库外）；它的“每次输入前检查前台”是 2026-09-25、09-28 两次误点用户应用之后加的规矩（D-019、PROCESS 第 10 节）。其他执行者（其他 AI、换机器）拿不到这个脚本，就只能用裸的 `adb shell input`，重蹈覆辙。
- 旧编号：T00d.1
- 相关：D-019（K90 随时可用，只点测试包，不碰 3.x 和正式包）；S02（真机清单和验证）；各任务的 `verify.md`；Z04（构建）

## 目标

仓库里有一个装机和截图助手（`tools/device/`），任何执行者 `source` 之后就能：把测试包装到指定设备、把测试包切到前台、每次点按/输入/滑动前确认前台是测试包、截图存到指定目录并缩到宽 540、按文字找控件点。默认包名是 `com.mystyle.purelive.v4dev`，永远不对 `com.mystyle.purelive`（用户的 3.x 和正式包）做任何输入或安装。

## 3.x 和现状

| 方面 | 3.x | 现在（仓库外 `~/tools/pl-adb.sh`） | 要做到 |
|---|---|---|---|
| 位置 | 3.x 的 `tool/` 下有一些设备脚本（Codex 时期） | 维护者本机，16 行，`source` 后用 | 仓库 `tools/device/`，有说明和测试 |
| 设备 | — | 写死 `D=192.168.1.2:5555`（`:3`） | 环境变量 `PL_DEVICE`，默认 K90 |
| 测试包名 | — | 默认 `PL_APP=com.mystyle.purelive.next`（`:7`，**旧包名**，现在测试包是 `.v4dev`） | 默认 `.v4dev`；设成 `com.mystyle.purelive` 时拒绝 |
| 前台检查 | — | `fg`（`:5`，`dumpsys window` 的 `mCurrentFocus`）、`need_pl`（`:8`）；`tap`、`key`、`text`、`swipe` 每次先查（`:9-12`） | 保留，并加“切到前台”（`am start` 测试包的入口），切换后再查一次 |
| 截图 | — | `shot <名字>`（`:13`）存到写死的某次会话 scratchpad（`:4`） | 目录可配置（默认任务文件夹的 `verify/`），自动缩到宽 540（PROCESS 第 10 节） |
| 按文字点 | — | `ui [正则]`、`tapl <正则>`（`:15-16`，`uiautomator dump`） | 保留 |
| 装机 | — | 没有（手动 `adb install`） | `pl_install <apk>`：只装包名是 `.v4dev` 的 APK（先用 `aapt2 dump badging` 看包名） |
| 其他自动化 | — | 没有检查 | 开始前提示 `adb logcat -d | grep "adbd service requested"`（S 组说明里的做法） |

## 方案

- c1 脚本：`tools/device/pl-adb.sh`（bash，`source` 用），函数：`pl_fg`、`pl_need`、`pl_front`（切到前台）、`pl_tap`、`pl_key`、`pl_text`、`pl_swipe`、`pl_shot`、`pl_ui`、`pl_tapl`、`pl_install`、`pl_check_others`；全部输入函数先 `pl_need`；包名是 `com.mystyle.purelive` 时直接拒绝。
- c2 配置：`PL_DEVICE`（默认 `192.168.1.2:5555`）、`PL_APP`（默认 `com.mystyle.purelive.v4dev`）、`PL_SHOTS`（默认当前目录下 `verify/`）。
- c3 截图缩放：截到 PNG 后用 Python（Pillow 有就用，没有就保留原图并提示）缩到宽 540 存 JPG。
- c4 说明：`tools/device/README.md` 写用法和规矩（每次输入前检查前台、不碰 3.x、Windows 上的注意）；`docs/PROCESS.md` 第 10 节和 S02 子分类说明里引用它（PROCESS 由维护者改）。
- c5 测试：`tools/gate/tests/test_device.py` 用假的 `adb`（PATH 里放一个桩脚本）验证：前台不是测试包时 `pl_tap` 不发命令；`PL_APP=com.mystyle.purelive` 时拒绝；`pl_install` 拒绝包名不对的 APK。

## 验证

- 自动测试：`tools/gate/tests/test_device.py`（门禁 `--all` 跑）。
- 真机：在 K90 上 `source tools/device/pl-adb.sh`，前台放别的应用时 `pl_tap 500 500` 被拒；`pl_front` 后能点；`pl_shot 01` 得到宽 540 的图（brief 的真机步骤）。

## 留下的问题

- 还没开始。仓库外的 `~/tools/pl-adb.sh` 在新脚本合并后是删掉还是改成转调，由维护者决定。
- Windows 主机的 GUI 助手（`C:\Users\123\claude-work\wingui.ps1`、`~/tools/wg.sh`）不在本任务范围，X01.3 做 Windows 验证时再定要不要进仓库。
