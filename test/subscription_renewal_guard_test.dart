import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_lekker/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  String? subscriptionCode;
  var autoRenew = true;
  var failSubscriptionLookup = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://renewal-test.supabase.co',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        Object body = <Object>[];
        if (path.endsWith('/rpc/get_subscription_status')) {
          body = {
            'subscription_status': 'active',
            'subscription_end_date': DateTime.now()
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
            'auto_renew': autoRenew,
          };
        } else if (path.endsWith('/rpc/claim_subscription_renewal')) {
          body = false;
        } else if (path.endsWith('/members_card_details')) {
          body = {'authorization_code': 'AUTH_test'};
        } else if (path.endsWith('/profiles') && request.method == 'GET') {
          body = {'email': 'member@example.com', 'subscription_plan': 'monthly'};
        } else if (path.endsWith('/subscriptions') &&
            request.method == 'GET') {
          if (failSubscriptionLookup) {
            return http.Response(
              jsonEncode({'message': 'Test lookup failure', 'code': 'XX000'}),
              500,
              request: request,
            );
          }
          body = {
            'id': 'test-subscription',
            'current_period_end': DateTime.now()
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
            'plan_type': 'monthly',
            'renewal_charge_cents': 9900,
            'paystack_subscription_code': subscriptionCode,
          };
        }
        return http.Response(jsonEncode(body), 200,
            request: request,
            headers: {'content-type': 'application/json'});
      }),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  setUp(() {
    requests.clear();
    subscriptionCode = 'SUB_test';
    autoRenew = true;
    failSubscriptionLookup = false;
  });

  test('Paystack-managed renewal never claims or charges locally', () async {
    expect(await SubscriptionService().processSubscriptionRenewal('member'),
        isFalse);
    expect(requests.any((r) => r.url.path.contains('/rpc/')), isFalse);
    expect(requests.any((r) => r.url.path.contains('/functions/')), isFalse);
  });

  test('locally managed renewal still uses the shared renewal claim', () async {
    subscriptionCode = null;
    expect(await SubscriptionService().processSubscriptionRenewal('member'),
        isFalse);
    expect(
        requests.where(
            (r) => r.url.path.endsWith('/rpc/claim_subscription_renewal')),
        hasLength(1));
    expect(requests.any((r) => r.url.path.contains('/functions/')), isFalse);
  });

  test('Paystack renewal grace does not charge or deactivate membership',
      () async {
    expect(
        await SubscriptionService().checkAndHandleExpiredSubscription('member'),
        isFalse);
    expect(requests.where((r) => r.method != 'GET'), hasLength(1));
    expect(requests.singleWhere((r) => r.method != 'GET').url.path,
        endsWith('/rpc/get_subscription_status'));
  });

  test('failed ownership lookup does not charge or deactivate membership',
      () async {
    failSubscriptionLookup = true;
    expect(
        await SubscriptionService().checkAndHandleExpiredSubscription('member'),
        isFalse);
    expect(requests.any((r) => r.method == 'PATCH'), isFalse);
    expect(requests.any((r) => r.url.path.contains('/functions/')), isFalse);
  });
}
