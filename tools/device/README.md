# 装机和截图助手（tools/device）

真机验证用的 adb 助手（Z04.1）。`source` 之后提供一组 `pl_*` 函数：装测试包、把测试包切到前台、点按和输入、截图并缩小、按文字找控件点。**每次输入前都检查前台是测试包**，不是就不发任何命令。

```bash
source tools/device/pl-adb.sh
export PL_DEVICE=<设备序列号或 地址:端口>   # 也可以用 D=...；没有默认值
pl_check_others          # 先看有没有别的程序在操作手机
pl_front                 # 测试包切到前台（检查成功打印 front: 包名）
pl_tapl '设置'           # 按文字点
pl_shot 01               # verify/01.jpg，宽 540
```

## 设置

每次调用时读取，改了不用重新 `source`；也可以只对一条命令生效：`PL_APP=... pl_front`。

| 变量 | 默认 | 说明 |
|---|---|---|
| `PL_DEVICE` | 没有（退回 `D`） | `adb -s` 用的设备；两个都没设时所有函数拒绝 |
| `PL_APP` | `com.mystyle.purelive.v4dev` | 被测的包；设成 `com.mystyle.purelive`（用户自己的 3.x 和正式包）时所有函数拒绝 |
| `PL_SHOTS` | `./verify` | 截图目录；做任务验证时放任务文件夹的 `verify/` |
| `PL_BACK_XY` | `80 228` | `pl_home` 点的标题栏返回箭头位置（K90 竖屏） |
| `PL_FRONT_WAIT` | `2` | `pl_front` 启动后等几秒再检查 |

## 函数

| 函数 | 做什么 | 先查前台 |
|---|---|---|
| `pl_env` | 打印当前设置 | — |
| `pl_fg` | 打印前台窗口的包名（`dumpsys window` 的 `mCurrentFocus`；不是应用窗口时为空） | — |
| `pl_need` | 前台是 `PL_APP` 才成功，否则打印 `ABORT: foreground is <包名>` | — |
| `pl_front` | 用 `am start` 启动测试包的 `MainActivity`，等 `PL_FRONT_WAIT` 秒后再查一次前台；不用返回键 | 启动后查 |
| `pl_tap X Y` | 点按 | 是 |
| `pl_hold X Y [毫秒]` | 长按（默认 900 毫秒） | 是 |
| `pl_key 代码` | 按键（数字或 `KEYCODE_*`） | 是 |
| `pl_text 文字` | 输入文字：只能英文字母、数字、空格和 `. _ @ : / + = -`（`input text` 打不了中文） | 是 |
| `pl_swipe X1 Y1 X2 Y2 [毫秒]` | 滑动 | 是 |
| `pl_shot 名字` | 竖屏截图，存成 `PL_SHOTS/名字.jpg`，宽 540 | 是 |
| `pl_shotl 名字` | 横屏截图，宽 1080 | 是 |
| `pl_row 输出 图...` | 几张图并排（每张宽 540，矮的下面补黑），存成 `PL_SHOTS/输出.jpg` | — |
| `pl_ui [正则]` | 列出屏幕上的文字和位置：`text="设置" "[x1,y1][x2,y2]"`（或 `content-desc`） | 是 |
| `pl_tapl 正则` | 点第一个匹配的控件的中心；找不到打印 `NOTFOUND` | 是（两次） |
| `pl_ctl 标签 [X Y]` | 点播放器控件；控件没显示时先点画面（默认 600 450）把控件叫出来 | 是 |
| `pl_home` | 切到前台，再点标题栏返回箭头（最多 6 次）直到看到底部导航 | 是 |
| `pl_rotation`、`pl_rotation_reset` | 看 `user_rotation`；改回 0（竖屏） | — |
| `pl_net off`、`pl_net on` | 只断开、恢复测试包的网络（adb 走 Wi-Fi 不受影响） | — |
| `pl_install APK` | 先用 `aapt2 dump badging`（或 `aapt`）读包名，不是 `.v4dev` 结尾就拒绝，然后 `adb install -r` | — |
| `pl_check_others [行数]` | 列出最近的 `adbd service requested`，看有没有别的 adb 客户端在操作手机 | — |

截图缩放用 `resize.py`：装了 Pillow 用 Pillow，没有就用 `ffmpeg`；都没有时 `pl_shot` 保留原始 PNG 并提示。

## 规矩和教训

- **每次输入前检查前台。** 2026-09-25 点按落到了用户的哔哩哔哩个人页和输入法的短信验证码页；之后所有输入都先 `pl_need`。截图和读控件树也查：不截、不读别的应用的屏幕。取不到前台（通知栏拉下、权限弹窗、锁屏）一律当成“不是测试包”。不要绕开这些函数直接用 `adb shell input`。
- **不碰用户的 3.x 和正式包**（D-019）：`com.mystyle.purelive` 不输入、不安装、不卸载、不清数据。`pl_install` 只装 `.v4dev` 结尾的包。
- **横屏时读控件树会锁住旋转。** 屏幕横着的时候 `uiautomator dump`（`pl_ui`、`pl_tapl`、`pl_ctl`、`pl_home`）会把 `user_rotation` 变成 3，之后手机一直横着。横屏检查做完要 `pl_rotation_reset`（`pl_ui` 发现不是 0 时会提示）；**测旋转时只用坐标点按**（`pl_tap`），不要读控件树，否则测到的是被锁住的方向。
- **断网只拦新连接。** `pl_net off`（`cmd connectivity set-chain3-enabled true` 加 `set-package-networking-enabled false <包名>`）只拦新建的连接，已经打开的视频流会继续播。要测“断网后重连”，先断网再让应用重新建连接（切换直播间、重新进入），或者等平台自己断开。用完 `pl_net on`；`chain3` 留着开着没有影响，确认没有别人在用时可以 `adb -s <设备> shell cmd connectivity set-chain3-enabled false` 关掉。
- **别的会话可能同时在用这台手机。** 开始前 `pl_check_others`；每条命令都带 `-s` 设备；控件树文件名带进程号，不和别人的冲突；全局设置（旋转、`wm size`、`wm density`）改了要改回来，不要改别人正在依赖的设置。
- `pl_home` 不按返回键：在首页按返回会退出应用，前台就变成桌面了。

## 测试

`tools/gate/tests/test_device.py`：PATH 前面放假的 `adb`、`aapt2`，不连真实设备。覆盖：前台不是测试包时不发输入；`PL_APP` 是 `com.mystyle.purelive` 时全部拒绝；`pl_install` 拒绝包名不对的 APK；按文字点的坐标；截图宽 540；`shellcheck`（装了才跑）。
