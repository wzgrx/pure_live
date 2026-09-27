# IPTV 提供方回看元数据、归档窗口与 URL 策略审计（2026-09-12）

## 结论

本批次把 IPTV 回看从固定 `playseek` 参数扩展为由播放列表与节目单共同驱动的提供方策略：M3U 头部默认值和频道覆盖值会完整解析、落库、刷新并传递到播放器；XMLTV/JSON 的节目回看 ID 会随节目持久化；节目单在发起播放前会按提供方开关、归档天数、时间修正和必需字段判定可用性。默认模板、append、shift、Flussonic、Xtream Codes、VOD 与旧 `playseek` 路径均由同一纯策略生成 URL，未知模式或缺失占位数据不会猜测网络请求。

源码基线为 `25e43a0b85d1f7e4223695def7dca4c6ea937456`。冻结的上游比较对象为 `c6c9bd70aedc503c003110dae10a83ad0bb891d8`；上游同样丢弃这些 M3U 回看字段并固定生成 `playseek`，因此本批次判为 `upstream-existing`。本轮没有 fetch、merge 或 cherry-pick，维护仓库继续作为唯一工作线。

## 一手规范依据

- [Kodi PVR IPTV Simple README 的 Catchup、Timeshift 与节目属性说明](https://github.com/kodi-pvr/pvr.iptvsimple/blob/Piers/README.md)：覆盖 `catchup`、`catchup-source`、`catchup-days`、`catchup-correction`、`timeshift`/`tvg-rec`，以及 epoch、格式化时间、duration、offset、除数和 `{catchup-id}` 占位符。
- 同一项目的 `Channel.cpp` 实现用于核对 Flussonic 与 Xtream Codes 自动地址结构；仓库代码只实现所需的可验证子集，没有引入第三方源码。

## 修订前的确定性问题

1. `M3uParser` 只保留频道名称、分组、台标和直播地址，头部/频道级回看字段在导入边界直接消失。
2. `Channel`、Drift 表和 `LiveRoom` 没有对应字段，刷新已有播放列表时也没有可继承的提供方策略。
3. XMLTV 的 `catchup-id` 没有进入节目模型与数据库。
4. 节目单把所有历史节目视为可回看，忽略提供方禁用状态、归档天数及模板所需字段。
5. `VideoController` 固定向直播地址附加 `playseek`，不能表达 append、shift、Flussonic、Xtream Codes 或 VOD 地址。

新增解析回归在旧实现上稳定得到 **32/33 PASS**，唯一失败为 `catchupMode` 字段缺失。第一轮实现后五文件联合得到 **109/114 PASS**，暴露 fragment 后追加查询串及其连锁断言；迁移回放随后复现重复加列，推动迁移改为先读取 `PRAGMA table_info` 再补齐缺失列。

## 实现范围

### M3U 与持久化

- 解析播放列表头部默认值与频道覆盖值：`catchup` / `catchup-type`、`catchup-source`、`catchup-days`、`catchup-correction`。
- 兼容 `timeshift` 与 `tvg-rec`；明确的 `0`、`false`、`off`、`none`、`disabled` 或零天窗口统一归一为禁用。
- `Channel`、播放列表刷新协调器、IPTV 仓库、`IptvSite` 和 `LiveRoom` 完整传递回看元数据；稳定频道 ID 在刷新后保持不变。
- 数据库 schema 从 7 升至 **8**。迁移根据实际列清单补列，因此从 1..7 升级及故意回放同一迁移均保持幂等；旧行的新字段为空。
- `LiveRoom` 的 JSON、复制与合并路径保留提供方策略，并过滤非有限数字；退出回看只清除当前回看 URL/区间，保留频道策略供下一次选择。
- XMLTV `catchup-id` 与 JSON `catchupId` / `catchup-id` 进入 `EpgProgramme` 和 Drift 表，替换节目源时随权威快照更新。

### URL 策略与窗口判定

- 可用性结果分为 available、disabled、outside-window 与 unsupported；归档窗口采用精确边界，节目单对不可用历史节目显示禁用状态和双语说明。
- 提供方字段一旦存在即优先于旧逻辑；完全没有元数据的历史频道继续兼容原有 `playseek`。
- 支持 default/full source、append、shift/timeshift、playseek、offset，以及 epoch/current/end/duration/offset、除数和格式化日期时间占位符。
- append 在直播地址原有重复查询参数和 fragment 存在时仍保持顺序与语义。
- `{catchup-id}` 缺失时返回 unsupported，不发送带残缺模板的地址。
- Flussonic 自动规则覆盖 MPEG-TS 的 `timeshift_abs-{start}.ts` 与 index/mono M3U8 的 `timeshift_rel-{offset:1}.m3u8`。
- Xtream Codes 识别 `live/user/pass/channel.m3u8`，生成 `timeshift/user/pass/{duration:60}/{Y}-{m}-{d}:{H}-{M}/channel.m3u8`。
- VOD 无模板时使用节目 `catchup-id` 的绝对地址；未知模式、未知占位符与畸形 source 统一判为 unsupported。

### 播放器与节目单

- `VideoController` 接收节目 `catchup-id`，由统一策略生成提供方 URL，并捕获 unsupported 结果。
- 节目行在提供方禁用、超出归档窗口或缺少必需回看 ID 时保持在列表中但禁止提交；点击不会关闭节目单或替换播放器。
- 可用回看继续复用既有 single-flight、latest-wins、完整区间和返回直播事务。

## 验证证据

| 层级 | 结果 |
| --- | --- |
| 稳定红测 | 32/33 PASS，旧模型缺少 `catchupMode` |
| 第一轮联合 | 109/114 PASS，定位 append/fragment 与迁移回放问题 |
| 直接九文件回归 | **226/226 PASS** |
| 最终 focused CI | **295/295 PASS** |
| 静态分析 | `flutter analyze`：**No issues found**（204.5 秒） |
| 格式门禁 | 24 个 Dart 文件，0 个待格式化 |
| 质量记录 | `local-artifacts/build-records/20260912T075710057Z-quality-focused.json` |
| 仓库审计 | errors 0；保留 2 项既有预期警告：测试 TLS key 与 33 项空 catch inventory |

前两次 focused CI 都在生成的 `database.g.dart` 格式门禁停止；显式格式化该生成文件后，第三次完整通过。Drift 重新生成除 schema 8 字段外也同步了当前生成器的关系/composer 代码；最终生成文件已进入编译、迁移和联合回归。

## 本批次边界与后续

- 本批次没有操作 ADB、手机、Windows GUI、真实 IPTV 提供方、真实解码器、构建安装包或发布版本。
- 本批次没有使用 Astra Light；该资源只保留给确需 Windows 客户端交互的单个 GUI 验收任务。
- 下一步仍需用真实提供方样本核对时间修正约定、服务器窗口和解码表现，并在 Android/Windows 最终候选中完成 GUI、播放、返回直播与安装升级验收。
- A1-05/A3-04 保持 RUN；宏观状态仍为 **20 PASS / 33 RUN / 9 NR**，共 **42 组**未闭环。
