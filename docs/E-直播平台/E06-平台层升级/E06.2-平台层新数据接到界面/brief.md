# E06.2 平台层新数据接到界面（E06.1“交给界面”的 7 项）

- 规模：中；分组：功能；依赖：—；能否和别的任务同时做：和 D01.32 都改聊天行，建议错开；和直播间组改 `room_controller.dart` 时错开
- 出设计：不用（照已确认的设计和本任务单）
- 先读：`docs/E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/record-2.md` 的“交给界面”一节；`docs/E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/README.md` 第 2、4 条
- 可以改：`features/live_play/`、`app/platforms.dart`、`packages/live_media`（只改 FC2 接手）、`packages/live_core`（只读）；其他目录不改。

## 要做的

- c1 哔哩哔哩轮播：直播间能播（轮播房间用 `getRoundPlayVideo` 的地址，`LivePlayUrlResolution.start` 传给 `PlaybackPlan.of`，从中途接着放，放完接下一个）。
- c2 17LIVE 等平台的名字颜色（`LiveMessage.nameColor`）和徽章（`badges`）在聊天行显示（颜色要过 D04.1 的对比度处理，或在这里同样处理）。
- c3 酷狗 PK：对方房间的消息（`sourceRoomId` 不是本房间）在聊天行加“对方”标签。
- c4 Twitch：保存的 Cookie 被拒时提示一次（`LiveSiteCookieRefusals.cookieRefusals`），文字和键名见记录；`platforms.dart` 按播放器能解的编码传 `TwitchSite(codecs:)`。
- c5 恢复时换了清晰度（Picarto 等）：`_refreshPlan` 里调 `resolveAppliedPlayQuality`，显示实际清晰度。
- c6 FC2：`platforms.dart` 传 `probeControl`，`live_media` 的 `Fc2RecipeOpener.adopt` 改成按频道接手。

## 验收

- 7 项都接上，各有测试（用仓库里的样本和假数据）。
- 测试：每条 c 至少一个。

## 真机上看的（写进记录，维护者在 K90 上看）

- 哔哩哔哩轮播房间能播放，从中途开始。
- 其余要代理（Twitch、17LIVE、FC2、Picarto）或特定时间（酷狗 PK），能看就看，看不了写进记录。

