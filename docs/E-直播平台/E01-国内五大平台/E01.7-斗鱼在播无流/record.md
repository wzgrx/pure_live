# E01.7 斗鱼在播但没有流：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（`[E01.7]` 提交）
- 设计或说明：[README.md](README.md)（没有任务书：登记表的 note 和委托的决定就是任务）

## 先复现

- `probe douyu 9263298`：详情在播（和平精英，3001106 热度），两档（原画、高清），线路 `hw1a.douyucdn2.cn/live/…` HTTP 404。
- 临时程序（`tools/live_cli/bin/` 下，没有提交）记下每次 `getH5PlayV1` 的 `data.streamStatus` 和线路开头：9263298 的元数据、原画、高清三次回答都是 0，线路 404。
- 扩大范围核对：
  - 推荐前 40 个：39 个是 1（包括 12 个轮播、回放房间），所有线路 200；只有 9263298 是 0。
  - 英雄联盟分区后部 15 个、王者荣耀分区后部 40 个（先取最低一档，看转码是不是要冷启动）：1 的全部 200；0 的 13 个（10880478、10841442、10740603、10510641、10360424、9991570、6827033、3563196、673305、11205397、12905401、12905391、8733439）每档每条线路都是 404。
  - 24422、5720533、1165924、288016 每一档（原画到高清）的回答都是 1，线路都通。
- 结论：`streamStatus` 就是“这个房间现在有没有推上来的流”；为 0 时地址一定 404。

## 根因

- `packages/live_core/lib/src/sites/douyu/douyu_api.dart` 的 `qualities`（修之前不读 `streamStatus`）：在播（`betard` 的 `show_status`）但没有推流的房间，元数据照样给出画质和地址，`resolvePlayUrlsRaw` 把 404 的地址交给播放器，播放器转圈、重试后报播放失败。

## 改了哪些文件

- `packages/live_core/lib/src/sites/douyu/douyu_api.dart`：`qualities` 在 `streamStatus` 为 0 时抛 `StreamUnavailable`（注释写明依据和只看元数据的原因）。
- `fixtures/douyu/S08-meta-9263298-nostream/`：新样本（直连，临时程序录的元数据回答；脱敏照 `S08-meta-24422`：`client_ip` 换成 `203.0.113.7`，`rtmp_live` 的 `wsAuth`、`token`、`did`，`p2pMeta` 的 `txSecret`，表单的 `enc_data`、`tt`、`did`、`auth`，Cookie 的设备号都换成同形的合成值，记在 `meta.json` 的 `scrubbed`）。
- `packages/live_core/test/sites/douyu_api_test.dart`、`douyu_site_test.dart`。
- `tools/live_cli/lib/src/patrol/checks.dart`（P9）、`tools/live_cli/test/checks_test.dart`、`tools/live_cli/test/fakes.dart`（`qualityErrors`）、`docs/E-直播平台/E07-平台巡检/CHECKS.md`。
- `docs/E-直播平台/E01-国内五大平台/E01.6-国内五大平台巡检和修复/record.md`：候选那一段后面注明由本任务落地。

## 新设置、翻译键、门禁基线

- 没有（提示文字用已有的 `room_mark_unplayable_hint`）。

## 测试

- 先写的失败测试：新样本的元数据是 `StreamUnavailable`（改之前返回两档）；site 的列画质和恢复（改之前给出画质）；巡检 P9 没有流的房间跳过（改之前判失败）。
- `douyu_*` 98 个通过；`tools/live_cli` 64 个通过。

## 巡检复测

- `patrol douyu`：正常 12、失败 0、没测到 1（P13 没加弹幕秒数）。P9：“9263298 没有流（StreamUnavailable：getH5PlayV1: streamStatus 0 (no stream pushed)，平台状态，跳过）”；P10 只测有流的 24422、5720533，全部 FLV。

## 和别的任务的关系

- 直播间“没有画面”的显示（`room_status.dart`）、提示文字和按钮没有改；界面那边如果在改面板或提示（UI 代理的提示、面板任务），这里只是让斗鱼走到已有的 `StreamUnavailable` 分支。

## 真机上要看的

- K90：斗鱼分区（王者荣耀、英雄联盟）列表后部找一个这样的房间（或巡检报告里写的房间号，可能已经恢复），进房应直接显示“平台显示在播，但没有给出可播放的地址”，有重试、换房间；正常房间照旧能播，切画质正常。

## K90 复查（2026-10-08，提交 `9126ec299`）

- 9263298 现在已恢复，进房正常播放（原画 1080P30）：正常房间照旧能播 ✓。“在播但没有流”的房间这次没找到，等巡检再遇到时看。
