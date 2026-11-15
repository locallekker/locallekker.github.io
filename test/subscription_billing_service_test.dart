import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_lekker/services/payment_status_service.dart';
import 'package:local_lekker/services/paystack_service.dart';
import 'package:local_lekker/services/subscription_billing_service.dart';
import 'package:local_lekker/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const userId = 'bc100000-0000-0000-0000-000000000001';
  final requests = <http.Request>[];
  var billingState = 'paid';
  int? billingErrorStatus;
  Object? billingErrorBody;
  final transaction = <String, dynamic>{
    'id': 42,
    'reference': 'll-sub-fixture',
    'status': 'success',
    'amount': 9900,
    'currency': 'ZAR',
    'metadata': {'payment_type': 'subscription', 'user_id': userId},
  };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      envString:
          'PAYSTACK_DEVELOPMENT_MODE=false\nSUPABASE_URL=https://billing-test.supabase.co\nSUPABASE_ANON_KEY=fixture',
    );
    final payload = base64Url
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
      url: 'https://billing-test.supabase.co',
      anonKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        Object body;
        if (request.url.path == '/auth/v1/token') {
          body = {
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.fixture',
            'refresh_token': 'fixture-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': userId,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'billing@example.test',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
              'created_at': '2026-01-01T00:00:00Z',
            },
          };
        } else if (request.url.path.endsWith('/subscription-billing')) {
          if (billingErrorStatus != null) {
            return http.Response(
              billingErrorBody is String
                  ? billingErrorBody as String
                  : jsonEncode(billingErrorBody),
              billingErrorStatus!,
              headers: {
                'content-type': billingErrorBody is String
                    ? 'text/plain'
                    : 'application/json',
              },
            );
          }
          final input = jsonDecode(request.body) as Map<String, dynamic>;
          body = {
            'state': billingState,
            'reference': 'll-sub-fixture',
            if (input['action'] == 'checkout')
              'authorization_url': 'https://checkout.paystack.com/fixture',
            if (billingState == 'paid') 'transaction': transaction,
          };
        } else {
          throw StateError(
            'Unexpected billing request: ${request.method} ${request.url.path}',
          );
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'billing@example.test',
      password: 'fixture',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    requests.clear();
    billingState = 'paid';
    billingErrorStatus = null;
    billingErrorBody = null;
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'saved-card membership charges use the dedicated server endpoint',
    () async {
      expect(
        await PaystackService().chargeSavedCard(
          authorizationCode: 'AUTH_fixture',
          amount: 0.01,
          userId: userId,
          userEmail: 'billing@example.test',
        ),
        'success',
      );
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/functions/v1/subscription-billing');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['action'], 'charge');
      expect(body['authorization_code'], 'AUTH_fixture');
      expect(body.containsKey('amount'), isFalse);
      expect(body.containsKey('user_id'), isFalse);
    },
  );

  test('membership checkout never creates a Paystack recurring plan', () async {
    final result = await PaystackService().initializeSubscription(
      plan: 'subscription',
      amount: 99,
      frequency: 1,
      userId: userId,
      userEmail: 'billing@example.test',
    );
    expect(result?['reference'], 'll-sub-fixture');
    expect(requests, hasLength(1));
    expect(jsonDecode(requests.single.body)['action'], 'checkout');
  });

  test(
    'unknown outcomes persist the reference and do not activate access',
    () async {
      billingState = 'unknown';
      await expectLater(
        PaystackService().chargeSavedCard(
          authorizationCode: 'AUTH_fixture',
          amount: 99,
          userId: userId,
          userEmail: 'billing@example.test',
        ),
        throwsException,
      );
      expect(
        (await PaymentStatusService().getPendingTransactionReference(
          userId,
        ))?['reference'],
        'll-sub-fixture',
      );
      expect(requests, hasLength(1));
    },
  );

  test('non-JSON billing gateway errors include the HTTP status', () async {
    billingErrorStatus = 404;
    billingErrorBody = 'Function not found';

    await expectLater(
      SubscriptionBillingService().request(action: 'checkout'),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('billing service HTTP 404'),
        ),
      ),
    );
  });

  test('billing function JSON errors preserve the server message', () async {
    billingErrorStatus = 409;
    billingErrorBody = {'error': 'Membership is already paid'};

    await expectLater(
      SubscriptionBillingService().request(action: 'checkout'),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Membership is already paid'),
        ),
      ),
    );
  });

  test(
    'callback activation verifies the ledger and never writes subscription or QR tables',
    () async {
      expect(
        await SubscriptionService().processManualPayment(
          userId: userId,
          planType: 'subscription',
          paymentReference: 'll-sub-fixture',
        ),
        isTrue,
      );
      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body)['action'], 'verify');
    },
  );

  test(
    'introductory checkout sends eligibility IDs, not client-controlled prices',
    () async {
      await PaystackService().startOneTimePayment(
        itemName: 'Intro',
        itemDescription: 'Offer',
        amount: 0.01,
        userId: userId,
        userEmail: 'billing@example.test',
        extraMetadata: {
          'payment_type': 'promotion_intro',
          'promotion_id': 'promo-fixture',
          'participant_id': 'participant-fixture',
        },
      );
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['promotion_id'], 'promo-fixture');
      expect(body['participant_id'], 'participant-fixture');
      expect(body.containsKey('amount'), isFalse);
    },
  );

  test(
    'deal saved-card charges retain the original proxy and partner settlement',
    () async {
      final proxyRequests = <http.Request>[];
      final result = await http.runWithClient(
        () => PaystackService().chargeSavedCard(
          authorizationCode: 'AUTH_deal',
          amount: 350,
          userId: userId,
          userEmail: 'billing@example.test',
          paymentType: 'one_time_payment',
          subaccountCode: 'ACCT_partner',
          extraMetadata: {'deal_authorization_id': 'deal-fixture'},
        ),
        () => MockClient((request) async {
          proxyRequests.add(request);
          return http.Response(
            jsonEncode({
              'data': {'status': 'success'},
            }),
            200,
          );
        }),
      );
      expect(result, 'success');
      expect(proxyRequests, hasLength(1));
      final request =
          jsonDecode(proxyRequests.single.body) as Map<String, dynamic>;
      expect(request['path'], '/transaction/charge_authorization');
      expect(request['body']['amount'], 35000);
      expect(request['body']['subaccount'], 'ACCT_partner');
      expect(request['body']['bearer'], 'account');
      expect(
        request['body']['metadata']['deal_authorization_id'],
        'deal-fixture',
      );
      expect(requests, isEmpty);
    },
  );

  test('another account cannot confirm a membership payment', () async {
    await expectLater(
      SubscriptionBillingService().confirm(
        'other-member',
        reference: 'll-sub-fixture',
      ),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });

  test('uncertain saved-card deal responses do not report a decline or retry', () async {
    for (final status in ['pending', 'ongoing', 'unknown', 'abandoned']) {
      var attempts = 0;
      final result = await http.runWithClient(
        () => PaystackService().chargeSavedCard(
          authorizationCode: 'AUTH_deal', amount: 99, userId: userId,
          userEmail: 'billing@example.test', paymentType: 'one_time_payment',
          extraMetadata: {'deal_authorization_id': 'deal-fixture'},
        ),
        () => MockClient((request) async {
          attempts++;
          return http.Response(jsonEncode({'data': {'status': status}}), 200);
        }),
      );
      expect(result, 'pending', reason: status);
      expect(attempts, 1);
    }
    var attempts = 0;
    final result = await http.runWithClient(
      () => PaystackService().chargeSavedCard(
        authorizationCode: 'AUTH_deal', amount: 99, userId: userId,
        userEmail: 'billing@example.test', paymentType: 'one_time_payment',
      ),
      () => MockClient((request) async {
        attempts++;
        throw http.ClientException('Connection lost after submission', request.url);
      }),
    );
    expect(result, 'pending');
    expect(attempts, 1);
  });

  test('card setup rejects nonreusable cards and unrelated successful transactions', () async {
    for (final change in [
      {'authorization': {'reusable': false, 'authorization_code': 'AUTH_fixture'}},
      {'metadata': {'user_id': 'other-member', 'payment_type': 'payment_method_setup'}},
      {'metadata': {'user_id': userId, 'payment_type': 'one_time_payment'}},
      {'reference': 'another-reference'},
    ]) {
      await http.runWithClient(
        () => expectLater(
          PaystackService().verifyPaymentMethod('pm_fixture', userId),
          throwsException,
        ),
        () => MockClient((request) async => http.Response(jsonEncode({
          'data': {
            'reference': 'pm_fixture', 'status': 'success', 'amount': 100, 'currency': 'ZAR',
            'metadata': {'user_id': userId, 'payment_type': 'payment_method_setup'},
            'authorization': {'reusable': true, 'authorization_code': 'AUTH_fixture'},
            ...change,
          },
        }), 200)),
      );
    }
    expect(requests, isEmpty);
  });

  test('a successful transaction for another deal cannot complete this checkout', () async {
    await http.runWithClient(
      () => expectLater(PaystackService().verifyTransaction('deal-ref', dealId: 'current-deal'), throwsException),
      () => MockClient((request) async => http.Response(jsonEncode({
        'data': {
          'reference': 'deal-ref', 'status': 'success',
          'metadata': {'user_id': userId, 'payment_type': 'one_time_payment', 'deal_authorization_id': 'other-deal'},
        },
      }), 200)),
    );
  });

  test('hosted deal checkout retains the authoritative server reference', () async {
    final checkout = await http.runWithClient(
      () => PaystackService().startOneTimePayment(
        itemName: 'Deal', itemDescription: 'Fixture', amount: 99,
        userId: userId, userEmail: 'billing@example.test',
        useCustomerCode: false,
        extraMetadata: {'deal_authorization_id': 'deal-fixture'},
      ),
      () => MockClient((request) async => http.Response(jsonEncode({
        'data': {
          'authorization_url': 'https://checkout.paystack.com/fixture',
          'reference': 'll-deal-authoritative',
        },
      }), 200)),
    );
    expect(checkout?['reference'], 'll-deal-authoritative');
    expect(requests, isEmpty);
  });
}
