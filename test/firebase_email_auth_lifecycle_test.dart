import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/auth/components/firebase_email_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('firebase-email-auth-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put<SettingsService>(_FixtureSettingsService());
  });

  tearDown(() async {
    await HivePrefUtil.flush();
  });

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  test('password reset is supported on every maintained platform', () {
    expect(const FirebaseEmailAuthBackend().supportsPasswordReset, isTrue);
  });

  test('sign-up metadata cannot replace canonical identity fields', () {
    final createdAt = Object();
    final data = buildFirebaseSignUpProfileData(
      email: 'fixture@example.com',
      metadata: {
        'email': 'override@example.com',
        'created_at': 'override',
        'createdAt': 'override',
        ' display_name ': '  Fixture User  ',
        '   ': 'ignored',
      },
      createdAt: createdAt,
    );

    expect(data['email'], 'fixture@example.com');
    expect(data['created_at'], same(createdAt));
    expect(data, isNot(contains('createdAt')));
    expect(data['display_name'], 'Fixture User');
    expect(data, isNot(contains('   ')));
  });

  testWidgets('all sign-in controls remain reachable at large text', (tester) async {
    await _pumpAuth(tester, english, const _FixtureBackend(), textScale: 3);

    await _scrollUntilHitTestable(tester, find.text('Sign in with GitHub'));
    expect(find.text('Sign in with GitHub').hitTestable(), findsOneWidget);
    await _scrollUntilHitTestable(tester, find.text("Don't have an account? Sign Up"));
    expect(find.text("Don't have an account? Sign Up").hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending sign-in locks fields and mode actions', (tester) async {
    final backend = _FixtureBackend(signInResult: Completer<UserCredential>());
    final errors = <Object>[];
    await _pumpAuth(tester, english, backend, onError: errors.add);

    await tester.enterText(find.byType(TextFormField).at(0), 'fixture@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pump();

    expect(backend.signInCalls, 1);
    expect(
      tester.widgetList<TextFormField>(find.byType(TextFormField)).every((field) => field.enabled == false),
      isTrue,
    );
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('toggleSignInButton'))).onPressed, isNull);

    backend.signInResult!.completeError(StateError('fixture failure'));
    await _pumpFrames(tester);
    expect(errors, hasLength(1));
    expect(find.widgetWithText(FilledButton, 'Sign In'), findsOneWidget);
  });

  testWidgets('password text is submitted without changing its boundaries', (tester) async {
    final backend = _FixtureBackend(signInResult: Completer<UserCredential>());
    await _pumpAuth(tester, english, backend, onError: (_) {});

    await tester.enterText(find.byType(TextFormField).at(0), 'fixture@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), ' password ');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pump();

    expect(backend.lastPassword, ' password ');
    backend.signInResult!.completeError(StateError('fixture failure'));
    await _pumpFrames(tester);
  });

  testWidgets('late sign-in failure after disposal has no visible callback', (tester) async {
    final result = Completer<UserCredential>();
    final backend = _FixtureBackend(signInResult: result);
    final errors = <Object>[];
    await _pumpAuth(tester, english, backend, onError: errors.add);

    await tester.enterText(find.byType(TextFormField).at(0), 'fixture@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    result.completeError(StateError('late fixture failure'));
    await _pumpFrames(tester);

    expect(errors, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password reset failure has a visible fallback message', (tester) async {
    final backend = _FixtureBackend(resetError: StateError('private reset detail'));
    await _pumpAuth(tester, english, backend);

    await tester.tap(find.text('Forgot Password?'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'fixture@example.com');
    await tester.tap(find.text('Reset Password'));
    await _pumpFrames(tester);

    expect(find.text('Password reset email was not sent. Try again.'), findsOneWidget);
    expect(find.textContaining('private reset detail'), findsNothing);
  });

  testWidgets('password reset stays busy until its completion callback finishes', (tester) async {
    final callbackResult = Completer<void>();
    await _pumpAuth(tester, english, const _FixtureBackend(), onPasswordResetEmailSent: () => callbackResult.future);

    await tester.tap(find.text('Forgot Password?'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'fixture@example.com');
    await tester.tap(find.text('Reset Password'));
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Reset Password'), findsNothing);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Back to Sign In')).onPressed, isNull);

    callbackResult.complete();
    await _pumpFrames(tester);
    expect(find.widgetWithText(FilledButton, 'Reset Password'), findsOneWidget);
  });
}

class _FixtureBackend extends FirebaseEmailAuthBackend {
  const _FixtureBackend({this.signInResult, this.resetError});

  final Completer<UserCredential>? signInResult;
  final Object? resetError;

  static int _calls = 0;
  static String? _password;

  int get signInCalls => _calls;
  String? get lastPassword => _password;

  @override
  bool get supportsPasswordReset => true;

  @override
  Future<UserCredential> signInWithEmail(String email, String password) {
    _calls++;
    _password = password;
    return signInResult?.future ?? Completer<UserCredential>().future;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (resetError != null) throw resetError!;
  }
}

Future<void> _pumpAuth(
  WidgetTester tester,
  Map<String, dynamic> english,
  FirebaseEmailAuthBackend backend, {
  double textScale = 1,
  void Function(Object error)? onError,
  FutureOr<void> Function()? onPasswordResetEmailSent,
}) async {
  _FixtureBackend._calls = 0;
  _FixtureBackend._password = null;
  tester.view.physicalSize = const Size(320, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    _localizedHost(
      english,
      Scaffold(
        appBar: AppBar(title: const Text('Sign In')),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FirebaseEmailAuth(
              backend: backend,
              onSignInComplete: (_) {},
              onSignUpComplete: (_) {},
              onError: onError,
              onPasswordResetEmailSent: onPasswordResetEmailSent,
            ),
          ),
        ),
      ),
      textScale: textScale,
    ),
  );
  await _pumpFrames(tester);
}

Widget _localizedHost(Map<String, dynamic> english, Widget page, {double textScale = 1}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    startLocale: const Locale('en'),
    fallbackLocale: const Locale('en'),
    saveLocale: false,
    path: 'assets/translations',
    assetLoader: _Translations(english),
    child: Builder(
      builder: (context) => GetMaterialApp(
        locale: context.locale,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
}

Future<void> _scrollUntilHitTestable(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 140, scrollable: find.byType(Scrollable).first);
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 6]) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => english;
}

class _FixtureSettingsService extends SettingsService {
  @override
  final font = FontSettingsController();

  @override
  final theme = ThemeSettingsController();

  @override
  // This fixture resolves only typography and loading-style settings.
  // ignore: must_call_super
  void onInit() {}
}
