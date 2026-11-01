import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../features/business/trusted_partner_analytics_dashboard.dart';
import '../features/business/trusted_partner_customers_page.dart';
import '../features/business/trusted_partner_repeat_customers_page.dart';
import 'package:local_lekker/core/theme/app_colors.dart';

/// Embedded analytics widget for Trusted Partner home page
/// Shows key metrics at a glance with option to view full dashboard
class TrustedPartnerAnalyticsWidget extends StatefulWidget {
  const TrustedPartnerAnalyticsWidget({super.key});

  @override
  State<TrustedPartnerAnalyticsWidget> createState() =>
      _TrustedPartnerAnalyticsWidgetState();
}

class _TrustedPartnerAnalyticsWidgetState
    extends State<TrustedPartnerAnalyticsWidget> {
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) {
        throw Exception('No authenticated user');
      }

      final response = await SupabaseService.instance.client.rpc(
        'get_trusted_partner_analytics',
        params: {'p_user_id': user.id},
      );

      setState(() {
        _analytics = response as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load analytics: $e';
        _isLoading = false;
      });
    }
  }

  String _formatCurrency(dynamic value) {
    final numValue = (value is num) ? value.toDouble() : 0.0;
    return 'R${NumberFormat('#,##0.00').format(numValue)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        margin: EdgeInsets.all(16),
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_errorMessage != null) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadAnalytics,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final overview = _analytics?['overview'] as Map<String, dynamic>?;
    final dealStatus = _analytics?['deal_status'] as Map<String, dynamic>?;
    final paymentMethods =
        _analytics?['payment_methods'] as Map<String, dynamic>?;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.analytics, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Business Analytics',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const TrustedPartnerAnalyticsDashboard(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View Full'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildRevenueSection(overview),
                const Divider(height: 32),
                _buildDealStatusSection(dealStatus),
                const Divider(height: 32),
                _buildPaymentMethodSection(paymentMethods),
                const Divider(height: 32),
                _buildCustomerSection(overview),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueSection(Map<String, dynamic>? overview) {
    if (overview == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Revenue',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4CAF50), Color(0xFF45a049)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Turnover',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  Text(
                    _formatCurrency(overview['total_turnover']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildRevenueChip(
                      '📱 In-App',
                      _formatCurrency(overview['in_app_income']),
                      Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildRevenueChip(
                      '🏪 POS',
                      _formatCurrency(overview['pos_income']),
                      Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildRevenueChip(
                      'This Month',
                      _formatCurrency(overview['monthly_turnover']),
                      Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildRevenueChip(
                      'Today',
                      _formatCurrency(overview['daily_turnover']),
                      Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRevenueChip(String label, String value, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[800])),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[900],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDealStatusSection(Map<String, dynamic>? dealStatus) {
    if (dealStatus == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Deal Requests',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatusCard(
                'Pending',
                '${dealStatus['pending'] ?? 0}',
                Icons.pending,
                Colors.amber,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatusCard(
                'Approved',
                '${dealStatus['approved'] ?? 0}',
                Icons.check_circle_outline,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatusCard(
                'Completed',
                '${dealStatus['completed'] ?? 0}',
                Icons.done_all,
                Colors.green,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard(
    String label,
    String count,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.05),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            count,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSection(Map<String, dynamic>? paymentMethods) {
    if (paymentMethods == null) return const SizedBox.shrink();

    final inApp = paymentMethods['in_app'] as Map<String, dynamic>?;
    final pos = paymentMethods['pos'] as Map<String, dynamic>?;

    final inAppCount = (inApp?['count'] ?? 0) as num;
    final posCount = (pos?['count'] ?? 0) as num;
    final total = inAppCount + posCount;

    final inAppPercent = total > 0 ? (inAppCount / total * 100) : 0.0;
    final posPercent = total > 0 ? (posCount / total * 100) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Methods',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  const Icon(Icons.phone_android, size: 36, color: Colors.blue),
                  const SizedBox(height: 8),
                  const Text(
                    'In-App',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '$inAppCount deals',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    _formatCurrency(inApp?['revenue']),
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${inAppPercent.toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const VerticalDivider(),
            Expanded(
              child: Column(
                children: [
                  const Icon(Icons.store, size: 36, color: Colors.orange),
                  const SizedBox(height: 8),
                  const Text(
                    'POS',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text('$posCount deals', style: const TextStyle(fontSize: 12)),
                  Text(
                    _formatCurrency(pos?['revenue']),
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${posPercent.toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomerSection(Map<String, dynamic>? overview) {
    if (overview == null) return const SizedBox.shrink();

    final totalCustomers = overview['total_customers'] ?? 0;
    final repeatCustomers = overview['repeat_customers'] ?? 0;
    final totalDeals = overview['total_deals_created'] ?? 0;
    final activeDeals = overview['active_deals'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Business Stats',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatTile(
                'Total Deals',
                '$totalDeals',
                Icons.local_offer,
                Colors.blue,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const TrustedPartnerAnalyticsDashboard(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatTile(
                'Active Deals',
                '$activeDeals',
                Icons.check_circle,
                Colors.green,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const TrustedPartnerAnalyticsDashboard(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildStatTile(
                'Customers',
                '$totalCustomers',
                Icons.people,
                Colors.indigo,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TrustedPartnerCustomersPage(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatTile(
                'Repeat',
                '$repeatCustomers',
                Icons.repeat,
                AppColors.primary,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const TrustedPartnerRepeatCustomersPage(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatTile(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(label, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
