# Android 物理音量键媒体流路由审计（2026-09-12）

## 范围与 Issue 映射

- 修订前基线：`ff108761bc2b632b85e6a08540c10032664fa644`；应用修订提交：`d8de9855219db61d7c85dc7ab793c402dd1f18b3`。
- [Issue #858](https://github.com/liuchuancong/pure_live/issues/858) 报告 3.1.2 / Android 16 偶发进入应用后物理音量键没有可见效果，退出再进入后恢复。报告没有设备型号、播放器、音频输出、媒体流数值、按键日志或稳定复现序列，因此原设备现象继续标记 `not-reproduced`，本批不把源码缺口直接写成该设备唯一根因。
- 同轮只读复核的 [#857](https://github.com/liuchuancong/pure_live/issues/857) 已由 `RoomExternalOpener` 的 YY 官方 HTTPS 地址与真实 launcher 回归覆盖；[#850](https://github.com/liuchuancong/pure_live/issues/850) 已由应用自有 ARGB 输入、透明度选择和弹窗回归覆盖，均不重复修改。最新 [#860](https://github.com/liuchuancong/pure_live/issues/860) 缺少房间、日志和一致的平台信息，首页随机性与多平台弹幕断连仍分开保留为 `not-reproduced`，不以重试或刷新掩盖。
- 冻结上游对象 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 的 `MainActivity.onResume` 同样没有媒体流绑定，来源归为 `upstream-existing`；本轮没有 fetch、merge 或同步上游。

## 第一处可验证缺口

`MainActivity` 是承载播放、弹窗、浏览器返回、系统画中画和后台恢复的前台窗口。修订前它在 `onResume()` 只恢复显示模式与预测返回回调，没有为硬件音量控件建议目标音频流。播放器取得音频焦点时系统通常会选择媒体流，但播放器尚未取得焦点、从其他 Activity/画中画返回或音频路由变化的窗口存在依赖系统当前流选择的空档。

Android 官方文档要求媒体界面在可见生命周期调用 `setVolumeControlStream()`，并给出 `AudioManager.STREAM_MUSIC` 示例；该调用只为当前 Activity 窗口建议硬件音量控件所作用的流，电话等更高优先级系统场景仍可接管：[Handling changes in audio output](https://developer.android.com/media/platform/output)、[Activity.setVolumeControlStream](https://developer.android.com/reference/android/app/Activity#setVolumeControlStream%28int%29)。

本批先加入 `test/android_volume_key_routing_test.dart`，原实现稳定 **0/1**：第一条断言即发现 `MainActivity` 未导入 `AudioManager`，也没有在 `onResume` 绑定媒体流。这证明宿主合同缺口，不等于复现报告者的物理按钮与 OEM 音频栈。

## 修订设计

- `MainActivity.onResume()` 在 `super.onResume()` 后调用 `setVolumeControlStream(AudioManager.STREAM_MUSIC)`，每次窗口重新可见都恢复媒体流归属。
- 保留系统原生音量键分发和系统音量 UI；没有拦截 `KeyEvent`，没有直接调用 `AudioManager.setStreamVolume`，也没有改播放器、音频焦点、全局静音、房间音量、通知、后台服务或硬件按键步长。
- 对话框继承宿主 Activity 的建议流；浏览器、其他 Activity、系统画中画或后台往返后由 `onResume` 再次提交，不依赖一次性启动顺序。
- 无设置迁移、数据清理、Root/LSP/ADB/系统配置变化。回滚点仅为 `MainActivity.kt` 的一处导入与一处生命周期调用。

## 验证

- 新宿主合同：`test/android_volume_key_routing_test.dart` **1/1 PASS**。
- 最终同提交 `d8de9855` 聚焦回归：物理键宿主合同、音量控件替换生命周期、房间音量弹窗、备份导入边界和真实 `VideoController` 音量代次共 **71/71 PASS**；记录 `local-artifacts/build-records/20260912T084549112Z-quality-focused.json`。
- 最终源码内容的全库 `flutter analyze`：**No issues found**（50.7 秒）；前两次聚焦门禁只因新测试尚未执行写入式 Dart format 而在格式检查停止，执行写入式格式化后同一文件为 0 changes，未掩盖产品测试失败。
- 精确提交 `d8de9855219db61d7c85dc7ab793c402dd1f18b3` 已完成 Android arm64 Debug 构建：`3.1.8` / manifest code `6121`，`288805822` B，SHA-256 `5AFC1A42C8CFDC8D5671AD738297EEC2A9CAE6095B39A1A6DAB784968B099679`；16 个 arm64 原生库的 ELF LOAD 对齐均不低于 `0x4000`，Flutter assets 1262 项，完整性门禁通过。记录 `local-artifacts/build-records/20260912T084421621Z-build-androidarm64-debug.json`。
- 仓库审计：错误 0，保留既有警告 2；证据 `local-artifacts/repository-audits/20260912T084503728Z-focused.json`。

## 后续原生验收

Debug APK 只完成构建与内容核验，未安装。物理键场景加入 `AND-PLAY-16`：普通页面、播放前/播放中、弹窗、全屏、系统画中画、外部浏览器和前后台返回分别按一次加/减，核对系统媒体流数值、应用显示与实际听感；同时记录音频输出路由、来电/蓝牙等系统接管条件，并恢复测试前音量。软件注入按键与手指实按证据分栏。

因此 #858 保留“源码宿主缺口已修订、报告设备现象待物理按钮复验”；A3-04 保持 `RUN`，A7-02 保持 `NR`。宏观仍为 **20 PASS / 33 RUN / 9 NR，共 42 组未闭环**。未发布版本、安装 APK、操作手机或使用 Astra Light。

## 09-12 当前累计候选补证

后续已在精确 `3e41e848` 累计 arm64 Debug 上完成同签名覆盖安装和基础运行，详见[当前候选审计](CURRENT_ANDROID_CANDIDATE_2026_09_12.md)。在播放器尚未创建的首页通过 framework 注入一次音量增加，`STREAM_MUSIC` 从 0 到 10，铃声流保持 0；按步降低后音乐流回到 0/muted，应用进程、前台与 stay-awake 均恢复。该结果将“首页软件输入→宿主建议流→媒体流”从待验推进为通过；实体按钮及播放中、弹窗、全屏、PiP、外部 Activity、前后台和不同输出路由仍待执行，因此上述 Issue 分类、A3-04/A7-02 和宏观计数不变。
