import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/base/live_directory_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/interface/live_directory.dart';

mixin _Probe<T> on BasePageScrollAndStateBone<T> {
  Future<void>? response;
  Future<List<ConnectivityResult>?>? connectivity;
  final modes = <bool>[];
  final sizes = <int>[];
  final errors = <Object>[];
  @override
  Future<List<ConnectivityResult>?> readRequestConnectivity() async =>
      connectivity == null ? null : await connectivity!;
  @override
  void handleError(Object error, {bool showPageError = false}) {
    errors.add(error);
  }

  Future<void> beforeFetch() async {
    modes.add(usesDesktopPagination);
    sizes.add(pageSize.value);
    await response;
  }
}

class _All extends ServerAllPageController<int> with _Probe<int> {
  @override
  Future<List<int>> fetchAllServerData() async {
    await beforeFetch();
    return List.generate(40, (i) => i);
  }
}

class _Fixed extends ServerFixedPageController<int> with _Probe<int> {
  _Fixed() : super(fixedServerPageSize: 40);
  @override
  Future<List<int>> fetchFixedNetworkData(int page, int size) async {
    await beforeFetch();
    return List.generate(size, (i) => i);
  }
}

class _Remote extends ServerRemotePageController<int> with _Probe<int> {
  @override
  Future<List<int>> fetchNetworkData(int page, int size) async {
    await beforeFetch();
    return List.generate(size, (i) => page * 100 + i);
  }
}

class _Source implements LiveSiteDirectoryPager {
  late Future<void> Function() beforeFetch;
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    await beforeFetch();
    return LiveDirectoryPage(
      rooms: List.generate(40, (i) => LiveRoom(roomId: '$i', platform: 'fixture')),
      page: page,
      hasMore: false,
    );
  }
}

class _Native extends LiveDirectoryController with _Probe<LiveRoom> {
  _Native() : super(directory: _Source()) {
    (directory as _Source).beforeFetch = beforeFetch;
  }
}

Future<BasePageScrollAndStateBone<dynamic>> _mount(
  WidgetTester tester,
  String kind,
  bool desktop, {
  Widget Function(BasePageScrollAndStateBone<dynamic>)? buildPage,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(desktop ? 900 : 400, 640);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Get.put(SettingsService(), permanent: true);
  BasePageScrollAndStateBone<dynamic>? c;
  await tester.pumpWidget(
    GetMaterialApp(
      home: Builder(
        builder: (_) {
          c ??= switch (kind) {
            'all' => _All(),
            'fixed' => _Fixed(),
            'remote' => _Remote(),
            _ => _Native(),
          };
          return buildPage?.call(c!) ?? const SizedBox();
        },
      ),
    ),
  );
  for (var frame = 0; frame < 10 && c == null; frame++) {
    await tester.pump();
  }
  expect(c, isNotNull, reason: 'GetMaterialApp must mount the route before constructing its controller');
  final result = c!;
  expect(result.usesDesktopPagination, desktop);
  result.pageSize.value = 2;
  addTearDown(() async {
    result.onDelete();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    Get.reset();
  });
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Hive.openBox('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  setUp(() {
    Get.testMode = true;
    Get.reset();
  });
  tearDownAll(Hive.close);

  for (final kind in ['all', 'fixed', 'remote', 'native']) {
    testWidgets('$kind stable breakpoint commits once despite repeated observations', (tester) async {
      final c = await _mount(tester, kind, false);
      final p = c as _Probe<dynamic>;
      c.checkAndNotifyLayoutChange(true);
      await tester.pump(const Duration(milliseconds: 70));
      c.checkAndNotifyLayoutChange(true);
      await tester.pump(const Duration(milliseconds: 60));
      expect(c.usesDesktopPagination, isTrue);
      expect(p.modes, [true]);
      expect(c.list, isNotEmpty);
    });

    for (final close in [false, true]) {
      testWidgets('$kind cancels a layout already awaiting its request close=$close', (tester) async {
        final c = await _mount(tester, kind, false);
        final p = c as _Probe<dynamic>;
        final gate = Completer<void>();
        p.response = gate.future;
        final operation = c.loadData();
        await tester.pump();
        c.checkAndNotifyLayoutChange(true);
        await tester.pump(const Duration(milliseconds: 200));
        if (close) {
          c.onDelete();
        } else {
          c.checkAndNotifyLayoutChange(false);
        }
        gate.complete();
        await tester.pump();
        await operation;
        await tester.pump();
        expect(c.usesDesktopPagination, isFalse);
        expect(c.pageSize.value, 2);
        expect(p.modes, [false]);
      });
    }

    for (final desktop in [false, true]) {
      for (final preflight in [false, true]) {
        testWidgets('$kind layout waits for ${preflight ? "connectivity" : "response"} from desktop=$desktop', (
          tester,
        ) async {
          final c = await _mount(tester, kind, desktop);
          final p = c as _Probe<dynamic>;
          final gate = Completer<void>();
          final connectivity = Completer<List<ConnectivityResult>?>();
          if (preflight) {
            p.connectivity = connectivity.future;
          } else {
            p.response = gate.future;
          }
          final load = c.loadData();
          await tester.pump();
          c.checkAndNotifyLayoutChange(!desktop);
          await tester.pump(const Duration(milliseconds: 200));
          final modeDuring = c.usesDesktopPagination;
          final sizeDuring = c.pageSize.value;
          if (preflight) {
            connectivity.complete(null);
          } else {
            gate.complete();
          }
          await tester.pump();
          await load;
          await tester.pump();
          expect(modeDuring, desktop);
          expect(sizeDuring, 2);
          expect(p.modes.first, desktop);
          expect(p.sizes.first, 2);
          expect(c.usesDesktopPagination, !desktop);
          expect(p.modes, [desktop, !desktop]);
          expect(p.errors, isEmpty);
          expect(c.list, isNotEmpty);
        });
      }

      testWidgets('$kind transient breakpoint crossing is cancelled desktop=$desktop', (tester) async {
        final c = await _mount(tester, kind, desktop);
        final p = c as _Probe<dynamic>;
        c.checkAndNotifyLayoutChange(!desktop);
        await tester.pump(const Duration(milliseconds: 50));
        c.checkAndNotifyLayoutChange(desktop);
        await tester.pump(const Duration(milliseconds: 200));
        expect(c.usesDesktopPagination, desktop);
        expect(c.pageSize.value, 2);
        expect(p.modes, isEmpty);
      });

      testWidgets('$kind closed layout observation is inert desktop=$desktop', (tester) async {
        final c = await _mount(tester, kind, desktop);
        final p = c as _Probe<dynamic>;
        c.onDelete();
        c.checkAndNotifyLayoutChange(!desktop);
        await tester.pump(const Duration(milliseconds: 200));
        expect(c.usesDesktopPagination, desktop);
        expect(c.pageSize.value, 2);
        expect(p.modes, isEmpty);
      });
    }
  }

  testWidgets('layout waits for remote adaptive re-paging as well as ordinary loads', (tester) async {
    final c = await _mount(tester, 'remote', true);
    final p = c as _Probe<dynamic>;
    final initial = c.loadData();
    await tester.pump();
    await initial;
    final gate = Completer<void>();
    p.response = gate.future;
    c.setPageSize(4);
    await tester.pump();
    expect(p.modes, [true, true]);
    c.checkAndNotifyLayoutChange(false);
    await tester.pump(const Duration(milliseconds: 200));
    final modeDuring = c.usesDesktopPagination;
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(modeDuring, isTrue);
    expect(c.usesDesktopPagination, isFalse);
    expect(p.modes, [true, true, false]);
  });

  for (final desktop in [false, true]) {
    testWidgets('actual BasePageView resize preserves in-flight dimensions from desktop=$desktop', (tester) async {
      var seeded = false;
      final c = await _mount(
        tester,
        'remote',
        desktop,
        buildPage: (owner) {
          if (!seeded) {
            owner.list.assignAll(<int>[1]);
            seeded = true;
          }
          return Scaffold(
            body: BasePageView(
              controller: owner,
              enableRefresh: false,
              enableLoadMore: false,
              wrapMobileRefresh: false,
              showScrollToTopBtn: false,
              contentBuilder: (_, rows, scroll) => ListView(
                key: const ValueKey('layout-rows'),
                controller: scroll,
                children: [for (final row in rows) Text('$row')],
              ),
            ),
          );
        },
      );
      final p = c as _Probe<dynamic>;
      await tester.pump();
      expect(find.byKey(const ValueKey('layout-rows')), findsOneWidget);
      final gate = Completer<void>();
      p.response = gate.future;
      final operation = c.loadData();
      await tester.pump();
      tester.view.physicalSize = Size(desktop ? 400 : 900, 640);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final modeDuring = c.usesDesktopPagination;
      final sizeDuring = c.pageSize.value;
      gate.complete();
      await tester.pump();
      await operation;
      await tester.pumpAndSettle();
      expect(modeDuring, desktop);
      expect(sizeDuring, 2);
      expect(c.usesDesktopPagination, !desktop);
      expect(p.modes, [desktop, !desktop]);
      expect(find.byKey(const ValueKey('layout-rows')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
