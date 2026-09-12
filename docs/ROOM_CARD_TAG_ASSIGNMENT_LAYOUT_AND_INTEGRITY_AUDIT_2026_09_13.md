# 房间卡片长按与标签分配布局/数据完整性审计（2026-09-13）

## 结论

`RoomCard` 的长按详情、关注、分享和标签分配此前同时存在数据源分叉、旧键回退、无效标签 ID、
窄屏操作溢出和新增表单行为不一致。产品提交
`c83ed5ccca1453e2d3895af5fe1cd9a00ea56921` 已把房间标签读取统一到
`TagManagementController.roomTagsMap`，规范写入并移除旧 room-id-only 键；长按弹窗和标签选择器
改为响应式布局，新增标签沿用 15/40 字符边界、IME 动作和自动选中语义。
后续提交 `d499e41cdd19279151c7a4423ae8383a8aef8658` 又修正了长按弹窗关注动作的本地陈旧状态、
全局 Navigator 误关闭和直接取消关注问题：按钮现在观察规范关注集合，按弹窗所属 Navigator 关闭，
取消关注需确认且取消保持详情与关注状态，写入只在实际变化时发布刷新事件。

标签专项原有 **4/4 PASS**、相邻十文件 **131/131 PASS**；追加关注动作后同文件 **8/8 PASS**、
相邻九文件 **73/73 PASS**，全库 analyze 为 `No issues found`。最新干净提交 arm64 Debug 已在
`25102RKBEC / myron / Android 17` 上保留数据覆盖安装；真实热门 Bilibili 房间完成长按、直接关注、
取消关注提示/取消/确认、再次关注、创建标签、自动选中、确认和重新打开保持选中的完整路径，进程日志
无 FATAL/ANR，规范 Hive 最终逐字节恢复。该证据更新 A1-05/A2-01 的当前覆盖，但两组仍为 `RUN`；宏观计数保持
**20 PASS / 40 RUN / 2 NR**，仍有 42 组未闭环。

## 稳定复现与首次错误状态

源码审查和 `test/room_card_tag_assignment_test.dart` 的初始 Widget 场景稳定暴露：

1. 分配弹窗从 `LiveRoom.tagIds` 初始化，而关注页实际筛选使用
   `TagManagementController.roomTagsMap`。房间刷新后 `tagIds` 可为旧快照，重新打开会显示错误选中；
   用户再次确认还会用旧集合覆盖当前映射。
2. `setRoomTags` 原样接受重复和已删除的 ID；清除平台作用域键后，历史 room-id-only 键仍可被
   `getTagsForRoom` 回退读取，使“清空”重新出现旧标签。
3. `RoomCard` 为一次标签写入临时构造完整 `FavoriteController`，连带刷新 Worker/定时器和页面状态，
   扩大了一个弹窗操作的生命周期与副作用。
4. 320×480、3.0 倍英文文字下，旧长按操作行横向溢出约 47 px，标签标题行溢出约 174 px，
   固定 68 px 标签单元纵向溢出约 60 px；平台尾标还可能占满 `ListTile` 的标题宽度。
5. 内嵌新增表单没有复用标签管理页的 15/40 字符限制与 IME 提交语义，创建成功后也没有自动加入
   当前房间的临时选择。
6. 长按弹窗的关注按钮只在 `initState` 读取一次状态，弹窗存在期间的外部关注变化不会刷新；点击时先
   乐观翻转，再用全局 `Get.context` 关闭路由，可关闭错误 Navigator。取消关注也不经确认，与播放页
   的同类动作不一致。

初始三个 Widget 场景为 **0/3**，同时保留了上述 overflow 诊断和错误选中结果；这不是只凭源码
推测的问题。追加关注状态观察红测也稳定得到 `Follow` 未变为 `Unfollow`；嵌套 Navigator 夹具首次
错误等待了未关闭路由，修正夹具后才用于验证产品路由所有权，未把夹具等待误记为产品失败。

## 产品修订

### 单一标签事实源

- `RoomCard` 以 `getTagsForRoom(room)` 初始化选择，并过滤当前仍存在的标签 ID、去重后再显示。
- `setRoomTags` 先按当前标签集合过滤和去重，再删除同房间的旧 room-id-only 映射，最后等待 Hive
  写入完成；清空平台作用域映射后不会再暴露旧键内容。
- 卡片直接调用标签控制器，不再为这次操作创建 `FavoriteController`。

### 长按与选择器布局

- 长按详情使用可滚动 `AlertDialog` 和窄边距；分享与标签入口均保留 48×48 最小触控面积和 tooltip。
- 关注/关闭动作交给标准响应式 `OverflowBar`，避免固定 `Row` 在窄屏或大字号下越界。
- 标签选择器在窄屏或文字比例较高时改为单列；3.0 倍文字的标签单元增高到 136 px，并保留独立滚动
  控制器、Scrollbar、选择状态和可访问 button 语义。
- 房间卡片在文字比例达到 1.8 或可用宽度不足时隐藏次要平台尾标，优先保证主播和标题可读。

### 新增标签操作

- 名称/描述分别固定 `15 / 40` 字符边界，键盘动作使用 Next / Done；标题区的取消与提交和描述框
  Done 复用同一个提交函数。
- 新标签成功后立即自动选中并回到列表；编辑态底部“确认”保持禁用，避免把半完成表单误当房间分配
  提交。
- 房间分配“确认”等待持久化结束后再关闭弹窗。

### 关注动作与路由所有权

- `FollowButton` 直接观察 `favoriteRooms` 规范集合，不再持有一次性本地布尔快照；弹窗打开期间的外部
  新增或移除会实时更新标签。
- 关注和取消关注只关闭当前按钮所属的详情 Navigator，不读取全局 `Get.context`；嵌套 Navigator
  回归明确验证根页面不被误弹出。
- 取消关注先在同一 Navigator 上显示可滚动确认框；取消保持详情和关注状态，确认写入成功后才关闭
  详情。按钮在异步事务期间禁用，避免重复提交。
- 关注集合实际发生变化时统一发送 `changeFavorite` 事件；并发下若目标状态已由其他入口完成，弹窗
  仍按最终规范状态收尾而不重复发布事件。

## 确定性回归

| 层级 | 结果 | 证据 |
| --- | --- | --- |
| 新增专项 | **4/4 PASS** | 旧键/无效 ID 规范化、权威映射重开、新增边界与 IME、320×480 / 3.0 倍英文滚动 |
| 相邻十文件 | **131/131 PASS** | RoomCard、标签管理、关注刷新/筛选/启动策略、热门网格、搜索与微博布局 |
| 关注动作增量 | **8/8 PASS** | 同文件含外部状态观察、所属 Navigator、取消/确认和 320×480 / 3.0 倍英文确认框 |
| 关注相邻九文件 | **73/73 PASS** | 关注刷新/筛选/启动/下拉、分区身份/页面与播放导航 |
| focused 记录 | `succeeded` | `local-artifacts/build-records/20260912T190415234Z-quality-focused.json` |
| 最终 analyze | `No issues found` | `local-artifacts/build-records/20260912T191150509Z-quality-focused.json` |
| 工具/文档整合门禁 | **4/4 PASS**；analyze 无问题 | `local-artifacts/build-records/20260912T194611261Z-quality-focused.json` |
| 关注增量门禁 | **73/73 PASS**；analyze 无问题 | `local-artifacts/build-records/20260912T201218265Z-quality-focused.json` |

## 构建与候选身份

最新干净 `d499e41c` 使用
`tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality`：

| 项目 | 结果 |
| --- | --- |
| 包名 / 版本 | `com.mystyle.purelive` / `3.1.8+4121` / manifest code `6121` |
| APK | `288827674` B |
| SHA-256 | `ABEEDA3687FA4EFF1A7D2BBCC7D3CEC18ACE1CBF76F0B2BB8928DAAE0CA21726` |
| ABI / 原生库 | `arm64-v8a`；16 个库；最小 ELF LOAD `0x4000` |
| Flutter 资源 | 1262 项 / `206864381` B |
| 构建记录 | `local-artifacts/build-records/20260912T201428919Z-build-androidarm64-debug.json` |

## K90 原生验收

最终结果：
`local-artifacts/diagnostics/android-room-tag-assignment-20260913T041726570/summary.json`。

- 测试前重新核对 `25102RKBEC / myron` 和 `uid=0(root)`；所有 ADB 命令显式绑定
  `192.168.1.2:5555`。
- `install -r -t` 返回 `Success`，`firstInstallTime` 保持 `2026-07-21 18:07:53`；设备
  `base.apk` 与候选 SHA-256 完全一致，首次启动前规范 Hive 哈希未变化。
- 冷启动进入热门 Bilibili，实时语义选中卡片边界 `[18,886][591,1425]` 并长按。分享、标签、关注、
  关闭分别为 `144×144 / 144×144 / 199×144 / 192×144`，均在 1200×2608 可视区域内。
- 当前房间原本未关注。直接点“关注”后详情关闭，再次长按显示“取消关注”；点“取消关注”显示完整
  主播名确认框，取消后关注和详情均保留。第二次确认后详情关闭，再长按恢复“关注”。确认框取消/确认
  均为 `192×144`，完全位于可视区域。
- 再次关注后标签入口直接进入选择器。标题宽 984 px；新增、取消、确认控件分别为
  `144×144 / 192×144 / 210×144`。
- 两个编辑框均为 `825×144`；数字夹具标签 `26091304172657` 创建后语义
  `selected=true`，描述 `31415926` 可见。确认分配后再次长按同一卡片并打开选择器，标签仍为
  `selected=true`。
- 同一应用 PID `32539` 的日志没有 FATAL、ANR、Fatal signal 或 SIGABRT；业务与清理门禁全部为
  `true`。
- 设置文件开始、覆盖安装后和最终恢复的 SHA-256 均为
  `19F40EA9E29A6017317ACB14AEBA8CF4378A6EEAA96BA15E09C7CD2312D1F050`；uid/gid/mode 保持
  `10946:10946:600`，SELinux context 前后一致。结束时 Pure Live 无进程，系统 stay-awake 从测试值
  `7` 恢复原值 `0`。

关键截图同目录保存为 `room-dialog-first.png`、`direct-unfollow-prompt.png`、
`room-dialog-after-direct-follow.png`、`tag-selector-initial.png`、`tag-add-form-filled.png` 和
`room-dialog-second.png`。

## 测试工具失败链与固化

早期轮次按失败保留，且每轮均先恢复用户设置再退出：

1. 本机 ADB daemon 在拉取标签弹窗截图前退出，命令没有送达设备；随后只对这类明确的 daemon/offline
   前置错误加入有界重试，不重启 adbd、不重选设备，也不泛化重放已可能执行的命令。
2. 初版把只读标题误要求为可点击；后续区分标题和动作，并用 bottom-most 选择真实“关闭”按钮，避免
   取到全屏弹窗遮罩。
3. 键盘弹出后弹窗重排，旧坐标会点到遮罩；工具现在每次焦点/键盘变化后重新读取语义边界。
4. 当前中文输入法会把英文 ADB 输入解释为拼音；最终使用唯一纯数字夹具，既不切换输入法，也保持字段
   内容的严格逐项比对。

最终流程固化为 `tool/android_room_tag_assignment_smoke.ps1`，静态合同
`tool/test_android_room_tag_assignment_smoke.ps1` 校验必填 serial/APK/hash、全部 ADB 入口的 `-s`、
身份与前台保护、覆盖安装、语义控件、直接关注关闭、取消关注确认/取消/确认、状态重开、进程日志、
Hive 精确恢复和结束停进程；该测试已加入 `tool/local_ci.ps1`。

## 验收边界

本轮覆盖一台 K90、一份 Debug APK、一个当时在线的 Bilibili 房间和正常字号中文界面；窄屏/3.0 倍
英文由确定性 Widget 覆盖。Windows 鼠标右键、键盘操作、Release 签名包、其他平台房间、已有大量
标签的原生滚动和跨进程重开仍按矩阵继续，因此 A1-05/A2-01 保持 `RUN`。本批 Windows Computer
Use 与 Astra Light 使用次数均为 **0**。
