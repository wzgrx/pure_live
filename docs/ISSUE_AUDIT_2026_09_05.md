# 2026-09-05 上游最新 Issue 审计

本轮只读检查上游 Issue 与最新代码树，不拉取、不合并、不改写上游提交；维护分支
`wzgrx/pure_live` 继续作为实现基线。按日期优先审查上游新报告 #850、#849、#848，
并把“能在当前分支稳定复现”“当前环境未复现”“报告信息不足”明确分开。

## 结论

| Issue | 来源与首个错误状态 | 维护分支处置 | 验证边界 |
|---|---|---|---|
| [#850 Android 颜色选择器不能调透明度](https://github.com/liuchuancong/pure_live/issues/850) | 上游和维护分支共有的 UI/持久化缺陷。旧页面没有启用 `ColorPicker.enableOpacity`，却把色阶标题写成“选择透明度”；加载颜色保存 `color.hex` 又会丢失 alpha。依赖自身的代码输入框固定为 6 位且只在色轮页可编辑，不能完成 AARRGGBB 编辑 | 新增统一 `AppColorPickerDialog`：需要透明度的加载颜色提供真实 alpha 滑块和始终可见的 8 位 ARGB 输入；主题色与小窗弹幕颜色使用 6 位 RGB，避免与独立不透明度设置冲突；输入支持 `#`/`0x`，错误格式原地提示，取消恢复原值。三个页面不再各自复制不同的弹窗逻辑 | Widget 回归覆盖 RGB/ARGB 解析、完整 ARGB 输入、即时预览、非法值与取消恢复；K90 Pro 共享轮转 cycle 198 使用最终 APK 真实验证主题/加载两个入口、`0x800080DD` 输入和取消恢复。证据：`local-artifacts/diagnostics/android-color-picker-20260905T024906912/summary.json` |
| [#849 Windows 10 在 2.0 后不能启动](https://github.com/liuchuancong/pure_live/issues/849) | 报告没有 Windows build、系统版本、事件查看器、缺失 DLL 或启动日志，因此当前证据不足以定位到一个代码错误 | 不以猜测性的启动延迟、打包库回退或全局异常吞噬覆盖现有启动链。现有 Windows 3.1.8 x64 调试构建在本机连续运行 903.642 秒，181/181 样本响应，进程没有退出；工作集 619.69→616.37 MiB、私有字节 759.00→747.06 MiB | 当前 Windows 主机的通过不能代表报告者的 Win10 环境。现有证据：`local-artifacts/diagnostics/windows-regression/20260904T122150002Z-startup-idle-gpu-15m-pid39732-summary.json`；后续至少需要失败机器的精确 Windows build、CPU、安装/便携类型、Event Viewer fault module 与应用日志 |
| [#848 3.1.2 系统字体问题](https://github.com/liuchuancong/pure_live/issues/848) | 报告正文没有截图和字体名称，但代码审查发现一个确定的共享语义错误：Android 选择“System Default”时仍强制 `GoogleFonts.roboto()`，没有遵循设备系统字体和厂商 CJK fallback | 将字体解析提为可测试的单一函数：已下载字体继续按 ID 使用；Windows 保留 `Microsoft YaHei` 性能基线；Android 和其他平台的系统默认返回 `null`，交给 Flutter/操作系统字体回退链。移除只为强制 Roboto 引入的 `google_fonts` 运行依赖；被删除或失效的自定义字体 ID 也安全回落系统字体 | 确定性测试覆盖自定义字体、Android 系统默认、失效字体 ID 和 Windows CJK 回退。由于 #848 没有复现材料，本修复只声明纠正了可证实的“系统默认不是真默认”，不宣称覆盖报告者未描述的所有字体问题 |

## 颜色设置的产品语义

1. **应用主题色**：只保存 RGB；主题明暗和 Material 色板负责表面层级，不允许透明主题种子。
2. **加载动画颜色**：保存 ARGB；alpha 滑块、8 位代码和预览使用同一个 `Color` 状态。
3. **小窗弹幕颜色**：保存 RGB；透明度继续由已有 `pipDanmakuOpacity` 独立设置，避免两个 alpha 控件互相覆盖。
4. 所有确认操作保存当前值；取消、系统返回和点遮罩都返回原值，不产生半保存状态。

上游最新代码中的直播卡片颜色入口仍使用旧的 Flex 弹窗参数。该功能尚未合并到维护分支；
以后若选择入站，应直接复用统一弹窗，而不是把同一个缺陷重新带入。

## 字体修复为什么不继续强制 Roboto

Flutter 在未指定 `fontFamily` 时使用平台默认字体及其回退链。Android 的拉丁默认通常为
Roboto，但中文实际会由设备系统 CJK 字体补齐；显式指定通过网络字体包解析出的 Roboto
只改变了“系统默认”的语义，并不能为中文提供更完整字形。返回 `null` 同时减少一次运行时字体
解析和一个未再使用的直接依赖。自定义字体仍由现有下载、注册和持久化流程处理，不受影响。

参考：[Flutter 自定义字体指南](https://docs.flutter.dev/cookbook/design/fonts)、
[Flutter `TextStyle` 字体回退说明](https://api.flutter.dev/flutter/painting/TextStyle-class.html)、
[FlexColorPicker `enableOpacity` API](https://pub.dev/documentation/flex_color_picker/latest/flex_color_picker/ColorPicker-class.html)。

## 质量与构建证据

- `flutter analyze` 0 issue；颜色、字体、Material 兼容与弹幕设置相邻回归共 15/15 通过。
  记录：`local-artifacts/build-records/20260904T184020806Z-quality-focused.json`。
- Android arm64 Debug 构建通过，包内只有目标 ABI，16 个原生库最小 ELF LOAD 对齐不低于
  `0x4000`，Flutter 资源与版本清单完整。产物：
  `local-artifacts/3.1.8-4121/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`；
  构建记录：`local-artifacts/build-records/20260904T184549085Z-build-androidarm64-debug.json`。

## 本轮边界

- 没有同步上游分支，也没有提交上游 PR。
- 没有把缺少复现信息的 Windows 报告标成已解决。
- 本轮代码改动只覆盖已证实的颜色/字体根因；其他平台播放、录制和长时矩阵沿用总验收表继续执行。
