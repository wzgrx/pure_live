# 小红书应用接线与实际 HLS 入口（2026-09-10）

## 当前结论

基线 `c54c516d55e01997e1945a48845374aa59a771a9`，实现 **`69f6db996b540430e0bb922fa846447e789a6c58`**，26 文件。承接[公开分享底层合同](XIAOHONGSHU_SHARE_API_AUDIT_2026_09_10.md)，现在小红书已进入应用注册表、分享导入、精确房间查询、收藏/外部打开与播放器/录制源解析。

当前为 **19 个直播站点 + IPTV、8 组参考平台未注册**：YouTube、niconico、Bigo、战旗、一直播、企鹅电竞、浪 Live、微博直播。已注册平台的未接入能力、双端原生与长时验收继续保留；历史 **62 组中 20 PASS / 32 RUN / 10 NR，42 组未闭环**，没有因本次注册改写宏观计数。

本轮取得注册适配器→房间→播放质量/线路→实际 `StreamResolverService`→HLS 的在线证据；尚未通过实际播放器打开或生成录制文件。没有构建、安装或发布，Android 候选 fb106ed6、Windows 候选 2fb471d3、版本 3.1.8+4121 保持。

## 应用合同

- **导航与空态**：注册 id=`xiaohongshu`，双语名称、默认通用图标与单站工厂。现阶段没有已验证的公开目录；热门页展示持久说明与空态，不塞固定直播种子，也不把下播推荐当全站目录。无虚构分类和分页。
- **精确导入**：接受数字字符串及精确 `www.xiaohongshu.com/livestream/{roomId}`，标准 http/https 端口；查询参数不变成房间身份。排除相似域名、userinfo、非默认端口、路径穿越/编码、用户主页及笔记。`hina`、裸域名、短链和其他别名路径尚未接入，未猜测重定向。
- **搜索说明**：新增 `roomLookup` 能力，与 TTing 的持久频道查询 `channelLookup` 分开；选择小红书或聚合页均说明“房间号/官网直播链接查询”。可返回下播房间，无昵称/关键词查询或网页搜索入口，第二页不发请求。
- **身份与收藏**：完整保留大整数房间号字符串，未取得持久主播身份时 userId 保持空。收藏跟踪该房间，不代表主播换房开播后自动跟随；房间页和空态明确提示。外部打开根据房间号重建官网 URL，不信任导入数据中的任意 link。
- **状态**：刷新/搜索不携带可播放快照 data；播放与录制重新获取完整房间。unknown 不返回 false 下播；真实下播让录制器产生终止性 notLive。受限或缺源直播仍是平台声明直播，但不发布可播放质量/源，也不改成 offline。
- **质量与线路**：按 codec + quality_type 建立稳定选择 ID，如 `h264:HD`；同档 HLS/FLV 是线路，不是额外画质。保留原始顺序、协议、URL query；不把 UI quality.data 中的 URL 当作取流依据，不将全局几何或标签冒充测量分辨率。
- **恢复**：错误恢复强制重新取目标房间和同一质量 ID；拒绝房间变更、已下播、访问条件变化或质量消失，不回落到推荐房、另一档质量或陈旧 URL。没有经过验证的过期字段时不虚构 URL lease。
- **共用请求头**：播放、多画面、音频模式、录制通过 `PlaybackHeaderResolver`/`FFmpegHeaderFactory` 使用相同官网 Referer 和客户端 UA，不注入账号 Cookie。弹幕暂为 EmptyDanmaku，未宣称已接入。
- **观看值**：网站 `displayViewerCount` 仅以“平台展示观看值”附在说明，不进入实时在线/累计人数/热度字段和排序。审查发现 `LiveRoom.watching` 默认 `'0'` 会使新适配器的未知数量变成假零，现显式传空字符串并对最终 audienceValue 回归；未增加实时在线设置项或迁移。

## 设置迁移与用户数据

`siteCatalogMigration` 从 11 到 **12**，仅追加小红书，不重新启用已隐藏的其他平台。用户随后隐藏小红书并正常关闭/重开 Hive 后，隐藏选择仍保持。备份导入规范化平台大小写、去重/顺序，保留房间号与标签；没有将房间号复制成 userId。

`audienceMetricMigration=7`、数据库 schema 7 和现有录制格式保持。既有九个平台目录迁移测试同步验证新尾项，旧平台排序/隐藏、真实在线选项保持原契约。

## 确定性与界面证据

主回归 **24 文件 320/320 + 在线探针 1 skip**；随后仅调整新适配器观看值空态，并以应用及搜索排序两文件 **31/31** 复验。两阶段各完成 **24 个改动 Dart 文件严格分析，无问题**。31 是已覆盖集合的复验，不与 320 相加作为独立测试数量。

覆盖注册/工厂/搜索能力、精确分享识别、下播/unknown/访问/缺源、跨房间数据污染、质量与线路、刷新换源、真实录制解析器线路轮换、头部一致性、备份/迁移及相邻搜索/目录/分享/录制消费者。

实际 `BasePageView` + `LiveDirectoryController` Widget：读取本次 zh/en 翻译资源，**320×640** 下持久范围说明与空态同时存在，未出现布局异常；没有目录网络请求。这是离线 Widget 布局证据，不是手机/Windows GUI 截图或全字号验收。普通未加载本地化资源的单元测试仍输出预期 missing-key 日志；两份正式资源中六个新增键分别唯一存在，双语 Widget 已实际加载。

## 注册适配器在线探针

`tool/probes/xiaohongshu_application_probe_test.dart` 为 opt-in，本轮开始时间 **2026-09-09T19:37:08.989296Z**，本机 DIRECT、干净共享 Dio，未操作系统代理或使用手机网络。

| 步骤 | 实测 |
| --- | --- |
| `Sites.of('xiaohongshu')` → detail | 实际 XiaohongshuSite；HTTP 200、房间号匹配、声明直播 |
| `getPlayQualites` → resolvePlayUrls | `h264:HD` 一档、4 个候选 URL |
| 实际 `StreamResolverService.resolveStream` | 重新读取房间 HTTP 200；相同质量 ID、4 候选，首线 HLS |
| 通过共享媒体头读取首线 | HTTP 200 / 426 B、3 个分片、无 ENDLIST；所有请求禁自动跳转 |

报告 `local-artifacts/xiaohongshu-application-20260910/first-production-report.json`：contract=passed、stage=complete、headersMatch=true，nativePlayback/nativeRecording 均 false。后续修改仅测试 matcher 和观看值展示，未改变本次已验证的取流路径；未再次运行相同在线请求。前批 1080p 单 TS 严格解码证据仍是外部 FFmpeg 单分片，不借用为应用录制结论。

## 失败、资源与提交对应

所有重型命令经资源守卫串行执行，最初等待其他任务的活跃 rg 搜索；没有结束其他进程或启动第二套测试。每个记录结束时活跃重型进程为 0。

| build-records 记录 | 结果 | 耗时；峰值 CPU / 工作集 |
| --- | --- | --- |
| `20260909T193714163Z-xiaohongshu-application-first.json` | 318 PASS / 3 FAIL，在线探针已 PASS；未进入 analyze | 320.83 s（含排队）；9.17% / 11,015,585,792 B |
| `20260909T193840081Z-xiaohongshu-application-diagnostic.json` | 单独重现三个失败：`anyOf(null, '')` 实际只匹配空字符串，合法空 userId 被测试误拒 | 31.22 s；24.40% / 10,568,761,344 B |
| `20260909T194010819Z-xiaohongshu-application-final.json` | matcher 改成 isNull/isEmpty；320 PASS / 在线 1 skip；严格分析 PASS | 74.86 s；9.25% / 10,589,261,824 B |
| `20260909T194217034Z-xiaohongshu-application-audience-final.json` | 观看值空态及应用/排序 31 PASS；24 文件严格分析 PASS | 61.14 s；9.33% / 10,798,907,392 B |

脚本/哈希/输出位于 `local-artifacts/xiaohongshu-application-20260910/`。首次 Start-Transcript 未完整收集子进程输出，诊断与后续检查增加 Tee-Object 保存测试输出；原失败记录不改写。验证脚本预检还曾使用不存在的 `stream_resolver_service_test.dart`，在执行重型任务前停止，核实后使用实际 `recorder_stream_resolver_test.dart`；没有漏跑该门禁。提交前以 audience-final-source.json 核对全部 24 个改动 Dart 文件。

## 下一步与回滚

1. 通过真实应用录制控制器与原生后端短录小红书，核对 HLS 预取、正常停止、自动 MP4 收尾、完整解码及重启录制；再补 Windows GUI 和可用窗口内的 Android 验收。
2. 公开目录、昵称搜索、持久主播/跨开播跟随、短链/别名、弹幕、特殊房间及完整平台能力仍待接入和验收，不能以本批精确房间查询代替原目标。
3. 本轮 ADB 仅核对 25102RKBEC/myron 与前台 `com.bilibili.app.in`，未唤醒、安装或接管；Root/LSP/MT 及所有远程网络边界保持。
4. 回滚点 c54c516d；撤销 69f6db99 移除应用注册与迁移，保留已备份的小红书房间数据，不卸载/清数据。若用户已运行目录迁移 12，降级/重新升级后的目录选择需按实际存档复核，不盲目重置迁移号。

关联：[当前剩余工作](ACCEPTANCE_STATUS_3_2_0.md)、[完整验收入口](ACCEPTANCE_3_2_0.md)、[参考平台差距](PLATFORM_EXPANSION_AUDIT_2026_09_07.md)。
