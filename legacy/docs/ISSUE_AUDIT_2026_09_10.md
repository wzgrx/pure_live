# Issue 增量及音量链路审查（2026-09-10）

## 查询范围

在 `a2b539cb2e63c9a1b685da4e417ee909b8739f56` 上只读查询 GitHub REST：两仓 open、updated 降序、每页 30。2026-09-10 09:16–09:18 UTC 的查询窗口，维护仓库返回 0，上游返回 18（均非 PR，低于页长）。相较 [09-09 记录](ISSUE_AUDIT_2026_09_09.md) 增加 #858、#859；本轮详细阅读这两条正文及 #849 评论增量，不宣称重新审读其余 16 条的全部附件/历史。

原始响应保存在忽略目录 `local-artifacts/candidates/android-a2b539cb/issues/`。没有评论、关闭 Issue、合并上游或操作设备；数量不是剩余 Bug 总数。

## #858：偶发硬件音量键无效

[原报告](https://github.com/liuchuancong/pure_live/issues/858)，09-09 00:16:34 UTC：3.1.2、Android 16，偶尔进入应用后音量键无效，退出再进恢复。缺少型号、播放器、音频输出路由、精确步骤和输入/媒体音量日志；当前维护源码 3.1.8+4121、所列手机 Android 17 与报告环境不同。分类 **not-reproduced**，保留排查，不标记已修复。

本轮限定源码审查：

- `MainActivity.kt` 继承 `AudioServiceActivity`，本文件未覆写 `dispatchKeyEvent/onKeyDown/onKeyUp/setVolumeControlStream`；不外推为系统、父类和所有插件都未处理按键。
- `video_keyboard.dart` 绑定媒体播放键及方向上/下键；方向键调用音量 setter，不是手机硬件音量键绑定。
- `video_controller.dart` 移动端使用 `VolumeController.instance`：初始化先注册监听、读取系统音量，再按房间偏好设音量；监听保存房间值。锁定插件 `volume_controller 3.6.1` 的 Android setter 使用 `AudioManager.STREAM_MUSIC`，`showSystemUI=false` 只改变 setter 的 UI flag，当前代码不支持“它关闭了物理按键”的推断。
- `_initVolumeController` 在 `getVolume` 返回与 `setVolume` 之间缺少局部退出/归属检查；外层退出检查在整个初始化之后。插件监听为单例，新增监听会取消旧监听。这是相邻生命周期审查线索，尚无本轮可复现用例，也不等于 #858 的根因。

后续快速方案：先补确定性迟到读取/退出/房间切换测试；若再需原生证据，在已取得的前台窗口中记录原音量及输出路由，分别比较按键输入、系统媒体流数值与应用显示，在普通页/全屏/前后台返回中每次只做单步增减并恢复本次改动。软件注入按键只覆盖 framework 路径，与现场物理按钮证据分开记录；缺少按钮实按时明确保留该缺口。失败时记录第一处分叉，不先修改系统按键分发或音频配置。

## #859：iOS 抖音全屏播放闪退

[原报告](https://github.com/liuchuancong/pure_live/issues/859)，09-09 13:23:14 UTC：iPhone 12 / iOS 16.5.1，版本只写“最新”，全屏播放抖音一段时间后退出。09-11 的两条评论已补充确认实际使用 **MPV + VideoToolbox 硬解**；仍缺精确 build、房间、持续时间、完整 MPV 自定义项、崩溃/Jetsam 日志及普通页/全屏对照。分类保持 **community-platform / not-reproduced**。

后续源码审查确认一处独立、可确定复现的跨平台设置缺口：旧设置或备份可把 Android `playerCompatMode=true`、`mediacodec_embed` / `mediacodec`，或 Windows `wasapi` / `d3d11va` / RTX VSR 带入 iOS；MPV 重置又会写入 `vo=gpu`，而当前锁定的 media_kit iOS Flutter 纹理路径使用 `vo=libmpv`。提交 `233efa57` 增加平台 MPV 配置画像，在设置启动、导入、导出、重置、UI 选择和 MediaKit 创建处共同归一化；iOS 只持久化 `libmpv`，音频仅保留 `auto/audiounit/null`，硬解仅保留通用项及 `videotoolbox` / `videotoolbox-copy`。Android 兼容模式和 Windows RTX VSR 同时增加实际平台门禁，合法的 iOS `videotoolbox` 选择保持不变。

上游 media-kit 的公开 [#1361](https://github.com/media-kit/media-kit/issues/1361) 记录了 iPhone 11 / iOS 16.6.1 在销毁 MPV render context 时的 `free_option_data` / `mpv_render_context_free` 竞态崩溃，现行 Darwin 输出代码仍保留相邻的异步释放结构。该线索与“iOS 16 + MPV + 播放后闪退”相邻，但当前报告没有调用栈、Jetsam 或销毁时序，故只登记为上游对照，不据此判定 #859 根因，也未在 Windows 环境直接修改 Swift 销毁流程。

验证保留完整红绿链：修改前 `20260912T093438195Z-quality-focused.json` 为 **9 PASS / 1 FAIL**，精确落在 iOS 导入仍保留 Android 兼容模式；首轮修订 `20260912T093904090Z-quality-focused.json` 又由缺失 `defaultTargetPlatform` 导入在 analyze 阶段失败；补齐后同内容全库 analyze 无问题、六文件 **147/147 PASS**（`20260912T094342600Z-quality-focused.json`），精确提交 `233efa57` 再跑六文件 **147/147 PASS**（`20260912T094651341Z-quality-focused.json`）。两次门禁实际 ADB 命令均为 0；本轮没有 iOS 构建、原生运行或闪退复现。#859 继续等待报告设备的 crash/Jetsam、房间、时长、普通页/全屏对照和完整设置快照；社区平台级别仅说明本轮证据来源，3.2.0 全平台验收范围保持。

## #849：评论增量

[Windows 启动报告](https://github.com/liuchuancong/pure_live/issues/849) 从 9 条变为 10 条评论。[新增回复](https://github.com/liuchuancong/pure_live/issues/849#issuecomment-5594641446) 的图片上传失败，没有新增可检查的错误截图或模块证据。继续保留 [Windows 候选审计](WINDOWS_RELEASE_CPU_AUDIT_2026_09_07.md) 的 app-local 运行库及实际加载结论，仅适用已验证环境；其他报告者仍待复验。没有安装用户系统运行库。

## 与当前门禁分层

完整门禁现已在 `a2b539cb` 实际执行：全库 analyze 无问题，Flutter 4069 通过、3 失败（CC 移动分页两项、播放器默认引擎替换一项），公开接口阶段未到达。记录 `local-artifacts/build-records/20260910T092336871Z-quality-full.json`。这些测试失败独立于上述 Issue；优先修复测试/契约偏差后重新验证，未构建新的 APK，更未把源码审查计为设备 PASS。YY/CC 的原生缺口继续引用 [09-08 审计](ISSUE_AUDIT_2026_09_08.md)。
