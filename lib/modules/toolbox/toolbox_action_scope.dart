import 'dart:async';

import 'package:dio/dio.dart';

class ToolBoxActionCancelled implements Exception {
  const ToolBoxActionCancelled();
}

/// One user action. Cancelling its wait does not close shared platform clients.
class ToolBoxActionScope {
  ToolBoxActionScope({bool Function()? ownerAlive, this.timeout = const Duration(seconds: 12)})
    : _ownerAlive = ownerAlive ?? (() => true);

  final bool Function() _ownerAlive;
  final Duration timeout;
  final cancelToken = CancelToken();
  bool get isActive => !cancelToken.isCancelled && _ownerAlive();

  void checkActive() {
    if (!isActive) throw const ToolBoxActionCancelled();
  }

  Future<T> wait<T>(Future<T> Function() start, {bool timed = true}) async {
    checkActive();
    final work = start();
    final deadline = Completer<T>();
    final timer = timed
        ? Timer(timeout, () => deadline.completeError(TimeoutException('Toolbox request timed out', timeout)))
        : null;
    try {
      final result = await Future.any<T>([
        work,
        if (timed) deadline.future,
        cancelToken.whenCancel.then<T>((_) => throw const ToolBoxActionCancelled()),
      ]);
      checkActive();
      return result;
    } finally {
      timer?.cancel();
    }
  }

  void cancel() {
    if (!cancelToken.isCancelled) cancelToken.cancel('Toolbox action ended');
  }
}
