import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';
import '../auth/discount_management_page.dart';
import 'admin_edit_partner_screen.dart';
import 'package:local_lekker/core/theme/app_colors.dart';
import '../../core/constants/deal_categories.dart';

class AdminPartnerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> partner;

  const AdminPartnerDetailScreen({super.key, required this.partner});

  @override
  State<AdminPartnerDetailScreen> createState() =>
      _AdminPartnerDetailScreenState();
}

class _AdminPartnerDetailScreenState extends State<AdminPartnerDetailScreen> {
  final _logger = Logger();
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _business;
  Map<String, dynamic>? _bankAccount;
  Map<String, dynamic>? _tpData;
  int _dealCount = 0;
  bool _isLoading = true;
  bool _isGeneratingKey = false;
  bool _isIssuingMemberKey = false;
  List<Map<String, dynamic>> _memberKeys = [];

  Map<String, dynamic> get _p => widget.partner;
  String get _partnerId => _p['id'] as String;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      // Parallel fetch: business, bank account, deal count
      final futures = await Future.wait<dynamic>([
        _supabase
            .from('businesses')
            .select()
            .eq('owner_member_id', _partnerId)
            .maybeSingle(),
        _supabase
            .from('trusted_partner_bank_accounts')
            .select()
            .eq('user_id', _partnerId)
            .maybeSingle(),
        _supabase
            .from('trusted_partner_discounts')
            .select('id')
            .eq('trusted_partner_id', _partnerId),
        _supabase
            .from('trusted_partners')
            .select('unique_key, key_used_by')
            .eq('user_id', _partnerId)
            .maybeSingle(),
        _supabase
            .from('tp_member_keys')
            .select()
            .eq('trusted_partner_id', _partnerId)
            .order('created_at', ascending: false),
      ]);

      if (!mounted) return;
      setState(() {
        _business = futures[0] as Map<String, dynamic>?;
        _bankAccount = futures[1] as Map<String, dynamic>?;
        _dealCount = (futures[2] as List).length;
        _tpData = futures[3] as Map<String, dynamic>?;
        _memberKeys = (futures[4] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      _logger.e('Error loading partner details: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String _generateRandomKey() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(12, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _generateNewKey() async {
    // Confirm with admin
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate New Key'),
        content: const Text(
          'This will replace the current promo key and notify the trusted partner via email. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isGeneratingKey = true);
    try {
      // Generate a new unique key
      String newKey;
      bool keyExists;
      do {
        newKey = _generateRandomKey();
        final check = await _supabase
            .from('trusted_partners')
            .select('user_id')
            .eq('unique_key', newKey)
            .maybeSingle();
        keyExists = check != null;
      } while (keyExists);

      // Update TP record: new key, reset key_used_by
      await _supabase
          .from('trusted_partners')
          .update({
            'unique_key': newKey,
            'key_used_by': null,
          })
          .eq('user_id', _partnerId);

      // Notify the TP via in-app notification
      await NotificationService().createNotification(
        userId: _partnerId,
        title: 'New Promo Key Generated',
        message: 'Your new promo key is: $newKey. Check your business profile.',
        type: 'new_key',
        data: {'new_key': newKey},
      );

      // Send email to TP via edge function
      final tpEmail = _p['email'] ?? '';
      final bizName = _business?['name'] ?? _p['business_name'] ?? '';
      try {
        await _supabase.functions.invoke(
          'send-new-key-email',
          body: {
            'email': tpEmail,
            'business_name': bizName,
            'new_key': newKey,
          },
        );
      } catch (e) {
        _logger.w('Edge function email failed (non-blocking): $e');
      }

      // Reload details to reflect new key
      await _loadDetails();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New key generated: $newKey'),
            backgroundColor: Colors.green,
          ),
        );
        // Copy to clipboard for convenience
        Clipboard.setData(ClipboardData(text: newKey));
      }
    } catch (e) {
      _logger.e('Failed to generate new key: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate key: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingKey = false);
    }
  }

  Future<void> _issueMemberKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Issue TP Member Key'),
        content: const Text(
          'This will generate a single-use key that allows this trusted partner to activate a member profile. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Issue Key'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isIssuingMemberKey = true);
    try {
      // Generate a unique key
      String newKey;
      bool keyExists;
      do {
        newKey = _generateRandomKey();
        // Check against both tables
        final checks = await Future.wait([
          _supabase
              .from('trusted_partners')
              .select('user_id')
              .eq('unique_key', newKey)
              .maybeSingle()
              .catchError((_) => null),
          _supabase
              .from('tp_member_keys')
              .select('id')
              .eq('key', newKey)
              .maybeSingle()
              .catchError((_) => null),
        ]);
        keyExists = checks[0] != null || checks[1] != null;
      } while (keyExists);

      // Get current admin user id
      final adminId = Supabase.instance.client.auth.currentUser?.id;

      // Insert into tp_member_keys
      await _supabase.from('tp_member_keys').insert({
        'trusted_partner_id': _partnerId,
        'key': newKey,
        'created_by': adminId,
      });

      // Notify the TP via in-app notification
      await NotificationService().createNotification(
        userId: _partnerId,
        title: 'New Member Activation Key',
        message:
            'A new member activation key has been issued: $newKey. Share it with a member to activate their profile.',
        type: 'new_member_key',
        data: {'member_key': newKey},
      );

      // Send email to TP via edge function
      final tpEmail = _p['email'] ?? '';
      final bizName = _business?['name'] ?? _p['business_name'] ?? '';
      try {
        await _supabase.functions.invoke(
          'send-new-key-email',
          body: {
            'email': tpEmail,
            'business_name': bizName,
            'new_key': newKey,
          },
        );
      } catch (e) {
        _logger.w('Edge function email failed (non-blocking): $e');
      }

      await _loadDetails();

      if (mounted) {
        Clipboard.setData(ClipboardData(text: newKey));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Member key issued: $newKey (copied)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _logger.e('Failed to issue member key: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to issue key: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isIssuingMemberKey = false);
    }
  }

  void _openDealManagement() {
    final lockedDealCategory = _business?['sells_fresh_produce'] == true
        ? kFreshLocalCategory
        : _business?['sells_alcohol'] == true
        ? kLocalSipsCategory
        : _business?['offers_sports_activities'] == true
        ? kLocallyActiveCategory
        : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiscountManagementPage(
          trustedPartnerId: _partnerId,
          businessName: _business?['name'] ??
              _p['business_name'] ??
              '${_p['name'] ?? ''} ${_p['surname'] ?? ''}'.trim(),
            lockedDealCategory: lockedDealCategory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = '${_p['name'] ?? ''} ${_p['surname'] ?? ''}'.trim();
    final bizName =
        _p['business_name'] ?? _business?['name'] ?? 'No business';
    final email = _p['email'] ?? 'No email';
    final verified = _p['verified'] == true;
    final termsAccepted = _p['partner_terms_accepted'] == true;
    final createdAt = _p['created_at'] != null
        ? DateTime.tryParse(_p['created_at'].toString())
        : null;

    return Scaffold(
      appBar: BrandedAppBar(
        title: Text(bizName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Partner',
            onPressed: () async {
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminEditPartnerScreen(
                    partner: _p,
                    business: _business,
                  ),
                ),
              );
              if (updated == true) {
                _loadDetails();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.local_offer),
            tooltip: 'Manage Deals',
            onPressed: _openDealManagement,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDetails,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Header card ──
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: termsAccepted
                                ? AppColors.primarySwatch.shade100
                                : Colors.orange.shade100,
                            backgroundImage: _business?['logo_url'] != null
                                ? NetworkImage(
                                    _business!['logo_url'] as String)
                                : null,
                            child: _business?['logo_url'] == null
                                ? Icon(Icons.store,
                                    size: 40,
                                    color: termsAccepted
                                        ? AppColors.primarySwatch.shade700
                                        : Colors.orange.shade700)
                                : null,
                          ),
                          const SizedBox(height: 12),
                          Text(bizName,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          if (name.isNotEmpty && name != bizName)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(name,
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14)),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _StatusChip(
                                label: termsAccepted
                                    ? 'Activated'
                                    : 'Pending T&Cs',
                                color: termsAccepted
                                    ? AppColors.primary
                                    : Colors.orange,
                              ),
                              if (verified) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.verified,
                                    color: Colors.blue.shade600, size: 20),
                                const SizedBox(width: 4),
                                Text('Verified',
                                    style: TextStyle(
                                        color: Colors.blue.shade600,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Contact info ──
                  _SectionCard(
                    title: 'Contact',
                    children: [
                      _DetailRow(
                          icon: Icons.email_outlined, label: 'Email', value: email),
                      if (_p['phone'] != null)
                        _DetailRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone',
                            value: _p['phone']),
                      if (_business?['contact_number'] != null)
                        _DetailRow(
                            icon: Icons.phone,
                            label: 'Business Phone',
                            value: _business!['contact_number']),
                      if (_business?['contact_email'] != null)
                        _DetailRow(
                            icon: Icons.alternate_email,
                            label: 'Business Email',
                            value: _business!['contact_email']),
                      if (_business?['address'] != null)
                        _DetailRow(
                            icon: Icons.location_on_outlined,
                            label: 'Address',
                            value: _business!['address']),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Business info ──
                  _SectionCard(
                    title: 'Business',
                    children: [
                      if (_business?['category'] != null)
                        _DetailRow(
                            icon: Icons.category_outlined,
                            label: 'Category',
                            value: _business!['category']),
                      if (_business?['city'] != null)
                        _DetailRow(
                            icon: Icons.location_city,
                            label: 'City',
                            value: _business!['city']),
                      _DetailRow(
                          icon: Icons.local_offer_outlined,
                          label: 'Active Deals',
                          value: '$_dealCount'),
                      if (createdAt != null)
                        _DetailRow(
                            icon: Icons.calendar_today_outlined,
                            label: 'Joined',
                            value:
                                '${createdAt.day}/${createdAt.month}/${createdAt.year}'),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Social ──
                  if (_business?['facebook_handle'] != null ||
                      _business?['instagram_handle'] != null ||
                      _business?['website_url'] != null)
                    _SectionCard(
                      title: 'Social',
                      children: [
                        if (_business?['facebook_handle'] != null)
                          _DetailRow(
                              icon: Icons.facebook,
                              label: 'Facebook',
                              value: _business!['facebook_handle']),
                        if (_business?['instagram_handle'] != null)
                          _DetailRow(
                              icon: Icons.camera_alt_outlined,
                              label: 'Instagram',
                              value: _business!['instagram_handle']),
                        if (_business?['website_url'] != null)
                          _DetailRow(
                              icon: Icons.language,
                              label: 'Website',
                              value: _business!['website_url']),
                      ],
                    ),
                  if (_business?['facebook_handle'] != null ||
                      _business?['instagram_handle'] != null ||
                      _business?['website_url'] != null)
                    const SizedBox(height: 12),

                  // ── Banking ──
                  _SectionCard(
                    title: 'Banking',
                    children: _bankAccount != null
                        ? [
                            _DetailRow(
                                icon: Icons.account_balance,
                                label: 'Bank',
                                value: _bankAccount!['bank_name'] ?? 'N/A'),
                            _DetailRow(
                                icon: Icons.numbers,
                                label: 'Account',
                                value:
                                    _bankAccount!['account_number'] ?? 'N/A'),
                            _DetailRow(
                                icon: Icons.person_outline,
                                label: 'Holder',
                                value:
                                    _bankAccount!['account_holder'] ?? 'N/A'),
                          ]
                        : [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Text('No bank account set up',
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontStyle: FontStyle.italic)),
                            ),
                          ],
                  ),
                  const SizedBox(height: 24),

                  // ── Promo Key section ──
                  if (_tpData?['unique_key'] != null)
                    _SectionCard(
                      title: 'Promo Key',
                      children: [
                        _DetailRow(
                            icon: Icons.vpn_key,
                            label: 'Current Key',
                            value: _tpData!['unique_key'] ?? 'N/A'),
                        _DetailRow(
                            icon: Icons.info_outline,
                            label: 'Status',
                            value: _tpData!['key_used_by'] != null
                                ? 'Used'
                                : 'Available'),
                      ],
                    ),
                  if (_tpData?['unique_key'] != null)
                    const SizedBox(height: 12),

                  // ── Generate New Key button ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isGeneratingKey ? null : _generateNewKey,
                      icon: _isGeneratingKey
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.vpn_key),
                      label: Text(_isGeneratingKey
                          ? 'Generating...'
                          : 'Generate New Key'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Issue TP Member Key button ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isIssuingMemberKey ? null : _issueMemberKey,
                      icon: _isIssuingMemberKey
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.vpn_key),
                      label: Text(_isIssuingMemberKey
                          ? 'Issuing...'
                          : 'Issue TP Member Key'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Issued Member Keys list ──
                  if (_memberKeys.isNotEmpty)
                    _SectionCard(
                      title: 'Issued Member Keys (${_memberKeys.length})',
                      children: _memberKeys.map((k) {
                        final isUsed = k['used_by'] != null;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                isUsed ? Icons.check_circle : Icons.vpn_key,
                                size: 18,
                                color: isUsed ? Colors.grey : Colors.deepPurple,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  k['key'] ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    color: isUsed
                                        ? Colors.grey
                                        : Colors.black87,
                                    decoration: isUsed
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isUsed
                                      ? Colors.grey.shade100
                                      : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isUsed ? 'Used' : 'Available',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isUsed
                                        ? Colors.grey.shade600
                                        : Colors.green.shade700,
                                  ),
                                ),
                              ),
                              if (!isUsed)
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 16),
                                  tooltip: 'Copy key',
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: k['key']));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Key copied'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  if (_memberKeys.isNotEmpty) const SizedBox(height: 12),

                  // ── Manage deals button ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openDealManagement,
                      icon: const Icon(Icons.local_offer),
                      label: Text('Manage Deals ($_dealCount)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}

// ── Helper widgets ──

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700)),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
