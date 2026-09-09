import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_controller.dart';
import 'package:pure_live/modules/popular/popular_grid_controller.dart';

// Keep the production connectivity ownership check; only replace its native IO.
mixin _Probe<T> on BasePageScrollAndStateBone<T> {
  bool desktop = false;
  Future<List<ConnectivityResult>?>? connectivity;
  int reads = 0;
  final finishes = <IndicatorResult>[];
  final errors = <Object>[];

  @override
  bool get usesDesktopPagination => desktop;
  @override
  Future<List<ConnectivityResult>?> readRequestConnectivity() async {
    reads++;
    return connectivity == null ? null : await connectivity!;
  }

  @override
  void finishRefreshControllers(IndicatorResult result) {
    finishes.add(result);
    super.finishRefreshControllers(result);
  }

  @override
  void handleError(Object exception, {bool showPageError = false}) {
    errors.add(exception);
    // Exercise real flags, but keep any unexpected late error off global UI.
    super.handleError(exception, showPageError: true);
  }

  Map<String, Object?> snapshot() => {
    'rows': list.toList(),
    'total': totalCount.value,
    'page': currentPage,
    'size': pageSize.value,
    'more': canLoadMore.value,
    'loading': loadding.value,
    'pageLoading': pageLoadding.value,
    'empty': pageEmpty.value,
    'error': pageError.value,
    'login': notLogin.value,
    'message': errorMsg.value,
    'cellular': showCellularBanner.value,
    'finishes': finishes.toList(),
    'errors': errors.toList(),
  };
}

mixin _Requests on BasePageScrollAndStateBone<int> {
  final requests = <(int, int)>[];
  Future<List<int>> Function(int, int)? handler;
  Future<List<int>> fetch(int page, int size) async {
    requests.add((page, size));
    return handler == null ? List.generate(size, (i) => (page - 1) * 10 + i) : await handler!(page, size);
  }
}

class _Fixed extends ServerFixedPageController<int> with _Probe<int>, _Requests {
  _Fixed() : super(fixedServerPageSize: 2);
  @override
  Future<List<int>> fetchFixedNetworkData(int page, int size) => fetch(page, size);
}

class _Remote extends ServerRemotePageController<int> with _Probe<int>, _Requests {
  @override
  Future<List<int>> fetchNetworkData(int page, int size) => fetch(page, size);
}

class _Site extends LiveSite {
  final gate = Completer<List<LiveRoom>>();
  int calls = 0;
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea area, {int page = 1, int pageSize = 30}) {
    calls++;
    return gate.future;
  }

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 20}) {
    calls++;
    return gate.future;
  }
}

class _AreaFixed extends AreaServerFixedController with _Probe<LiveRoom> {
  _AreaFixed(super.site, super.subCategory) : super(fixedSize: 2);
}

class _AreaRemote extends AreaServerRemoteController with _Probe<LiveRoom> {
  _AreaRemote(super.site, super.subCategory);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  T track<T extends BasePageScrollAndStateBone<dynamic>>(T c) {
    addTearDown(c.onDelete);
    return c;
  }

  for (final fixed in [false, true]) {
    BasePageScrollAndStateBone<int> make({bool desktop = false}) {
      final c = track(fixed ? _Fixed() : _Remote());
      (c as _Probe<int>).desktop = desktop;
      c.pageSize.value = 4;
      return c;
    }

    for (final desktop in [false, true]) {
      for (final fails in [false, true]) {
        for (final partial in [false, true]) {
          test('fixed=$fixed desktop=$desktop late fails=$fails partial=$partial stays closed', () async {
            final c = make(desktop: desktop);
            final p = c as _Probe<int>;
            final r = c as _Requests;
            final gate = Completer<List<int>>();
            r.handler = (page, size) async {
              if (partial && r.requests.length == 1) return [1, 2];
              if (r.requests.length == (partial ? 2 : 1)) return await gate.future;
              return [9, 10];
            };
            final operation = c.loadData();
            await _flush();
            expect(r.requests, hasLength(partial ? 2 : 1));
            c.onDelete();
            final before = p.snapshot();
            if (fails) {
              gate.completeError(StateError('late'));
            } else {
              gate.complete([3, 4]);
            }
            await operation;
            expect(p.snapshot(), before);
            expect(r.requests, hasLength(partial ? 2 : 1));
          });
        }
      }

      test('fixed=$fixed desktop=$desktop closed cached entrypoints are inert', () async {
        final c = make(desktop: desktop);
        final p = c as _Probe<int>;
        final r = c as _Requests;
        await c.loadData();
        expect(c.list, hasLength(4));
        c.onDelete();
        final before = p.snapshot();
        final calls = r.requests.length;
        await c.goToPage(2);
        c.setPageSize(1);
        await c.loadMoreData();
        await c.loadData();
        await c.refreshData();
        await _flush();
        expect(p.snapshot(), before);
        expect(r.requests, hasLength(calls));
      });
    }

    for (final fails in [false, true]) {
      test('fixed=$fixed deleted connectivity fails=$fails never fetches or finishes', () async {
        final c = make();
        final p = c as _Probe<int>;
        final gate = Completer<List<ConnectivityResult>?>();
        p.connectivity = gate.future;
        final operation = c.loadData();
        expect(p.reads, 1);
        c.onDelete();
        final before = p.snapshot();
        if (fails) {
          gate.completeError(StateError('plugin'));
        } else {
          gate.complete([ConnectivityResult.mobile]);
        }
        await operation;
        expect(p.snapshot(), before);
        expect((c as _Requests).requests, isEmpty);
      });
    }

    test('fixed=$fixed closed before first load starts no work', () async {
      final c = make()..onDelete();
      final p = c as _Probe<int>;
      final before = p.snapshot();
      await c.loadData();
      await c.loadMoreData();
      await c.refreshData();
      expect(p.reads, 0);
      expect((c as _Requests).requests, isEmpty);
      expect(p.snapshot(), before);
    });

    test('fixed=$fixed queued refresh stops at deletion', () async {
      final c = make();
      final p = c as _Probe<int>;
      final r = c as _Requests;
      final gate = Completer<List<int>>();
      r.handler = (_, _) => gate.future;
      final operation = c.loadData();
      await _flush();
      final refresh = c.refreshData();
      c.onDelete();
      final before = p.snapshot();
      gate.complete([]);
      await Future.wait([operation, refresh]);
      expect(p.snapshot(), before);
      expect(r.requests, hasLength(1));
    });

    for (final error in [null, '-352', "NoSuchMethodError: '[]'"]) {
      for (final closed in [false, true]) {
        test('fixed=$fixed area response error=$error closed=$closed retains ownership', () async {
          final source = _Site();
          final site = Site(id: 'fixture', name: 'Fixture', logo: '', liveSite: source);
          final area = LiveArea(areaId: 'a', areaName: 'new');
          final c = track(fixed ? _AreaFixed(site, area) : _AreaRemote(site, area));
          c.pageSize.value = 1;
          final p = c;
          final row = LiveRoom(roomId: 'r', area: 'original');
          final operation = c.loadData();
          await _flush();
          expect(source.calls, 1);
          if (closed) c.onDelete();
          final before = p.snapshot();
          if (error == null) {
            source.gate.complete([row]);
          } else {
            source.gate.completeError(Exception(error));
          }
          await operation;
          if (closed) {
            expect(p.snapshot(), before);
            expect(row.area, 'original');
          } else {
            expect(c.notLogin.value, error != null);
            expect(c.list, error == null ? [row] : isEmpty);
            expect(row.area, error == null ? 'new' : 'original');
            expect(p.errors, isEmpty);
          }
        });
      }
    }

    test('fixed=$fixed popular late hook skips released settings', () async {
      expect(Get.isRegistered<SettingsService>(), isFalse);
      final source = _Site();
      final site = Site(id: 'fixture', name: 'Fixture', logo: '', liveSite: source);
      final c = track(fixed ? PopularServerFixedController(site, fixedSize: 2) : PopularServerRemoteController(site));
      final operation = fixed
          ? (c as PopularServerFixedController).fetchFixedNetworkData(1, 2)
          : (c as PopularServerRemoteController).fetchNetworkData(1, 2);
      c.onDelete();
      source.gate.complete([LiveRoom(roomId: 'r')]);
      expect(await operation, isEmpty);
    });
  }

  for (final phase in ['connectivity', 'success', 'failure']) {
    test('open remote adaptive resizing still completes phase=$phase', () async {
      final c = track(
        _Remote()
          ..desktop = true
          ..pageSize.value = 2,
      );
      await c.loadData();
      final response = Completer<List<int>>();
      final connectivity = Completer<List<ConnectivityResult>?>();
      if (phase == 'connectivity') c.connectivity = connectivity.future;
      c.handler = (_, _) => response.future;
      c.setPageSize(4);
      await _flush();
      if (phase == 'connectivity') {
        expect(c.requests, hasLength(1));
        connectivity.complete([ConnectivityResult.mobile]);
        await _flush();
      }
      expect(c.requests, hasLength(2));
      expect(c.loadding.value, isTrue);
      if (phase == 'failure') {
        response.completeError(StateError('current adaptive error'));
      } else {
        response.complete([3, 4]);
      }
      await _flush();
      expect(c.list, phase == 'failure' ? [0, 1] : [0, 1, 3, 4]);
      expect(c.errors, hasLength(phase == 'failure' ? 1 : 0));
      expect(c.loadding.value, isFalse);
      expect(c.finishes, hasLength(2));
    });

    test('remote adaptive resizing stops after close phase=$phase', () async {
      final c = track(
        _Remote()
          ..desktop = true
          ..pageSize.value = 2,
      );
      await c.loadData();
      final response = Completer<List<int>>();
      final connectivity = Completer<List<ConnectivityResult>?>();
      if (phase == 'connectivity') c.connectivity = connectivity.future;
      c.handler = (_, _) async => response.future;
      final initialCalls = c.requests.length;
      c.setPageSize(4);
      await _flush();
      expect(c.requests.length, initialCalls + (phase == 'connectivity' ? 0 : 1));
      c.onDelete();
      final before = c.snapshot();
      if (phase == 'connectivity') {
        connectivity.complete([ConnectivityResult.mobile]);
        response.complete([]);
      } else if (phase == 'failure') {
        response.completeError(StateError('adaptive late'));
      } else {
        response.complete([3, 4]);
      }
      // setPageSize is the production void API; drain its microtask chain.
      await _flush();
      await _flush();
      expect(c.snapshot(), before);
      expect(c.requests.length, initialCalls + (phase == 'connectivity' ? 0 : 1));
    });
  }
}
