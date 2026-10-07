# N02.1 投屏

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构：`packages/live_cast`）
- 来源：模块重构计划 M10（3.x 的 DLNA 投屏：对话框里的流程 + 第三方包 `dlna_dart`，换成纯 Dart 包）
- 旧编号：M10、T12c.1
- 相关：参考 3.x `lib/modules/live_play/dialogs/live_dlna_dialog.dart` 和它的测试、`dlna_dart` 0.1.1、归档 v4 的 `packages/live_cast`（只作参考）；之后的 C01.2（接进直播间的取流弹窗）、`949c2ee1a`（电视显示“主播 - 标题”）、Y01.1 第 4 节（搜索前申请本地网络权限）；记录 [record.md](record.md)

## 目标

投屏的协议和流程全部放进 `packages/live_cast`（只依赖 `meta`、`xml`、`dart:io`），界面只剩画图；行为照 3.x（搜索节奏、20 秒、刷新、先设地址再播放、换设备先暂停、关闭后不再发命令），并修掉 `dlna_dart` 的 11 个问题（列出不能投的设备、反复下载描述、按地址认设备、开 VPN 搜不到等）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11` + `dlna_dart` 0.1.1） | 现在（`packages/live_cast/lib/src/`） | 要做到 |
|---|---|---|---|
| 流程 | 写在对话框的 `State` 里（`live_dlna_dialog.dart`） | `DlnaCastController`（`controller.dart:123`），状态不可变，界面监听重画 | 完成 |
| 列出的设备 | 只要描述能解析就列出（路由器、NAS 也在），点了报 `StateError`（`xmlParser.dart:201-230`、`dlna.dart:57-66`） | 只列有 AVTransport 和可用控制地址的（`description.dart:109`） | 完成 |
| 描述下载 | 每个 SSDP 包都重下一次（`dlna.dart:568-590`） | 按 USN 每次搜索每台只读一次（`discovery.dart:58`） | 完成 |
| 设备身份 | 按基础地址（`dlna.dart:574-578`），同主机两台只剩一台、有线无线出现两次 | 按 UDN | 完成 |
| VPN | 套接字绑 `0.0.0.0`（`dlna.dart:635`），开 Clash TUN 时搜不到 | 每个网卡一个套接字并设组播出口（`ssdp.dart:286`） | 完成 |
| 1900 端口被占 | 整个搜索失败（`dlna.dart:611-633`） | 通告监听尽力而为，靠搜索应答也能找到 | 完成 |
| 控制地址 | 字符串拼接（`dlna.dart:63-64`） | RFC 3986 解析（`description.dart:153`） | 完成 |
| 超时 | 连接阶段不计时（`dlna.dart:472`、`:487`） | 整次计时：动作 15 秒、描述 10 秒 | 完成 |
| 元数据 | 子元素直接塞进参数没转义、`dc:date` 不合法、演出者 `unknow`（`dlna.dart:233-277`） | DIDL-Lite 转义后作字符串参数（`renderer.dart:49`） | 完成 |
| 设备离开 | `byebye` 不处理（`dlna.dart:526-541`） | 收到就去掉；120 秒无消息也去掉 | 完成 |
| 电视上的标题 | 地址 | 当时照 3.x 用地址；`949c2ee1a` 改成“主播 - 标题”（`CastMedia.roomTitle`，`renderer.dart:41`） | 完成 |

## 结果

- 提交：`a070b0ed4`（2026-10-01 合并）。
- 做了什么（详见 [record.md](record.md)“做法”“保留的 v3 行为”）：
  - c1 `controller.dart`：v3 对话框的流程原样搬出；`normalizeDlnaSource` 不变。
  - c2 `discovery.dart` + `ssdp.dart`：照 `dlna_dart` 的节奏（每 2 秒一轮、首轮三个目标间隔 30 毫秒、五轮循环、报文头顺序），交出整份设备列表；按网卡开套接字。
  - c3 `description.dart`、`renderer.dart`、`soap.dart`、`http.dart`、`failure.dart`：设备描述、SOAP 控制、带类型的错误（部分来自归档 v4）。
  - c4 修了 11 个问题（record“审查发现的 v3 问题”），去掉 `dlna_dart` 的 `print`。
- 有意差异：设备 id 是 UDN（副标题仍显示地址）；SOAPAction 用描述里声明的服务类型；`Content-Type` 带 charset、不复用连接；设置地址回 701/705/715 时先停止再设一次、播放回 701 时等 0.8 秒再播（只在 3.x 会直接失败的地方多试一次）；第一轮一个包都发不出时直接“搜索失败”；描述读失败的下一轮再试。
- 依赖：v3 的 `dlna_dart` 换成只依赖 `meta`、`xml` 7.1.0、`dart:io`；测试另用 `fake_async`。
- 测试：当时 56 个；现在 `packages/live_cast/test/` 共 57 个（controller 14、discovery 7、description 10、ssdp 8、renderer 5、soap 9、http 4）。

## 验证

- 自动测试：`cd packages/live_cast && dart test`。
- 真机：**没有**。当时在 WSL 上看到套接字和组播发送正常（1900 端口监听收到了本机每个网卡发出的 M-SEARCH），但局域网里没有设备应答，没能对真电视测试。K90 对真电视投屏 → [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 1 阶段（CHECKLIST 第 1 节第 13 条，F-RT-01）；Android 17 本地网络权限 → O04.1。登记表按当时“单元测试通过”记成“完成”。

## 留下的问题

- 当时“留给其他模块”的都做了：对话框界面和入口（C01.2，现在是 `stream_dialogs.dart` 的 `CastDevices`）；会话型的流不进投屏（C03，`stream_dialogs.dart:111`）；Android 组播锁（`MulticastLock`，`pure_live/multicast_lock`）和本地网络权限（Y01.1 第 4 节）；投给电视的标题（`949c2ee1a`，record 写着“要改先问用户”，提交时没有记录用户的确认——请维护者确认或在 DECISIONS 补一条）。
- 真机：见上。
- `UpnpActionFailure` 的错误码没有变成用户看得懂的提示 → N02 已知问题，真机看到常见错误码后再定。
