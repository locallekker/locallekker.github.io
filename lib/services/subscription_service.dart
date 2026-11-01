import 'package:supabase_flutter/supabase_flutter.dart';
import 'qr_code_service.dart';
import 'paystack_service.dart';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';
import 'promotion_campaign_service.dart';

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  /// Returns a DateTime exactly one calendar month from [from].
  /// e.g. Feb 8 → Mar 8, Jan 31 → Feb 28.
  static DateTime oneCalendarMonthFrom(DateTime from) {
    var year = from.year;
    var month = from.month + 1;
    if (month > 12) {
      month = 1;
      year++;
    }
    // Clamp the day so e.g. Jan 31 → Feb 28
    final maxDay = DateTime(year, month + 1, 0).day;
    final day = from.day > maxDay ? maxDay : from.day;
    return DateTime(year, month, day, from.hour, from.minute, from.second, from.millisecond, from.microsecond);
  }

  /// Returns a DateTime [months] calendar months from [from], clamping the day
  /// (e.g. Jan 31 + 1 month → Feb 28). Handles year rollover in both directions.
  static DateTime addCalendarMonths(DateTime from, int months) {
    var year = from.year;
    var month = from.month + months;
    while (month > 12) {
      month -= 12;
      year++;
    }
    while (month < 1) {
      month += 12;
      year--;
    }
    final maxDay = DateTime(year, month + 1, 0).day;
    final day = from.day > maxDay ? maxDay : from.day;
    return DateTime(year, month, day, from.hour, from.minute, from.second, from.millisecond, from.microsecond);
  }

  Future<bool> processManualPayment({
    required String userId,
    required String planType,
    String? paystackSubscriptionCode,
    int renewalAmountCents = 9900,
  }) async {
    try {
      if (kDebugMode) {
        print(
          '[processManualPayment] Starting for userId=$userId, planType=$planType',
        );
      }
      final profile = await _client
          .from('profiles')
          .select('name, surname')
          .eq('id', userId)
          .single();
      if (kDebugMode) {
        print('[processManualPayment] Profile: $profile');
      }
      final name = profile['name'] as String? ?? 'Unknown';
      final surname = profile['surname'] as String? ?? 'Unknown';

      // First, deactivate ALL QR codes for this user (simpler query)
      if (kDebugMode) {
        print('[processManualPayment] Deactivating old QR codes...');
      }
      try {
        final deactivateResult = await _client
            .from('user_qr_codes')
            .update({'is_active': false})
            .eq('user_id', userId); // Remove the .eq('is_active', true) filter
        if (kDebugMode) {
          print(
            '[processManualPayment] Deactivated ALL QR codes for user: $deactivateResult',
          );
        }
      } catch (deactivateError) {
        if (kDebugMode) {
          print(
            '[processManualPayment] Deactivation error (continuing): $deactivateError',
          );
        }
      }

      // Try to create QR code, but don't fail activation if it fails
      try {
        final newQrCode = await QrCodeService().generateUniqueQrCode(userId);
        if (kDebugMode) {
          print('[processManualPayment] New QR code: $newQrCode');
        }

        final qrResult = await _client.from('user_qr_codes').insert({
          'user_id': userId,
          'qr_code': newQrCode,
          'name': name,
          'surname': surname,
          'is_active': true,
          'expires_at': oneCalendarMonthFrom(DateTime.now())
              .toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        if (kDebugMode) {
          print('[processManualPayment] QR insert result: $qrResult');
        }
      } catch (qrError) {
        if (kDebugMode) {
          print(
            '[processManualPayment] WARNING: QR code creation failed (non-critical): $qrError',
          );
        }
        // Continue with activation - QR can be regenerated later
      }

      // CRITICAL: Check if subscription exists, then INSERT or UPDATE
      // Use .limit(1) instead of .maybeSingle() to avoid throwing when
      // multiple subscription records exist for the same user (race
      // condition between app and webhook, or duplicate payments).
      final existingSubList = await _client
          .from('subscriptions')
          .select('id')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1);
      final existingSub = existingSubList.isNotEmpty ? existingSubList.first : null;

      if (kDebugMode) {
        print('[processManualPayment] Existing subscription: $existingSub');
      }

      final now = DateTime.now();
      final subscriptionData = {
        'user_id': userId,
        'plan_type': planType,
        'current_period_start': now.toIso8601String(),
        'current_period_end': oneCalendarMonthFrom(now)
            .toIso8601String(),
        'status': 'active',
        'auto_renew': true,
        'updated_at': now.toIso8601String(),
        'renewal_charge_cents': renewalAmountCents,
      };

      if (paystackSubscriptionCode != null) {
        subscriptionData['paystack_subscription_code'] =
            paystackSubscriptionCode;
      }

      if (existingSub == null) {
        // INSERT new subscription for first-time payment
        if (kDebugMode) {
          print('[processManualPayment] Creating NEW subscription record...');
        }
        subscriptionData['created_at'] = now.toIso8601String();
        final insertResult = await _client
            .from('subscriptions')
            .insert(subscriptionData)
            .select()
            .single();
        if (kDebugMode) {
          print(
            '[processManualPayment] Subscription INSERT result: $insertResult',
          );
        }
      } else {
        // UPDATE existing subscription for renewal (target the specific record
        // to avoid issues when multiple subscription rows exist for this user)
        if (kDebugMode) {
          print('[processManualPayment] Updating EXISTING subscription...');
        }
        final updateResult = await _client
            .from('subscriptions')
            .update(subscriptionData)
            .eq('id', existingSub['id'])
            .select()
            .single();
        if (kDebugMode) {
          print(
            '[processManualPayment] Subscription UPDATE result: $updateResult',
          );
        }
      }

      final updatedSubList = await _client
          .from('subscriptions')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1);
      final updatedSub = updatedSubList.isNotEmpty ? updatedSubList.first : null;
      if (kDebugMode) {
        print('[processManualPayment] Final subscription state: $updatedSub');
      }

      // CRITICAL: Update the user's profile subscription field to 'active'
      if (kDebugMode) {
        print(
          '[processManualPayment] Updating profile subscription to active...',
        );
      }
      final profileUpdateResult = await _client
          .from('profiles')
          .update({
            'subscription': 'active',
            'is_deactivated': false,
            'deactivation_reason': null,
            'deactivated_at': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
      if (kDebugMode) {
        print(
          '[processManualPayment] ✅ Profile subscription update result: $profileUpdateResult',
        );
      }

      // Try to insert renewal record, but don't fail if RLS blocks it
      try {
        final subId = updatedSub != null ? updatedSub['id'] : null;
        final renewalResult = await _client
            .from('subscription_renewals')
            .insert({
              'subscription_id': subId,
              'user_id': userId,
              'renewal_date': DateTime.now().toIso8601String(),
              'amount': renewalAmountCents / 100,
              'status': 'success',
              'qr_code_updated': true,
            });
        if (kDebugMode) {
          print('[processManualPayment] Renewal insert result: $renewalResult');
        }
      } catch (renewalError) {
        if (kDebugMode) {
          print(
            '[processManualPayment] WARNING: Renewal insert failed (non-critical): $renewalError',
          );
        }
        // Continue anyway - renewal record is optional for activation
      }

      // Create an in-app notification for the member. The notifications-insert
      // database webhook also turns this into an FCM push. Idempotency: skip if
      // the Paystack webhook already created an activation notification in the
      // last 10 minutes (covers the app-killed recovery race where the webhook
      // activates the subscription before the app does).
      try {
        final periodEnd = oneCalendarMonthFrom(now);
        final recentNotif = await _client
            .from('notifications')
            .select('id')
            .eq('user_id', userId)
            .eq('type', 'subscription_renewal')
            .gte(
              'created_at',
              now.subtract(const Duration(minutes: 10)).toIso8601String(),
            )
            .limit(1);
        if (recentNotif.isEmpty) {
          await _client.from('notifications').insert({
            'user_id': userId,
            'title': 'Subscription Activated',
            'message':
                'Your Local Lekker subscription is active until ${periodEnd.day}/${periodEnd.month}/${periodEnd.year}.',
            'type': 'subscription_renewal',
            'is_read': false,
            'data': {
              'expires_at': periodEnd.toIso8601String(),
              'amount': renewalAmountCents / 100,
              'source': 'app',
            },
          });
          if (kDebugMode) {
            print('[processManualPayment] Activation notification created');
          }
        } else if (kDebugMode) {
          print(
            '[processManualPayment] Recent activation notification exists, skipping',
          );
        }
      } catch (notifyError) {
        if (kDebugMode) {
          print(
            '[processManualPayment] WARNING: notification insert failed (non-critical): $notifyError',
          );
        }
      }

      // After subscription + terms completion, mark user verified for admin tabs
      try {
        await SupabaseService.instance.syncVerificationStatus(userId);
      } catch (verificationError) {
        if (kDebugMode) {
          print(
            '[processManualPayment] WARNING: syncVerificationStatus failed: $verificationError',
          );
        }
      }

      if (kDebugMode) {
        print('[processManualPayment] SUCCESS');
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        print('[processManualPayment] ERROR: $e\n$st');
      }
      return false;
    }
  }

  Future<bool> activateIntroCampaignSubscription({
    required String userId,
    required String promotionId,
    required String participantId,
    required int freeMonths,
    required int initialChargeCents,
    required int renewalChargeCents,
    String? introChargeReference,
  }) async {
    try {
      final profile = await _client
          .from('profiles')
          .select('name, surname')
          .eq('id', userId)
          .single();

      final name = profile['name'] as String? ?? 'Unknown';
      final surname = profile['surname'] as String? ?? 'Unknown';

      await _client
          .from('user_qr_codes')
          .update({'is_active': false})
          .eq('user_id', userId);

      // Authoritative free-month lookup. promotions.free_months IS NULL means a
      // lifetime membership (never expires) — see confirm_promo_signup(). The
      // passed-in freeMonths is only a fallback: callers coerce NULL -> 0, which
      // previously produced current_period_end == now (an already-expired
      // subscription) and blocked the member from requesting deals right after
      // paying the R1 intro fee.
      var isLifetime = false;
      var effectiveFreeMonths = freeMonths;
      try {
        final promoRow = await _client
            .from('promotions')
            .select('free_months')
            .eq('id', promotionId)
            .maybeSingle();
        if (promoRow != null) {
          final dbFreeMonths = promoRow['free_months'];
          if (dbFreeMonths == null) {
            isLifetime = true;
          } else if (dbFreeMonths is int) {
            effectiveFreeMonths = dbFreeMonths;
          } else {
            effectiveFreeMonths =
                int.tryParse(dbFreeMonths.toString()) ?? effectiveFreeMonths;
          }
        }
      } catch (_) {
        // Non-critical: fall back to the passed-in freeMonths.
      }

      final now = DateTime.now();
      // Never create an already-expired subscription. Lifetime → 100 years;
      // otherwise grant the free months, with a one-month floor so the R1
      // payment always buys at least the first billing period before R99.
      final monthsToGrant = isLifetime
          ? 1200
          : (effectiveFreeMonths > 0 ? effectiveFreeMonths : 1);
      final freePeriodEnd = addCalendarMonths(now, monthsToGrant);

      final newQrCode = await QrCodeService().generateUniqueQrCode(userId);
      await _client.from('user_qr_codes').insert({
        'user_id': userId,
        'qr_code': newQrCode,
        'name': name,
        'surname': surname,
        'is_active': true,
        'expires_at': freePeriodEnd.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final existingSubList = await _client
          .from('subscriptions')
          .select('id')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1);
      final existingSub =
          existingSubList.isNotEmpty ? existingSubList.first : null;

      final subscriptionData = {
        'user_id': userId,
        'plan_type': 'promotion_intro',
        'promotion_id': promotionId,
        'promo_participant_id': participantId,
        'current_period_start': now.toIso8601String(),
        'current_period_end': freePeriodEnd.toIso8601String(),
        'free_period_end': freePeriodEnd.toIso8601String(),
        'initial_charge_cents': initialChargeCents,
        'renewal_charge_cents': renewalChargeCents,
        'intro_charge_reference': introChargeReference,
        'intro_charge_paid_at': now.toIso8601String(),
        'status': 'active',
        'auto_renew': true,
        'updated_at': now.toIso8601String(),
      };

      if (existingSub == null) {
        subscriptionData['created_at'] = now.toIso8601String();
        await _client.from('subscriptions').insert(subscriptionData);
      } else {
        await _client
            .from('subscriptions')
            .update(subscriptionData)
            .eq('id', existingSub['id']);
      }

      await _client
          .from('profiles')
          .update({
            'subscription': 'active',
            'is_deactivated': false,
            'deactivation_reason': null,
            'deactivated_at': null,
            'updated_at': now.toIso8601String(),
          })
          .eq('id', userId);

      await PromotionCampaignService().markParticipantClaimed(
        participantId: participantId,
        userId: userId,
      );

      final existingSubId = existingSub?['id'];
      if (existingSubId != null) {
        try {
          await _client.from('subscription_renewals').insert({
            'subscription_id': existingSubId,
            'user_id': userId,
            'renewal_date': now.toIso8601String(),
            'amount': initialChargeCents / 100,
            'status': 'success',
            'qr_code_updated': true,
          });
        } catch (_) {
          // Non-critical audit insert.
        }
      }

      // In-app + push notification for the member. Idempotent vs. the webhook
      // intro-recovery race (skip if one was created in the last 10 minutes).
      try {
        final recentNotif = await _client
            .from('notifications')
            .select('id')
            .eq('user_id', userId)
            .eq('type', 'subscription_renewal')
            .gte(
              'created_at',
              now.subtract(const Duration(minutes: 10)).toIso8601String(),
            )
            .limit(1);
        if (recentNotif.isEmpty) {
          final benefit = isLifetime
              ? 'Your lifetime membership is now active. Enjoy Local Lekker!'
              : effectiveFreeMonths > 0
                  ? 'Enjoy $effectiveFreeMonths month(s) free until ${freePeriodEnd.day}/${freePeriodEnd.month}/${freePeriodEnd.year}.'
                  : 'Your membership is active until ${freePeriodEnd.day}/${freePeriodEnd.month}/${freePeriodEnd.year}.';
          await _client.from('notifications').insert({
            'user_id': userId,
            'title': 'Entry Offer Activated',
            'message': 'Welcome to Local Lekker! $benefit',
            'type': 'subscription_renewal',
            'is_read': false,
            'data': {
              'expires_at': freePeriodEnd.toIso8601String(),
              'amount': initialChargeCents / 100,
              'promotion_id': promotionId,
              'free_months': effectiveFreeMonths,
              'lifetime': isLifetime,
              'source': 'app',
            },
          });
        }
      } catch (notifyError) {
        if (kDebugMode) {
          print(
            '[activateIntroCampaignSubscription] WARNING: notification insert failed (non-critical): $notifyError',
          );
        }
      }

      return true;
    } catch (e, st) {
      if (kDebugMode) {
        print('[activateIntroCampaignSubscription] ERROR: $e\n$st');
      }
      return false;
    }
  }

  Future<Map<String, dynamic>?> getSubscriptionStatus(String userId) async {
    // Primary path: SECURITY DEFINER RPC that is resilient to profile/QR RLS
    // recursion issues in direct table reads.
    try {
      final rpcResult = await _client.rpc(
        'get_subscription_status',
        params: {'p_user_id': userId},
      );

      if (rpcResult is Map<String, dynamic>) {
        final mapped = Map<String, dynamic>.from(rpcResult);

        // Preserve legacy keys consumed by existing app logic.
        final rpcStatus = mapped['subscription_status'] as String?;
        mapped['status'] = rpcStatus;
        mapped['current_period_end'] = mapped['subscription_end_date'];
        return mapped;
      }
    } catch (e) {
      if (kDebugMode) {
        print('WARN getSubscriptionStatus: RPC get_subscription_status failed: $e');
      }
    }

    List<dynamic> response = [];

    // Fetch most recent subscription from Supabase (handle multiple subscriptions)
    try {
      response = await _client
          .from('subscriptions')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1);
    } catch (e) {
      if (kDebugMode) {
        print('WARN getSubscriptionStatus: subscriptions query failed: $e');
      }
    }

    Map<String, dynamic>? subscription;

    if (response.isNotEmpty) {
      subscription = Map<String, dynamic>.from(response[0]);
    } else {
      // Legacy fallback: older accounts may only have profiles.subscription.
      Map<String, dynamic>? legacyProfile;
      try {
        legacyProfile = await _client
            .from('profiles')
            .select('subscription')
            .eq('id', userId)
            .maybeSingle();
      } catch (e) {
        if (kDebugMode) {
          print('WARN getSubscriptionStatus: profiles fallback query failed: $e');
        }
      }

      final legacyStatus = legacyProfile?['subscription'] as String?;
      if (legacyStatus != 'active') return null;

      subscription = {
        'status': 'active',
        'subscription_status': 'active',
        'source': 'profiles.subscription',
      };
    }

    // Check if there's an active QR code. This should never determine
    // subscription status; it is supplemental data for UI/diagnostics.
    List<dynamic> qrCodeResponse = [];
    try {
      qrCodeResponse = await _client
          .from('user_qr_codes')
          .select('id, is_active, expires_at')
          .eq('user_id', userId)
          .eq('is_active', true)
          .gte('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1);
    } catch (e) {
      if (kDebugMode) {
        print('WARN getSubscriptionStatus: qr code query failed: $e');
      }
    }

    subscription['has_active_qr'] = qrCodeResponse.isNotEmpty;

    // Calculate days until renewal if not auto-renew
    if (subscription['current_period_end'] != null) {
      try {
        final renewalDate = DateTime.parse(subscription['current_period_end']);
        final now = DateTime.now();
        if (renewalDate.isAfter(now)) {
          subscription['days_until_renewal'] = renewalDate
              .difference(now)
              .inDays;
        } else {
          subscription['days_until_renewal'] = 0;
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Error calculating days until renewal: $e');
        }
      }
    }

    subscription['subscription_status'] = subscription['status'];

    return subscription;
  }

  Future<Map<String, dynamic>?> getUserQrCode(String userId) async {
    // Fetch most recent QR code from Supabase (handle multiple QR codes)
    final response = await _client
        .from('user_qr_codes')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1);

    if (response.isEmpty) return null;
    return response[0];
  }

  /// Checks if subscription is expired and deactivates QR code if necessary
  /// Returns true if subscription was expired and QR was deactivated
  Future<bool> checkAndHandleExpiredSubscription(String userId) async {
    if (kDebugMode) {
      print('🔍 Checking subscription expiry for user: $userId');
    }

    try {
      // Get subscription status
      final subscription = await getSubscriptionStatus(userId);

      if (subscription == null) {
        if (kDebugMode) {
          print('⚠️ No subscription found for user');
        }
        return false;
      }

      // Check if subscription has expired
      final currentPeriodEnd = subscription['current_period_end'];
      if (currentPeriodEnd == null) {
        if (kDebugMode) {
          print('⚠️ No current_period_end found in subscription');
        }
        return false;
      }

      final expiryDate = DateTime.parse(currentPeriodEnd);
      final now = DateTime.now();

      if (expiryDate.isBefore(now)) {
        final shouldAutoRenew = subscription['auto_renew'] == true;
        final latestSub = await _client
            .from('subscriptions')
            .select('paystack_subscription_code')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        final paystackSubscriptionCode =
            latestSub?['paystack_subscription_code'] as String?;

        final isPaystackManagedAutoRenew =
            paystackSubscriptionCode != null &&
            paystackSubscriptionCode.trim().isNotEmpty;

        if (shouldAutoRenew &&
            isPaystackManagedAutoRenew &&
            now.difference(expiryDate) < const Duration(hours: 36)) {
          if (kDebugMode) {
            print(
              '⏳ Paystack-managed auto-renew detected; skipping local renewal charge during grace window',
            );
          }
          return false;
        }

        if (shouldAutoRenew) {
          if (kDebugMode) {
            print('🔁 Subscription expired, attempting auto-renew charge...');
          }

          final renewed = await processSubscriptionRenewal(userId);
          if (renewed) {
            if (kDebugMode) {
              print('✅ Auto-renew successful, keeping subscription active');
            }
            return false;
          }
        }

        if (kDebugMode) {
          print('⏰ Subscription EXPIRED on ${expiryDate.toIso8601String()}');
        }
        if (kDebugMode) {
          print('📅 Current time: ${now.toIso8601String()}');
        }

        // Deactivate all QR codes for this user
        await _client
            .from('user_qr_codes')
            .update({'is_active': false})
            .eq('user_id', userId)
            .eq('is_active', true);

        if (kDebugMode) {
          print('🚫 QR codes deactivated for expired subscription');
        }

        // Update subscription status to 'expired' if not already
        if (subscription['status'] != 'expired') {
          await _client
              .from('subscriptions')
              .update({'status': 'expired'})
              .eq('user_id', userId)
              .eq('id', subscription['id']);

          if (kDebugMode) {
            print('📝 Subscription status updated to expired');
          }
        }

        // Sync profiles.subscription so NavigationService routes the member
        // to PaymentRequiredScreen on next login instead of MembersHomePage.
        try {
          await _client
              .from('profiles')
              .update({
                'subscription': 'expired',
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', userId);
          if (kDebugMode) {
            print('📝 Profile subscription field updated to expired');
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Could not update profile subscription field: $e');
          }
        }

        // Insert a payment_failure notification so the PaymentFailureAlert
        // banner shows on MembersHomePage if the user somehow gets there.
        try {
          final recentFailure = await _client
              .from('notifications')
              .select('id')
              .eq('user_id', userId)
              .eq('type', 'payment_failure')
              .gte(
                'created_at',
                DateTime.now()
                    .subtract(const Duration(hours: 24))
                    .toIso8601String(),
              )
              .limit(1);

          if (recentFailure.isEmpty) {
            await _client.from('notifications').insert({
              'user_id': userId,
              'title': 'Subscription Payment Failed',
              'message':
                  'Your automatic subscription renewal could not be processed. '
                  'Please update your payment method to continue enjoying Local Lekker discounts.',
              'type': 'payment_failure',
              'is_read': false,
              'data': {
                'reason': 'auto_renewal_failed',
                'expired_at': expiryDate.toIso8601String(),
              },
            });
            if (kDebugMode) {
              print('🔔 Payment failure notification created');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Could not create payment failure notification: $e');
          }
        }

        return true; // Subscription was expired
      } else {
        final daysRemaining = expiryDate.difference(now).inDays;
        if (kDebugMode) {
          print('✅ Subscription active - expires in $daysRemaining days');
        }
        return false; // Subscription is still active
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking subscription expiry: $e');
      }
      return false;
    }
  }

  Duration getTimeUntilNextPayment(DateTime subscriptionEndDate) {
    final now = DateTime.now();
    if (subscriptionEndDate.isBefore(now)) return Duration.zero;
    return subscriptionEndDate.difference(now);
  }

  /// Process subscription renewal using the primary payment method
  Future<bool> processSubscriptionRenewal(String userId) async {
    String? claimedSubscriptionId;
    try {
      if (kDebugMode) {
        print(
          '[processSubscriptionRenewal] Starting renewal for user: $userId',
        );
      }

      final paystackService = PaystackService();
      final primaryMethodId = await paystackService.getPrimaryPaymentMethod(
        userId,
      );

      if (primaryMethodId == null) {
        if (kDebugMode) {
          print('[processSubscriptionRenewal] No primary payment method found');
        }
        return false;
      }

      final profile = await _client
          .from('profiles')
          .select('email, name, surname, subscription_plan')
          .eq('id', userId)
          .single();

      final userEmail = profile['email'] as String?;
      if (userEmail == null) {
        if (kDebugMode) {
          print('[processSubscriptionRenewal] No email found in profile');
        }
        return false;
      }

      final subscriptionPlan = profile['subscription_plan'] as String?;
      final currentSubscription = await _client
          .from('subscriptions')
          .select(
            'id, current_period_end, plan_type, renewal_charge_cents, paystack_subscription_code',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final paystackSubscriptionCode =
          currentSubscription?['paystack_subscription_code'] as String?;
      if (paystackSubscriptionCode != null &&
          paystackSubscriptionCode.trim().isNotEmpty) {
        if (kDebugMode) {
          print(
            '[processSubscriptionRenewal] Skipping local charge because Paystack recurring subscription is active ($paystackSubscriptionCode)',
          );
        }
        return false;
      }

      final planType = (currentSubscription?['plan_type'] as String?) ??
          subscriptionPlan ??
          'subscription';
      final renewalChargeCents =
          (currentSubscription?['renewal_charge_cents'] as int?) ?? 9900;
      final amount = renewalChargeCents / 100;
      final subscriptionId = currentSubscription?['id'] as String?;
      final currentPeriodEnd = currentSubscription?['current_period_end'] as String?;

      if (subscriptionId == null || currentPeriodEnd == null) {
        return false;
      }

      final claimed = await _client.rpc(
        'claim_subscription_renewal',
        params: {'p_subscription_id': subscriptionId},
      ) as bool? ?? false;

      if (!claimed) {
        if (kDebugMode) {
          print('[processSubscriptionRenewal] Renewal already claimed or completed');
        }
        return false;
      }
      claimedSubscriptionId = subscriptionId;

      final renewalReference =
          'renewal_${subscriptionId}_${DateTime.parse(currentPeriodEnd).millisecondsSinceEpoch}';

      if (kDebugMode) {
        print(
          '[processSubscriptionRenewal] Charging saved card with authorization: $primaryMethodId',
        );
      }

      final success = await paystackService.chargeSavedCard(
        authorizationCode: primaryMethodId,
        amount: amount,
        userId: userId,
        userEmail: userEmail,
        reference: renewalReference,
        paymentType: 'subscription_renewal',
        extraMetadata: {
          'subscription_id': subscriptionId,
          'billing_period_end': currentPeriodEnd,
        },
      );

      if (success == 'success') {
        if (kDebugMode) {
          print(
            '[processSubscriptionRenewal] Payment successful, updating subscription',
          );
        }

        final now = DateTime.now();
        final nextBillingDate = oneCalendarMonthFrom(now);

        // Deactivate all existing QR codes
        try {
          await _client
              .from('user_qr_codes')
              .update({'is_active': false})
              .eq('user_id', userId);
        } catch (e) {
          if (kDebugMode) {
            print('[processSubscriptionRenewal] QR deactivation error: $e');
          }
        }

        // Generate new QR code
        try {
          final profileData = await _client
              .from('profiles')
              .select('name, surname')
              .eq('id', userId)
              .maybeSingle();
          final name = profileData?['name'] as String? ?? 'Unknown';
          final surname = profileData?['surname'] as String? ?? 'Unknown';
          final newQrCode = await QrCodeService().generateUniqueQrCode(userId);
          await _client.from('user_qr_codes').insert({
            'user_id': userId,
            'qr_code': newQrCode,
            'name': name,
            'surname': surname,
            'is_active': true,
            'expires_at': nextBillingDate.toIso8601String(),
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          });
        } catch (e) {
          if (kDebugMode) {
            print('[processSubscriptionRenewal] QR creation error (non-critical): $e');
          }
        }

        // Update subscriptions table (matching processManualPayment)
        final subscriptionData = {
          'user_id': userId,
          'plan_type': planType,
          'current_period_start': now.toIso8601String(),
          'current_period_end': nextBillingDate.toIso8601String(),
          'status': 'active',
          'auto_renew': true,
          'renewal_charge_cents': renewalChargeCents,
          'renewal_in_progress_at': null,
          'updated_at': now.toIso8601String(),
        };

        final existingSubList2 = await _client
            .from('subscriptions')
            .select('id')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(1);
        final existingSub = existingSubList2.isNotEmpty ? existingSubList2.first : null;

        if (existingSub == null) {
          subscriptionData['created_at'] = now.toIso8601String();
          await _client.from('subscriptions').insert(subscriptionData);
        } else {
          await _client
              .from('subscriptions')
              .update(subscriptionData)
              .eq('id', existingSub['id']);
        }

        // Update profile subscription status
        await _client
            .from('profiles')
            .update({
              'subscription': 'active',
              'is_deactivated': false,
              'deactivation_reason': null,
              'deactivated_at': null,
              'updated_at': now.toIso8601String(),
            })
            .eq('id', userId);

        // Insert renewal record
        try {
          final updatedSubList2 = await _client
              .from('subscriptions')
              .select('id')
              .eq('user_id', userId)
              .order('created_at', ascending: false)
              .limit(1);
          final updatedSub = updatedSubList2.isNotEmpty ? updatedSubList2.first : null;
          await _client.from('subscription_renewals').insert({
            'subscription_id': updatedSub?['id'],
            'user_id': userId,
            'renewal_date': now.toIso8601String(),
            'amount': amount,
            'status': 'success',
            'qr_code_updated': true,
          });
        } catch (e) {
          if (kDebugMode) {
            print('[processSubscriptionRenewal] Renewal record insert error: $e');
          }
        }

        if (kDebugMode) {
          print(
            '[processSubscriptionRenewal] Subscription renewed successfully',
          );
        }
        return true;
      } else {
        await _client.rpc(
          'release_subscription_renewal_claim',
          params: {'p_subscription_id': subscriptionId},
        );
        if (kDebugMode) {
          print('[processSubscriptionRenewal] Payment failed');
        }
        return false;
      }
    } catch (e) {
      if (claimedSubscriptionId != null) {
        try {
          await _client.rpc(
            'release_subscription_renewal_claim',
            params: {'p_subscription_id': claimedSubscriptionId},
          );
        } catch (_) {
          // The stale-claim timeout remains the fallback after a crash.
        }
      }
      if (kDebugMode) {
        print('[processSubscriptionRenewal] Error: $e');
      }
      return false;
    }
  }

  /// Get primary payment method details for a user
  Future<Map<String, dynamic>?> getPrimaryPaymentMethodDetails(
    String userId,
  ) async {
    try {
      final paystackService = PaystackService();
      final primaryMethodId = await paystackService.getPrimaryPaymentMethod(
        userId,
      );

      if (primaryMethodId == null) return null;

      final paymentMethods = await paystackService.getSavedPaymentMethods(
        userId,
      );
      for (final method in paymentMethods) {
        if (method['id'] == primaryMethodId ||
            method['authorization_code'] == primaryMethodId) {
          return method;
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting primary payment method details: $e');
      }
      return null;
    }
  }
}
