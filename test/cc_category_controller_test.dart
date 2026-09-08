import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/cc/cc_site.dart';
import 'package:pure_live/core/interface/live_directory.dart';
import 'package:pure_live/common/base/live_directory_controller.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_binding.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final ResponseBody Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancel) async =>
      reply(options);
  @override
  void close({bool force = false}) {}
}

List<String> _ids(int first, int last) => [for (var id = first; id <= last; id++) '$id'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio previous;
  late Dio dio;
  late List<RequestOptions> requests;
  var count = 75;
  var invalid = false;
  setUpAll(() async {
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put(SettingsService());
    previous = HttpClient.instance.dio;
    requests = [];
    count = 75;
    invalid = false;
    dio = Dio()
      ..httpClientAdapter = _Adapter((request) {
        requests.add(request);
        final start = request.queryParameters['start'] as int;
        final size = request.queryParameters['size'] as int;
        return ResponseBody.fromString(
          jsonEncode(
            invalid
                ? {'error': 'fixture'}
                : {
                    'gametype': 3,
                    'lives': [
                      for (var id = start + 1; id <= start + size && id <= count; id++)
                        {'cuteid': '$id', 'status': 1, 'gamename': 'Server name'},
                    ],
                    'videos': [],
                  },
          ),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    HttpClient.instance.dio = dio;
  });
  tearDown(() {
    HttpClient.instance.dio = previous;
    dio.close(force: true);
    Get.reset();
  });
  tearDownAll(() async => Hive.close());

  BasePageScrollAndStateBone<LiveRoom> controllerFor({bool desktop = true, int size = 20}) {
    final site = Site(id: 'cc', name: 'CC', logo: '', liveSite: CCSite());
    final oldFavorite = LiveArea.fromJson({
      'platform': 'cc',
      'areaId': '3',
      'areaType': '2',
      'areaName': 'Favorite label',
    });
    final controller = AreaRoomsBinding.createController(site, oldFavorite);
    controller.checkAndNotifyLayoutChange(desktop);
    controller.pageSize.value = size;
    addTearDown(controller.onClose);
    return controller;
  }

  test('actual category binding keeps the tail of a 30-row response on desktop', () async {
    final controller = controllerFor();
    await controller.loadData();
    expect(controller.list.map((r) => r.roomId), _ids(1, 20));
    await controller.goToPage(2);
    expect(controller.list.map((r) => r.roomId), _ids(21, 40));
    await controller.goToPage(3);
    expect(controller.list.map((r) => r.roomId), _ids(41, 60));
    await controller.goToPage(4);
    expect(controller.list.map((r) => r.roomId), _ids(61, 75));
    expect(controller.canLoadMore.value, isFalse);
    expect(requests.map((r) => r.queryParameters['start']), [0, 30, 60]);
    expect(requests.map((r) => r.queryParameters['size']), everyElement(30));
  });

  test('actual category binding appends all native response tails on mobile', () async {
    final controller = controllerFor(desktop: false);
    await controller.loadData();
    await controller.loadMoreData();
    expect(controller.list.map((r) => r.roomId), _ids(1, 40));
    await controller.loadMoreData();
    await controller.loadMoreData();
    expect(controller.list.map((r) => r.roomId), _ids(1, 75));
    expect(controller.canLoadMore.value, isFalse);
  });

  test('desktop page-size change re-slices retained rooms without gaps', () async {
    final controller = controllerFor();
    await controller.loadData();
    await controller.goToPage(2);
    controller.setPageSize(40);
    await controller.loadData();
    expect(controller.list.map((r) => r.roomId), _ids(1, 40));
    await controller.goToPage(2);
    expect(controller.list.map((r) => r.roomId), _ids(41, 75));
    expect(controller.canLoadMore.value, isFalse);
    expect(requests.map((r) => r.queryParameters['start']), [0, 30, 60]);
  });

  test('a larger UI page combines native pages and keeps the final short tail', () async {
    final controller = controllerFor(size: 60);
    await controller.loadData();
    expect(controller.list.map((r) => r.roomId), _ids(1, 60));
    await controller.goToPage(2);
    expect(controller.list.map((r) => r.roomId), _ids(61, 75));
    expect(controller.canLoadMore.value, isFalse);
  });

  test('category-only capability preserves recommendation routing and favorite identity', () async {
    final source = CCSite();
    expect(source, isNot(isA<LiveSiteDirectoryPager>()));
    final controller = controllerFor();
    expect(controller, isA<LiveDirectoryController>());
    await controller.loadData();
    expect(controller.list.map((r) => r.area), everyElement('Favorite label'));
    final category = (controller as LiveDirectoryController).category!;
    expect(category.areaId, '3');
    expect(category.areaType, '2');
    expect(requests.single.cancelToken, isNotNull);
    await expectLater(source.categoryDirectory.getDirectoryPage(), throwsArgumentError);
    expect(requests, hasLength(1));
  });

  test('failed refresh retains visible cards and paging until retry succeeds', () async {
    final controller = controllerFor();
    await controller.loadData();
    await controller.goToPage(2);
    invalid = true;
    await controller.refreshData();
    expect(controller.list.map((r) => r.roomId), _ids(21, 40));
    expect(controller.currentPage, 2);
    expect(controller.pageError.value, isTrue);
    expect(controller.canLoadMore.value, isTrue);
    invalid = false;
    count = 5;
    await controller.retryData();
    expect(controller.list.map((r) => r.roomId), _ids(1, 5));
    expect(controller.currentPage, 1);
    expect(controller.pageError.value, isFalse);
    expect(controller.canLoadMore.value, isFalse);
  });

  test('mobile page-size change keeps buffered rooms and resumes the fixed offset', () async {
    final controller = controllerFor(desktop: false);
    await controller.loadData();
    controller.setPageSize(40);
    await controller.loadData();
    expect(controller.list.map((r) => r.roomId), _ids(1, 40));
    await controller.loadMoreData();
    expect(controller.list.map((r) => r.roomId), _ids(1, 75));
    expect(requests.map((r) => r.queryParameters['start']), [0, 30, 60]);
    expect(requests.map((r) => r.queryParameters['size']), everyElement(30));
  });
}
