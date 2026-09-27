import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Diagnostic CLI, not an application transport. A stalled TLS handshake on
// the pinned SDK can leave its Future pending even after raw socket close.
// The final timeout is intentionally a nonzero observation, not a repair.

Future<void> main() async {
  final hello = Completer<void>();
  final sockets = <Socket>[];
  var peerClosed = false;
  var completed = false;
  Object? failure;
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final sub = server.listen((s) {
    sockets.add(s);
    s.listen(
      (bytes) {
        if (bytes.isNotEmpty && !hello.isCompleted) hello.complete();
      },
      onError: (Object e) {},
      onDone: () {
        peerClosed = true;
      },
    );
  });
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  final pending = client
      .getUrl(Uri.parse('https://127.0.0.1:${server.port}/fixture'))
      .then<void>(
        (r) {
          completed = true;
          r.abort();
        },
        onError: (Object e) {
          completed = true;
          failure = e;
        },
      );
  try {
    await hello.future.timeout(const Duration(seconds: 2));
    client.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    // ignore: avoid_print
    print(
      jsonEncode({
        'afterCloseMs': 1500,
        'clientHelloObserved': hello.isCompleted,
        'peerClosedBeforeFixtureCleanup': peerClosed,
        'requestCompleted': completed,
        'error': failure?.toString(),
      }),
    );
  } finally {
    for (final s in sockets) {
      s.destroy();
    }
    client.close(force: true);
    await pending;
    await server.close();
    await sub.cancel();
  }
  await observeRaw();
}

Future<void> observeRaw() async {
  final hello = Completer<void>();
  final sockets = <Socket>[];
  var peerClosed = false;
  var completed = false;
  Object? failure;
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final sub = server.listen((s) {
    sockets.add(s);
    s.listen(
      (bytes) {
        if (bytes.isNotEmpty && !hello.isCompleted) hello.complete();
      },
      onError: (Object e) {},
      onDone: () {
        peerClosed = true;
      },
    );
  });
  final raw = await RawSocket.connect(InternetAddress.loopbackIPv4, server.port);
  final pending = RawSecureSocket.secure(raw).then<void>(
    (s) {
      completed = true;
      s.close();
    },
    onError: (Object e) {
      completed = true;
      failure = e;
    },
  );
  try {
    await hello.future.timeout(const Duration(seconds: 2));
    await raw.close();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    // ignore: avoid_print
    print(
      jsonEncode({
        'mode': 'retained_raw_socket',
        'afterCloseMs': 1500,
        'clientHelloObserved': hello.isCompleted,
        'peerClosedBeforeFixtureCleanup': peerClosed,
        'requestCompleted': completed,
        'error': failure?.toString(),
      }),
    );
  } finally {
    for (final s in sockets) {
      s.destroy();
    }
    await raw.close();
    try {
      await pending.timeout(const Duration(seconds: 2));
    } finally {
      await server.close();
      await sub.cancel();
    }
  }
}
