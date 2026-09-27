import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/index.dart';

mixin _Fixture on BasePageScrollAndStateBone<int> {
  bool desktop = true;
  Future<List<ConnectivityResult>?>? connectivity;
  Future<List<int>> Function(int, int)? handler;
  final requests = <(int, int)>[];
  int running = 0;
  int peak = 0;
  final errors = <Object>[];
  @override
  bool get usesDesktopPagination => desktop;
  @override
  Future<List<ConnectivityResult>?> readRequestConnectivity() async =>
      connectivity == null ? null : await connectivity!;
  @override
  void handleError(Object error, {bool showPageError = false}) {
    errors.add(error);
  }

  Future<List<int>> fetch(int page, int size) async {
    requests.add((page, size));
    running++;
    if (running > peak) peak = running;
    try {
      return handler == null ? List.generate(size, (i) => (page - 1) * size + i) : await handler!(page, size);
    } finally {
      running--;
    }
  }
}

class _Fixed extends ServerFixedPageController<int> with _Fixture {
  _Fixed() : super(fixedServerPageSize: 8);
  @override
  Future<List<int>> fetchFixedNetworkData(int page, int size) => fetch(page, size);
}

class _Remote extends ServerRemotePageController<int> with _Fixture {
  @override
  Future<List<int>> fetchNetworkData(int page, int size) => fetch(page, size);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  T track<T extends BasePageScrollAndStateBone<int>>(T c) {
    c.pageSize.value = 2;
    addTearDown(c.onDelete);
    return c;
  }

  for (final fixed in [false, true]) {
    BasePageScrollAndStateBone<int> make() => track(fixed ? _Fixed() : _Remote());

    test('fixed=$fixed rejects non-positive page sizes without work', () async {
      final c = make();
      final f = c as _Fixture;
      c.setPageSize(0);
      c.setPageSize(-1);
      c.setPageSize(null);
      await _flush();
      expect(c.pageSize.value, 2);
      expect(f.requests, isEmpty);
    });

    for (final refreshFirst in [false, true]) {
      test('fixed=$fixed initial load queues size and refresh refreshFirst=$refreshFirst', () async {
        final c = make();
        final f = c as _Fixture;
        final gate = Completer<List<int>>();
        f.handler = (page, size) async => f.requests.length == 1
            ? await gate.future
            : List.generate(size, (i) => 100 + (page - 1) * (fixed ? 8 : 2) + i);
        final initial = c.loadData();
        await _flush();
        Future<void> refresh;
        if (refreshFirst) {
          refresh = c.refreshData();
          c.setPageSize(3);
        } else {
          c.setPageSize(3);
          refresh = c.refreshData();
        }
        gate.complete(List.generate(fixed ? 8 : 2, (i) => i));
        // Initial callers can still observe this operation independently of
        // the queued refresh; it is not one never-ending drain Future.
        await initial;
        await refresh;
        await _flush();
        await c.loadData();
        expect(c.pageSize.value, 3);
        expect(c.list, [100, 101, 102]);
        expect(f.peak, 1);
        expect(f.errors, isEmpty);
      });
    }

    test('fixed=$fixed failed load preserves pending size and allows recovery', () async {
      final c = make();
      final f = c as _Fixture;
      final gate = Completer<List<int>>();
      f.handler = (_, size) async => f.requests.length == 1 ? await gate.future : List.generate(size, (i) => 100 + i);
      final initial = c.loadData();
      await _flush();
      c.setPageSize(3);
      gate.completeError(StateError('initial failure'));
      await initial;
      await _flush();
      await c.refreshData();
      expect(c.pageSize.value, 3);
      expect(c.list, [100, 101, 102]);
      expect(f.errors, hasLength(1));
      expect(f.peak, 1);
    });

    test('fixed=$fixed resize waits for the active response and last selection wins', () async {
      final c = make();
      final f = c as _Fixture;
      final gate = Completer<List<int>>();
      f.handler = (page, size) async =>
          f.requests.length == 1 ? await gate.future : List.generate(size, (i) => 100 + i);
      final initial = c.loadData();
      await _flush();
      c.setPageSize(4);
      c.setPageSize(3);
      final sizeDuringLoad = c.pageSize.value;
      gate.complete(List.generate(fixed ? 8 : 2, (i) => i));
      await initial;
      await _flush();
      await c.loadData();
      expect(sizeDuringLoad, 2);
      expect(c.pageSize.value, 3);
      expect(c.list, fixed ? [0, 1, 2] : [0, 1, 100]);
      expect(f.peak, 1);
      expect(f.errors, isEmpty);
    });

    test('fixed=$fixed selecting original size cancels queued resize', () async {
      final c = make();
      final f = c as _Fixture;
      final gate = Completer<List<int>>();
      f.handler = (_, _) => gate.future;
      final initial = c.loadData();
      await _flush();
      c.setPageSize(4);
      c.setPageSize(2);
      gate.complete(List.generate(fixed ? 8 : 2, (i) => i));
      await initial;
      await _flush();
      expect(c.pageSize.value, 2);
      expect(c.list, [0, 1]);
      expect(f.requests, hasLength(1));
    });

    test('fixed=$fixed resize during connectivity does not mix request dimensions', () async {
      final c = make();
      final f = c as _Fixture;
      final gate = Completer<List<ConnectivityResult>?>();
      f.connectivity = gate.future;
      final initial = c.loadData();
      c.setPageSize(4);
      c.setPageSize(3);
      final pendingSize = c.pageSize.value;
      gate.complete(null);
      await initial;
      await _flush();
      await c.loadData();
      expect(pendingSize, 2);
      expect(f.requests.first.$2, fixed ? 8 : 2);
      expect(c.pageSize.value, 3);
      expect(c.list, hasLength(3));
      expect(f.peak, 1);
    });

    test('fixed=$fixed mobile load-more preflight does not increment page twice', () async {
      final c = make();
      final f = c as _Fixture;
      f.desktop = false;
      final gate = Completer<List<ConnectivityResult>?>();
      f.connectivity = gate.future;
      final first = c.loadMoreData();
      final second = c.loadMoreData();
      final pageDuring = c.currentPage;
      gate.complete(null);
      await Future.wait([first, second]);
      expect(pageDuring, 2);
      expect(c.currentPage, 2);
      expect(f.requests, hasLength(1));
      expect(c.list, hasLength(2));
    });

    test('fixed=$fixed pending size is discarded after deletion', () async {
      final c = make();
      final f = c as _Fixture;
      final gate = Completer<List<int>>();
      f.handler = (_, _) => gate.future;
      final initial = c.loadData();
      await _flush();
      c.setPageSize(4);
      c.onDelete();
      gate.complete([]);
      await initial;
      await _flush();
      expect(c.pageSize.value, 2);
      expect(c.list, isEmpty);
      expect(f.requests, hasLength(1));
    });
  }

  for (final preflight in [false, true]) {
    for (final refreshFirst in [false, true]) {
      test('remote adaptive resize and refresh serialize preflight=$preflight refreshFirst=$refreshFirst', () async {
        final c = track(_Remote());
        await c.loadData();
        final gate = Completer<List<int>>();
        final connectivity = Completer<List<ConnectivityResult>?>();
        if (preflight) c.connectivity = connectivity.future;
        c.handler = (_, size) async => c.requests.length == 2 ? await gate.future : List.generate(size, (i) => 100 + i);
        c.setPageSize(4);
        await _flush();
        Future<void> refresh;
        if (refreshFirst) {
          refresh = c.refreshData();
          c.setPageSize(3);
        } else {
          c.setPageSize(3);
          refresh = c.refreshData();
        }
        await _flush();
        if (preflight) connectivity.complete(null);
        await _flush();
        final before = c.requests.length;
        gate.complete([2, 3]);
        await refresh;
        await _flush();
        await c.loadData();
        expect(before, 2);
        expect(c.peak, 1);
        expect(c.pageSize.value, 3);
        expect(c.list, [100, 101, 102]);
        expect(c.currentPage, 1);
        expect(c.errors, isEmpty);
      });
    }
  }
}
