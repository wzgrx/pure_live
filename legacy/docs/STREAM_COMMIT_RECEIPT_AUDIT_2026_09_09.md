# 切源确认与刷新所有权审计（2026-09-09）

实现提交 `29de9ada91cf156955e3d98b593244ad274d3cce`，基线 `dffde99baf9da5b901175aeba2c61b502c5a2dda`。延续 [主播放器输入审计](PLAYBACK_SOURCE_TRANSPORT_AUDIT_2026_09_09.md) 的路由取消缺口；没有安装 APK 或启动原生解码。

## 复现、来源与第一处错误

真实 PlayerController 默认 opener → 真实 PlayerManager → 可控 UnifiedPlayer 替身：先提交旧源，开始 Windows 同房间新画质候选，在 native open 等待中暂停或关闭，再放行候选。旧实现的切源结果为 true；暂停时仍是旧源，关闭时提交已为空，但路由 fallback 把请求元数据当作成功结果。房间定时器到期直接调用 manager.pause，未推进路由选择代次，因此路由自己的 epoch 检查并不覆盖这种取消。

另一条序列：旧源有 resolver，新候选传新 resolver 或 null，暂停取消后恢复旧源并触发源错误。旧实现分别调用新 resolver、或不再调用 resolver。第一处错误在 public play 的队列回调：候选尚未取代旧播放器就覆盖刷新所有者。旧源仍在播放时触发的主动刷新也会误用候选 resolver。

来源归为 `fork-regression`：opener 的正常完成检查和 resolver 提前替换由维护提交 `db7d0df33` 演进而来；原始 opener 可追到 `733932f91`。冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 有 void opener，但 manager.play 仅排队执行普通打开，没有本次 sourceRefreshResolver / 暖切能力。因此不把正常 void 返回本身认作上游缺陷；问题是新增可取消暖切之后，维护分支调用契约没有同步。未拉取或合并上游。

## 实现

- 默认 opener 等待 play 后，核对新提交 revision、manager 当前源有效性、房间与平台。取消的正常 Future 完成不等于切源成功；取消返回 false，保留旧 UI，不弹播放失败提示。真正 native 错误仍走原错误反馈。
- 确认后的提交同步交给 applySourceCommit，和路由广播 listener 通过 revision 去重。恢复可能选择别的线路或画质，不用请求 URL 相等判据覆盖实际提交。
- 保留已有自定义 StreamSourceOpener 的 Future<void> 测试契约；增加可选 streamPlayerManager，仅用于切源默认路径注入，并非声称整个 VideoController 后端均已注入。
- 候选准备期间保留旧 resolver、缓存与重试预算。刷新所有者在暖切实际安装前、或普通破坏性打开前替换，不在发起候选时替换。
- 安装阶段失败并恢复旧提交时，按 revision、远端 URL、房间及当前 session 有效性恢复刷新配置；有效播放才重新安排刷新计时。关闭、破坏性打开、新提交不恢复旧配置。缓存失效时间仍由原消费逻辑核对。
- 无数据库、设置迁移或持久化格式变化；主控制器和 manager 共用路径受影响，Windows 暖切时序为直接复现范围。普通/音频/恢复相邻逻辑由定向测试覆盖，横竖屏、画中画和真机效果仍需 native 验收。

## 证据

新增 8 项：真实路由成功/暂停/关闭 3 项；刷新所有者暂停含新 resolver、暂停含 null、正常成功、安装绑定失败回滚 4 项；候选准备中主动刷新仍属于旧源 1 项。替身不连接生产直播，也未启动 libmpv/Fijk。

| 原始记录 | 结果 | 耗时、峰值资源 |
|---|---|---|
| `20260909T023033968Z-stream-commit-receipt-red.json` | fixture 编译失败：新增 host 忘记使用 ui 前缀调用 resolveVideoControllerUpdate；无产品断言执行 | 378.955 秒，CPU 28.48%，WS 29,385,482,240 B，结束活跃重型进程 0 |
| `20260909T024047289Z-stream-commit-receipt-red.json` | 2 通过、4 产品失败：暂停/关闭返回 true；旧源调用新 resolver；null 覆盖导致 resolver 等待超时 | 563.709 秒，CPU 25.59%，WS 28,761,800,704 B，结束活跃重型进程 0 |
| `20260909T025423883Z-stream-commit-receipt-green.json` | 五文件 **198/198**；三变更文件 `analyze --fatal-infos` **No issues found**；两退出码均 0 | 588.516 秒，CPU 30.36%，WS 27,394,211,840 B，结束活跃重型进程 0 |

五文件为 player_error_recovery、stream_selection_controller、player_source_query_metadata、player_audio_mode_transition、playback_source_transport。日志、脚本、输入哈希在忽略目录 `local-artifacts/stream-commit-receipt-20260909/`；提交前 verified-source.json 核对三份源码与 green-source.json 完全相同。排队等待其他 Java 工作结束，没有终止其他进程；跨轮旧工具句柄消失后读取最终日志和任务记录确认成功，没有重启测试。

## 交付边界与下一步

本批只完成源码/确定性回归；版本仍 3.1.8+4121，Android bee143e2、Windows f3de664a 候选保持原样且不包含本批。无 ADB/MT、覆盖安装、重启、Root/LSP 修改、卸载/清数据或发布。历史 42 个宏观未闭环项仍保留，8 条新增测试不是减去 8 个验收项目。

下一步是多画面解析结果到每格输入、代理与释放链，再推进 TTing 适配和全平台验收。稳定 3.2.0 保持完整验收后发布的条件。回滚本批同时还原上述实现提交中的 controller、manager 和测试，不改用户数据。
