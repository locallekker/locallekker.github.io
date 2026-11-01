import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/admin_service.dart';
import 'package:local_lekker/core/theme/app_colors.dart';
import '../../widgets/profile_photo.dart';

enum _MemberTab { active, pending, deactivated }

class AdminMembersScreen extends StatefulWidget {
  const AdminMembersScreen({super.key});

  @override
  State<AdminMembersScreen> createState() => _AdminMembersScreenState();
}

class _AdminMembersScreenState extends State<AdminMembersScreen>
    with SingleTickerProviderStateMixin {
  final _logger = Logger();
  final _adminService = AdminService();
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  late TabController _tabController;
  List<Map<String, dynamic>> _activeMembers = [];
  List<Map<String, dynamic>> _pendingMembers = [];
  List<Map<String, dynamic>> _deactivatedMembers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMembers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    try {
      final allNonDeactivated = await _supabase
          .from('profiles')
          .select('*')
          .eq('role', 'member')
          .or('is_deactivated.is.null,is_deactivated.eq.false')
          .order('created_at', ascending: false);

      final deactivated = await _adminService.getDeactivatedMembers();
      final contactStatusRows = await _supabase.rpc(
        'get_admin_member_signup_contact_statuses',
      );
      final contactStatuses = <String, Map<String, dynamic>>{
        for (final row in contactStatusRows as List)
          row['user_id'].toString(): Map<String, dynamic>.from(row as Map),
      };

      // Split non-deactivated members by subscription status
      final active = <Map<String, dynamic>>[];
      final pending = <Map<String, dynamic>>[];
      for (final m in allNonDeactivated) {
        final member = Map<String, dynamic>.from(m);
        final contactStatus = contactStatuses[member['id'].toString()];
        if (contactStatus != null) {
          member['signup_reminder_status'] = contactStatus;
        }
        final sub = (m['subscription'] ?? '').toString().toLowerCase();
        if (sub == 'active') {
          active.add(member);
        } else {
          pending.add(member);
        }
      }

      if (!mounted) return;
      setState(() {
        _activeMembers = active;
        _pendingMembers = pending;
        _deactivatedMembers = deactivated;
        _isLoading = false;
      });
    } catch (e) {
      _logger.e('Error loading members: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load members: $e')),
      );
    }
  }

  List<Map<String, dynamic>> _filteredList(List<Map<String, dynamic>> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((m) {
      final name = '${m['name'] ?? ''} ${m['surname'] ?? ''}'.toLowerCase();
      final email = (m['email'] ?? '').toString().toLowerCase();
      final phone = (m['contact'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q) || phone.contains(q);
    }).toList();
  }

  Future<void> _deactivateMember(Map<String, dynamic> member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Member'),
        content: Text(
          'Deactivate ${member['name'] ?? ''} ${member['surname'] ?? ''}?\n\n'
          'This will cancel their subscription, disable QR codes, and hide them from the platform.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _adminService.deactivateMember(member['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member deactivated successfully')),
      );
      _loadMembers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to deactivate: $e')),
      );
    }
  }

  Future<void> _reactivateMember(Map<String, dynamic> member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reactivate Member'),
        content: Text(
          'Reactivate ${member['name'] ?? ''} ${member['surname'] ?? ''}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _adminService.reactivateMember(member['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member reactivated successfully')),
      );
      _loadMembers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reactivate: $e')),
      );
    }
  }

  Future<void> _emailMember(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app is available')),
      );
    }
  }

  Future<void> _copyMemberPhone(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Phone number copied')),
    );
  }

  Future<void> _deleteMember(Map<String, dynamic> member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanently Delete Member'),
        content: Text(
          'WARNING: This will permanently delete ALL data for '
          '${member['name'] ?? ''} ${member['surname'] ?? ''} including their '
          'profile, subscriptions, QR codes, payments, and auth account.\n\n'
          'This action cannot be undone. They will need to re-signup to return.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Show a non-dismissible progress dialog so the admin can see something
    // is happening. The full delete chain (Paystack cancel + RPC + auth
    // Edge Function with retries) can take 30+ seconds.
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Deleting member…')),
          ],
        ),
      ),
    );

    void closeProgress() {
      if (!mounted) return;
      // Pop only the progress dialog, not the underlying screen.
      Navigator.of(context, rootNavigator: true).pop();
    }

    try {
      await _adminService
          .deleteMember(member['id'])
          .timeout(const Duration(minutes: 2));
      closeProgress();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Member completely deleted (data + auth account)'),
          backgroundColor: Colors.green,
        ),
      );
      _loadMembers();
    } catch (e) {
      closeProgress();
      if (!mounted) return;
      final errorMsg = e.toString();
      // A TimeoutException means the operation exceeded the 2-minute budget.
      // The DB data is almost certainly deleted by then; only the auth account
      // deletion (Edge Function) may be incomplete.
      final isTimeout = e is TimeoutException ||
          errorMsg.contains('TimeoutException') ||
          errorMsg.contains('Future not completed');
      final isPartialDelete = isTimeout ||
          errorMsg.contains('auth account removal failed') ||
          errorMsg.contains('Failed to delete auth user');

      if (isPartialDelete) {
        // Data deleted but auth remains - offer retry
        final retryConfirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Auth Deletion Failed'),
            content: const Text(
              'Member data was deleted but the auth account could not be removed '
              '(server timeout). The member may still be able to log in.\n\n'
              'Would you like to retry deleting the auth account?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Retry Delete Auth'),
              ),
            ],
          ),
        );
        if (retryConfirmed == true && mounted) {
          try {
            await _adminService.retryDeleteAuthUser(member['id']);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Auth account deleted successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          } catch (retryError) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Auth deletion still failing: $retryError'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 8),
              ),
            );
          }
        }
        _loadMembers();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
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
              hintText: 'Search members...',
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
            Tab(text: 'Active (${_activeMembers.length})'),
            Tab(text: 'Pending (${_pendingMembers.length})'),
            Tab(text: 'Deactivated (${_deactivatedMembers.length})'),
          ],
        ),
        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMemberList(_filteredList(_activeMembers), status: _MemberTab.active),
                    _buildMemberList(_filteredList(_pendingMembers), status: _MemberTab.pending),
                    _buildMemberList(_filteredList(_deactivatedMembers), status: _MemberTab.deactivated),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildMemberList(List<Map<String, dynamic>> members, {required _MemberTab status}) {
    final isActive = status == _MemberTab.active;
    final isDeactivated = status == _MemberTab.deactivated;

    if (members.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No members match your search'
                  : isActive
                      ? 'No active members'
                      : isDeactivated
                          ? 'No deactivated members'
                          : 'No pending members',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMembers,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: members.length,
        itemBuilder: (context, index) {
          final m = members[index];
          final name = '${m['name'] ?? 'Unknown'} ${m['surname'] ?? ''}'.trim();
          final email = (m['email'] ?? '').toString().trim();
          final phone = (m['contact'] ?? '').toString().trim();
          final city = m['city'] ?? '';
            final reminderStatus =
              m['signup_reminder_status'] as Map<String, dynamic>?;
            final optedOutAt = reminderStatus?['opted_out_at'] != null
              ? DateTime.tryParse(reminderStatus!['opted_out_at'].toString())
              : null;
            final openedAt = reminderStatus?['opened_at'] != null
              ? DateTime.tryParse(reminderStatus!['opened_at'].toString())
              : null;
            final reminderSentAt = reminderStatus?['reminder_sent_at'] != null
              ? DateTime.tryParse(
                reminderStatus!['reminder_sent_at'].toString(),
              )
              : null;
            final openCount = (reminderStatus?['open_count'] as num?)?.toInt() ?? 0;
          // Show the right status label per tab
          final String statusLabel;
          final Color statusColor;
          if (isDeactivated) {
            statusLabel = 'deactivated';
            statusColor = Colors.red;
          } else {
            final sub = (m['subscription'] ?? 'unknown').toString().toLowerCase();
            statusLabel = sub;
            statusColor = sub == 'active' ? Colors.green : Colors.orange;
          }
          final createdAt = m['created_at'] != null
              ? DateTime.tryParse(m['created_at'].toString())
              : null;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: ProfilePhoto(
                imageUrl: m['profile_photo_url'] as String?,
                displayName: name,
                size: 40,
                backgroundColor: isDeactivated
                    ? Colors.grey.shade300
                    : isActive
                        ? AppColors.primarySwatch.shade100
                        : Colors.orange.shade100,
                foregroundColor: isDeactivated
                    ? Colors.grey.shade600
                    : isActive
                        ? AppColors.primarySwatch.shade700
                        : Colors.orange.shade700,
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (status == _MemberTab.pending)
                    Text(
                      'Stopped after email verification, before subscription payment',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (email.isNotEmpty)
                    InkWell(
                      onTap: optedOutAt == null ? () => _emailMember(email) : null,
                      child: SizedBox(
                        width: double.infinity,
                        child: Row(
                          children: [
                            Icon(
                              optedOutAt == null
                                ? Icons.email_outlined
                                : Icons.unsubscribe_outlined,
                              size: 15,
                              color: optedOutAt == null
                                ? Colors.blue.shade700
                                : Colors.red.shade700,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                email,
                                style: TextStyle(
                                    color: optedOutAt == null
                                      ? Colors.blue.shade700
                                      : Colors.red.shade700,
                                  fontSize: 13,
                                    decoration: optedOutAt == null
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      'No email',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  if (phone.isNotEmpty)
                    InkWell(
                      onTap: () => _copyMemberPhone(phone),
                      child: SizedBox(
                        width: double.infinity,
                        child: Row(
                          children: [
                            Icon(Icons.phone_outlined, size: 15, color: Colors.blue.shade700),
                            const SizedBox(width: 5),
                            Text(
                              phone,
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Icon(Icons.copy, size: 13, color: Colors.grey.shade600),
                          ],
                        ),
                      ),
                    ),
                  if (city.isNotEmpty)
                    Text(city, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  if (status == _MemberTab.pending && optedOutAt != null)
                    _ContactStatusRow(
                      icon: Icons.do_not_disturb_alt_outlined,
                      text:
                          'Opted out ${_formatDateTime(optedOutAt)} - do not contact',
                      color: Colors.red.shade700,
                    )
                  else if (status == _MemberTab.pending && openedAt != null)
                    _ContactStatusRow(
                      icon: Icons.open_in_new,
                      text:
                          'Opened reminder link ${_formatDateTime(openedAt)} ($openCount ${openCount == 1 ? 'time' : 'times'}); subscription still pending',
                      color: Colors.blue.shade700,
                    )
                  else if (status == _MemberTab.pending && reminderSentAt != null)
                    _ContactStatusRow(
                      icon: Icons.mark_email_read_outlined,
                      text: 'Reminder sent ${_formatDateTime(reminderSentAt)}',
                      color: Colors.teal.shade700,
                    ),
                  Row(
                    children: [
                      _StatusChip(
                        label: statusLabel,
                        color: statusColor,
                      ),
                      if (createdAt != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Joined ${_formatDate(createdAt)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  switch (action) {
                    case 'deactivate':
                      _deactivateMember(m);
                      break;
                    case 'reactivate':
                      _reactivateMember(m);
                      break;
                    case 'delete':
                      _deleteMember(m);
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  if (!isDeactivated)
                    const PopupMenuItem(
                      value: 'deactivate',
                      child: ListTile(
                        leading: Icon(Icons.block, color: Colors.orange),
                        title: Text('Deactivate'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (isDeactivated)
                    const PopupMenuItem(
                      value: 'reactivate',
                      child: ListTile(
                        leading: Icon(Icons.check_circle, color: AppColors.primary),
                        title: Text('Reactivate'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_forever, color: Colors.red),
                      title: Text('Delete'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
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

  String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${_formatDate(local)} $hour:$minute';
  }
}

class _ContactStatusRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _ContactStatusRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
