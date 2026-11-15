import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_lekker/services/paystack_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];

  group('PaystackService Banking Details Tests', () {
    late PaystackService paystackService;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://paystack-test.supabase.co',
        anonKey: 'test-anon-key',
        authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<Object>[]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
    });

    tearDownAll(() => Supabase.instance.dispose());

    setUp(() {
      requests.clear();
      SharedPreferences.setMockInitialValues({});
      paystackService = PaystackService();
    });

    test(
      'Get banking details returns null when no recipient code exists',
      () async {
        final result = await paystackService.getBankingDetailsForUser(
          'non-existent-user-id',
        );

        expect(result, isNull);
        expect(requests, hasLength(1));
        expect(
          requests.single.url.path,
          '/rest/v1/trusted_partner_bank_accounts',
        );
        expect(
          requests.single.url.queryParameters['user_id'],
          'eq.non-existent-user-id',
        );
        expect(requests.single.url.queryParameters['is_active'], 'eq.true');
      },
    );
  });
}
