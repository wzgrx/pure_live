import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/modules/popular/popular_grid_controller.dart';

mixin _Probe<T> on LocalReactivePageController<T> {
  bool? desktop;
  final finishes = <IndicatorResult>[];
  final errors = <Object>[];
  @override
  bool get usesDesktopPagination => desktop ?? super.usesDesktopPagination;
  @override
  void finishRefreshControllers(IndicatorResult result) {
    finishes.add(result);
  }

  @override
  void handleError(Object error, {bool showPageError = false}) {
    errors.add(error);
    pageError.value = true;
    errorMsg.value = error.toString();
  }

  Map<String, Object?> snapshot() => {
    'list': list.toList(),
    'size': pageSize.value,
    'page': currentPage,
    'total': totalCount.value,
    'empty': pageEmpty.value,
    'loading': loadding.value,
    'pageLoading': pageLoadding.value,
    'canLoadMore': canLoadMore.value,
    'notLogin': notLogin.value,
    'error': pageError.value,
    'message': errorMsg.value,
    'finishes': finishes.toList(),
    'errors': errors.toList(),
  };
}

class _Local extends LocalReactivePageController<int> with _Probe<int> {}

class _Site extends LiveSite {
  Future<List<LiveRoom>>? response;
  int calls = 0;
  final sizes = <int>[];
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 20}) async {
    calls++;
    sizes.add(pageSize);
    return response == null ? [LiveRoom(roomId: 'b'), LiveRoom(roomId: 'a')] : await response!;
  }
}

class _Popular extends PopularLocalReactiveController with _Probe<LiveRoom> {
  _Popular(_Site source, {String id = Sites.iptvSite})
    : super(Site(id: id, name: 'Fixture', logo: '', liveSite: source));
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Hive.openBox('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  tearDownAll(Hive.close);
  T track<T extends LocalReactivePageController<dynamic>>(T c) {
    addTearDown(c.onDelete);
    return c;
  }

  for (final desktop in [false, true]) {
    test('local committed mode controls projection desktop=$desktop', () async {
      final c = track(
        _Local()
          ..desktop = desktop
          ..pageSize.value = 2,
      );
      c.updateLocalReactivePool([1, 2, 3, 4]);
      expect(c.list, desktop ? [1, 2] : [1, 2, 3, 4]);
      if (desktop) {
        await c.goToPage(2);
        expect(c.list, [3, 4]);
        c.setPageSize(4);
        expect(c.list, [1, 2, 3, 4]);
      }
    });

    test('closed local projections and entrypoints stay inert desktop=$desktop', () async {
      final c = track(
        _Local()
          ..desktop = desktop
          ..pageSize.value = 2,
      );
      c.updateLocalReactivePool([1, 2, 3, 4]);
      var callbacks = 0;
      c.onExternalRefresh = () async {
        callbacks++;
      };
      c.onDelete();
      final before = c.snapshot();
      c.updateLocalReactivePool([9]);
      c.setPageSize(1);
      await c.goToPage(2);
      await c.loadData();
      await c.loadMoreData();
      await c.refreshData();
      expect(c.snapshot(), before);
      expect(callbacks, 0);
    });

    test('local page size validates input and preserves mode desktop=$desktop', () {
      final c = track(
        _Local()
          ..desktop = desktop
          ..pageSize.value = 2,
      );
      c.updateLocalReactivePool([1, 2, 3, 4]);
      final before = c.snapshot();
      for (final value in <int?>[null, 0, -2]) {
        c.setPageSize(value);
      }
      expect(c.snapshot(), before);
      c.setPageSize(3);
      expect(c.pageSize.value, 3);
      expect(c.list, desktop ? [1, 2, 3] : [1, 2, 3, 4]);
    });
  }

  test('snapshot ownership exists before a synchronous callback reenters loading', () async {
    final c = track(_Local());
    Future<void>? nested;
    var calls = 0;
    c.onExternalRefresh = () async {
      calls++;
      nested = c.loadExternalSnapshot();
      c.updateLocalReactivePool([1]);
    };
    final operation = c.loadExternalSnapshot();
    expect(identical(nested, operation), isTrue);
    await operation;
    expect(calls, 1);
    expect(c.finishes, [IndicatorResult.noMore]);
    expect(c.activePageOperation, isNull);
  });

  test('a generic external callback can await cached projection without waiting on itself', () async {
    final c = track(_Local()..desktop = false);
    c.onExternalRefresh = () async {
      c.updateLocalReactivePool([1]);
      await c.loadData();
    };
    await c.refreshData();
    expect(c.list, [1]);
    expect(c.finishes, [IndicatorResult.noMore]);
  });

  test('unchanged external snapshot still resets the page and completes once', () async {
    final c = track(
      _Local()
        ..desktop = true
        ..pageSize.value = 2,
    );
    final rows = [1, 2, 3, 4];
    c.updateLocalReactivePool(rows);
    await c.goToPage(2);
    final finishes = c.finishes.length;
    c.onExternalRefresh = () async {
      c.updateLocalReactivePool(rows);
    };
    await c.refreshData();
    expect(c.currentPage, 1);
    expect(c.list, [1, 2]);
    expect(c.finishes, hasLength(finishes + 1));
    expect(c.loadding.value, isFalse);
    expect(c.pageEmpty.value, isFalse);
  });

  test('closing discards queued refresh and page-size intents but observes the active result', () async {
    final c = track(
      _Local()
        ..desktop = true
        ..pageSize.value = 2,
    );
    c.updateLocalReactivePool([1, 2, 3]);
    final gate = Completer<void>();
    var calls = 0;
    c.onExternalRefresh = () async {
      calls++;
      await gate.future;
      c.updateLocalReactivePool([4]);
    };
    final first = c.refreshData();
    final pending = c.refreshData();
    final more = c.loadMoreData();
    c.setPageSize(3);
    c.onDelete();
    final before = c.snapshot();
    gate.completeError(StateError('late failure'));
    await Future.wait([first, pending, more]);
    await _flush();
    expect(calls, 1);
    expect(c.snapshot(), before);
    expect(c.activePageOperation, isNull);
  });

  test('selecting the current size cancels an earlier pending size', () async {
    final c = track(
      _Local()
        ..desktop = true
        ..pageSize.value = 2,
    );
    final gate = Completer<void>();
    c.onExternalRefresh = () async {
      await gate.future;
      c.updateLocalReactivePool([1, 2, 3, 4]);
    };
    final operation = c.refreshData();
    c.setPageSize(3);
    c.setPageSize(2);
    gate.complete();
    await operation;
    await _flush();
    expect(c.pageSize.value, 2);
    expect(c.list, [1, 2]);
    expect(c.finishes, [IndicatorResult.success]);
  });

  for (final fails in [false, true]) {
    test('local external response after delete fails=$fails is observed without publication', () async {
      final c = track(_Local());
      c.updateLocalReactivePool([1]);
      final gate = Completer<void>();
      c.onExternalRefresh = () async {
        await gate.future;
        c.updateLocalReactivePool([2]);
      };
      final operation = c.refreshData();
      await _flush();
      c.onDelete();
      final before = c.snapshot();
      Object? escaped;
      final observed = operation.catchError((Object e) {
        escaped = e;
      });
      if (fails) {
        gate.completeError(StateError('late'));
      } else {
        gate.complete();
      }
      await observed;
      expect(c.snapshot(), before);
      expect(escaped, isNull);
      expect(c.activePageOperation, isNull);
    });
  }

  test('external refresh keeps indicator ownership until callback completes', () async {
    final c = track(_Local());
    c.updateLocalReactivePool([1]);
    final initialFinishes = c.finishes.length;
    final gate = Completer<void>();
    c.onExternalRefresh = () async {
      c.updateLocalReactivePool([2]);
      await gate.future;
    };
    final operation = c.refreshData();
    final during = c.finishes.length;
    final hasActive = c.activePageOperation != null;
    gate.complete();
    await operation;
    expect(during, initialFinishes);
    expect(hasActive, isTrue);
    expect(c.finishes, hasLength(initialFinishes + 1));
    expect(c.list, [2]);
  });

  test('external failure retains rows and finishes failure instead of success', () async {
    final c = track(_Local());
    c.updateLocalReactivePool([1]);
    c.onExternalRefresh = () async {
      throw StateError('current');
    };
    Object? escaped;
    await c.refreshData().catchError((Object e) {
      escaped = e;
    });
    expect(escaped, isNull);
    expect(c.errors, hasLength(1));
    expect(c.list, [1]);
    expect(c.finishes.last, IndicatorResult.fail);
    expect(c.loadding.value, isFalse);
    c.onExternalRefresh = () async {
      c.updateLocalReactivePool([2]);
    };
    await c.refreshData();
    expect(c.list, [2]);
    expect(c.pageError.value, isFalse);
  });

  test('repeated external refresh queues one fresh snapshot, not parallel callbacks', () async {
    final c = track(_Local());
    var calls = 0;
    final first = Completer<void>();
    final second = Completer<void>();
    c.onExternalRefresh = () async {
      final mine = ++calls;
      await (mine == 1 ? first.future : second.future);
      c.updateLocalReactivePool([mine]);
    };
    final initial = c.refreshData();
    final refresh = c.refreshData();
    final duplicate = c.refreshData();
    final during = calls;
    first.complete();
    await initial;
    await _flush();
    second.complete();
    await Future.wait([refresh, duplicate]);
    expect(during, 1);
    expect(calls, 2);
    expect(c.list, [2]);
  });

  test('page size intent waits for external snapshot and applies the final selection', () async {
    final c = track(
      _Local()
        ..desktop = true
        ..pageSize.value = 2,
    );
    c.updateLocalReactivePool([1, 2, 3, 4]);
    final gate = Completer<void>();
    c.onExternalRefresh = () async {
      await gate.future;
      c.updateLocalReactivePool([5, 6, 7, 8]);
    };
    final refresh = c.refreshData();
    c.setPageSize(4);
    c.setPageSize(3);
    final during = c.pageSize.value;
    gate.complete();
    await refresh;
    await _flush();
    expect(during, 2);
    expect(c.pageSize.value, 3);
    expect(c.list, [5, 6, 7]);
  });

  for (final fails in [false, true]) {
    test('IPTV late loading fails=$fails never publishes or presents', () async {
      final source = _Site();
      final gate = Completer<List<LiveRoom>>();
      source.response = gate.future;
      final c = track(_Popular(source));
      final operation = c.loadData();
      await _flush();
      c.onDelete();
      final before = c.snapshot();
      if (fails) {
        gate.completeError(StateError('late'));
      } else {
        gate.complete([LiveRoom(roomId: 'late')]);
      }
      await operation;
      expect(c.snapshot(), before);
    });
  }

  test('IPTV initial load shares one operation and preserves playlist order', () async {
    final source = _Site();
    final gate = Completer<List<LiveRoom>>();
    source.response = gate.future;
    final c = track(_Popular(source));
    final first = c.loadData();
    final second = c.loadData();
    final during = source.calls;
    gate.complete([LiveRoom(roomId: 'b'), LiveRoom(roomId: 'a')]);
    await Future.wait([first, second]);
    expect(during, 1);
    expect(c.list.map((e) => e.roomId), ['b', 'a']);
    expect(c.finishes, hasLength(1));
    expect(c.activePageOperation, isNull);
  });

  test('IPTV refresh failure stays failed and a later refresh recovers', () async {
    final source = _Site();
    final c = track(_Popular(source));
    await c.loadData();
    final old = c.list.toList();
    final gate = Completer<List<LiveRoom>>();
    source.response = gate.future;
    final refresh = c.refreshData();
    await _flush();
    gate.completeError(StateError('playlist failed'));
    await refresh;
    expect(c.list, old);
    expect(c.errors, hasLength(1));
    expect(c.finishes.last, IndicatorResult.fail);
    source.response = null;
    await c.refreshData();
    expect(c.errors, hasLength(1));
    expect(c.pageError.value, isFalse);
    expect(c.list.map((e) => e.roomId), ['b', 'a']);
  });

  test('popular local raw hook does not read settings after deletion', () async {
    final source = _Site();
    final gate = Completer<List<LiveRoom>>();
    source.response = gate.future;
    final c = track(_Popular(source, id: 'fixture'));
    final operation = c.getLocalRawData();
    c.onDelete();
    gate.complete([LiveRoom(roomId: 'late')]);
    expect(await operation, isEmpty);
  });

  test('empty IPTV snapshot completes the initial loading state once', () async {
    final source = _Site()..response = Future.value(<LiveRoom>[]);
    final c = track(_Popular(source));
    await c.loadData();
    expect(c.totalCount.value, 0);
    expect(c.pageEmpty.value, isTrue);
    expect(c.loadding.value, isFalse);
    expect(c.pageLoadding.value, isFalse);
    expect(c.finishes, [IndicatorResult.noMore]);
  });

  for (final desktop in [false, true]) {
    testWidgets('IPTV BasePageView resize waits for its external snapshot desktop=$desktop', (tester) async {
      Get.testMode = true;
      Get.reset();
      Get.put(SettingsService(), permanent: true);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(desktop ? 900 : 400, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = _Site();
      _Popular? owner;
      await tester.pumpWidget(
        GetMaterialApp(
          home: Builder(
            builder: (_) {
              owner ??= _Popular(source)
                ..pageSize.value = 2
                ..updateLocalReactivePool([LiveRoom(roomId: 'seed')]);
              return Scaffold(
                body: BasePageView<_Popular, LiveRoom>(
                  controller: owner!,
                  enableRefresh: false,
                  enableLoadMore: false,
                  wrapMobileRefresh: false,
                  showScrollToTopBtn: false,
                  contentBuilder: (_, rows, scroll) => ListView(
                    key: const ValueKey('local-rows'),
                    controller: scroll,
                    children: [for (final room in rows) Text(room.roomId ?? '')],
                  ),
                ),
              );
            },
          ),
        ),
      );
      for (var frame = 0; frame < 10 && owner == null; frame++) {
        await tester.pump();
      }
      expect(owner, isNotNull);
      final c = owner!;
      addTearDown(() async {
        c.onDelete();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        Get.reset();
      });
      await tester.pump();
      expect(find.byKey(const ValueKey('local-rows')), findsOneWidget);
      expect(c.usesDesktopPagination, desktop);
      final gate = Completer<List<LiveRoom>>();
      source.response = gate.future;
      final operation = c.loadData();
      await tester.pump();
      tester.view.physicalSize = Size(desktop ? 400 : 900, 640);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final duringMode = c.usesDesktopPagination;
      final duringSize = c.pageSize.value;
      gate.complete(List.generate(40, (i) => LiveRoom(roomId: '$i')));
      await tester.pump();
      await operation;
      await tester.pumpAndSettle();
      expect(duringMode, desktop);
      expect(duringSize, 2);
      expect(c.usesDesktopPagination, !desktop);
      expect(source.calls, 2);
      expect(source.sizes, [2, c.pageSize.value]);
      expect(c.list.length, desktop ? 40 : c.pageSize.value.clamp(1, 40));
      expect(c.list.first.roomId, '0');
      expect(find.byKey(const ValueKey('local-rows')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
