import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/supabase_service.dart';
import '../../widgets/branded_app_bar.dart';

class TrustedPartnerAnalyticsDashboard extends StatefulWidget {
  const TrustedPartnerAnalyticsDashboard({super.key});

  @override
  State<TrustedPartnerAnalyticsDashboard> createState() =>
      _TrustedPartnerAnalyticsDashboardState();
}

class _TrustedPartnerAnalyticsDashboardState
    extends State<TrustedPartnerAnalyticsDashboard> {
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
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Business Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalytics,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadAnalytics,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _buildDashboard(),
    );
  }

  Widget _buildDashboard() {
    final overview = _analytics?['overview'] as Map<String, dynamic>?;
    final dealStatus = _analytics?['deal_status'] as Map<String, dynamic>?;
    final paymentMethods =
        _analytics?['payment_methods'] as Map<String, dynamic>?;
    final topDeals = _analytics?['top_deals'] as List<dynamic>?;
    final recentTransactions =
        _analytics?['recent_transactions'] as List<dynamic>?;
    final monthlyTrends = _analytics?['monthly_trends'] as List<dynamic>?;

    return RefreshIndicator(
      onRefresh: _loadAnalytics,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Key Metrics Overview
            _buildOverviewSection(overview),
            const SizedBox(height: 24),

            // Revenue Breakdown
            _buildRevenueBreakdownSection(overview),
            const SizedBox(height: 24),

            // Payment Method Stats
            _buildPaymentMethodSection(paymentMethods),
            const SizedBox(height: 24),

            // Deal Status Overview
            _buildDealStatusSection(dealStatus),
            const SizedBox(height: 24),

            // Customer Insights
            _buildCustomerInsightsSection(overview),
            const SizedBox(height: 24),

            // Monthly Trends Chart
            if (monthlyTrends != null && monthlyTrends.isNotEmpty)
              _buildMonthlyTrendsSection(monthlyTrends),
            const SizedBox(height: 24),

            // Top Performing Deals
            if (topDeals != null && topDeals.isNotEmpty)
              _buildTopDealsSection(topDeals),
            const SizedBox(height: 24),

            // Recent Transactions
            if (recentTransactions != null && recentTransactions.isNotEmpty)
              _buildRecentTransactionsSection(recentTransactions),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection(Map<String, dynamic>? overview) {
    if (overview == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Deals Created',
                '${overview['total_deals_created'] ?? 0}',
                Icons.local_offer,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Active Deals',
                '${overview['active_deals'] ?? 0}',
                Icons.check_circle,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Completed Deals',
                '${overview['completion_rate']?.toStringAsFixed(1) ?? '0.0'}%',
                Icons.done_all,
                Colors.purple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Avg Deal Value',
                _formatCurrency(overview['avg_deal_value']),
                Icons.attach_money,
                Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRevenueBreakdownSection(Map<String, dynamic>? overview) {
    if (overview == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Revenue',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildRevenueRow(
                  'Total Turnover',
                  _formatCurrency(overview['total_turnover']),
                  Colors.green,
                  isBold: true,
                ),
                const Divider(),
                _buildRevenueRow(
                  'In-App Income',
                  _formatCurrency(overview['in_app_income']),
                  Colors.blue,
                ),
                const SizedBox(height: 8),
                _buildRevenueRow(
                  'POS Income',
                  _formatCurrency(overview['pos_income']),
                  Colors.orange,
                ),
                const Divider(),
                _buildRevenueRow(
                  'This Month',
                  _formatCurrency(overview['monthly_turnover']),
                  Colors.purple,
                ),
                const SizedBox(height: 8),
                _buildRevenueRow(
                  'Last 7 Days',
                  _formatCurrency(overview['weekly_turnover']),
                  Colors.teal,
                ),
                const SizedBox(height: 8),
                _buildRevenueRow(
                  'Today',
                  _formatCurrency(overview['daily_turnover']),
                  Colors.amber,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRevenueRow(
    String label,
    String value,
    Color color, {
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 18 : 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodSection(Map<String, dynamic>? paymentMethods) {
    if (paymentMethods == null) return const SizedBox.shrink();

    final inApp = paymentMethods['in_app'] as Map<String, dynamic>?;
    final pos = paymentMethods['pos'] as Map<String, dynamic>?;

    final inAppCount = (inApp?['count'] ?? 0) as num;
    final posCount = (pos?['count'] ?? 0) as num;
    final total = inAppCount + posCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Methods',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Icon(Icons.phone_android, size: 48, color: Colors.blue),
                      const SizedBox(height: 8),
                      const Text(
                        'In-App',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('$inAppCount deals'),
                      Text(
                        _formatCurrency(inApp?['revenue']),
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (total > 0)
                        Text(
                          '${((inAppCount / total) * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(),
                Expanded(
                  child: Column(
                    children: [
                      Icon(Icons.store, size: 48, color: Colors.orange),
                      const SizedBox(height: 8),
                      const Text(
                        'POS',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('$posCount deals'),
                      Text(
                        _formatCurrency(pos?['revenue']),
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (total > 0)
                        Text(
                          '${((posCount / total) * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDealStatusSection(Map<String, dynamic>? dealStatus) {
    if (dealStatus == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Deal Requests',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Pending',
                '${dealStatus['pending'] ?? 0}',
                Icons.pending,
                Colors.amber,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                'Approved',
                '${dealStatus['approved'] ?? 0}',
                Icons.check_circle_outline,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                'Completed',
                '${dealStatus['completed'] ?? 0}',
                Icons.done_all,
                Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                'Rejected',
                '${dealStatus['rejected'] ?? 0}',
                Icons.cancel,
                Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomerInsightsSection(Map<String, dynamic>? overview) {
    if (overview == null) return const SizedBox.shrink();

    final totalCustomers = overview['total_customers'] ?? 0;
    final repeatCustomers = overview['repeat_customers'] ?? 0;
    final repeatRate = totalCustomers > 0
        ? (repeatCustomers / totalCustomers * 100)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer Insights',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Customers',
                '$totalCustomers',
                Icons.people,
                Colors.indigo,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Repeat Customers',
                '$repeatCustomers (${repeatRate.toStringAsFixed(1)}%)',
                Icons.repeat,
                Colors.teal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyTrendsSection(List<dynamic> monthlyTrends) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Monthly Revenue Trend',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(height: 250, child: _buildLineChart(monthlyTrends)),
          ),
        ),
      ],
    );
  }

  Widget _buildLineChart(List<dynamic> monthlyTrends) {
    if (monthlyTrends.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    // Reverse to show oldest to newest (left to right)
    final reversedTrends = monthlyTrends.reversed.toList();

    final spots = reversedTrends.asMap().entries.map((entry) {
      final revenue = (entry.value['revenue'] ?? 0) as num;
      return FlSpot(entry.key.toDouble(), revenue.toDouble());
    }).toList();

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Text(
                  'R${NumberFormat.compact().format(value)}',
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 &&
                    value.toInt() < reversedTrends.length) {
                  final month = reversedTrends[value.toInt()]['month'] ?? '';
                  // Show only first 3 characters of month
                  return Text(
                    month.toString().split(' ').first.substring(0, 3),
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const Text('');
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: true),
        minY: 0,
        maxY: maxY > 0 ? maxY : 100,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.green,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopDealsSection(List<dynamic> topDeals) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top Performing Deals',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: topDeals.length > 5 ? 5 : topDeals.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final deal = topDeals[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Text('${index + 1}'),
                ),
                title: Text(
                  deal['deal_name'] ?? 'Unknown Deal',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text('${deal['completions']} completions'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatCurrency(deal['total_revenue']),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    Text(
                      'Avg: ${_formatCurrency(deal['avg_value'])}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTransactionsSection(List<dynamic> recentTransactions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Transactions',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentTransactions.length > 10
                ? 10
                : recentTransactions.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final transaction = recentTransactions[index];
              final paymentMethod = transaction['payment_method'] ?? 'unknown';
              final status = transaction['status'] ?? 'unknown';

              return ListTile(
                leading: Icon(
                  paymentMethod == 'in_app' ? Icons.phone_android : Icons.store,
                  color: paymentMethod == 'in_app'
                      ? Colors.blue
                      : Colors.orange,
                ),
                title: Text(
                  transaction['deal_name'] ?? 'Unknown Deal',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(transaction['member_name'] ?? 'Unknown'),
                    Text(
                      _formatDate(transaction['created_at']),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatCurrency(transaction['amount']),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'approved':
        return Colors.blue;
      case 'pending':
        return Colors.amber;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM d, yyyy HH:mm').format(date);
    } catch (e) {
      return 'Unknown';
    }
  }
}
