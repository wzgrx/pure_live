# Android 主弹幕模板与辅助语义原生审计（2026-09-12）

## 结论

精确产品提交 `cc3ab5b221eff2368a5c595fa4c690440a972838` 修复主弹幕设置的模板事务和辅助语义，并已构建为 Android arm64 Debug 候选。随后在 `25102RKBEC / myron / Android 17` 上通过显式网络 ADB `192.168.1.2:5555` 完成同签名覆盖安装、小窗弹幕设置回归以及真实 Bilibili 直播间中的主弹幕模板保存/修改/恢复/重启往返。可重复原生脚本提交为 `9cc76caa85e7486b839aec5dda12918a4f973174`。

A2-04 继续标记 `RUN`：本轮已关闭 Android 主弹幕模板、嵌入页恢复入口、主设置开关/滑块/计数器具名语义和小窗设置回归；Windows 双栏 GUI、颜色及其余滑块的逐项原生输入、真实系统小窗中的完整视觉对照和长时性能仍继续。宏观状态保持 **20 PASS / 34 RUN / 8 NR，42 组未闭环**。本批 Astra Light 使用 **0** 次。

## 根因与修订

修改前存在四个相互关联的缺口：

1. 直播间嵌入式弹幕设置隐藏“恢复已保存模板”，与独立页面能力不一致。
2. 模板恢复按 JSON 字段依次写入 Rx；后部字段损坏时，前部字段已经改变，形成部分提交。
3. 保存内容未包含纯文字模式；旧模板新增字段没有兼容回退与完整数值边界。
4. 自定义 `Row + Switch`、主滑块和 `CountButton` 没有完整的设置名、当前值及增减动作语义。

`cc3ab5b2` 完成以下修订：

- 新增 schema 2 的 `DanmakuViewingTemplate`，在任何设置写入前完整解析类型、有限值、整数和范围；旧模板缺失的新字段保留当前值。
- 保存/恢复覆盖纯文字、区域、上下留白、速度、字号、字重、描边宽度、透明度、描边开关、FPS 与自动 FPS；恢复一次性提交完整快照。
- 嵌入页与独立页始终提供恢复动作；主开关改为整行可点的 `SwitchListTile`。
- 七类主滑块公布“设置名 + 格式化值”，计数器公布具名当前值及增加/减少动作；小窗统一颜色和最大显示数同步补齐语义。
- 启动、当前格式备份和旧格式提取都将主弹幕数值归一化到实际控件范围，非有限值回到集中默认值。

## 确定性回归

有效红灯记录为 `local-artifacts/build-records/20260912T113326275Z-quality-focused.json`：

- 嵌入式设置中找不到恢复入口；
- 一个后部 `opacity` 字段损坏的模板在报错前已改变区域、留白、速度、字号等前部设置，直接证明部分提交。

修订后，精确当前工具提交 `9cc76caa` 运行：

```powershell
.\tool\local_ci.ps1 -Scope Focused -TestPath @(
  'test/danmaku_settings_surface_test.dart',
  'test/danmaku_viewing_preset_test.dart',
  'test/pip_danmaku_preview_test.dart',
  'test/danmaku_settings_controller_test.dart',
  'test/danmaku_refresh_rate_policy_test.dart',
  'test/backup_import_validation_test.dart',
  'test/translation_contract_test.dart'
) -Analyze -SkipPubGet
```

结果：

- Flutter：**52 / 52 PASS**；
- Analyze：`No issues found`；
- 仓库审计：4802 个跟踪文件、0 个未跟踪文件、0 error；
- 质量记录：`local-artifacts/build-records/20260912T121230459Z-quality-focused.json`；
- 仓库审计：`local-artifacts/repository-audits/20260912T121102267Z-focused.json`。

新增覆盖包括模板全部字段往返、旧模板回退、损坏/越界/非整数模板整体拒绝、非有限备份值归一化、嵌入页恢复入口、整行开关、滑块与计数器语义、小窗颜色与计数器语义。

## 候选构建与覆盖安装

Android 候选严格绑定产品提交 `cc3ab5b2`：

| 项目 | 值 |
|---|---|
| 文件 | `local-artifacts/3.1.8-4121/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk` |
| 版本 | `3.1.8+4121` |
| Manifest versionCode | `6121` |
| ABI | `arm64-v8a` |
| 大小 | `288808125` B |
| SHA-256 | `168FBAE87863684A76D8A3997D63CE639B4BA3FA9F2471303BBCD84288C4658D` |
| ELF 最小 LOAD 对齐 | `0x4000` |
| 构建记录 | `local-artifacts/build-records/20260912T115639759Z-build-androidarm64-debug.json` |

`tool/android_pip_danmaku_settings_smoke.ps1` 使用 `adb install -r -t` 覆盖安装成功；`firstInstallTime` 保持 `2026-07-21 18:07:53`，安装前规范 Hive 与安装后首启前 SHA-256 均为 `701C666A...8EA60C`，设备 `base.apk` 哈希与候选完全相同。

## 小窗弹幕设置原生回归

证据：`local-artifacts/diagnostics/android-pip-danmaku-settings-20260912T195738455/summary.json`。

- 主开关状态序列：开 → 关 → 进程重启仍关 → 开 → 进程重启仍开；Switch 数为 4 → 1 → 1 → 4 → 4。
- 四个可见 Switch 均具名；字号滑块原生语义为 `字体大小, 12.0`。
- 恢复确认取消保持自定义关闭状态；确认后恢复 14 项小窗默认值并跨进程保持。
- 候选覆盖安装保留数据，设备 APK 与候选哈希一致。
- 结束时规范 Hive 精确恢复，Pure Live 进程退出。

## 主弹幕模板原生往返

可重复脚本：`tool/android_danmaku_template_settings_smoke.ps1`。通过记录：`local-artifacts/diagnostics/android-danmaku-template-settings-20260912T200727935/summary.json`。

脚本在真实 Bilibili 直播间进入“弹幕设置”标签并确认：

| 阶段 | 纯文字 | 顶部留白 | 区域滑块原生语义 | 模板动作 |
|---|---:|---:|---|---|
| 基线 | 关 | 0 | `画面顶部占用高度, 41%` | 保存、恢复均可见 |
| 自定义 | 开 | 1 | `画面顶部占用高度, 41%` | 使用具名增加动作 |
| 立即恢复 | 关 | 0 | `画面顶部占用高度, 41%` | 两项一起回到保存值 |
| 进程重启 | 关 | 0 | `画面顶部占用高度, 41%` | 恢复结果持续存在 |

计数器同时暴露 `顶部留白（像素）, 0/1`、`增加顶部留白（像素）` 与 `减少顶部留白（像素）`。纯文字整行点击立即改变 Switch 状态；恢复动作一次将该开关与计数器共同还原，随后强制结束并重新进入直播间仍保持。

前两轮脚本迭代分别记录于 `...T200328381` 与 `...T200559315`：第一轮只因页面标题断言使用了较短别名，第二轮只因计数器解析先匹配到标题节点；两轮 `settingsFileRestoredExactly=true`、`appStopped=true`。修正证据解析后第三轮完整通过。

## 设备与清理边界

- 每轮实际命令均绑定 `-s 192.168.1.2:5555`，身份再次确认为 `25102RKBEC / myron`，`su -c id` 为 `uid=0(root)`。
- 设备同时出现固定 IP 和 mDNS 两条 transport；测试始终使用明确固定 IP，不按列表顺序选择。
- 全部原生操作通过 `tool/run_android_device_test_turn.ps1 -NoRotation` 取得设备轮次；未重启手机/adbd、未更改 Wi-Fi/ADB 端口/调试授权、未执行 `adb kill-server`，也未更新 Root/LSP/模块。
- 每轮先停止 Pure Live 再复制规范 Hive；结束时按原 UID/GID/mode 写回并 `restorecon`，原始/恢复 SHA-256 均为 `701C666A664A784F5E466D5274F5A13C015DEAAF893BFBA51801ED989D8EA60C`。
- 最终 `stay_on_while_plugged_in=0`、Pure Live 无进程、前台为 `com.miui.home/.launcher.Launcher`。

## GitHub 同步

- 产品修复：`cc3ab5b2` 已推送 `origin/master`。
- 原生回归脚本：`9cc76caa` 已推送 `origin/master`。
- 两次均在推送后用 `git ls-remote origin refs/heads/master` 核对远端完整 SHA；本报告提交后继续执行同样核对。
