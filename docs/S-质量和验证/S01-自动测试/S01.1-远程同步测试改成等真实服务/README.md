# S01.1 远程同步测试改成等真实服务启动（负载高时随机失败）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证（测试稳定性）
- 来源：2026-10-02 门禁里 `remote_sync_test.dart` 的页面测试随机失败（并行跑全套应用测试时）
- 旧编号：T15a.1
- 相关：决定 D-017（测试规则）；[PROCESS.md](../../../PROCESS.md) 第 12 节（随机失败先找根因）；设备同步的功能在 [J05](../../../J-设置和数据/J05-设备同步/README.md)，界面在 A12.6

## 目标

设备同步页的组件测试在机器忙的时候也稳定通过，不再靠重跑门禁；以后写“起真实服务再断言”的测试有一个照着做的写法。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 修之前 | 修之后 |
|---|---|---|---|
| 设备同步页测试 | `v3.2.11:test/remote_sync_test.dart`（105 行）只测协议和服务：配对码六位、二维码带地址和配对码、没配对码先拒绝、对的配对码还要用户同意、不开 CORS；没有起真实服务的页面测试 | `apps/pure_live/test/features/remote_receiver/remote_sync_test.dart` 的 `_pumpPage` 起真实的同步服务（HTTP 服务、UDP 和 mDNS 套接字），固定给 5 × 50 毫秒的真实时间，再把假设备喂进去 | `_pumpPage` 用 `_until(() => service?.running ?? false)` 等服务真正在服务（最多 10 秒），再喂设备 |
| 开关、预览的等待 | — | 点开关后固定 3 × 20 毫秒、输入配对码后固定 5 × 20 毫秒 | 等“同步服务未运行”的文字出现、等 `remote-sync-preview` 出现 |

## 结果

- 根因：服务在机器忙时 250 毫秒内还没起来，喂进去的设备丢了，后面的点按落到“手动输入地址”的按钮上；并行跑 6 次全部失败。
- 改动（提交 `661fa07ad`，只改了 `apps/pure_live/test/features/remote_receiver/remote_sync_test.dart`，25 行增、23 行删）：
  - 新辅助 `_until(tester, done)`（文件第 237 行）：每次真实等 20 毫秒再 `pump`，最多 500 次（10 秒），超时用 `expect(done(), isTrue, reason: 'still waiting after 10 s')` 报清楚是在等什么。
  - 四处固定等待改成按条件等：页面起来后等配对码出现；关掉服务后等“同步服务未运行”；输入配对码后等预览出现；`_pumpPage` 等服务 `running`。
- 改后并行跑 8 次全部通过；没有改被测代码。

## 验证

- 自动测试：`remote_sync_test.dart` 全部用例；门禁 `bash tools/gate/gate.sh --all` 通过。
- 真机：不需要（只改测试）。设备同步本身的真机验证在 [S02.4](../../S02-真机验证/S02.4-K90验证数据和其他/README.md)。

## 留下的问题

- 同样的“固定短等待后直接断言”还有很多（应用测试里 48 个文件用了 `Future<void>.delayed(const Duration(milliseconds: …))`），按条件等的辅助也重复写了三份（本文件、`update_dialogs_test.dart:159`、`live_play_more_test.dart:77`）。列清单和合并辅助归 [S01.2](../S01.2-测试覆盖清单/README.md)。
