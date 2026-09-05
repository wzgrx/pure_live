# 弹幕渲染器吞掉播放器键盘事件（2026-09-06）

## 根因与来源

- 起点 `f91dd15b69b1cffb3c6653953cffc6307e03ff09`，冻结上游 `c6c9bd70`，不合并。
- 分类 `upstream-existing`：上游和本分支的 `FlameBarrageWidget` 均使用
  `GameWidget(game: _engine)`，`BarrageEngine extends FlameGame with TapCallbacks`，没有
  键盘处理契约。本分支可追溯到 `f8db47da` 的弹幕组件引入，不是虎牙服务器错误。
- 锁定 Flame 1.38.2 的 `GameWidget` 默认 `autofocus=true`；取得主焦点后，游戏没有
  `KeyboardEvents` 时 `_handleKeyEvent` 直接返回 `KeyEventResult.handled`。
  弹幕层只包 `IgnorePointer`，这仅屏蔽指针，不屏蔽键盘焦点。
- 结果：真实弹幕画布先于外层 `VideoKeyboardShortcuts` 消费 Escape、媒体键等。此前只用
  普通占位内容测试路由/FocusScope，遗漏了真实 Flame 组件，导致 Widget 通过但客户端失败。

## 实际客户端证据

- 本机干净 `f91dd15b` Debug 构建，命令
  `tool/build_local_release.ps1 -Target WindowsX64 -Configuration Debug -SkipQuality -SkipInstaller`。
  引用上一轮 34/34 定向回归，不冒充本轮完整发布门禁。
- 构建记录 `20260905T180914766Z-build-windowsx64-debug.json`，309.715 秒（Flutter 264.4 秒），
  结束活跃重型进程 0。保留 CMP0175、MSB8028、C4244、Firebase 缺 PDB 的 LNK4099 警告。
- ZIP 141,195,445 B，SHA256 `B3C0480BD1815B68FE4B2BE8DC22D7C9343B949302A067B02C515CED452DD678`；
  runner `09D8AABD6F8A3E8793723ED7B0EB06ED5AB53A6AE4157E767E8CC31D10F22651`；
  kernel blob `988E6648A5EFFFDB6D4EA62B7C0793A891CFC1E19A4563A5A92041F3022C874A`。
- 独立目录 `local-artifacts/candidates/windows-f91dd15-debug`，实例 `acceptance_f91dd15`，
  PID 41076；预置空插件配置避免导入主实例，用户安装目录和配置未动。
- 虎牙楚河公开房间 TX FLV 30M：普通页视频→音频→视频实际成功；耳机悬停超过 5.2 秒，
  操作栏保持。进入全屏成功，但 Escape 仍失败；双击退出成功。
- 只读调用该调试实例现有的 `ext.flutter.debugDumpFocusTree`，主焦点链明确为
  `Focus ← FocusScope ← GameWidget<BarrageEngine> ← ... ← FlameBarrageWidget`。
  证据 `local-artifacts/diagnostics/windows-f91dd15-20260906/focus-fullscreen.json`。
  未使用主焦点注入或强行抢焦点来制造通过。最初 VM evaluate 因无编译服务返回错误，改用
  Flutter 已注册的只读诊断扩展；该工具错误不算产品错误。
- 小窗进入、中心播放/暂停、右上退出小窗恢复普通页成功，恢复后真实弹幕列表继续更新。
  小窗中心是播放/暂停，不是恢复按钮；该误读已依据源码和实际状态纠正。
- 正常返回首页、标题栏退出并确认；PID 消失。该 Debug 只验证功能，不测 Release 帧率/功耗。

## 确定性复现与修复设计

- 新测试装入真实 `FlameBarrageWidget`、实际 `VideoKeyboardShortcuts`，只替身最终模式控制器。
  指针交互关闭/开启两种情况均红测：期望 fullscreen exits=1，实际 0；构建前异常检查通过。
  记录 `20260905T181529511Z-quality-focused.json`。
- 渲染边界设置 `GameWidget(autofocus:false)`，并使用 `ExcludeFocus` 防止后续 Tab 或重新
  挂载使渲染器取得焦点。保留触摸/鼠标弹幕操作、画布渲染与 ticker，不更改外层路由返回规则。
- 不加入全局 HardwareKeyboard 监听；避免 Escape 同时关闭菜单和退出直播，避免抢走输入框焦点。
- 新增两画布挂载时保留本地输入框焦点及文字输入测试；相邻回归覆盖既有弹幕帧率/缓存、
  菜单 Escape、竖屏恢复及上一轮控制栏悬停。
- 参考 [Flame GameWidget 文档](https://docs.flame-engine.org/latest/flame/game_widget.html)，
  实际行为以锁定的 1.38.2 源码为准。此项修复适用于各平台共用弹幕画布，不触及平台取流。

## 验收边界与回滚

六组 **42/42** 定向回归通过，`20260905T181838454Z-quality-focused.json`，86.087 秒，
一次 analyze 41.5 秒无诊断，结束活跃重型进程 0。两种真实画布 Escape 红测转绿；
双画布挂载期间输入框继续持有主焦点并接收文字。源码/自动化与原生客户端结果分层登记。

本次 `f91dd15b` 候选在补丁之前构建，用于复现；修复后独立构建与复验见下节。
Android 实际呈现与全平台 3.2.0 正式交付仍独立保留。
回滚只撤销弹幕画布的焦点隔离和对应测试，保留取流、悬停、模式状态机及缓存修复。

## 修复后的真实 Windows 闭环

- 干净业务提交 `1c22bffe19b9a2f66635730f3fd34811edfcc3b6`，相同 Debug 构建命令与独立目录
  `local-artifacts/candidates/windows-1c22bffe-debug`；实例 `acceptance_1c22bffe`，PID 17292。
- 记录 `20260905T182329731Z-build-windowsx64-debug.json`，含互斥排队 189.548 秒，Flutter
  增量阶段 55.7 秒，结束活跃重型进程 0；没有 clean、并发打包或占用其他项目进程。
- 新 ZIP 141,176,274 B，SHA256 `F595332B49588636552CD23AB3385EB90AED71B567CAE7C4470C8A66C95942BF`；
  新 kernel blob `00F6C5FBAC747734D9B47D06B2649457BD7E6D3AC815FC0F356E063B2EB15412`，
  与复现候选不同。此目录中的旧 Release ZIP、setup 和 APK 不属于本轮构建。
- 同一公开虎牙房间、弹幕画布已显示：按钮进入全屏后 **Escape 返回普通页成功**；
  **空格暂停、再次空格恢复**，原生 playing=false/true 时间分别为 02:25:15.810、02:25:26.782。
- 画质菜单打开后 **Escape 只关闭菜单，直播间保留**；再按 Escape **返回热门页**，
  没有回到“全局按键监听一键穿透多层”的旧问题。
- 再取只读 focus tree，主焦点链为 `VideoControllerPanel` 中的 Focus，而非 Flame 画布；
  证据 `local-artifacts/diagnostics/windows-1c22bffe-20260906/focus-after-menu.json`。
- 从热门页正常确认退出，操作系统查询两个测试 PID 均已消失。本轮两次构建串行、只运行
  独立候选，未改用户安装目录、账户配置和手机。
- 这些结果关闭上述 Windows 键盘场景，不外推为全平台键盘、音频连续性、性能或全部功能
  验收完成。Debug 帧率/CPU 不作为 Release 性能数字；3.2.0 保持未发布。
