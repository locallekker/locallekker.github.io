import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/core/utils/safe_retry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('isTransientNetworkError', () {
    test('treats timeouts and dropped connections as transient', () {
      expect(isTransientNetworkError(TimeoutException('slow')), isTrue);
      expect(
        isTransientNetworkError(Exception('SocketException: Connection reset by peer')),
        isTrue,
      );
      expect(isTransientNetworkError(Exception('ClientException: Failed to fetch')), isTrue);
    });

    test('never retries database rejections', () {
      expect(
        isTransientNetworkError(
          const PostgrestException(message: 'new row violates row-level security', code: '42501'),
        ),
        isFalse,
      );
      expect(isTransientNetworkError(Exception('duplicate key value')), isFalse);
    });
  });

  group('runWithSafeRetry', () {
    test('runs the action once when it succeeds', () async {
      var calls = 0;
      var checks = 0;
      await runWithSafeRetry(
        action: () async => calls++,
        alreadyDone: () async {
          checks++;
          return false;
        },
        baseDelay: Duration.zero,
      );
      expect(calls, 1);
      expect(checks, 0);
    });

    test('retries a transient failure and then succeeds', () async {
      var calls = 0;
      await runWithSafeRetry(
        action: () async {
          calls++;
          if (calls == 1) throw TimeoutException('lost');
        },
        alreadyDone: () async => false,
        baseDelay: Duration.zero,
      );
      expect(calls, 2);
    });

    test('does not repeat the write when it already landed', () async {
      var calls = 0;
      await runWithSafeRetry(
        action: () async {
          calls++;
          throw TimeoutException('response lost');
        },
        alreadyDone: () async => true,
        baseDelay: Duration.zero,
      );
      expect(calls, 1);
    });

    test('rethrows non-transient errors without retrying', () async {
      var calls = 0;
      await expectLater(
        runWithSafeRetry(
          action: () async {
            calls++;
            throw const PostgrestException(message: 'rls', code: '42501');
          },
          alreadyDone: () async => false,
          baseDelay: Duration.zero,
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 1);
    });

    test('gives up after maxRetries and rethrows the original error', () async {
      var calls = 0;
      await expectLater(
        runWithSafeRetry(
          action: () async {
            calls++;
            throw TimeoutException('down');
          },
          alreadyDone: () async => false,
          maxRetries: 2,
          baseDelay: Duration.zero,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 3);
    });

    test('surfaces the original error if the existence check fails', () async {
      var calls = 0;
      await expectLater(
        runWithSafeRetry(
          action: () async {
            calls++;
            throw TimeoutException('down');
          },
          alreadyDone: () async => throw StateError('offline'),
          baseDelay: Duration.zero,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1);
    });
  });
}
