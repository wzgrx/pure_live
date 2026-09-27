import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';

/// Lets a tap's work and a dialog or sheet transition finish (fixed time;
/// no pumpAndSettle).
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Account settings in memory (the drift store's writes never finish on the
/// widget tests' fake clock).
final class MemoryAccountSettings implements AccountSettings {
  @override
  DateTime? douyuSavedAt;

  int bilibiliUid = 0;

  @override
  Future<void> setDouyuSavedAt(DateTime? at) async => douyuSavedAt = at;

  @override
  Future<void> setBilibiliUid(int uid) async => bilibiliUid = uid;
}

/// An account store on an in-memory secret store.
Future<(AccountStore, SecretStore, MemoryAccountSettings)> memoryAccounts([
  Map<String, String> secrets = const {},
]) async {
  final store = await SecretStore.memory(secrets);
  final settings = MemoryAccountSettings();
  return (AccountStore(store, settings), store, settings);
}

typedef QrPoll = ({BilibiliQrState state, String? cookie});

/// Scripted B 站 sign-in calls; each poll answer is taken in order.
class FakeBilibiliLogin implements BilibiliLoginApi {
  final codes = <String>[];
  final polls = <String>[];
  final answers = <Object>[];
  Object accountAnswer = const AccountIdentity(name: '测试', uid: '42');
  final checked = <String>[];

  @override
  Future<({String key, Uri url})> qrCode() async {
    final key = 'k${codes.length + 1}';
    codes.add(key);
    return (key: key, url: Uri.parse('https://account.bilibili.com/h5/qr?key=$key'));
  }

  @override
  Future<QrPoll> qrPoll(String key) async {
    polls.add(key);
    final answer = answers.isEmpty ? (state: BilibiliQrState.waiting, cookie: null) : answers.removeAt(0);
    if (answer is QrPoll) return answer;
    Error.throwWithStackTrace(answer, StackTrace.current);
  }

  @override
  Future<AccountIdentity> account(String cookie) async {
    checked.add(cookie);
    final result = accountAnswer;
    if (result is AccountIdentity) return result;
    Error.throwWithStackTrace(result, StackTrace.current);
  }
}
