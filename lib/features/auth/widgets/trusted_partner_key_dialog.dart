import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/supabase_service.dart';
import '../../../services/paystack_service.dart';
import '../../../services/qr_code_service.dart';
import '../../../services/tp_membership_service.dart';

class TrustedPartnerKeyDialog extends StatefulWidget {
  final String userId;
  final VoidCallback onSuccess;
  final bool isTrustedPartnerKey;

  const TrustedPartnerKeyDialog({
    super.key,
    required this.userId,
    required this.onSuccess,
    this.isTrustedPartnerKey = false,
  });

  @override
  State<TrustedPartnerKeyDialog> createState() =>
      _TrustedPartnerKeyDialogState();
}

class _TrustedPartnerKeyDialogState extends State<TrustedPartnerKeyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _keyController = TextEditingController();
  final _cardHolderNameController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _cardExpiryController = TextEditingController();
  final _cardCvvController = TextEditingController();
  bool _isVerifying = false;

  @override
  void dispose() {
    _keyController.dispose();
    _cardHolderNameController.dispose();
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    super.dispose();
  }

  Future<void> _verifyAndSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isVerifying = true;
    });

    try {
      final keyText = _keyController.text.trim().toUpperCase();
      final userEmail =
          SupabaseService.instance.getCurrentUser()?.email ?? '';

      // Check admin_promo_keys table first (admin-issued email-locked keys)
      final adminKeyResponse = await SupabaseService.instance.client
          .from('admin_promo_keys')
          .select('id, email, duration_months, used_by')
          .eq('key', keyText)
          .maybeSingle();

      if (adminKeyResponse != null) {
        // Admin promo key found — validate email and usage
        if (adminKeyResponse['used_by'] != null) {
          _showError('This promo key has already been used');
          setState(() => _isVerifying = false);
          return;
        }

        // Check email matches
        final keyEmail =
            (adminKeyResponse['email'] as String).toLowerCase();
        if (keyEmail != userEmail.toLowerCase()) {
          _showError(
              'This promo key is not linked to your email address');
          setState(() => _isVerifying = false);
          return;
        }

        // Save card details if provided
        await _saveCardIfProvided();

        // Create subscription with the specified duration
        final durationMonths = adminKeyResponse['duration_months'] as int?;
        await _createPromoSubscription(
          widget.userId,
          durationMonths: durationMonths,
        );

        // Mark admin key as used
        await SupabaseService.instance.client
            .from('admin_promo_keys')
            .update({
              'used_by': widget.userId,
              'used_at': DateTime.now().toIso8601String(),
            })
            .eq('key', keyText);

        if (mounted) {
          Navigator.of(context).pop();
          widget.onSuccess();
        }
        return;
      }

      // Check tp_member_keys table (issued member keys).
      // Wrapped in try-catch so a missing table (404) doesn't block
      // the legacy trusted_partners.unique_key path.
      Map<String, dynamic>? memberKeyResponse;
      try {
        memberKeyResponse = await SupabaseService.instance.client
            .from('tp_member_keys')
            .select('id, trusted_partner_id, used_by')
            .eq('key', keyText)
            .maybeSingle();
      } catch (_) {
        memberKeyResponse = null;
      }

      // Then check legacy trusted_partners.unique_key
      final tpResponse = await SupabaseService.instance.client
          .from('trusted_partners')
          .select('user_id, key_used_by')
          .eq('unique_key', keyText)
          .maybeSingle();

      if (memberKeyResponse == null && tpResponse == null) {
        _showError('Invalid promo key');
        setState(() => _isVerifying = false);
        return;
      }

      // Check if the key has already been used
      final bool isUsed;

      if (memberKeyResponse != null) {
        isUsed = memberKeyResponse['used_by'] != null;
      } else {
        isUsed = tpResponse!['key_used_by'] != null;
      }

      if (isUsed) {
        _showError('This promo key has already been used');
        setState(() => _isVerifying = false);
        return;
      }

      // Save card details if provided
      await _saveCardIfProvided();

      await TpMembershipService.instance.activateDirect(widget.userId);

      // Mark the key as used via RPC (bypasses RLS so members can
      // mark keys belonging to other users' trusted_partners rows)
      await SupabaseService.instance.client.rpc('mark_tp_key_used', params: {
        'p_key': keyText,
        'p_user_id': widget.userId,
      });

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() {
        _isVerifying = false;
      });
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _saveCardIfProvided() async {
    final hasCard = _cardNumberController.text.trim().isNotEmpty &&
        _cardExpiryController.text.trim().isNotEmpty &&
        _cardCvvController.text.trim().isNotEmpty;
    if (!hasCard) return;

    final expiryParts = _cardExpiryController.text.split('/');
    if (expiryParts.length != 2) {
      throw Exception('Invalid expiry date format. Use MM/YY');
    }

    final paystackService = PaystackService();
    final userEmail = SupabaseService.instance.getCurrentUser()?.email ?? '';

    final tokenizationResult = await paystackService.tokenizeCard(
      cardNumber: _cardNumberController.text.trim(),
      expiryMonth: expiryParts[0].trim(),
      expiryYear: expiryParts[1].trim(),
      cvv: _cardCvvController.text.trim(),
      cardHolderName: _cardHolderNameController.text.trim(),
      userEmail: userEmail,
      userId: widget.userId,
    );

    if (tokenizationResult != null) {
      final existingCard = await SupabaseService.instance.client
          .from('members_card_details')
          .select()
          .eq('user_id', widget.userId)
          .eq('is_primary', true)
          .maybeSingle();

      final cardData = {
        'user_id': widget.userId,
        'authorization_code': tokenizationResult['authorization_code'],
        'card_type': tokenizationResult['card_type'] ?? 'card',
        'last4': tokenizationResult['last4'],
        'exp_month': tokenizationResult['exp_month'],
        'exp_year': tokenizationResult['exp_year'],
        'bank': tokenizationResult['bank'] ?? '',
        'brand': tokenizationResult['brand'] ?? '',
        'is_primary': true,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existingCard != null) {
        await SupabaseService.instance.client
            .from('members_card_details')
            .update(cardData)
            .eq('id', existingCard['id']);
      } else {
        cardData['created_at'] = DateTime.now().toIso8601String();
        await SupabaseService.instance.client
            .from('members_card_details')
            .insert(cardData);
      }
    } else {
      throw Exception(
          'Failed to tokenize card. Please check your card details.');
    }
  }

  Future<void> _createPromoSubscription(
    String userId, {
    required int? durationMonths,
  }) async {
    final client = SupabaseService.instance.client;
    final now = DateTime.now();

    // Calculate period end
    final DateTime periodEnd;
    if (durationMonths == null) {
      // All time — 100 years
      periodEnd = now.add(const Duration(days: 36500));
    } else {
      periodEnd = DateTime(
        now.year,
        now.month + durationMonths,
        now.day,
        now.hour,
        now.minute,
        now.second,
      );
    }

    // Create subscription
    final existingSubList = await client
        .from('subscriptions')
        .select('id')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1);
    final existingSub =
        existingSubList.isNotEmpty ? existingSubList.first : null;

    final subscriptionData = {
      'user_id': userId,
      'plan_type': 'admin_promo',
      'current_period_start': now.toIso8601String(),
      'current_period_end': periodEnd.toIso8601String(),
      'status': 'active',
      'updated_at': now.toIso8601String(),
    };

    if (existingSub == null) {
      subscriptionData['created_at'] = now.toIso8601String();
      await client.from('subscriptions').insert(subscriptionData);
    } else {
      await client
          .from('subscriptions')
          .update(subscriptionData)
          .eq('id', existingSub['id']);
    }

    // Update profile subscription status
    await SupabaseService.instance.updateUserProfile(
      userId: userId,
      profileData: {'subscription': 'active'},
    );

    // Generate QR code
    final existingQr = await client
        .from('user_qr_codes')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (existingQr != null) {
      await client.from('user_qr_codes').update({
        'is_active': true,
        'expires_at': periodEnd.toIso8601String(),
      }).eq('user_id', userId);
    } else {
      final qrCode =
          await QrCodeService().generateUniqueQrCode(userId);
      await client.from('user_qr_codes').insert({
        'user_id': userId,
        'qr_code': qrCode,
        'is_active': true,
        'expires_at': periodEnd.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyLabel = widget.isTrustedPartnerKey
        ? 'Trusted Partner key'
        : 'Promo Key';

    return Dialog(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.vpn_key, color: Colors.blue, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Enter $keyLabel',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Enter your $keyLabel to activate your membership for free.',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _keyController,
                  decoration: InputDecoration(
                    labelText: keyLabel,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.vpn_key),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return 'Please enter the key';
                    }
                    if (value!.length != 12) {
                      return 'Key must be 12 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Card Details (Optional)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can add card details later in your profile or when making your first purchase.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cardHolderNameController,
                  decoration: const InputDecoration(
                    labelText: 'Card Holder Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cardNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Card Number',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.credit_card),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(16),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cardExpiryController,
                        decoration: const InputDecoration(
                          labelText: 'Expiry (MM/YY)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(5),
                          _ExpiryDateFormatter(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _cardCvvController,
                        decoration: const InputDecoration(
                          labelText: 'CVV',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock),
                        ),
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isVerifying ? null : _verifyAndSave,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isVerifying
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verify and Activate'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('/', '');
    if (text.length > 4) return oldValue;

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(text[i]);
    }

    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}
