<!-- 由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改 -->

# T14b 刷新率

属于 [T14 性能和流畅度](../README.md)。30～240 Hz 屏幕的刷新率策略和帧率匹配。

- 代码：`platform/display_mode.dart`、`features/live_play/logic/room_refresh_rate.dart`
- 进度：`███████████████████░` 95%

## 任务

| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| T14b.1 | 刷新率和帧率匹配 | 性能 | 完成 | 2026-10-02 | b8462638a | [设计或说明](T14b.1/README.md)、[记录](T14b.1/record.md)、[评审页](T14b.1/page/01-说明.jpg) |
| T14b.2 | 刷新率策略修正：播放中只用帧率声明、没有整数倍取最高、系统限速提示 | 性能 | 待真机 | 2026-10-02 | 584da6662 | [任务书](T14b.2/brief.md)、[记录](T14b.2/record.md) |
