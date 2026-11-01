import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:logger/logger.dart';
import '../../services/supabase_service.dart';
import '../../services/notification_service.dart';
import 'package:local_lekker/core/theme/app_colors.dart';

class PromotionDetailPage extends StatefulWidget {
  final Map<String, dynamic> promotion;

  const PromotionDetailPage({
    super.key,
    required this.promotion,
  });

  @override
  State<PromotionDetailPage> createState() => _PromotionDetailPageState();
}

class _PromotionDetailPageState extends State<PromotionDetailPage> {
  final Logger _logger = Logger();
  final NotificationService _notificationService = NotificationService();

  bool _isSigningUp = false;
  bool _hasSignedUp = false;
  String? _signupStatus;

  @override
  void initState() {
    super.initState();
    _checkExistingSignup();
  }

  Future<void> _checkExistingSignup() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      final response = await SupabaseService.instance.client
          .from('promotion_signups')
          .select('status')
          .eq('promotion_id', widget.promotion['id'])
          .eq('user_id', user.id)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _hasSignedUp = true;
          _signupStatus = response['status'];
        });
      }
    } catch (e) {
      _logger.w('Error checking existing signup: $e');
    }
  }

  Future<void> _signUp() async {
    setState(() => _isSigningUp = true);

    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) throw Exception('Not logged in');

      // Get user profile for cached fields
      final profile = await SupabaseService.instance.client
          .from('profiles')
          .select('name, surname, email, contact_number')
          .eq('id', user.id)
          .single();

      final isIntroCampaign = widget.promotion['is_intro_campaign'] == true;
      final email = (profile['email'] as String?)?.trim().toLowerCase();
      if (isIntroCampaign) {
        if (email == null || email.isEmpty) {
          throw Exception('No email found on your profile.');
        }

        final eligible = await SupabaseService.instance.client
            .from('promotion_participant_emails')
            .select('id')
            .eq('promotion_id', widget.promotion['id'])
            .eq('email', email)
            .limit(1);

        if (eligible.isEmpty) {
          throw Exception(
            'Your email is not registered for this campaign. Please contact admin support.',
          );
        }
      }

      final fullName = [profile['name'], profile['surname']]
          .where((s) => s != null && s.toString().isNotEmpty)
          .join(' ');

      // Insert signup
      await SupabaseService.instance.client.from('promotion_signups').insert({
        'promotion_id': widget.promotion['id'],
        'user_id': user.id,
        'user_name': fullName.isNotEmpty ? fullName : null,
        'user_email': profile['email'],
        'user_contact': profile['contact_number'],
        'status': 'pending',
      });

      setState(() {
        _hasSignedUp = true;
        _signupStatus = 'pending';
      });

      // IMPORTANT: Do NOT mark the participant email as claimed here.
      // The `is_claimed` flag gates the R1 intro-campaign price — the
      // eligibility RPC (check_promo_eligibility_for_email) only returns the
      // R1 offer while `is_claimed = false`. Claiming it now, before payment,
      // silently removes the R1 offer so the member is charged the standard
      // R99 instead. The email is marked claimed only after the intro payment
      // completes (SubscriptionService.activateIntroCampaignSubscription).
      // Admins still see this signup via the `promotion_signups` list.

      // Send email notification to admin
      try {
        await SupabaseService.instance.client.functions.invoke(
          'send-promo-signup-email',
          body: {
            'member_name': fullName.isNotEmpty ? fullName : 'Member',
            'member_email': profile['email'],
            'member_contact': profile['contact_number'],
            'promotion_name': widget.promotion['name'],
            'free_months': widget.promotion['free_months'],
          },
        );
      } catch (emailError) {
        _logger.w('Failed to send signup email: $emailError');
      }

      // Send in-app notification to admins
      try {
        await _notificationService.notifyAdmins(
          title: '📢 New Promo Signup',
          message:
              '${fullName.isNotEmpty ? fullName : "A member"} signed up for "${widget.promotion['name']}"',
          type: 'promo_signup',
          data: {
            'promotion_id': widget.promotion['id'],
            'promotion_name': widget.promotion['name'],
            'member_id': user.id,
            'member_name': fullName,
          },
        );
      } catch (notifError) {
        _logger.w('Failed to notify admins: $notifError');
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 28),
                const SizedBox(width: 8),
                const Expanded(child: Text('Signed Up!')),
              ],
            ),
            content: const Text(
              'You have successfully signed up for this promotion! '
              'An admin will review and confirm your signup shortly.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _logger.e('Error signing up for promotion: $e');
      if (mounted) {
        String message = 'Error signing up';
        if (e.toString().contains('unique') ||
            e.toString().contains('duplicate')) {
          message = 'You have already signed up for this promotion';
          setState(() {
            _hasSignedUp = true;
            _signupStatus = 'pending';
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final promo = widget.promotion;
    final imageUrl = promo['image_url'] as String?;
    final freeMonths = promo['free_months'];
    final durationText = freeMonths != null
      ? '$freeMonths month(s) free'
      : 'Free lifetime membership';
    final endsAt = promo['ends_at'];

    return Scaffold(
      appBar: BrandedAppBar(
        title: Text(promo['name'] ?? 'Promotion'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner image
            if (imageUrl != null && imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  color: AppColors.primarySwatch.shade50,
                  child: const Center(
                    child: Icon(Icons.campaign, size: 48, color: AppColors.primary),
                  ),
                ),
              )
            else
              Container(
                height: 120,
                color: AppColors.primarySwatch.shade50,
                child: const Center(
                  child: Icon(Icons.campaign, size: 48, color: AppColors.primary),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    promo['name'] ?? 'Promotion',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Duration badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.card_giftcard,
                            size: 20, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Text(
                          durationText,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  Text(
                    _buildPromoNote(freeMonths),
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Colors.grey.shade800,
                    ),
                  ),

                  // End date countdown
                  if (endsAt != null) ...[
                    const SizedBox(height: 12),
                    _buildEndDateInfo(endsAt),
                  ],

                  // Description
                  if (promo['description'] != null &&
                      (promo['description'] as String).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      promo['description'],
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Sign up button or status
                  _buildSignupSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildPromoNote(dynamic freeMonthsValue) {
    final freeMonths = freeMonthsValue as int?;
    const initialChargeText = 'R1.00';

    if (freeMonths == null) {
      return 'Pay $initialChargeText signup and enjoy a free lifetime membership.';
    }

    return 'Pay $initialChargeText signup and enjoy $freeMonths month(s) free.';
  }

  Widget _buildEndDateInfo(String endsAt) {
    try {
      final endDate = DateTime.parse(endsAt).toLocal();
      final now = DateTime.now();
      final daysLeft = endDate.difference(now).inDays;

      Color textColor;
      String text;
      if (daysLeft <= 0) {
        textColor = Colors.red;
        text = 'This promotion has ended';
      } else if (daysLeft <= 3) {
        textColor = Colors.orange;
        text = 'Ends in $daysLeft day(s) – hurry!';
      } else {
        textColor = Colors.grey.shade600;
        text = 'Ends on ${endDate.day}/${endDate.month}/${endDate.year} ($daysLeft days left)';
      }

      return Row(
        children: [
          Icon(Icons.schedule, size: 16, color: textColor),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: textColor, fontSize: 13)),
        ],
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildSignupSection() {
    if (_hasSignedUp) {
      IconData icon;
      String text;
      Color color;

      switch (_signupStatus) {
        case 'confirmed':
          icon = Icons.check_circle;
          text = 'Confirmed! Your subscription has been extended.';
          color = Colors.green;
          break;
        case 'cancelled':
          icon = Icons.cancel;
          text = 'Your signup was cancelled.';
          color = Colors.red;
          break;
        default:
          icon = Icons.hourglass_empty;
          text = 'Signed up – awaiting admin confirmation';
          color = Colors.orange;
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 48,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSigningUp ? null : _signUp,
        icon: _isSigningUp
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.how_to_reg),
        label: Text(
          _isSigningUp ? 'Signing Up...' : 'Sign Up for This Promotion',
          style: const TextStyle(fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
