# 分享口令交接与导入弹窗审计（2026-09-13）

## 结论

产品提交 `5e1b942328d1f8c18c7a1906e96f1b4c1117c67f` 修正了分享口令在剪贴板读取、
系统分享、失败重试和桌面导入弹窗上的生命周期缺口。分享口令现在只在消费者真正接收后记为已处理；
并发检查合并为单一事务；自分享抑制使用有界 SHA-256 历史；平台交接失败会留在可重试状态并显示双语
反馈。桌面导入弹窗改为发起页面所有的标准路由，窄窗口和 3 倍英文文字下仍可滚动、取消或进入房间。

专项与相邻七文件最终 **40/40 PASS**，全库 analyze 为 `No issues found`。同一精确提交构建的
Android arm64 Debug 已保留数据覆盖 K90；真实 Bilibili 房间的分享动作打开
`com.android.intentresolver/.ChooserActivity`，口令预览和系统分享目标可见，随后只关闭系统面板并
返回原房间详情，没有选择外部应用。候选、设备 `base.apk` 与期望 SHA-256 完全一致，规范 Hive 最终
逐字节恢复，应用停止且 stay-awake 恢复为 0。

该证据补充 A1-05/A2-01 的 Android 分享路径，但 Windows 原生剪贴板导入、双实例、真实接收与异常
平台通道仍继续，因此两组保持 `RUN`；宏观计数保持 **20 PASS / 40 RUN / 2 NR**，仍有 42 组未闭环。

## 稳定复现与根因

1. 旧 `checkClipboard` 在调用消费者之前写入生命周期哈希。消费者抛错或路由暂时不可用后，同一口令
   会被永久跳过；有效红测第一次得到调用次数 1，而期望为 2。
2. 两次生命周期/窗口事件可同时读取剪贴板并重复打开导入流程；读取与消费之间没有 single-flight。
3. 自分享 MD5 集合没有容量边界，还重复记录仅空白不同、实际哈希相同的字符串；长时运行会持续增长。
4. 系统剪贴板或分享面板抛错时，调用方没有等待结果；旧实现又在交接前先加入黑名单，使失败口令随后
   也被当作成功自分享。
5. 只验证签名而不检查房间身份，空平台、空 room ID 和占位 room ID 可进入导入路由。
6. 桌面弹窗依赖全局 `Get.context!`、固定 320 px 内容和多组固定 `Row`；窄窗口/大字号可能越界，
   延迟 resume 检查在 State 销毁后仍可运行，弹窗标志只依赖 `.then` 清理。

## 产品修订

- 剪贴板检查合并为一个活动 Future；消费者成功后才提交已处理哈希，失败保留下一次重试机会。
- 导入与导出统一要求有效平台和 room ID；空值以及 `0/null/undefined/nan/none` room ID 在平台通道前
  被拦截。
- 自分享使用裁剪文本的 SHA-256，`LinkedHashSet` 默认最多 128 项；成功交接后才提交，最近项保持
  抑制，最旧项按边界淘汰。
- 桌面剪贴板写入、移动端系统分享、分享后剪贴板读取和反馈回调分别收口。主交接失败返回 `false` 并
  使用 `share_failed` 双语提示；系统分享已成功后的附加剪贴板读取失败不反转结果。
- `DesktopWindowMixin` 持有并取消 resume 计时器，所有延迟入口检查 `mounted`；导入弹窗由当前
  State 的 `BuildContext` 打开，在 `finally` 中释放单弹窗门禁，只对显式 `true` 结果导航。
- 新弹窗使用可滚动 `AlertDialog`、360 px 最大正文宽度、响应式房间身份/元数据布局和 48 px 最小操作
  面，头像使用共享回退组件。

## 确定性回归

| 项目 | 结果 |
| --- | --- |
| 有效红灯 | 消费者首次失败后第二次调用仍被抑制：实际 1、期望 2 |
| 分享处理器 | 重试、并发合并、无效身份、桌面/移动成功与失败、有界历史、双语反馈全部通过 |
| 导入弹窗 | 320×480、3.0 倍英文、长标题/主播/平台/room ID；内容可滚动，Cancel/Enter 可命中并返回明确布尔值 |
| 相邻七文件 | **40/40 PASS** |
| 全库静态分析 | `No issues found` |
| focused 记录 | `local-artifacts/build-records/20260912T205916510Z-quality-focused.json` |

## 构建与 K90 原生验收

`tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality` 绑定精确产品提交：

| 项目 | 结果 |
| --- | --- |
| 版本 / manifest code | `3.1.8+4121` / `6121` |
| APK | `288832063` B |
| SHA-256 | `5A8B6A081495DD1D68B07D6BEBEE75EC1957FF212193B82388D3FD9409D3A23A` |
| ABI / 原生库 | `arm64-v8a` / 16；最小 ELF LOAD `0x4000` |
| Flutter 资源 | 1262 项 / `206882176` B |
| 构建记录 | `local-artifacts/build-records/20260912T205018910Z-build-androidarm64-debug.json` |

最终原生结果：
`local-artifacts/diagnostics/android-room-tag-assignment-20260913T050020522/summary.json`。

- 测试前核对 `25102RKBEC / myron / uid=0(root)`；全部 ADB 入口显式绑定
  `192.168.1.2:5555`。
- `install -r -t` 返回 `Success`，`firstInstallTime` 保持 `2026-07-21 18:07:53`；设备
  `base.apk` 与上述候选哈希一致，首次启动前规范 Hive 哈希未变化。
- 真实热门 Bilibili 卡片长按后，“分享”为 `144×144`，完全位于 1200×2608 可视区域。
- 点击分享后顶层组件为 `com.android.intentresolver/.ChooserActivity`，根包为
  `com.android.intentresolver`；XML 长 12,537 字符，标题“分享”、390 字符口令预览、复制文字及系统
  目标列表均存在。测试只读取并截图系统面板，没有选取任何分享目标。
- 系统返回关闭面板后，Pure Live 回到前台；重新长按同一卡片，分享/标签/关注/关闭四个动作继续可达。
- 为避免把工具改动误记成产品回归，同轮还再次执行直接关注、取消关注提示的取消/确认、再次关注、标签
  新建/自动选中/确认/重开保持；所有业务和清理检查均为 `true`，应用日志无 FATAL/ANR。
- Hive 开始、覆盖安装后与恢复后的 SHA-256 均为
  `19F40EA9E29A6017317ACB14AEBA8CF4378A6EEAA96BA15E09C7CD2312D1F050`；uid/gid/mode 和
  SELinux context 保持。结束时应用无进程，stay-awake 为 0。

系统分享截图为同目录 `share-surface-1.png`，UI 层级为 `share-surface-1.xml`。

## 工具与验收边界

`tool/android_room_tag_assignment_smoke.ps1` 现把系统分享面板作为只读外部系统表面单独采集；只接受
Android Resolver/Chooser 组件，随后发送系统返回并等待 Pure Live 重新成为前台。静态合同继续检查
显式 serial、覆盖安装、候选哈希、Hive 精确恢复、进程清理和禁用设备操作，并新增分享面板与返回门禁。

本轮覆盖一台 K90、一份 Debug APK、一个当时在线的 Bilibili 房间和中文系统分享面板。Windows 原生
导入弹窗、移动端从另一实例接收口令、分享目标实际发送、Release 包和异常平台通道继续按矩阵执行。
本批 Windows Computer Use 与 Astra Light 使用次数均为 **0**。
