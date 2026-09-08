import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/site/cc/cc_site.dart';
import 'package:pure_live/modules/areas/widgets/area_card.dart';
import 'package:pure_live/routes/app_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <Map<Object?, Object?>>[];
  var success = true;
  var throwLaunch = false;
  Completer<bool>? pending;
  final site = Site(id: 'cc', name: 'CC', logo: '', liveSite: CCSite());
  LiveArea entry({String id = 'official:249133'}) => LiveArea(
    platform: 'cc',
    areaId: id,
    areaType: 'official',
    areaName: 'Fixture event',
    typeName: 'Official event',
    areaPic: '',
  );

  setUpAll(() async {
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  tearDownAll(() async => Hive.close());
  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put(SettingsService());
    launches.clear();
    success = true;
    throwLaunch = false;
    pending = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'launch') throw StateError('Unexpected launcher call');
      launches.add(Map<Object?, Object?>.from(call.arguments as Map));
      if (pending != null) return pending!.future;
      if (throwLaunch) throw PlatformException(code: 'fixture');
      return success;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    Get.reset();
  });

  test('official entry opens its bounded CC destination externally, not a category API', () async {
    await AppNavigator.toCategoryDetail(site: site, category: LiveArea.fromJson(entry().toJson()));
    expect(launches.single['url'], 'https://cc.163.com/249133/?open=blizzardtv&from=8382&platform=ds');
    expect(launches.single['useWebView'], isFalse);
    expect(launches.single['useSafariVC'], isFalse);
  });

  test('malformed saved official identities and mismatched site never reach the OS', () async {
    for (final id in ['official:../file', 'official:0', 'official:https://example.test']) {
      await AppNavigator.toCategoryDetail(
        site: site,
        category: entry(id: id),
      );
    }
    await AppNavigator.toCategoryDetail(
      site: Site(id: 'huya', name: '', logo: '', liveSite: CCSite()),
      category: entry(),
    );
    expect(launches, isEmpty);
  });

  test('duplicate opening is coalesced and failed launch releases the gate', () async {
    pending = Completer<bool>();
    final first = AppNavigator.toCategoryDetail(site: site, category: entry());
    await Future<void>.delayed(Duration.zero);
    await AppNavigator.toCategoryDetail(site: site, category: entry());
    expect(launches, hasLength(1));
    pending!.complete(false);
    await first;
    pending = null;
    throwLaunch = true;
    await AppNavigator.toCategoryDetail(site: site, category: entry());
    throwLaunch = false;
    await AppNavigator.toCategoryDetail(site: site, category: entry());
    expect(launches, hasLength(3));
  });

  for (final width in [120.0, 220.0]) {
    testWidgets('official card labels the external action and opens it at width $width', (tester) async {
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: AreaCard(category: entry()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
      expect(find.text('open_in_system_browser'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(AreaCard));
      await tester.pumpAndSettle();
      expect(launches, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('ordinary category card retains in-app routing', (tester) async {
    final category = entry(id: '3')..typeName = 'Game';
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: '/',
        getPages: [
          GetPage(
            name: '/',
            page: () => Scaffold(
              body: SizedBox(width: 220, child: AreaCard(category: category)),
            ),
          ),
          GetPage(
            name: RoutePath.kAreaRooms,
            page: () => const Scaffold(body: Text('category target')),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
    await tester.tap(find.byType(AreaCard));
    await tester.pumpAndSettle();
    expect(find.text('category target'), findsOneWidget);
    expect(launches, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
