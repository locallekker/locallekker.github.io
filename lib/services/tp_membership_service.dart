import 'package:logger/logger.dart';
import 'supabase_service.dart';
import 'qr_code_service.dart';

/// Service to centralize Trusted Partner membership activation logic.
/// Converts a Trusted Partner into a TP Member (dual access) by:
/// 1. Validating the supplied unique key (when provided)
/// 2. Setting profiles.is_tp_member = true
/// 3. Setting trusted_partners.tp_member_status = 'active'
/// 4. Upserting memberships row (role = member, gateway = trusted_partner_key)
/// 5. Generating or activating a permanent QR code (100-year expiry)
class TpMembershipService {
  TpMembershipService._internal();
  static final TpMembershipService _instance = TpMembershipService._internal();
  factory TpMembershipService() => _instance;
  static TpMembershipService get instance => _instance;

  final Logger _logger = Logger();

  /// Activate TP membership using a Trusted Partner unique key.
  /// Returns true on success, false if key invalid.
  Future<bool> activateViaKey(String key, String userId) async {
    try {
      final formattedKey = key.trim().toUpperCase();
      if (formattedKey.length != 12) {
        _logger.w('TP key length invalid: $formattedKey');
        return false;
      }

      // Check tp_member_keys table first.
      // Wrapped in try-catch so a missing table (404) falls through
      // to the legacy trusted_partners.unique_key path.
      Map<String, dynamic>? memberKeyResponse;
      try {
        memberKeyResponse = await SupabaseService.instance.client
            .from('tp_member_keys')
            .select('id, trusted_partner_id, used_by')
            .eq('key', formattedKey)
            .maybeSingle();
      } catch (e) {
        _logger.w('tp_member_keys lookup failed (table may not exist): $e');
        memberKeyResponse = null;
      }

      if (memberKeyResponse != null) {
        if (memberKeyResponse['used_by'] != null) {
          _logger.w('TP member key already used: $formattedKey');
          return false;
        }

        await _applyActivation(userId);

        // Mark member key as used via RPC
        await SupabaseService.instance.client.rpc('mark_tp_key_used', params: {
          'p_key': formattedKey,
          'p_user_id': userId,
        });

        return true;
      }

      // Fall back to legacy trusted_partners.unique_key
      final tpResponse = await SupabaseService.instance.client
          .from('trusted_partners')
          .select('user_id, key_used_by')
          .eq('unique_key', formattedKey)
          .maybeSingle();

      if (tpResponse == null) {
        _logger.i('TP key not found: $formattedKey');
        return false;
      }

      // Check if key has already been used
      if (tpResponse['key_used_by'] != null) {
        _logger.w('TP key already used: $formattedKey');
        return false;
      }

      await _applyActivation(userId);

      // Mark key as used via RPC
      await SupabaseService.instance.client.rpc('mark_tp_key_used', params: {
        'p_key': formattedKey,
        'p_user_id': userId,
      });

      return true;
    } catch (e) {
      _logger.e('Failed activateViaKey: $e');
      rethrow;
    }
  }

  /// Direct activation (when key already validated externally).
  Future<void> activateDirect(String userId) async {
    await _applyActivation(userId);
  }

  Future<void> _applyActivation(String userId) async {
    final client = SupabaseService.instance.client;

    await client.rpc(
      'activate_tp_member_profile',
      params: {'p_user_id': userId},
    );

    // QR code activation / generation — use limit(1) to avoid
    // maybeSingle() error when user has multiple QR rows
    final existingQrList = await client
        .from('user_qr_codes')
        .select()
        .eq('user_id', userId)
        .order('is_active', ascending: false)
        .limit(1);

    if (existingQrList.isNotEmpty) {
      final existingQr = existingQrList.first;
      await client
          .from('user_qr_codes')
          .update({
            'is_active': true,
            'expires_at': DateTime.now()
                .add(const Duration(days: 36500))
                .toIso8601String(),
          })
          .eq('id', existingQr['id']);
      _logger.d('Reactivated existing permanent QR for $userId');
    } else {
      final qrCode = await QrCodeService().generateUniqueQrCode(userId);
      await client.from('user_qr_codes').insert({
        'user_id': userId,
        'qr_code': qrCode,
        'is_active': true,
        'expires_at': DateTime.now()
            .add(const Duration(days: 36500))
            .toIso8601String(),
      });
      _logger.d('Generated new permanent QR for $userId');
    }

    _logger.i('TP membership activated for user $userId');
  }
}
