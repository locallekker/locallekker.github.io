import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// True for transient transport failures (timeouts, dropped connections).
///
/// Errors returned by the database itself ([PostgrestException], e.g. RLS or
/// constraint violations) are deterministic, so retrying them cannot help.
bool isTransientNetworkError(Object error) {
  if (error is PostgrestException) return false;
  if (error is TimeoutException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('connection closed') ||
      text.contains('connection reset') ||
      text.contains('connection refused') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('timed out') ||
      text.contains('failed to fetch');
}

/// Runs a non-idempotent write and retries it only after transient network
/// failures, checking [alreadyDone] first so a write that actually reached
/// the server (but whose response was lost) is never duplicated.
///
/// Returns normally on success, or when [alreadyDone] confirms the write
/// landed. Rethrows the original error when it is not retryable, when
/// retries are exhausted, or when [alreadyDone] cannot be checked.
Future<void> runWithSafeRetry({
  required Future<void> Function() action,
  required Future<bool> Function() alreadyDone,
  int maxRetries = 2,
  Duration baseDelay = const Duration(seconds: 1),
  bool Function(Object error) isRetryable = isTransientNetworkError,
  void Function(int attempt, Object error)? onRetry,
}) async {
  var attempt = 0;
  while (true) {
    try {
      await action();
      return;
    } catch (error, stackTrace) {
      if (attempt >= maxRetries || !isRetryable(error)) rethrow;
      attempt++;
      onRetry?.call(attempt, error);
      await Future<void>.delayed(baseDelay * attempt);

      bool done;
      try {
        done = await alreadyDone();
      } catch (_) {
        // Can't prove the write didn't land; surface the original failure.
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (done) return;
    }
  }
}
