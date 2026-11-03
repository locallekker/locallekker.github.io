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
  var currentSubscriptionStatus = 'active';
  var claimRenewal = false;
  var cancelAfterClaim = false;
  var subscriptionReads = 0;
  late String currentPeriodEnd;

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
          body = claimRenewal;
        } else if (path.endsWith('/members_card_details')) {
          body = {'authorization_code': 'AUTH_test'};
        } else if (path.endsWith('/profiles') && request.method == 'GET') {
          body = {'email': 'member@example.com', 'subscription_plan': 'monthly'};
        } else if (path.endsWith('/subscriptions') &&
            request.method == 'GET') {
          subscriptionReads++;
          if (failSubscriptionLookup) {
            return http.Response(
              jsonEncode({'message': 'Test lookup failure', 'code': 'XX000'}),
              500,
              request: request,
            );
          }
          final cancelledAfterClaim = cancelAfterClaim && subscriptionReads > 1;
          body = {
            'id': 'test-subscription',
            'status': cancelledAfterClaim ? 'cancelled' : currentSubscriptionStatus,
            'auto_renew': cancelledAfterClaim ? false : autoRenew,
            'renewal_in_progress_at': claimRenewal && subscriptionReads > 1
                ? DateTime.now().toIso8601String()
                : null,
            'cancellation_requested_at': cancelledAfterClaim
                ? DateTime.now().toIso8601String()
                : null,
            'current_period_end': currentPeriodEnd,
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
    currentSubscriptionStatus = 'active';
    claimRenewal = false;
    cancelAfterClaim = false;
    subscriptionReads = 0;
    currentPeriodEnd = DateTime.now()
      .subtract(const Duration(hours: 1))
      .toIso8601String();
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

    test('cancelled or opted-out subscription never claims a local charge',
      () async {
    subscriptionCode = null;
    autoRenew = false;

    expect(await SubscriptionService().processSubscriptionRenewal('member'),
      isFalse);
    expect(
      requests.where(
        (r) => r.url.path.endsWith('/rpc/claim_subscription_renewal')),
      isEmpty);
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

  test('cancelled status blocks charge even when auto-renew is stale', () async {
    subscriptionCode = null;
    currentSubscriptionStatus = 'cancelled';

    expect(await SubscriptionService().processSubscriptionRenewal('member'),
        isFalse);
    expect(
        requests.where(
            (r) => r.url.path.endsWith('/rpc/claim_subscription_renewal')),
        isEmpty);
    expect(requests.any((r) => r.url.path.contains('/functions/')), isFalse);
  });

  test('cancellation after claim releases claim before any Paystack charge',
      () async {
    subscriptionCode = null;
    claimRenewal = true;
    cancelAfterClaim = true;

    expect(await SubscriptionService().processSubscriptionRenewal('member'),
        isFalse);
    expect(
        requests.where(
        (r) => r.url.path.endsWith('/rpc/release_subscription_renewal_claim')),
        hasLength(1));
    expect(requests.any((r) => r.url.path.contains('/functions/')), isFalse);
  });
}
