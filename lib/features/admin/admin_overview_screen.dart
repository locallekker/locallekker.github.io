import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/admin_service.dart';
import '../../models/admin_dashboard_model.dart';
import 'admin_engagement_screen.dart';
import '../auth/deal_selection_page.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:local_lekker/core/theme/app_colors.dart';

/// Overview tab showing aggregate metrics and charts.
class AdminOverviewScreen extends StatefulWidget {
  const AdminOverviewScreen({super.key});

  @override
  State<AdminOverviewScreen> createState() => _AdminOverviewScreenState();
}

class _AdminOverviewScreenState extends State<AdminOverviewScreen> {
  final _logger = Logger();
  final _service = AdminService();
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _error;

  // Member breakdown
  int _activeMemberCount = 0;
  int _pendingMemberCount = 0;
  int _deactivatedMemberCount = 0;

  // Partner breakdown
  int _activePartnerCount = 0;
  int _pendingPartnerCount = 0;

  // Deal count
  int _totalDealCount = 0;
  int _activeDealCount = 0;
  int _inactiveDealCount = 0;

  // Per-region (province) counts of active members and partners.
  // Map<region, (memberCount, partnerCount)>
  final Map<String, _RegionCounts> _regionCounts = {};

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fetch main dashboard + breakdowns in parallel
      final results = await Future.wait<dynamic>([
        _service.fetchDashboard(),
        _supabase
            .from('profiles')
            .select('id, subscription, is_deactivated, province, city')
            .eq('role', 'member'),
        _supabase
            .from('profiles')
            .select('id, partner_terms_accepted, is_deactivated, province, city')
            .eq('role', 'trusted_partner'),
        _supabase
            .from('trusted_partner_discounts')
            .select('id, is_active'),
        // Trusted partners' real location lives on their business record,
        // so fetch the city for every business owner to attribute partners
        // to a region.
        _supabase
            .from('businesses')
            .select('owner_member_id, city'),
      ]);

      final d = results[0] as Map<String, dynamic>;
      final allMembers = results[1] as List;
      final allPartners = results[2] as List;
      final allDeals = results[3] as List;
      final allBusinesses = results[4] as List;

      // Build owner_id -> business city lookup for partner region attribution.
      final Map<String, String> partnerBusinessCity = {};
      for (final biz in allBusinesses) {
        final owner = biz['owner_member_id']?.toString();
        final city = (biz['city'] ?? '').toString().trim();
        if (owner != null && owner.isNotEmpty && city.isNotEmpty) {
          partnerBusinessCity[owner] = city;
        }
      }

      // Member breakdown
      int activeMem = 0, pendingMem = 0, deactivatedMem = 0;
      final Map<String, _RegionCounts> regionCounts = {};
      String normaliseRegion(dynamic v) {
        final s = (v ?? '').toString().trim();
        return s.isEmpty ? 'Unknown' : s;
      }

      for (final m in allMembers) {
        if (m['is_deactivated'] == true) {
          deactivatedMem++;
        } else {
          final sub = (m['subscription'] ?? '').toString().toLowerCase();
          if (sub == 'active') {
            activeMem++;
          } else {
            pendingMem++;
          }
          // Prefer province; fall back to city when province isn't captured.
          final region = normaliseRegion(m['province'] ?? m['city']);
          regionCounts.putIfAbsent(region, () => _RegionCounts()).members++;
        }
      }

      // Partner breakdown
      int activeTP = 0, pendingTP = 0;
      for (final p in allPartners) {
        if (p['is_deactivated'] == true) continue;
        if (p['partner_terms_accepted'] == true) {
          activeTP++;
        } else {
          pendingTP++;
        }
        // Trusted-partner profiles rarely carry province; their location
        // lives on the linked business record. Fall back to profile fields.
        final id = p['id']?.toString();
        final region = normaliseRegion(
          (id != null ? partnerBusinessCity[id] : null) ??
              p['province'] ??
              p['city'],
        );
        regionCounts.putIfAbsent(region, () => _RegionCounts()).partners++;
      }

      // Deal breakdown
      int activeDeals = 0, inactiveDeals = 0;
      for (final deal in allDeals) {
        if (deal['is_active'] == true) {
          activeDeals++;
        } else {
          inactiveDeals++;
        }
      }

      if (!mounted) return;
      setState(() {
        _data = d;
        _activeMemberCount = activeMem;
        _pendingMemberCount = pendingMem;
        _deactivatedMemberCount = deactivatedMem;
        _activePartnerCount = activeTP;
        _pendingPartnerCount = pendingTP;
        _totalDealCount = allDeals.length;
        _activeDealCount = activeDeals;
        _inactiveDealCount = inactiveDeals;
        _regionCounts
          ..clear()
          ..addAll(regionCounts);
        _loading = false;
      });
    } catch (e) {
      _logger.e('Dashboard load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text('Failed to load dashboard', style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _loadDashboard,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final summaryMap = _data ?? <String, dynamic>{};
    final dashboard = AdminDashboard.fromMap(summaryMap);
    final categorySummary = dashboard.categorySummary;

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.insights, color: AppColors.primary),
                title: const Text('Sales, signups & deal engagement'),
                subtitle: const Text(
                  'Compare partner performance and find deals to discuss or improve.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminEngagementScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Metric Cards ──
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                final cardWidth = isWide
                    ? (constraints.maxWidth - 48) / 4
                    : (constraints.maxWidth - 24) / 2;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(
                      width: cardWidth,
                      icon: Icons.people,
                      iconColor: AppColors.primary,
                      label: 'Members',
                      value: dashboard.totalMembers.toString(),
                      subLabels: [
                        _SubLabel('Active', _activeMemberCount, Colors.green),
                        _SubLabel('Pending', _pendingMemberCount, Colors.orange),
                        _SubLabel('Deactivated', _deactivatedMemberCount, Colors.red),
                      ],
                    ),
                    _MetricCard(
                      width: cardWidth,
                      icon: Icons.store,
                      iconColor: Colors.blue,
                      label: 'Trusted Partners',
                      value: dashboard.totalTrustedPartners.toString(),
                      subLabels: [
                        _SubLabel('Active', _activePartnerCount, Colors.green),
                        _SubLabel('Pending', _pendingPartnerCount, Colors.orange),
                      ],
                    ),
                    _MetricCard(
                      width: cardWidth,
                      icon: Icons.shopping_cart,
                      iconColor: Colors.purple,
                      label: 'Online Revenue',
                      value: 'R${dashboard.totalOnlinePurchases.toStringAsFixed(2)}',
                    ),
                    _MetricCard(
                      width: cardWidth,
                      icon: Icons.storefront,
                      iconColor: Colors.orange,
                      label: 'In-Store Revenue',
                      value: 'R${dashboard.totalInStorePurchases.toStringAsFixed(2)}',
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DealSelectionPage(isAdminMode: true),
                          ),
                        );
                      },
                      child: _MetricCard(
                        width: cardWidth,
                        icon: Icons.local_offer,
                        iconColor: AppColors.primary,
                        label: 'Deals',
                        value: _totalDealCount.toString(),
                        subLabels: [
                          _SubLabel('Active', _activeDealCount, Colors.green),
                          _SubLabel('Inactive', _inactiveDealCount, Colors.grey),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),

            // ── Per-Region Counts ──
            _RegionBreakdownCard(regionCounts: _regionCounts),

            const SizedBox(height: 32),

            // ── Chart Section ──
            if (categorySummary.isNotEmpty) ...[
              Text(
                'Revenue by Category',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: categorySummary.asMap().entries.map((entry) {
                      final e = entry.value;
                      final colorIndex = entry.key % _chartColors.length;
                      return PieChartSectionData(
                        value: double.tryParse(
                              (e['total_amount'] ?? '0').toString(),
                            ) ??
                            0,
                        title: e['category']?.toString() ?? '',
                        color: _chartColors[colorIndex],
                        radius: 60,
                        titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Category Details ──
              ...categorySummary.map((cat) {
                final catName = cat['category'] as String? ?? 'Unknown';
                final details = dashboard.categoryDetails[catName] ?? [];
                final amount = double.tryParse(
                      (cat['total_amount'] ?? '0').toString(),
                    ) ??
                    0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ExpansionTile(
                    title: Text(catName),
                    subtitle: Text(
                      'R${amount.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    children: details.isEmpty
                        ? [
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No details available'),
                            ),
                          ]
                        : details.map((d) {
                            return ListTile(
                              dense: true,
                              title: Text(d['product_name']?.toString() ?? ''),
                              trailing: Text('x${d['quantity'] ?? 0}'),
                            );
                          }).toList(),
                  ),
                );
              }),
            ] else ...[
              // Empty state
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.analytics_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'No purchase data yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                      Text(
                        'Category breakdowns will appear here once members make purchases.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _chartColors = [
    AppColors.primary,
    Colors.blue,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.indigo,
    Colors.amber,
    Colors.cyan,
  ];
}

class _SubLabel {
  final String label;
  final int count;
  final Color color;
  const _SubLabel(this.label, this.count, this.color);
}

class _RegionCounts {
  int members = 0;
  int partners = 0;
}

class _RegionBreakdownCard extends StatelessWidget {
  final Map<String, _RegionCounts> regionCounts;
  const _RegionBreakdownCard({required this.regionCounts});

  @override
  Widget build(BuildContext context) {
    final entries = regionCounts.entries.toList()
      ..sort((a, b) {
        final totalCmp = (b.value.members + b.value.partners)
            .compareTo(a.value.members + a.value.partners);
        if (totalCmp != 0) return totalCmp;
        return a.key.compareTo(b.key);
      });

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.map_outlined, color: Colors.indigo.shade400),
                const SizedBox(width: 8),
                Text(
                  'By Region',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Active member & trusted partner totals per region',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No regional data yet.',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              )
            else
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Region',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Members',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primarySwatch.shade700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Partners',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 8),
                  ...entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              e.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${e.value.members}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${e.value.partners}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final List<_SubLabel>? subLabels;

  const _MetricCard({
    required this.width,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.subLabels,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              if (subLabels != null && subLabels!.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...subLabels!.map((s) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${s.count} ${s.label}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
