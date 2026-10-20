import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../models/deal_authorization.dart';
import '../core/utils/display_name_helpers.dart';
import 'discount_service.dart';
import 'notification_service.dart';

class DealAuthorizationService {
  static final DealAuthorizationService _instance =
      DealAuthorizationService._internal();
  factory DealAuthorizationService() => _instance;
  DealAuthorizationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final DiscountService _discountService = DiscountService();
  final NotificationService _notificationService = NotificationService();
  final Logger _logger = Logger();

  Future<DealAuthorization> requestDealAuthorization({
    required String memberId,
    required String discountId,
    required String paymentMethod,
    required double amount,
    int? quantity,
    double? memberEnteredPrice,
    double? appliedDiscountAmount,
    String? dealType,
    Map<String, dynamic>? dealSnapshot,
    String? notes,
    Map<String, dynamic>? billData,
  }) async {
    try {
      if (kDebugMode) {
        print('🔍 [REQUEST_DEAL] Starting for discountId: $discountId');
      }

      // TP members (activated via promo key) bypass subscriptions entirely,
      // so check for TP membership first before requiring an active subscription.
      final profileCheck = await _supabase
          .from('profiles')
          .select('is_tp_member')
          .eq('id', memberId)
          .maybeSingle();

      final isTpMember = profileCheck?['is_tp_member'] == true;

      if (!isTpMember) {
        // Verify member has active subscription before allowing deal request
        final subscriptionCheck = await _supabase
            .from('subscriptions')
            .select('status, current_period_end')
            .eq('user_id', memberId)
            .eq('status', 'active')
            .maybeSingle();

        if (subscriptionCheck == null) {
          throw Exception('You need an active subscription to request deals.');
        }

        final periodEnd = subscriptionCheck['current_period_end'] as String?;
        if (periodEnd != null) {
          final expiryDate = DateTime.parse(periodEnd);
          if (expiryDate.isBefore(DateTime.now())) {
            throw Exception('Your subscription has expired. Please renew to request deals.');
          }
        }
      }

      // Get discount details - now includes business_id directly
      final discountResponse = await _supabase
          .from('trusted_partner_discounts')
          .select(
            'id, name, trusted_partner_id, business_id, is_once_off, deal_type, custom_data, requires_manual_price, percentage, fixed_amount, item_price, item_name',
          )
          .eq('id', discountId)
          .single();

      if (kDebugMode) {
        print('🔍 [DISCOUNT_FETCH] Response keys: ${discountResponse.keys}');
        print('🔍 [DISCOUNT_FETCH] Full response: $discountResponse');
      }

      final trustedPartnerUserId =
          discountResponse['trusted_partner_id'] as String?;
      final businessId = discountResponse['business_id'] as String?;

      if (kDebugMode) {
        print(
          '🔍 Extracted - trustedPartnerUserId: $trustedPartnerUserId, businessId: $businessId',
        );
      }

      if (businessId == null) {
        throw Exception(
          'This deal is missing business information. Please contact the trusted partner to update their deal.',
        );
      }

      if (trustedPartnerUserId == null) {
        throw Exception(
          'This deal is missing trusted partner information. Please contact support.',
        );
      }

      final isOnceOff = discountResponse['is_once_off'] == true;
      if (isOnceOff) {
        // Check for any existing authorization (pending, approved, OR completed)
        // to prevent duplicate once-off deal requests
        final existingRedeem = await _supabase
            .from('deal_authorizations')
            .select('id, status')
            .eq('member_id', memberId)
            .eq('discount_id', discountId)
            .inFilter('status', ['pending', 'approved', 'completed'])
            .limit(1);

        if (existingRedeem.isNotEmpty) {
          final existingStatus = existingRedeem.first['status'] as String?;
          if (existingStatus == 'completed') {
            throw Exception('You have already redeemed this once-off deal.');
          } else {
            throw Exception('You already have a pending or approved request for this once-off deal.');
          }
        }
      }

      // Create the deal authorization
      final dealAuth = await _discountService.createDealAuthorization(
        memberId: memberId,
        discountId: discountId,
        trustedPartnerUserId: trustedPartnerUserId,
        businessId: businessId,
        paymentMethod: paymentMethod,
        amount: amount,
        quantity: quantity,
        memberEnteredPrice: memberEnteredPrice,
        appliedDiscountAmount: appliedDiscountAmount,
        dealType: dealType ?? discountResponse['deal_type'] as String?,
        dealSnapshot: dealSnapshot ?? discountResponse,
        notes: notes,
        billData: billData,
      );

      // Get member details for notification + TP email
      final memberResponse = await _supabase
          .from('profiles')
          .select('name, surname, email, contact')
          .eq('id', memberId)
          .maybeSingle();

      final memberFirstName = memberResponse?['name'] as String? ?? '';
      final memberSurname = memberResponse?['surname'] as String? ?? '';
      final memberEmail = memberResponse?['email'] as String? ?? '';
      final memberPhone = memberResponse?['contact'] as String? ?? '';

      String memberName = '$memberFirstName $memberSurname'.trim();
      if (memberName.isEmpty) memberName = 'A member';

      final dealName = discountResponse['name'] as String? ?? 'a deal';

      // Send push notification to trusted partner (non-blocking – don't fail the deal request)
      try {
        await _notificationService.notifyTrustedPartnerOfDealRequest(
          trustedPartnerId: trustedPartnerUserId,
          dealAuthorizationId: dealAuth.id,
          memberId: memberId,
          memberName: memberName,
          dealName: dealName,
          amount: amount,
          paymentMethod: paymentMethod,
          quantity: quantity,
        );
      } catch (notifError) {
        // Log but don't block – the deal authorization was already created
        _logger.w('Could not send notification to trusted partner: $notifError');
      }

      // Send email to trusted partner (non-blocking – don't fail the deal request)
      try {
        await _supabase.functions.invoke(
          'send-deal-request-email',
          body: {
            'trusted_partner_id': trustedPartnerUserId,
            'member_id': memberId,
            'member_name': memberName,
            'member_first_name': memberFirstName,
            'member_surname': memberSurname,
            'member_email': memberEmail,
            'member_phone': memberPhone,
            'deal_name': dealName,
            'amount': amount,
            'payment_method': paymentMethod,
            'quantity': quantity,
            'deal_authorization_id': dealAuth.id,
          },
        );
        _logger.i('Deal request email sent to trusted partner');
      } catch (emailError) {
        // Log but don't block – push notification was already sent
        _logger.w('Could not send deal request email to trusted partner: $emailError');
      }

      return dealAuth;
    } catch (e) {
      throw Exception('Failed to request deal authorization: $e');
    }
  }

  Future<void> approveDealAuthorization({
    required String dealId,
    required String trustedPartnerId,
  }) async {
    try {
      // Update deal status to approved - this is the critical operation
      await _discountService.updateDealAuthorizationStatus(
        dealId: dealId,
        status: 'approved',
      );
    } catch (e) {
      _logger.e('Failed to update deal status to approved: $e');
      throw Exception('Failed to approve deal authorization: $e');
    }

    // Send notification separately - don't let notification failure block approval
    try {
      final deal = await _getDealAuthorization(dealId);
      _logger.i('Approval notification: memberId=${deal.memberId}, dealId=$dealId');

      final tpResponse = await _supabase
          .from('businesses')
          .select('name, contact_number, contact_email')
          .eq('owner_member_id', trustedPartnerId)
          .maybeSingle();

      final businessName = tpResponse?['name'] as String? ?? 'Business';
      final businessContact = tpResponse?['contact_number'] as String? ?? '';
      final businessEmail = tpResponse?['contact_email'] as String? ?? '';
      final dealSnapshot = deal.dealSnapshot;
      final dealName = dealSnapshot?['name'] as String? ?? 'deal';
      final quantity = dealSnapshot?['quantity'] as int?;

      _logger.i('Sending approval notification to member ${deal.memberId} for deal "$dealName" from "$businessName"');

      await _notificationService.notifyMemberOfDealApproval(
        memberId: deal.memberId,
        dealAuthorizationId: dealId,
        trustedPartnerName: businessName,
        businessName: businessName,
        dealName: dealName,
        amount: deal.amount ?? 0.0,
        paymentMethod: deal.paymentMethod ?? 'pos',
        quantity: quantity,
      );
      _logger.i('Approval notification sent successfully to member ${deal.memberId}');

      // Send email to member (non-blocking – don't fail the approval)
      try {
        await _supabase.functions.invoke(
          'send-deal-approval-email',
          body: {
            'member_id': deal.memberId,
            'trusted_partner_id': trustedPartnerId,
            'business_name': businessName,
            'business_contact': businessContact,
            'business_email': businessEmail,
            'deal_name': dealName,
            'amount': deal.amount ?? 0.0,
            'payment_method': deal.paymentMethod ?? 'pos',
            'quantity': quantity,
            'deal_authorization_id': dealId,
          },
        );
        _logger.i('Deal approval email sent to member ${deal.memberId}');
      } catch (emailError) {
        _logger.w('Could not send deal approval email to member: $emailError');
      }
    } catch (notifError) {
      _logger.e('Failed to send approval notification: $notifError');
      // Retry once with a delay — edge case where RPC cold-starts or network hiccups
      try {
        await Future.delayed(const Duration(seconds: 2));
        final deal = await _getDealAuthorization(dealId);
        final tpResponse = await _supabase
            .from('businesses')
            .select('name')
            .eq('owner_member_id', trustedPartnerId)
            .maybeSingle();
        final businessName = tpResponse?['name'] as String? ?? 'Business';
        final dealSnapshot = deal.dealSnapshot;
        final dealName = dealSnapshot?['name'] as String? ?? 'deal';
        final quantity = dealSnapshot?['quantity'] as int?;

        _logger.i('Retrying approval notification to member ${deal.memberId}');
        await _notificationService.notifyMemberOfDealApproval(
          memberId: deal.memberId,
          dealAuthorizationId: dealId,
          trustedPartnerName: businessName,
          businessName: businessName,
          dealName: dealName,
          amount: deal.amount ?? 0.0,
          paymentMethod: deal.paymentMethod ?? 'pos',
          quantity: quantity,
        );
        _logger.i('Approval notification retry succeeded');
      } catch (retryError) {
        _logger.e('Approval notification retry also failed: $retryError');
      }
    }
  }

  Future<void> rejectDealAuthorization({
    required String dealId,
    required String trustedPartnerId,
    required String rejectionReason,
  }) async {
    try {
      // Update deal status to rejected - this is the critical operation
      await _discountService.updateDealAuthorizationStatus(
        dealId: dealId,
        status: 'rejected',
        rejectionReason: rejectionReason,
      );
    } catch (e) {
      _logger.e('Failed to update deal status to rejected: $e');
      throw Exception('Failed to reject deal authorization: $e');
    }

    // Send notification separately - don't let notification failure block rejection
    try {
      final deal = await _getDealAuthorization(dealId);
      _logger.i('Rejection notification: memberId=${deal.memberId}, dealId=$dealId');

      final tpResponse = await _supabase
          .from('businesses')
          .select('name')
          .eq('owner_member_id', trustedPartnerId)
          .maybeSingle();

      final businessName = tpResponse?['name'] as String? ?? 'Business';
      final dealSnapshot = deal.dealSnapshot;
      final dealName = dealSnapshot?['name'] as String? ?? 'deal';

      _logger.i('Sending rejection notification to member ${deal.memberId}');

      await _notificationService.notifyMemberOfDealRejection(
        memberId: deal.memberId,
        dealAuthorizationId: dealId,
        trustedPartnerName: businessName,
        businessName: businessName,
        dealName: dealName,
        rejectionReason: rejectionReason,
      );
      _logger.i('Rejection notification sent successfully to member ${deal.memberId}');

      // Send email to member (non-blocking – don't fail the rejection)
      try {
        await _supabase.functions.invoke(
          'send-deal-rejection-email',
          body: {
            'member_id': deal.memberId,
            'business_name': businessName,
            'deal_name': dealName,
            'rejection_reason': rejectionReason,
            'deal_authorization_id': dealId,
          },
        );
        _logger.i('Deal rejection email sent to member ${deal.memberId}');
      } catch (emailError) {
        _logger.w('Could not send deal rejection email to member: $emailError');
      }
    } catch (notifError) {
      _logger.e('Failed to send rejection notification: $notifError');
      // Retry once
      try {
        await Future.delayed(const Duration(seconds: 2));
        final deal = await _getDealAuthorization(dealId);
        final tpResponse = await _supabase
            .from('businesses')
            .select('name')
            .eq('owner_member_id', trustedPartnerId)
            .maybeSingle();
        final businessName = tpResponse?['name'] as String? ?? 'Business';
        final dealSnapshot = deal.dealSnapshot;
        final dealName = dealSnapshot?['name'] as String? ?? 'deal';

        await _notificationService.notifyMemberOfDealRejection(
          memberId: deal.memberId,
          dealAuthorizationId: dealId,
          trustedPartnerName: businessName,
          businessName: businessName,
          dealName: dealName,
          rejectionReason: rejectionReason,
        );
        _logger.i('Rejection notification retry succeeded');
      } catch (retryError) {
        _logger.e('Rejection notification retry also failed: $retryError');
      }
    }
  }

  Future<String> processInAppPayment({
    required String dealId,
    required String memberId,
  }) async {
    try {
      // Get deal details
      final deal = await _getDealAuthorization(dealId);

      if (deal.paymentMethod != 'in_app') {
        throw Exception('This deal is not set up for in-app payment');
      }

      if (deal.status != 'approved') {
        throw Exception(
          'Deal must be approved before payment can be processed',
        );
      }

      if (deal.amount == null) {
        throw Exception('Deal amount is required for payment processing');
      }

      // Get member's payment method from subscription
      final memberProfile = await _supabase
          .from('profiles')
          .select('subscription_payment_method_id')
          .eq('id', memberId)
          .single();

      final paymentMethodId = memberProfile['subscription_payment_method_id'];
      if (paymentMethodId == null) {
        throw Exception('No payment method found for member');
      }

      // For now, simulate payment processing (integrate with actual payment provider later)
      // In production, this would call the actual payment service
      final paymentResult = {
        'status': 'success',
        'message': 'Payment processed successfully',
      };

      if (paymentResult['status'] == 'success') {
        // Generate receipt number
        final receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';
        final qrCode = 'QR-${dealId.substring(0, 8)}';

        // Get business and member details
        final discount = await _getDiscountWithTrustedPartner(deal.discountId);
        final businessResponse = await _supabase
            .from('businesses')
            .select('id, name, owner_member_id, contact_number, contact_email')
            .eq('owner_member_id', discount['trusted_partner_id'])
            .single();

        final memberResponse = await _supabase
            .from('profiles')
            .select('name, surname, email, contact')
            .eq('id', memberId)
            .single();

        final memberName =
            '${memberResponse['name'] ?? ''} ${memberResponse['surname'] ?? ''}'
                .trim();
        final memberEmail = memberResponse['email'] ?? '';
        final memberPhone = memberResponse['contact'] ?? '';
        final resolvedDiscountName = await _resolveDiscountName(deal);

        // Create receipt in deal_receipts table (for trusted partner's receipt tab)
        await _supabase.from('deal_receipts').insert({
          'deal_authorization_id': dealId,
          'member_id': memberId,
          'trusted_partner_id': discount['trusted_partner_id'],
          'business_id': businessResponse['id'],
          'receipt_number': receiptNumber,
          'amount': deal.amount,
          'payment_method': 'in_app',
          'business_name': businessResponse['name'],
          'business_contact': businessResponse['contact_number'],
          'business_email': businessResponse['contact_email'],
          'discount_name': resolvedDiscountName,
          'member_name': memberName,
          'member_email': memberEmail,
          'member_phone': memberPhone,
        });

        // Update deal status to completed
        await _discountService.updateDealAuthorizationStatus(
          dealId: dealId,
          status: 'completed',
        );

        final receiptData = {
          'deal_id': dealId,
          'amount': deal.amount,
          'payment_method': 'in_app',
          'transaction_date': DateTime.now().toUtc().toIso8601String(),
          'receipt_number': receiptNumber,
        };

        final virtualReceipt = await _discountService.createVirtualReceipt(
          dealAuthorizationId: dealId,
          receiptNumber: receiptNumber,
          receiptData: receiptData,
          qrCode: qrCode,
        );

        // Save to member's receipt book
        await _discountService.saveReceiptToMemberBook(
          memberId: memberId,
          virtualReceiptId: virtualReceipt.id,
          receiptNumber: receiptNumber,
          businessName: businessResponse['name'],
          amount: deal.amount!,
          transactionDate: DateTime.now().toUtc(),
        );

        // Create payment success notification
        await _discountService.createNotification(
          userId: memberId,
          title: 'Payment Successful',
          message:
              'Your payment of R${deal.amount!.toStringAsFixed(2)} has been processed successfully.',
          type: 'payment_success',
          data: {
            'deal_authorization_id': dealId,
            'amount': deal.amount,
            'receipt_id': virtualReceipt.id,
          },
        );

        return virtualReceipt.id;
      } else {
        throw Exception('Payment failed: ${paymentResult['message']}');
      }
    } catch (e) {
      throw Exception('Failed to process in-app payment: $e');
    }
  }

  Future<String> requestPOSPayment({
    required String dealId,
    required String memberId,
  }) async {
    try {
      // Get deal details
      final deal = await _getDealAuthorization(dealId);

      if (deal.paymentMethod != 'pos') {
        throw Exception('This deal is not set up for POS payment');
      }

      if (deal.status != 'approved') {
        throw Exception(
          'Deal must be approved before POS payment can be requested',
        );
      }

      if (deal.amount == null) {
        throw Exception('Deal amount is required for POS payment');
      }

      // Get trusted partner info
      final discount = await _getDiscountWithTrustedPartner(deal.discountId);
      final trustedPartnerId = discount['trusted_partner_id'];

      // Create POS payment request notification for trusted partner
      await _discountService.createNotification(
        userId: trustedPartnerId,
        title: 'POS Payment Request',
        message:
            'A member is ready to pay R${deal.amount!.toStringAsFixed(2)} at your POS terminal.',
        type: 'pos_payment_request',
        data: {
          'deal_authorization_id': dealId,
          'member_id': memberId,
          'amount': deal.amount,
        },
      );

      // Create notification for member
      await _discountService.createNotification(
        userId: memberId,
        title: 'POS Payment Requested',
        message:
            'Your POS payment request has been sent to the trusted partner. Please proceed to their location.',
        type: 'pos_payment_requested',
        data: {'deal_authorization_id': dealId, 'amount': deal.amount},
      );

      return 'POS payment request sent successfully';
    } catch (e) {
      throw Exception('Failed to request POS payment: $e');
    }
  }

  Future<void> completePOSPayment({
    required String dealId,
    required String trustedPartnerId,
  }) async {
    try {
      // Get deal details first
      final deal = await _getDealAuthorization(dealId);

      // Idempotency guard: if already completed, treat as success.
      if (deal.status == 'completed') {
        return;
      }

      // Check if deal is in approved status
      if (deal.status != 'approved') {
        throw Exception(
          'Cannot complete payment: Deal status is "${deal.status}", expected "approved"',
        );
      }

      // Generate receipt number
      final receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';
      final qrCode = 'QR-${dealId.substring(0, 8)}';

      // Get business details from the exact business referenced by this deal.
      // Querying by owner_member_id can fail when a TP owns multiple businesses.
      Map<String, dynamic>? businessResponse;

      if (deal.businessId != null && deal.businessId!.isNotEmpty) {
        businessResponse = await _supabase
            .from('businesses')
            .select('id, name, contact_number, contact_email')
            .eq('id', deal.businessId!)
            .maybeSingle();
      }

      // Fallback for legacy rows where business_id may be missing.
      businessResponse ??= await _supabase
          .from('businesses')
          .select('id, name, contact_number, contact_email')
          .eq('owner_member_id', trustedPartnerId)
          .limit(1)
          .maybeSingle();

      if (businessResponse == null) {
        throw Exception('Business not found for POS payment completion');
      }

      // Get member details
      final memberResponse = await _supabase
          .from('profiles')
          .select('name, surname, email, contact')
          .eq('id', deal.memberId)
          .single();

      final memberEmail = (memberResponse['email'] as String?) ?? '';
      final memberPhone = (memberResponse['contact'] as String?) ?? '';
      final memberName = buildMemberDisplayName(
        name: memberResponse['name'] as String?,
        surname: memberResponse['surname'] as String?,
        email: memberEmail,
      );
      final resolvedDiscountName = await _resolveDiscountName(deal);

      // Create receipt in deal_receipts table
      await _supabase.from('deal_receipts').insert({
        'deal_authorization_id': dealId,
        'member_id': deal.memberId,
        'trusted_partner_id': trustedPartnerId,
        'business_id': businessResponse['id'],
        'receipt_number': receiptNumber,
        'amount': deal.amount,
        'payment_method': 'pos',
        'business_name': businessResponse['name'],
        'business_contact': businessResponse['contact_number'],
        'business_email': businessResponse['contact_email'],
        'discount_name': resolvedDiscountName,
        'member_name': memberName,
        'member_email': memberEmail,
        'member_phone': memberPhone,
      });

      // Update deal status to completed and set completed_at timestamp
      await _discountService.updateDealAuthorizationStatus(
        dealId: dealId,
        status: 'completed',
      );

      // Build receipt data & create virtual receipt (to appear in member receipt page)
      final receiptData = {
        'deal_id': dealId,
        'amount': deal.amount,
        'payment_method': 'pos',
        'transaction_date': DateTime.now().toUtc().toIso8601String(),
        'receipt_number': receiptNumber,
        'note': 'in-store payment',
      };

      final virtualReceipt = await _discountService.createVirtualReceipt(
        dealAuthorizationId: dealId,
        receiptNumber: receiptNumber,
        receiptData: receiptData,
        qrCode: qrCode,
      );

      // Save to member's receipt book
      if (deal.amount != null) {
        await _discountService.saveReceiptToMemberBook(
          memberId: deal.memberId,
          virtualReceiptId: virtualReceipt.id,
          receiptNumber: receiptNumber,
          businessName: businessResponse['name'],
          amount: deal.amount!,
          transactionDate: DateTime.now().toUtc(),
        );
      }

      // Create notification for member
      await _discountService.createNotification(
        userId: deal.memberId,
        title: 'Receipt Issued',
        message:
            'Your receipt for R${deal.amount?.toStringAsFixed(2) ?? 'N/A'} has been issued. Receipt #: $receiptNumber',
        type: 'receipt_issued',
        data: {
          'deal_authorization_id': dealId,
          'amount': deal.amount,
          'receipt_number': receiptNumber,
          'virtual_receipt_id': virtualReceipt.id,
        },
      );
    } catch (e) {
      throw Exception('Failed to complete POS payment: $e');
    }
  }

  /// Cancel POS payment when payment is unsuccessful at terminal
  Future<void> cancelPOSPayment({
    required String dealId,
    required String memberId,
    required String reason,
  }) async {
    try {
      // Update deal status to rejected/cancelled
      await _discountService.updateDealAuthorizationStatus(
        dealId: dealId,
        status: 'rejected',
      );

      // Add rejection reason
      await _supabase
          .from('deal_authorizations')
          .update({'rejection_reason': reason})
          .eq('id', dealId);

      // Create notification for member about failed payment
      await _discountService.createNotification(
        userId: memberId,
        title: 'Payment Failed',
        message:
            'Your payment was unsuccessful at the store. The deal has been cancelled. Please try again or contact the business for assistance.',
        type: 'payment_failed',
        data: {'deal_authorization_id': dealId, 'reason': reason},
      );
    } catch (e) {
      throw Exception('Failed to cancel POS payment: $e');
    }
  }

  Future<DealAuthorization> _getDealAuthorization(String dealId) async {
    final response = await _supabase
        .from('deal_authorizations')
        .select()
        .eq('id', dealId)
        .single();

    return DealAuthorization.fromJson(response);
  }

  Future<String> _resolveDiscountName(DealAuthorization deal) async {
    // Prefer in-memory relationship when present.
    final joinedName = deal.discount?.name.trim();
    if (joinedName != null && joinedName.isNotEmpty) {
      return joinedName;
    }

    // Fall back to persisted request snapshot for resilience.
    final snapshotName = deal.dealSnapshot?['name']?.toString().trim();
    if (snapshotName != null && snapshotName.isNotEmpty) {
      return snapshotName;
    }

    // Last resort: query the discount row by ID.
    if (deal.discountId.isNotEmpty) {
      try {
        final discount = await _supabase
            .from('trusted_partner_discounts')
            .select('name')
            .eq('id', deal.discountId)
            .maybeSingle();

        final dbName = discount?['name']?.toString().trim();
        if (dbName != null && dbName.isNotEmpty) {
          return dbName;
        }
      } catch (e) {
        _logger.w('Could not resolve discount name for ${deal.discountId}: $e');
      }
    }

    return 'Unknown Deal';
  }

  Future<Map<String, dynamic>> _getDiscountWithTrustedPartner(
    String discountId,
  ) async {
    // First get the discount
    final discount = await _supabase
        .from('trusted_partner_discounts')
        .select('*')
        .eq('id', discountId)
        .single();

    // Then get the business owned by the trusted partner
    final business = await _supabase
        .from('businesses')
        .select('id, owner_member_id, name')
        .eq('owner_member_id', discount['trusted_partner_id'])
        .single();

    // Combine the results
    return {...discount, 'businesses': business};
  }
}
