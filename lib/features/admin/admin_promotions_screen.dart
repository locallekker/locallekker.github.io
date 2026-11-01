import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../../services/supabase_service.dart';
import 'admin_create_promotion_screen.dart';
import 'admin_promotion_detail_screen.dart';

class AdminPromotionsScreen extends StatefulWidget {
  const AdminPromotionsScreen({super.key});

  @override
  State<AdminPromotionsScreen> createState() => _AdminPromotionsScreenState();
}

class _AdminPromotionsScreenState extends State<AdminPromotionsScreen> {
  final Logger _logger = Logger();
  List<Map<String, dynamic>> _promotions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPromotions();
  }

  Future<void> _loadPromotions() async {
    setState(() => _isLoading = true);
    try {
      final response = await SupabaseService.instance.client
          .from('promotions')
          .select('*, promotion_signups(count)')
          .order('created_at', ascending: false);

      setState(() {
        _promotions = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      _logger.e('Error loading promotions: $e');
      setState(() => _isLoading = false);
    }
  }

  bool _isExpired(Map<String, dynamic> promo) {
    final endsAt = promo['ends_at'];
    if (endsAt == null) return false;
    return DateTime.parse(endsAt).isBefore(DateTime.now());
  }

  int _getSignupCount(Map<String, dynamic> promo) {
    final signups = promo['promotion_signups'];
    if (signups is List && signups.isNotEmpty) {
      return signups.first['count'] ?? 0;
    }
    return 0;
  }

  Future<void> _toggleActive(Map<String, dynamic> promo) async {
    try {
      final newActive = !(promo['is_active'] ?? true);
      await SupabaseService.instance.client
          .from('promotions')
          .update({'is_active': newActive})
          .eq('id', promo['id']);
      _loadPromotions();
    } catch (e) {
      _logger.e('Error toggling promotion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _deletePromotion(Map<String, dynamic> promo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Promotion'),
        content: Text('Delete "${promo['name']}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SupabaseService.instance.client
          .from('promotions')
          .delete()
          .eq('id', promo['id']);
      _loadPromotions();
    } catch (e) {
      _logger.e('Error deleting promotion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_promotions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No promotions yet',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first promotion to get started',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminCreatePromotionScreen(),
                  ),
                );
                if (result == true) _loadPromotions();
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Promotion'),
            ),
          ],
        ),
      );
    }

    // Sort: active first, then by created_at desc
    final sorted = List<Map<String, dynamic>>.from(_promotions);
    sorted.sort((a, b) {
      final aActive = (a['is_active'] ?? false) && !_isExpired(a);
      final bActive = (b['is_active'] ?? false) && !_isExpired(b);
      if (aActive != bActive) return aActive ? -1 : 1;
      return (b['created_at'] ?? '').compareTo(a['created_at'] ?? '');
    });

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadPromotions,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80, top: 8, left: 8, right: 8),
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final promo = sorted[index];
              return _buildPromoCard(promo);
            },
          ),
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminCreatePromotionScreen(),
                ),
              );
              if (result == true) _loadPromotions();
            },
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _buildPromoCard(Map<String, dynamic> promo) {
    final isActive = promo['is_active'] ?? false;
    final expired = _isExpired(promo);
    final signupCount = _getSignupCount(promo);
    final freeMonths = promo['free_months'];
    final durationText = freeMonths != null ? '$freeMonths month(s) free' : 'Lifetime';
    final imageUrl = promo['image_url'] as String?;

    String statusText;
    Color statusColor;
    if (expired) {
      statusText = 'Expired';
      statusColor = Colors.red;
    } else if (isActive) {
      statusText = 'Active';
      statusColor = Colors.green;
    } else {
      statusText = 'Inactive';
      statusColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminPromotionDetailScreen(
                promotionId: promo['id'],
              ),
            ),
          );
          if (result == true) _loadPromotions();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 80,
                  color: Colors.grey.shade200,
                  child: const Center(child: Icon(Icons.broken_image, size: 32)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          promo['name'] ?? 'Untitled',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor.withOpacity(0.5)),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.card_giftcard, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(durationText, style: TextStyle(color: Colors.grey.shade600)),
                      const Spacer(),
                      Icon(Icons.people, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text('$signupCount signups', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                  if (promo['ends_at'] != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          'Ends: ${_formatDate(promo['ends_at'])}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _toggleActive(promo),
                    icon: Icon(
                      isActive ? Icons.pause : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(isActive ? 'Deactivate' : 'Activate'),
                    style: TextButton.styleFrom(
                      foregroundColor: isActive ? Colors.orange : Colors.green,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _deletePromotion(promo),
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'No end date';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}
