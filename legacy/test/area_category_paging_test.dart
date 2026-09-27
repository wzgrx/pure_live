import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';

List<LiveArea> _areas(String prefix, int count) => [
  for (var i = 1; i <= count; i++) LiveArea(platform: 'fixture', areaId: '$prefix$i'),
];

List<String?> _ids(Iterable<LiveArea> areas) => areas.map((a) => a.areaId).toList();

class _Site extends LiveSite {
  _Site(this.catalog);
  final List<LiveCategory> catalog;
  int calls = 0;
  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    calls++;
    return catalog;
  }
}

class _Controller extends AreasListController {
  _Controller(_Site source, {this.desktop = true})
    : super(Site(id: 'fixture', name: 'Fixture', logo: '', liveSite: source));
  final bool desktop;
  final errors = <Object>[];
  @override
  bool get usesDesktopPagination => desktop;
  @override
  Future<bool> checkNetworkBeforeRequest() async => true;
  @override
  void handleError(Object error, {bool showPageError = false}) {
    errors.add(error);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _Controller controllerFor(_Site source, {bool desktop = true}) {
    final controller = _Controller(source, desktop: desktop)..pageSize.value = 2;
    addTearDown(controller.onClose);
    return controller;
  }

  test('view category owns a mutable list separate from the adapter result', () {
    final source = LiveCategory(id: 'a', name: 'A', children: _areas('a', 3));
    final view = AppLiveCategory.fromLiveCategory(source);
    expect(identical(view.children, source.children), isFalse);
    view.children.clear();
    expect(_ids(source.children), ['a1', 'a2', 'a3']);
  });

  for (final immutable in [true, false]) {
    test('desktop replaces a page without mutating ${immutable ? 'immutable' : 'mutable'} source', () async {
      final sourceRows = _areas('a', 5);
      final category = LiveCategory(
        id: 'a',
        name: 'A',
        children: immutable ? List.unmodifiable(sourceRows) : sourceRows,
      );
      final source = _Site([category]);
      final controller = controllerFor(source);
      await controller.loadData();
      expect(controller.errors, isEmpty);
      expect(_ids(controller.categories.single.children), ['a1', 'a2']);
      for (var i = 0; i < 3; i++) {
        controller.processLocalPaging();
        expect(_ids(controller.categories.single.children), ['a1', 'a2']);
      }
      await controller.goToPage(2);
      expect(_ids(controller.list), ['a3', 'a4']);
      expect(_ids(controller.categories.single.children), ['a3', 'a4']);
      await controller.goToPage(3);
      expect(_ids(controller.list), ['a5']);
      expect(controller.canLoadMore.value, isFalse);
      await controller.goToPage(1);
      controller.setPageSize(4);
      expect(_ids(controller.categories.single.children), ['a1', 'a2', 'a3', 'a4']);
      await controller.refreshData();
      expect(controller.errors, isEmpty);
      expect(controller.totalCount.value, 5);
      expect(_ids(category.children), ['a1', 'a2', 'a3', 'a4', 'a5']);
      expect(source.calls, 2);
    });
  }

  test('page navigation uses the selected category rather than the initial category count', () async {
    final source = _Site([
      LiveCategory(id: 'short', name: 'Short', children: _areas('s', 1)),
      LiveCategory(id: 'long', name: 'Long', children: _areas('l', 5)),
    ]);
    final controller = controllerFor(source);
    await controller.loadData();
    controller.selectCategory(1);
    expect(controller.totalCount.value, 5);
    await controller.goToPage(3);
    expect(controller.currentPage, 3);
    expect(_ids(controller.list), ['l5']);
    controller.selectCategory(0);
    await controller.goToPage(2);
    expect(controller.currentPage, 1);
    expect(_ids(controller.list), ['s1']);
    expect(source.calls, 1);
  });

  test('fixed-size category responses are accepted by desktop paging', () async {
    final category = LiveCategory(id: 'a', name: 'A', children: List.of(_areas('a', 3), growable: false));
    final controller = controllerFor(_Site([category]));
    await controller.loadData();
    expect(controller.errors, isEmpty);
    expect(_ids(controller.categories.single.children), ['a1', 'a2']);
    expect(category.children, hasLength(3));
  });

  test('empty category can switch to a populated category and reach its last page', () async {
    final controller = controllerFor(
      _Site([
        LiveCategory(id: 'empty', name: 'Empty', children: const []),
        LiveCategory(id: 'full', name: 'Full', children: List.unmodifiable(_areas('f', 3))),
      ]),
    );
    await controller.loadData();
    expect(controller.pageEmpty.value, isTrue);
    controller.selectCategory(1);
    await controller.goToPage(2);
    expect(_ids(controller.list), ['f3']);
    controller.selectCategory(0);
    expect(controller.list, isEmpty);
    expect(controller.canLoadMore.value, isFalse);
  });

  test('mobile keeps complete category lists without changing the adapter lists', () async {
    final rows = List<LiveArea>.unmodifiable(_areas('m', 5));
    final controller = controllerFor(_Site([LiveCategory(id: 'm', name: 'M', children: rows)]), desktop: false);
    await controller.loadData();
    controller.processLocalPaging();
    expect(controller.errors, isEmpty);
    expect(controller.list, hasLength(5));
    expect(controller.categories.single.children, hasLength(5));
    expect(rows, hasLength(5));
    expect(controller.canLoadMore.value, isFalse);
  });
}
