# 搜索取消与页面生命周期（2026-09-10）

## 基线与来源

业务基线 `6f8a736f282670ecdf434e4dbd18da6b4cb3ad1d`，3.1.8+4121；本轮只改公共搜索生命周期及 niconico 的搜索取消入口，未合并上游。只读对照本地冻结 `upstream/master=c6c9bd70aedc503c003110dae10a83ad0bb891d8`，merge base 为 `527fea1b40885e3621d53c9646b523dd8522290c`，并非查询最新远端。

- `upstream-existing`：冻结上游与本地均在 onInit 排队 Windows 检测，回调及异步返回未检查页面关闭；onClose 只增加搜索代次，没有阻止该检测或后续 dialog。相关历史提交 `a533505b`。
- `upstream-existing`：selectPlatform 先改 index，再调用 doSearch；输入已清空时 doSearch 在代次递增前返回，旧平台结果留在新标签下，旧请求还可继续写入。冻结上游存在同一时序；相关搜索代次历史 `1a0629a5`。
- `integration-conflict`：新增 niconico directory 已接受取消，但搜索页仍使用无 token 的旧 searchRooms + timeout；代次栅栏只忽略返回值，没有将退出/换词/切平台传给传输。

## 修改

1. 增加可选 LiveCancellableSearch 与统一调用扩展，调用前后检查 token；旧 LiveSite 入口与所有旧适配器签名不变。
2. niconico 实现可选合同，保持关键词验证、固定 40 条原生页及目录解析，token 经 directory/API 传给实际请求。没有建立播放 seat 或读取登录数据。
3. SearchController 每个提交关键词拥有父 token，每个平台请求拥有独立子 token 和 12 秒默认 deadline。成功收尾、平台失败或 timeout 不关闭共享 HTTP client。替换、换平台及关闭取消原父 token。
4. 实现可选合同的平台等待其 Future 收尾；旧平台只取消 UI 等待，并继续消费迟到成功/错误，不把它记作底层 HTTP 已停止。过时代次的所有批次继续收尾，但没有结果/分页/错误写入。
5. 空草稿换平台重置结果、分页、关键词和提示状态，不弹空关键词 toast；用户主动提交空输入的原有提示保持。新搜索仍渐进展示快平台结果，全部首批完成前维持原有分页阻挡，去重、排序及离线筛选逻辑保持。
6. 页面关闭有显式、幂等栅栏；排队 Windows 检测开始前及返回后均检查，公共搜索/筛选/web action 关闭后不再执行。Linux 浏览器启动的迟到失败也不再给已关闭页弹 toast。

## 复现与测试记录

第一次测试只调用 pump，没有强制安排一帧，导致第二项尚未执行检测回调就检查 probes；这是测试调度错误，不计作产品复现。原记录保留：`local-artifacts/build-records/20260910T082853914Z-search-lifecycle-baseline.json`，1 PASS / 1 FAIL，117.01 秒。

改用 pumpWidget 安排真实帧后，在修改业务前两项均稳定失败：关闭前排队的 probe 仍调用一次；probe 已开始再关闭，迟到 false 仍调用一次 dialog。记录 `local-artifacts/build-records/20260910T083141811Z-search-lifecycle-baseline-frame.json`，0 PASS / 2 FAIL，129.42 秒，收尾重型进程 0。

本轮新增两项 Windows Widget 及十三项请求回归：预取消不分配、实际 NiconicoSite/API token 在退出/替换/切平台传递、空草稿标签切换、快慢平台渐进返回/分页/去重、deadline 与 provider 收尾门闩、兄弟 token 隔离、legacy 退出/替换/超时后的迟到错误、分页中换词以及关闭幂等。请求测试使用真实控制器；Nico 网络响应为固定公开目录 fixture，其他适配器使用可控替身，不是外部服务或实际手机证据。

七个文件定向回归 **142/142 PASS**，含新增 15 项；其余为搜索页面双语/大字号/键盘/滚动/筛选/排序、目录及应用注册的相邻回归。五个变更 Dart 文件执行 `dart analyze --fatal-infos`，结果 **No issues found**。记录 `local-artifacts/build-records/20260910T083807411Z-search-lifecycle-final.json`：296.90 秒，峰值 CPU 11.26%、工作集 13,086,261,248 字节，最终活跃重型进程 0。未运行外部 HTTP、ADB、APK 构建或发布。

## 影响与后续

- 不涉及版本、依赖、设置 schema、保存的数据、播放器/录制会话、几何布局、弹幕或任何设备配置。
- 其余旧平台仍待逐个接通传输取消，包括内部可变 cursor 的迟到请求隔离；本批不声称全站 HTTP 取消已覆盖。
- SearchController 的异步查询 Future 等待各 provider 返回，onClose 自身仍是框架同步回调。Nico API 原有取消竞速保留；本批证据是传输 token 取消，不等同完整底层 socket/响应流物理释放已测量。
- 20 直播站点 + IPTV、7 组未注册、62 组中的 42 组未闭环保持。全量质量门、最新候选、双端 GUI/多路/长录与全平台 3.2.0 发布仍未完成；旧 Android 152cf151 与 Windows 2fb471d3 不含此改动。
- 下一阶段先准备累计候选的正式质量门和构建，再按明确设备身份、前台/录制、备份与签名检查进入保留数据升级验收；手机未进入适合测试的窗口则不抢前台。MT MCP/lspctl 是可用路径的用户说明，本轮没有调用或配置它们。
- 回滚范围：本批五个 Dart 文件及审计索引；无数据迁移或安装回滚需求。本批仍按用户要求暂缓正式版本发布。
