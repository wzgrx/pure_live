import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/auth/auth_controller.dart';
import 'package:pure_live/modules/auth/utils/firebase_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.testMode = true;
    Get.reset();
  });

  tearDown(() {
    Get.reset();
  });

  test('SDK initialization is attempted without a marketing-site preflight', () async {
    final backend = _FixtureBackend(canAccessWebsite: false);
    final controller = AuthController(backend: backend, autoStart: false);

    await controller.startAsyncInit();

    expect(backend.initializeCalls, 1);
    expect(controller.isInitSuccess, isTrue);
    expect(controller.isReady, isTrue);
  });

  test('Firebase manager preserves one process-wide coordinator instance', () {
    expect(FirebaseManager.getInstance(), same(FirebaseManager.getInstance()));
  });

  test('missing or blank cloud config is treated as an empty profile', () {
    expect(parseFirebaseStoredConfig(null), isNull);
    expect(parseFirebaseStoredConfig('   '), isNull);
  });

  test('stored cloud config accepts JSON and map representations', () {
    expect(parseFirebaseStoredConfig('{"favorite": {"rooms": []}}'), {
      'favorite': {'rooms': <dynamic>[]},
    });
    expect(parseFirebaseStoredConfig({'version': 2}), {'version': 2});
  });

  test('a scalar cloud config is rejected as corrupted data', () {
    expect(() => parseFirebaseStoredConfig('42'), throwsFormatException);
  });

  test('an initial signed-in session becomes ready without waiting for a stream echo', () async {
    final backend = _FixtureBackend(currentUser: _FixtureUser('fixture-user'));
    final controller = AuthController(backend: backend, autoStart: false);

    await controller.startAsyncInit();

    expect(controller.isLogin, isTrue);
    expect(controller.userId, 'fixture-user');
    expect(controller.isReady, isTrue);
    expect(backend.syncedUserIds, ['fixture-user']);
  });

  test('the initial stream echo shares the existing user synchronization', () async {
    final user = _FixtureUser('fixture-user');
    final backend = _FixtureBackend(currentUser: user);
    final controller = AuthController(backend: backend, autoStart: false);
    await controller.startAsyncInit();

    backend.emit(user);
    await _flushAsync();

    expect(backend.syncedUserIds, ['fixture-user']);
  });

  test('retry replaces the auth listener instead of accumulating subscriptions', () async {
    final backend = _FixtureBackend();
    final controller = AuthController(backend: backend, autoStart: false);
    await controller.startAsyncInit();
    await controller.startAsyncInit();

    backend.emit(_FixtureUser('fixture-user'));
    await _flushAsync();

    expect(backend.syncedUserIds, ['fixture-user']);
  });

  test('a malformed empty user event clears the previous session', () async {
    final user = _FixtureUser('fixture-user');
    final backend = _FixtureBackend(currentUser: user);
    final controller = AuthController(backend: backend, autoStart: false);
    await controller.startAsyncInit();

    backend.emit(_FixtureUser('   '));
    await _flushAsync();

    expect(controller.isLogin, isFalse);
    expect(controller.user, isNull);
    expect(controller.userId, isEmpty);
    expect(backend.clearSessionCalls, 1);
  });

  test('closing during initialization prevents late setup and subscription', () async {
    final accessResult = Completer<bool>();
    final backend = _FixtureBackend(accessResult: accessResult);
    final controller = AuthController(backend: backend, autoStart: false);

    final initialization = controller.startAsyncInit();
    controller.onClose();
    accessResult.complete(true);
    await initialization;
    await _flushAsync();

    expect(backend.initializeCalls, 0);
    expect(backend.listenerCount, 0);
  });

  test('direct completion and its stream echo share one in-flight synchronization', () async {
    final syncResult = Completer<void>();
    final backend = _FixtureBackend(syncResult: syncResult);
    final controller = AuthController(backend: backend, autoStart: false);
    await controller.startAsyncInit();
    final user = _FixtureUser('fixture-user');

    final directCompletion = controller.acceptAuthenticatedUser(user);
    backend.emit(user);
    await _flushAsync();

    expect(backend.syncedUserIds, ['fixture-user']);
    syncResult.complete();
    await directCompletion;
    await _flushAsync();
    expect(controller.isReady, isTrue);
  });

  test('sign-out invalidates a late synchronization result for the same user', () async {
    final syncResult = Completer<void>();
    final backend = _FixtureBackend(syncResult: syncResult);
    final controller = AuthController(backend: backend, autoStart: false);
    await controller.startAsyncInit();
    final user = _FixtureUser('fixture-user');

    final firstCompletion = controller.acceptAuthenticatedUser(user);
    await controller.acceptSignedOut();
    syncResult.complete();
    await firstCompletion;
    expect(controller.isLogin, isFalse);

    backend.emit(user);
    await _flushAsync();
    expect(backend.syncedUserIds, ['fixture-user', 'fixture-user']);
  });

  test('failed optional synchronization leaves auth ready and retries on the next event', () async {
    final user = _FixtureUser('fixture-user');
    final backend = _FixtureBackend(currentUser: user, syncFailuresRemaining: 1);
    final controller = AuthController(backend: backend, autoStart: false);

    await controller.startAsyncInit();
    expect(controller.isLogin, isTrue);
    expect(controller.isReady, isTrue);

    backend.emit(user);
    await _flushAsync();
    expect(backend.syncedUserIds, ['fixture-user', 'fixture-user']);
  });

  test('failed SDK initialization reaches a retryable terminal state', () async {
    final backend = _FixtureBackend(initializeFailuresRemaining: 1);
    final controller = AuthController(backend: backend, autoStart: false);

    await controller.startAsyncInit();
    expect(controller.isInitSuccess, isFalse);
    expect(controller.isConnecting, isFalse);
    expect(controller.isReady, isTrue);
    expect(backend.listenerCount, 0);

    await controller.startAsyncInit();
    expect(controller.isInitSuccess, isTrue);
    expect(controller.isConnecting, isFalse);
    expect(backend.listenerCount, 1);
  });

  test('closing an active controller detaches its auth listener', () async {
    final backend = _FixtureBackend();
    final controller = AuthController(backend: backend, autoStart: false);
    await controller.startAsyncInit();
    expect(backend.listenerCount, 1);

    controller.onClose();
    await _flushAsync();
    backend.emit(_FixtureUser('late-user'));
    await _flushAsync();

    expect(backend.listenerCount, 0);
    expect(backend.syncedUserIds, isEmpty);
  });
}

class _FixtureBackend extends FirebaseAuthControllerBackend {
  _FixtureBackend({
    this.canAccessWebsite = true,
    this.accessResult,
    this.currentUser,
    this.syncResult,
    this.syncFailuresRemaining = 0,
    this.initializeFailuresRemaining = 0,
  }) {
    addTearDown(_authStates.close);
  }

  final bool canAccessWebsite;
  final Completer<bool>? accessResult;
  @override
  final fb.User? currentUser;
  final Completer<void>? syncResult;
  int syncFailuresRemaining;
  int initializeFailuresRemaining;
  final _authStates = StreamController<fb.User?>.broadcast();
  final syncedUserIds = <String>[];
  int initializeCalls = 0;
  int clearSessionCalls = 0;
  int listenerCount = 0;

  @override
  Future<bool> canAccessFirebaseWebsite() async => accessResult?.future ?? canAccessWebsite;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (initializeFailuresRemaining > 0) {
      initializeFailuresRemaining--;
      throw StateError('fixture initialization failure');
    }
  }

  @override
  Stream<fb.User?> authStateChanges() {
    return Stream<fb.User?>.multi((controller) {
      listenerCount++;
      final subscription = _authStates.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () async {
        listenerCount--;
        await subscription.cancel();
      };
    });
  }

  @override
  Future<void> syncConfigs(String userId) async {
    syncedUserIds.add(userId);
    if (syncFailuresRemaining > 0) {
      syncFailuresRemaining--;
      throw StateError('fixture synchronization failure');
    }
    await syncResult?.future;
  }

  @override
  void clearSessionMetadata() {
    clearSessionCalls++;
  }

  void emit(fb.User? user) {
    _authStates.add(user);
  }
}

class _FixtureUser implements fb.User {
  _FixtureUser(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flushAsync() async {
  for (var index = 0; index < 6; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
