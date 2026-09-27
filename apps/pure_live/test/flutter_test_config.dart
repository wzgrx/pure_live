import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests run in Simplified Chinese, the base language (F-APP-06): the app
/// follows the system language by default, and the test binding would
/// otherwise report en-US. Only suites that use the widget binding get it
/// (declaring a `testWidgets` creates the binding); plain `test` suites keep
/// real HTTP, which the widget binding would mock. Tests that change the
/// language restore [testSystemLocales].
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
  if (BindingBase.debugBindingType() != null) {
    TestWidgetsFlutterBinding.instance.platformDispatcher.localesTestValue = testSystemLocales;
  }
}

/// The system languages tests start with.
const testSystemLocales = [Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN')];
