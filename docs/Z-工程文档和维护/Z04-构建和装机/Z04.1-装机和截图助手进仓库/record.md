# Z04.1 装机和截图助手进仓库：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `d34ad44d1` 开始）
- 设计或说明：[README.md](README.md)、[brief.md](brief.md)

## 来源

两份仓库外的脚本（只读，没有运行）：

- `~/tools/pl-adb.sh`（16 行）：`fg`、`need_pl`、`tap`、`key`、`text`、`swipe`、`shot`、`ui`、`tapl`；设备写死成 K90 的地址，截图目录写死成某次会话的 scratchpad。
- 某次会话 scratchpad 里的 `ui/s.sh`：`s`（截图缩到宽 540）、`sl`（横屏宽 1080）、`row`（并排）、`hold`（长按，带前台检查）、`front`（`am start` 切前台）、`home`（点标题栏返回箭头回到底部导航）、`ctl`（先叫出播放器控件再按标签点；文件里定义了两次，第二次生效）。

## 做了什么

- `tools/device/pl-adb.sh`（`source` 用）：`pl_env`、`pl_fg`、`pl_need`、`pl_front`、`pl_tap`、`pl_hold`、`pl_key`、`pl_text`、`pl_swipe`、`pl_shot`、`pl_shotl`、`pl_row`、`pl_ui`、`pl_tapl`、`pl_ctl`、`pl_home`、`pl_rotation`、`pl_rotation_reset`、`pl_net`、`pl_install`、`pl_check_others`。
  - 输入函数（点按、长按、按键、文字、滑动、按文字点、控件、回首页）和读屏函数（截图、控件树）先 `pl_need`，不是测试包就打印 `ABORT: foreground is <包名>` 返回 1。取不到前台时当成不是测试包。
  - `PL_APP` 是 `com.mystyle.purelive` 时所有函数拒绝（不发任何 adb 命令）。
  - 设置每次调用时读：`PL_DEVICE`（退回 `D`）、`PL_APP`（默认 `.v4dev`）、`PL_SHOTS`（默认 `./verify`）、`PL_BACK_XY`、`PL_FRONT_WAIT`。
  - `pl_install` 用 `aapt2 dump badging`（PATH 里的 `aapt2`、`aapt`，或 `ANDROID_HOME/build-tools/*/aapt2` 里最新的）读包名，不是 `.v4dev` 结尾就拒绝。
  - `pl_text` 只收英文字母、数字、空格和少数符号，空格换成 `%s`；防止中文和 shell 特殊字符传到手机上的 shell。
  - `pl_ui` 的控件树文件名带进程号，读完删掉；读完看 `user_rotation`，不是 0 就提示 `pl_rotation_reset`。
- `tools/device/resize.py`：`shrink`（缩到指定宽度存 JPG，删 PNG）、`row`（并排、矮的补黑）；Pillow 优先，没有用 `ffmpeg`/`ffprobe`，都没有时 `shrink` 保留 PNG 并提示。只用标准库加这两个可选工具。
- `tools/device/README.md`：用法、设置、函数表、规矩和教训（每次输入前查前台；横屏时 `uiautomator dump` 把 `user_rotation` 变成 3，横屏检查后改回 0，测旋转只用坐标点按；按包断网只拦新连接，已经打开的视频流继续播；别的会话可能同时在用手机）。
- `docs/inventory/OWNERS.toml`：`tools/device/` 归 Z04。

## 和任务书不一样的地方

- 设备没有默认值（任务书写默认 K90 的地址）：派活时要求仓库里不写死个人地址，所以 `PL_DEVICE` 没设时退回 `D`，两个都没有就拒绝。
- 多了 s.sh 里的 `pl_hold`、`pl_shotl`、`pl_row`、`pl_ctl`、`pl_home`，和 `pl_rotation*`、`pl_net`（把教训做成函数）。
- 截图和读控件树也先查前台（任务书只要求输入函数）：不截、不读别的应用的屏幕。

## 测试

- `tools/gate/tests/test_device.py` 18 个用例：PATH 前面放假的 `adb`、`aapt2`（记录参数、按设定回答前台、控件树、截图）。前台是别的应用时 `pl_tap` 等 7 个函数都不发命令；前台是测试包时发 `shell input tap 1 2`；`PL_APP=com.mystyle.purelive` 时 `pl_front`、`pl_tap`、`pl_fg`、`pl_net`、`pl_install` 拒绝且没有任何 adb 调用；没有设备时拒绝；`D` 兜底；`pl_front` 的 `am start`；`pl_install` 拒绝 `com.mystyle.purelive` 和旧的 `.next`、接受 `.v4dev`；`pl_tapl` 点中心；找不到时 `NOTFOUND`；旋转提示；`pl_text` 的空格和拒绝；`pl_net off` 只对测试包；`pl_shot` 宽 540；`row` 补齐高度；`shellcheck`（装了才跑，本机通过）。
- 本机的 Pillow 坏了（系统包和 Python 3.12 不配），截图测试走的是 `ffmpeg` 分支。

## 真机

没有运行（派活要求不碰 adb）。维护者按 [brief.md](brief.md)“真机验证”6 步在 K90 上试一遍；第 6 步现在的期望是打印 `REFUSED: PL_APP is com.mystyle.purelive`。

## 留给维护者

- PROCESS 第 10 节、S 组“风险和注意”（还写着 `~/tools/pl-adb.sh` 和旧包名 `.next`）改成引用 `tools/device/`。
- 仓库外的 `~/tools/pl-adb.sh` 建议改成一行 `source <仓库>/tools/device/pl-adb.sh`（再 `export PL_DEVICE=...`），s.sh 的函数都有对应的 `pl_*`。
