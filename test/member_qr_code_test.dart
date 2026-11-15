import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_lekker/services/qr_code_service.dart';
import 'package:local_lekker/widgets/custom_qr_code.dart';
import 'package:local_lekker/widgets/member_qr_code.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const userId = 'bc100000-0000-0000-0000-000000000001';
  final requests = <http.Request>[];
  late Map<String, dynamic> row;
  bool rejectUpdate = false;
  Completer<void>? readGate;

  String payload(DateTime expiry) => jsonEncode({
    'type': 'user_qr_v2',
    'user_id': userId,
    'exp': expiry.millisecondsSinceEpoch ~/ 1000,
  });

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final jwtPayload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': userId,
              'exp':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch ~/
                  1000,
            }),
          ),
        )
        .replaceAll('=', '');
    await Supabase.initialize(
      url: 'https://qr-test.supabase.co',
      anonKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        Object body;
        if (request.url.path == '/auth/v1/token') {
          body = {
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$jwtPayload.fixture',
            'refresh_token': 'fixture-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': userId,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'qr@example.test',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
              'created_at': '2026-01-01T00:00:00Z',
            },
          };
        } else if (request.url.path.endsWith('/profiles')) {
          body = {'name': 'Fixture', 'surname': 'Member'};
        } else if (request.url.path.endsWith('/user_qr_codes')) {
          expectSync(request.url.queryParameters['is_active'], 'eq.true');
          if (request.method == 'PATCH') {
            if (rejectUpdate) {
              return http.Response(
                jsonEncode({
                  'code': 'PGRST116',
                  'message': 'No active row was updated',
                  'details': 'The result contains 0 rows',
                }),
                406,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            row.addAll(jsonDecode(request.body) as Map<String, dynamic>);
          } else {
            await readGate?.future;
          }
          body = row;
        } else {
          throw StateError('Unexpected QR request: ${request.url.path}');
        }
        return http.Response(
          jsonEncode(body),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'qr@example.test',
      password: 'fixture',
    );
  });

  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    requests.clear();
    rejectUpdate = false;
    readGate = null;
    row = {
      'id': 'qr-id',
      'user_id': userId,
      'qr_code': payload(DateTime.now().subtract(const Duration(minutes: 1))),
      'expires_at': DateTime.now()
          .add(const Duration(days: 36500))
          .toIso8601String(),
    };
  });

  test(
    'refreshes an expired payload without changing permanent membership',
    () async {
      final expiry = row['expires_at'];
      final result = await QrCodeService().refreshMemberQrCode(userId);
      expect(result, row['qr_code']);
      expect(QrCodeService.isFreshMemberQrCode(result!), isTrue);
      final update = requests.singleWhere(
        (request) => request.method == 'PATCH',
      );
      final body = jsonDecode(update.body) as Map<String, dynamic>;
      expect(body.keys, unorderedEquals(['qr_code', 'updated_at']));
      expect(row['expires_at'], expiry);
      expect(update.url.queryParameters['expires_at'], startsWith('gt.'));
    },
  );

  test(
    'reuses a registered payload with more than 15 seconds remaining',
    () async {
      row['qr_code'] = payload(DateTime.now().add(const Duration(seconds: 35)));
      final original = row['qr_code'];
      expect(await QrCodeService().refreshMemberQrCode(userId), original);
      expect(requests.where((request) => request.method == 'PATCH'), isEmpty);
    },
  );

  test(
    'does not renew an expired membership or fabricate a successful write',
    () async {
      row['expires_at'] = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      expect(await QrCodeService().refreshMemberQrCode(userId), isNull);
      expect(requests.where((request) => request.method == 'PATCH'), isEmpty);

      row['expires_at'] = DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String();
      rejectUpdate = true;
      await expectLater(
        QrCodeService().refreshMemberQrCode(userId),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  testWidgets('a QR dialog refreshes on open, periodically, and on resume', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const Dialog(child: MemberQrCode(size: 220)),
              ),
              child: const Text('Open QR'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open QR'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomQrCode), findsOneWidget);
    expect(
      tester.widget<CustomQrCode>(find.byType(CustomQrCode)).data,
      row['qr_code'],
    );

    row['qr_code'] = payload(
      DateTime.now().subtract(const Duration(seconds: 1)),
    );
    final writes = requests
        .where((request) => request.method == 'PATCH')
        .length;
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(
      requests.where((request) => request.method == 'PATCH').length,
      writes + 1,
    );
    expect(
      tester.widget<CustomQrCode>(find.byType(CustomQrCode)).data,
      row['qr_code'],
    );

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    await tester.pump();
    expect(find.byType(CustomQrCode), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();
    expect(find.byType(CustomQrCode), findsOneWidget);
    expect(
      requests.where((request) => request.method == 'PATCH').length,
      writes + 2,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'does not show an unregistered QR and offers retry after failure',
    (tester) async {
      rejectUpdate = true;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MemberQrCode(size: 220))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomQrCode), findsNothing);
      expect(find.text('Retry'), findsOneWidget);

      rejectUpdate = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomQrCode), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'hides an expired displayed code even if refresh is still pending',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MemberQrCode(size: 220))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomQrCode), findsOneWidget);
      readGate = Completer<void>();
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 31));
      expect(find.byType(CustomQrCode), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      readGate!.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
