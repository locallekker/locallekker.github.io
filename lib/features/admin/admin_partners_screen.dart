import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/admin_service.dart';
import '../../services/notification_service.dart';
import '../auth/discount_management_page.dart';
import 'admin_add_partner_screen.dart';
import 'admin_edit_partner_screen.dart';
import 'admin_partner_detail_screen.dart';
import 'package:local_lekker/core/theme/app_colors.dart';

enum _PartnerStatus { activated, pending }

class AdminPartnersScreen extends StatefulWidget {
  const AdminPartnersScreen({super.key});

  @override
  State<AdminPartnersScreen> createState() => AdminPartnersScreenState();
}

class AdminPartnersScreenState extends State<AdminPartnersScreen>
    with SingleTickerProviderStateMixin {
  /// Public entry point used by the parent dashboard's AppBar action.
  Future<void> navigateToAddPartner() => _navigateToAddPartner();

  final _logger = Logger();
  final _adminService = AdminService();
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  late TabController _tabController;
  List<Map<String, dynamic>> _activatedPartners = [];
  List<Map<String, dynamic>> _pendingPartners = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // ── Static in-memory cache so data survives tab/screen switches ──
  static List<Map<String, dynamic>>? _cachedActivated;
  static List<Map<String, dynamic>>? _cachedPending;
  static DateTime? _cacheTimestamp;
  static const _cacheMaxAge = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPartners();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Clears the static cache (call after add / delete / deactivate).
  static void invalidateCache() {
    _cachedActivated = null;
    _cachedPending = null;
    _cacheTimestamp = null;
  }

  Future<void> _loadPartners() async {
    // ── Show cached data instantly while refreshing in background ──
    final hasValidCache = _cachedActivated != null &&
        _cachedPending != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < _cacheMaxAge;

    if (hasValidCache) {
      setState(() {
        _activatedPartners = _cachedActivated!;
        _pendingPartners = _cachedPending!;
        _isLoading = false;
      });
      // Still refresh in background for freshness
      _fetchPartners(silent: true);
      return;
    }

    setState(() => _isLoading = true);
    await _fetchPartners(silent: false);
  }

  Future<void> _fetchPartners({required bool silent}) async {
    const maxAttempts = 2;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        // 1) Load all non-deactivated trusted partners in ONE query
        final allTps = await _supabase
            .from('profiles')
            .select('*')
            .eq('role', 'trusted_partner')
            .neq('is_deactivated', true)
            .order('created_at', ascending: false);

        // 2) Batch-fetch business info for ALL partners in ONE query
        final tpIds = allTps
            .map<String>((p) => p['id'] as String)
            .toList();

        final Map<String, Map<String, dynamic>> bizByOwner = {};
        final Map<String, String> tpBizNames = {};
        if (tpIds.isNotEmpty) {
          final results = await Future.wait([
            _supabase
                .from('businesses')
                .select('owner_member_id, name, category, city')
                .inFilter('owner_member_id', tpIds),
            _supabase
                .from('trusted_partners')
                .select('user_id, business_name')
                .inFilter('user_id', tpIds),
          ]);
          for (final biz in results[0] as List) {
            bizByOwner[biz['owner_member_id'] as String] =
                Map<String, dynamic>.from(biz);
          }
          for (final tp in results[1] as List) {
            final bn = tp['business_name']?.toString() ?? '';
            if (bn.isNotEmpty) {
              tpBizNames[tp['user_id'] as String] = bn;
            }
          }
        }

        // 3) Merge & split in-memory (instant, no extra queries)
        final activated = <Map<String, dynamic>>[];
        final pending = <Map<String, dynamic>>[];
        for (final p in allTps) {
          final map = Map<String, dynamic>.from(p);
          final biz = bizByOwner[p['id']];
          if (biz != null) {
            map['business_name'] = biz['name'];
            map['business_category'] = biz['category'];
            map['business_city'] = biz['city'];
          } else if (tpBizNames.containsKey(p['id'])) {
            // Fallback: use business_name from trusted_partners table
            map['business_name'] = tpBizNames[p['id']];
          }
          if (map['partner_terms_accepted'] == true) {
            activated.add(map);
          } else {
            pending.add(map);
          }
        }

        // 4) Update cache
        _cachedActivated = activated;
        _cachedPending = pending;
        _cacheTimestamp = DateTime.now();

        if (!mounted) return;
        setState(() {
          _activatedPartners = activated;
          _pendingPartners = pending;
          _isLoading = false;
        });
        return;
      } catch (e) {
        lastError = e;
        final isTransientNetworkError = e is SocketException ||
            e.toString().contains('SocketException') ||
            e.toString().contains('ClientException') ||
            e.toString().contains('Failed host lookup') ||
            e.toString().contains('connection abort');

        if (!(isTransientNetworkError && attempt < maxAttempts)) {
          break;
        }
        _logger.w('Transient partner fetch failure (attempt $attempt): $e');
      }
    }

    _logger.e('Error loading partners: $lastError');
    if (!mounted) return;
    if (!silent) {
      setState(() => _isLoading = false);
      final isNetworkError = lastError is SocketException ||
          lastError.toString().contains('SocketException') ||
          lastError.toString().contains('ClientException') ||
          lastError.toString().contains('Failed host lookup') ||
          lastError.toString().contains('connection abort');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNetworkError
                ? 'No internet connection. Check your network and try again.'
                : 'Failed to load partners: $lastError',
          ),
        ),
      );
    }
  }

  List<Map<String, dynamic>> _filteredList(List<Map<String, dynamic>> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((m) {
      final name = '${m['name'] ?? ''} ${m['surname'] ?? ''}'.toLowerCase();
      final email = (m['email'] ?? '').toString().toLowerCase();
      final biz = (m['business_name'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q) || biz.contains(q);
    }).toList();
  }

  Future<void> _deactivatePartner(Map<String, dynamic> partner) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Partner'),
        content: Text(
          'Deactivate ${partner['business_name'] ?? partner['name'] ?? 'this partner'}?\n\n'
          'Their deals will be hidden and they won\'t be able to accept payments.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _adminService.deactivateTrustedPartner(partner['id']);
      invalidateCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partner deactivated successfully')),
      );
      _loadPartners();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to deactivate: $e')),
      );
    }
  }

  Future<void> _deletePartner(Map<String, dynamic> partner) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanently Delete Partner'),
        content: Text(
          'WARNING: This will permanently delete all data for '
          '${partner['business_name'] ?? partner['name'] ?? 'this partner'}.\n\n'
          'Receipts will be archived. Deals and business profile will be deleted. '
          'They will need to re-signup with OTP verification.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await _adminService.deleteTrustedPartner(partner['id']);
      if (result['success'] != true) {
        final backendMessage = result['message']?.toString();
        throw Exception(
          backendMessage == null || backendMessage.isEmpty
              ? 'Failed to delete trusted partner.'
              : backendMessage,
        );
      }

      invalidateCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partner deleted successfully')),
      );
      _loadPartners();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  Future<void> _editPartner(Map<String, dynamic> partner) async {
    // Fetch the latest business data for this partner
    Map<String, dynamic>? business;
    try {
      business = await _supabase
          .from('businesses')
          .select()
          .eq('owner_member_id', partner['id'] as String)
          .maybeSingle();
    } catch (_) {}

    if (!mounted) return;
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminEditPartnerScreen(
          partner: partner,
          business: business,
        ),
      ),
    );
    if (updated == true) {
      invalidateCache();
      _loadPartners();
    }
  }

  String _generateRandomKey() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(12, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _issueMemberKey(Map<String, dynamic> partner) async {
    final partnerId = partner['id'] as String;
    final bizName = partner['business_name'] ?? partner['name'] ?? 'this partner';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Issue TP Member Key'),
        content: Text(
          'Issue a single-use member activation key for $bizName?',
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

    try {
      String newKey;
      bool keyExists;
      do {
        newKey = _generateRandomKey();
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

      final adminId = Supabase.instance.client.auth.currentUser?.id;

      await _supabase.from('tp_member_keys').insert({
        'trusted_partner_id': partnerId,
        'key': newKey,
        'created_by': adminId,
      });

      // Notify the TP via in-app notification
      await NotificationService().createNotification(
        userId: partnerId,
        title: 'New Member Activation Key',
        message:
            'A new member activation key has been issued: $newKey. Share it with a member to activate their profile.',
        type: 'new_member_key',
        data: {'member_key': newKey},
      );

      // Send email to TP via edge function
      final tpEmail = partner['email'] ?? '';
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

      if (mounted) {
        await Clipboard.setData(ClipboardData(text: newKey));
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
    }
  }

  Future<void> _navigateToAddPartner() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AdminAddPartnerScreen()),
    );
    if (created == true) {
      invalidateCache();
      _loadPartners();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search partners...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        // Tabs
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(text: 'Activated (${_activatedPartners.length})'),
            Tab(text: 'Pending (${_pendingPartners.length})'),
          ],
        ),
        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPartnerList(
                      _filteredList(_activatedPartners),
                      status: _PartnerStatus.activated,
                    ),
                    _buildPartnerList(
                      _filteredList(_pendingPartners),
                      status: _PartnerStatus.pending,
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildPartnerList(List<Map<String, dynamic>> partners, {required _PartnerStatus status}) {
    final isActivated = status == _PartnerStatus.activated;

    if (partners.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No partners match your search'
                  : isActivated
                      ? 'No activated partners'
                      : 'No pending partners',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            if (!isActivated && _searchQuery.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Partners appear here after admin creates them\nand before they accept Terms & Conditions.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPartners,
      child: ListView.builder(
        padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 80),
        itemCount: partners.length,
        itemBuilder: (context, index) {
          final p = partners[index];
          final name = '${p['name'] ?? 'Unknown'} ${p['surname'] ?? ''}'.trim();
          final email = p['email'] ?? 'No email';
          final bizName = p['business_name'] ?? '';
          final bizCategory = p['business_category'] ?? p['category'] ?? '';
          final bizCity = p['business_city'] ?? p['city'] ?? '';
          final verified = p['verified'] == true;
          final createdAt = p['created_at'] != null
              ? DateTime.tryParse(p['created_at'].toString())
              : null;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminPartnerDetailScreen(partner: p),
                  ),
                );
              },
              child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isActivated ? AppColors.primarySwatch.shade100 : Colors.orange.shade100,
                child: Icon(
                  isActivated ? Icons.store : Icons.hourglass_top,
                  color: isActivated ? AppColors.primarySwatch.shade700 : Colors.orange.shade700,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      bizName.isNotEmpty ? bizName : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (isActivated && verified) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified, color: Colors.blue.shade600, size: 18),
                  ],
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bizName.isNotEmpty)
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!isActivated)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Text(
                            'Awaiting T&Cs',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      if (bizCategory.isNotEmpty)
                        _TagChip(label: bizCategory, color: Colors.purple),
                      if (bizCity.isNotEmpty)
                        _TagChip(label: bizCity, color: Colors.blue),
                      if (createdAt != null)
                        Text(
                          'Since ${_formatDate(createdAt)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                    ],
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.vpn_key, color: Colors.orange, size: 20),
                    tooltip: 'Issue Member Key',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () => _issueMemberKey(p),
                  ),
                  IconButton(
                    icon: const Icon(Icons.local_offer, color: AppColors.primary, size: 20),
                    tooltip: 'Add Deal',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DiscountManagementPage(
                            trustedPartnerId: p['id'] as String,
                            businessName: bizName.isNotEmpty ? bizName : name,
                          ),
                        ),
                      );
                    },
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    onSelected: (action) {
                      switch (action) {
                        case 'edit':
                          _editPartner(p);
                          break;
                        case 'deactivate':
                          _deactivatePartner(p);
                          break;
                        case 'delete':
                          _deletePartner(p);
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit, color: AppColors.primary),
                          title: Text('Edit Partner'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (isActivated)
                        const PopupMenuItem(
                          value: 'deactivate',
                          child: ListTile(
                            leading: Icon(Icons.block, color: Colors.orange),
                            title: Text('Deactivate'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_forever, color: Colors.red),
                          title: Text('Delete Permanently'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  const _TagChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color.shade700, fontWeight: FontWeight.w500),
      ),
    );
  }
}

extension _ColorShade on Color {
  Color get shade700 {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness * 0.6).clamp(0.0, 1.0)).toColor();
  }
}
