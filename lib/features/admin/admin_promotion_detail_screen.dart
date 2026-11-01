import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:logger/logger.dart';
import '../../services/supabase_service.dart';
import '../../services/notification_service.dart';
import '../../services/promotion_campaign_service.dart';
import 'package:local_lekker/core/theme/app_colors.dart';

class AdminPromotionDetailScreen extends StatefulWidget {
  final String promotionId;

  const AdminPromotionDetailScreen({
    super.key,
    required this.promotionId,
  });

  @override
  State<AdminPromotionDetailScreen> createState() =>
      _AdminPromotionDetailScreenState();
}

class _AdminPromotionDetailScreenState
    extends State<AdminPromotionDetailScreen> {
  final Logger _logger = Logger();
  final NotificationService _notificationService = NotificationService();

  Map<String, dynamic>? _promotion;
  List<Map<String, dynamic>> _signups = [];
  List<Map<String, dynamic>> _participants = [];
  bool _isLoading = true;
  bool _isImporting = false;
  Set<String> _confirmingIds = {};
  final TextEditingController _emailInputController = TextEditingController();
  final FocusNode _emailInputFocusNode = FocusNode();
  final List<String> _pendingEmails = [];

  @override
  void dispose() {
    _emailInputController.dispose();
    _emailInputFocusNode.dispose();
    super.dispose();
  }

  void _addEmailChip() {
    final email = _emailInputController.text.trim().toLowerCase();
    if (email.isEmpty) return;
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) return;
    if (_pendingEmails.contains(email)) {
      _emailInputController.clear();
      return;
    }
    setState(() {
      _pendingEmails.add(email);
      _emailInputController.clear();
    });
    _emailInputFocusNode.requestFocus();
  }

  void _removeEmailChip(String email) {
    setState(() => _pendingEmails.remove(email));
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final promo = await SupabaseService.instance.client
          .from('promotions')
          .select()
          .eq('id', widget.promotionId)
          .single();

      final signups = await SupabaseService.instance.client
          .from('promotion_signups')
          .select()
          .eq('promotion_id', widget.promotionId)
          .order('created_at', ascending: false);

      final participants = await PromotionCampaignService()
          .getPromotionParticipants(promotionId: widget.promotionId);

      setState(() {
        _promotion = promo;
        _signups = List<Map<String, dynamic>>.from(signups);
        _participants = participants;
        _isLoading = false;
      });
    } catch (e) {
      _logger.e('Error loading promotion detail: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importParticipants() async {
    // Add any email still typed in the field before importing
    _addEmailChip();
    if (_pendingEmails.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add at least one email before importing.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isImporting = true);
    try {
      final rawInput = _pendingEmails.join('\n');
      final result = await PromotionCampaignService().importParticipantEmails(
        promotionId: widget.promotionId,
        rawInput: rawInput,
      );

      final inserted = result['inserted'] as int? ?? 0;
      final alreadyExists = result['alreadyExists'] as int? ?? 0;
      final invalidEmails = (result['invalidEmails'] as List).length;
      final duplicates = result['duplicates'] as int? ?? 0;

      setState(() => _pendingEmails.clear());
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Import complete: $inserted added, $alreadyExists existing, $invalidEmails invalid, $duplicates duplicate input.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _logger.e('Error importing participants: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _confirmSignup(Map<String, dynamic> signup) async {
    final signupId = signup['id'] as String;
    setState(() => _confirmingIds.add(signupId));

    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) throw Exception('Not logged in');

      final result = await SupabaseService.instance.client.rpc(
        'confirm_promo_signup',
        params: {
          'p_signup_id': signupId,
          'p_admin_id': user.id,
        },
      );

      final response = result as Map<String, dynamic>;
      if (response['success'] != true) {
        throw Exception(response['error'] ?? 'Unknown error');
      }

      // Send confirmation email to member
      try {
        await SupabaseService.instance.client.functions.invoke(
          'send-promo-confirmation-email',
          body: {
            'member_id': signup['user_id'],
            'promotion_name': _promotion?['name'] ?? 'Promotion',
            'free_months': _promotion?['free_months'],
          },
        );
      } catch (emailError) {
        _logger.w('Failed to send confirmation email: $emailError');
      }

      // Send in-app notification to member
      try {
        final promoName = _promotion?['name'] ?? 'Promotion';
        final freeMonths = _promotion?['free_months'];
        final durationText = freeMonths != null
            ? '$freeMonths month(s) free'
            : 'lifetime access';

        await _notificationService.createNotification(
          userId: signup['user_id'],
          title: '🎉 Promotion Confirmed!',
          message:
              'Your signup for "$promoName" has been confirmed! You now have $durationText added to your subscription.',
          type: 'promo_confirmed',
          data: {
            'promotion_id': widget.promotionId,
            'promotion_name': promoName,
            'free_months': freeMonths,
          },
        );
      } catch (notifError) {
        _logger.w('Failed to send in-app notification: $notifError');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signup confirmed and subscription extended!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      _loadData();
    } catch (e) {
      _logger.e('Error confirming signup: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _confirmingIds.remove(signupId));
    }
  }

  Future<void> _cancelSignup(Map<String, dynamic> signup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Signup'),
        content: Text(
          'Cancel signup for ${signup['user_name'] ?? 'this member'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SupabaseService.instance.client
          .from('promotion_signups')
          .update({'status': 'cancelled'})
          .eq('id', signup['id']);
      _loadData();
    } catch (e) {
      _logger.e('Error cancelling signup: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleActive() async {
    if (_promotion == null) return;
    try {
      final newActive = !(_promotion!['is_active'] ?? true);
      await SupabaseService.instance.client
          .from('promotions')
          .update({'is_active': newActive})
          .eq('id', widget.promotionId);
      _loadData();
    } catch (e) {
      _logger.e('Error toggling promotion: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: BrandedAppBar(title: const Text('Promotion')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_promotion == null) {
      return Scaffold(
        appBar: BrandedAppBar(title: const Text('Promotion')),
        body: const Center(child: Text('Promotion not found')),
      );
    }

    final promo = _promotion!;
    final isActive = promo['is_active'] ?? false;
    final freeMonths = promo['free_months'];
    final durationText = freeMonths != null ? '$freeMonths month(s) free' : 'Lifetime';
    final imageUrl = promo['image_url'] as String?;
    final pendingParticipants =
        _participants.where((p) => p['is_claimed'] != true).length;
    final claimedParticipants =
        _participants.where((p) => p['is_claimed'] == true).length;

    return Scaffold(
      appBar: BrandedAppBar(
        title: Text(promo['name'] ?? 'Promotion'),
        actions: [
          IconButton(
            icon: Icon(isActive ? Icons.pause : Icons.play_arrow),
            tooltip: isActive ? 'Deactivate' : 'Activate',
            onPressed: _toggleActive,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Promo header card
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    Image.network(
                      imageUrl,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.card_giftcard, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(durationText,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (promo['description'] != null &&
                            (promo['description'] as String).isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(promo['description']),
                        ],
                        if (promo['ends_at'] != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Ends: ${_formatDate(promo['ends_at'])}',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildStatChip(
                                Icons.hourglass_empty,
                                '$pendingParticipants pending',
                                color: Colors.orange),
                            const SizedBox(width: 8),
                            _buildStatChip(
                                Icons.check_circle,
                                '$claimedParticipants confirmed',
                                color: Colors.green),
                            const SizedBox(width: 8),
                            _buildStatChip(
                                Icons.group,
                                '${_participants.length} total',
                                color: Colors.blue),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _participants.isNotEmpty
                                  ? _showParticipantEmailsDialog
                                  : null,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  Icons.mail_outline,
                                  size: 18,
                                  color: _participants.isNotEmpty
                                      ? Colors.indigo
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_participants.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '$claimedParticipants/${_participants.length} participant emails claimed',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Participant Email Allocation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Type an email and tap Add (or press Enter) to add it as a chip.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    // Chip display
                    if (_pendingEmails.isNotEmpty) ...[  
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _pendingEmails.map((email) {
                          return Chip(
                            label: Text(
                              email,
                              style: const TextStyle(fontSize: 13),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => _removeEmailChip(email),
                            backgroundColor: AppColors.primarySwatch.shade50,
                            deleteIconColor: AppColors.primarySwatch.shade700,
                            side: BorderSide(color: AppColors.primarySwatch.shade200),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                    ],
                    // Input row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _emailInputController,
                            focusNode: _emailInputFocusNode,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addEmailChip(),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'member@email.com',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _addEmailChip,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                          ),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_pendingEmails.length} email${_pendingEmails.length == 1 ? '' : 's'} ready',
                          style: TextStyle(
                            fontSize: 13,
                            color: _pendingEmails.isEmpty
                                ? Colors.grey
                                : AppColors.primarySwatch.shade700,
                            fontWeight: _pendingEmails.isEmpty
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isImporting ? null : _importParticipants,
                          icon: _isImporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.upload_file),
                          label: Text(
                            _isImporting ? 'Importing...' : 'Import Emails',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            if (_participants.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Allocated Participants (${_participants.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ..._participants.map((participant) => _buildParticipantCard(participant)),
              const SizedBox(height: 12),
            ],

            // Signups header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Signups (${_signups.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 8),

            if (_signups.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No signups yet',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              )
            else
              ..._signups.map((signup) => _buildSignupCard(signup)),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteParticipant(Map<String, dynamic> participant) async {
    final email = participant['email'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Email'),
        content: Text('Remove "$email" from this promotion?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PromotionCampaignService().deleteParticipantEmail(
        participantId: participant['id'] as String,
      );
      await _loadData();
    } catch (e) {
      _logger.e('Error deleting participant: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to remove email')),
        );
      }
    }
  }

  void _showParticipantEmailsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.mail_outline, color: Colors.indigo),
            const SizedBox(width: 8),
            Text('Participant Emails (${_participants.length})'),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _participants.length,
            itemBuilder: (_, i) {
              final p = _participants[i];
              final isClaimed = p['is_claimed'] == true;
              return ListTile(
                dense: true,
                leading: Icon(
                  isClaimed ? Icons.check_circle : Icons.hourglass_empty,
                  size: 18,
                  color: isClaimed ? Colors.green : Colors.orange,
                ),
                title: Text(
                  p['email'] ?? '',
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isClaimed ? Colors.green : Colors.orange)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isClaimed ? 'CONFIRMED' : 'PENDING',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isClaimed ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantCard(Map<String, dynamic> participant) {
    final isClaimed = participant['is_claimed'] == true;
    final statusColor = isClaimed ? Colors.green : Colors.orange;
    final statusText = isClaimed ? 'CLAIMED' : 'PENDING';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.email, color: statusColor),
        title: Text(participant['email'] ?? ''),
        subtitle: Text(
          isClaimed
              ? 'Claimed: ${_formatDate(participant['claimed_at'] as String?)}'
              : 'Awaiting signup claim',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
            if (!isClaimed) ...
              [
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Remove email',
                  onPressed: () => _deleteParticipant(participant),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildSignupCard(Map<String, dynamic> signup) {
    final status = signup['status'] ?? 'pending';
    final isConfirming = _confirmingIds.contains(signup['id']);

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'confirmed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    signup['user_name'] ?? 'Unknown Member',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (signup['user_email'] != null)
              _buildDetailRow(Icons.email, signup['user_email']),
            if (signup['user_contact'] != null)
              _buildDetailRow(Icons.phone, signup['user_contact']),
            _buildDetailRow(
              Icons.access_time,
              'Signed up: ${_formatDate(signup['created_at'])}',
            ),
            if (signup['confirmed_at'] != null)
              _buildDetailRow(
                Icons.check,
                'Confirmed: ${_formatDate(signup['confirmed_at'])}',
              ),
            if (status == 'pending') ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _cancelSignup(signup),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed:
                        isConfirming ? null : () => _confirmSignup(signup),
                    icon: isConfirming
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(isConfirming ? 'Confirming...' : 'Confirm'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}
