import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

import '../../models/admin_engagement_report.dart';
import '../../services/admin_engagement_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/branded_app_bar.dart';
import 'admin_partner_detail_screen.dart';

typedef EngagementReportLoader =
    Future<AdminEngagementReport> Function({
      required DateTime start,
      required DateTime end,
    });

class AdminEngagementScreen extends StatefulWidget {
  final EngagementReportLoader? loadReport;

  const AdminEngagementScreen({super.key, this.loadReport});

  @override
  State<AdminEngagementScreen> createState() => _AdminEngagementScreenState();
}

class _AdminEngagementScreenState extends State<AdminEngagementScreen> {
  final _logger = Logger();
  final _currency = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
  final _date = DateFormat('dd MMM yyyy');
  late DateTimeRange _range;
  AdminEngagementReport? _report;
  bool _loading = true;
  String? _error;
  String _search = '';
  String _sort = 'review';
  bool _reviewOnly = false;
  int _requestId = 0;
  String? _openingPartnerId;

  @override
  void initState() {
    super.initState();
    _range = _lastDays(30);
    _load();
  }

  DateTimeRange _lastDays(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTimeRange(
      start: DateTime(today.year, today.month, today.day - days + 1),
      end: DateTime(today.year, today.month, today.day + 1),
    );
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
    });
    try {
      final loader = widget.loadReport ?? AdminEngagementService().fetchReport;
      final report = await loader(start: _range.start, end: _range.end);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e, stack) {
      _logger.e('Admin reporting unavailable', error: e, stackTrace: stack);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error =
            'Reporting could not be loaded. Please retry. '
            'If this is a new installation, ensure the reporting migration has been applied.';
        _loading = false;
      });
    }
  }

  Future<void> _pickDates() async {
    final today = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: _range.start,
        end: _range.end.subtract(const Duration(days: 1)),
      ),
    );
    if (selected == null || !mounted) return;
    _range = DateTimeRange(
      start: selected.start,
      end: DateTime(
        selected.end.year,
        selected.end.month,
        selected.end.day + 1,
      ),
    );
    await _load();
  }

  List<PartnerEngagement> _partners(AdminEngagementReport report) {
    final query = _search.trim().toLowerCase();
    final partners = report.partners.where((p) {
      if (_reviewOnly && p.reviewDealCount == 0 && p.deals.isNotEmpty) {
        return false;
      }
      return '${p.name} ${p.city} ${p.deals.map((d) => d.name).join(' ')}'
          .toLowerCase()
          .contains(query);
    }).toList();
    partners.sort((a, b) {
      int comparison;
      switch (_sort) {
        case 'views':
          comparison = a.views.compareTo(b.views);
        case 'sales':
          comparison = b.sales.compareTo(a.sales);
        case 'redemptions':
          comparison = b.redemptions.compareTo(a.redemptions);
        default:
          comparison = b.reviewDealCount.compareTo(a.reviewDealCount);
          if (comparison == 0) comparison = a.views.compareTo(b.views);
      }
      return comparison == 0 ? a.name.compareTo(b.name) : comparison;
    });
    return partners;
  }

  Future<void> _openPartner(PartnerEngagement partner) async {
    if (_openingPartnerId != null) return;
    setState(() => _openingPartnerId = partner.id);
    try {
      final profile = await SupabaseService.instance.client
          .from('profiles')
          .select()
          .eq('id', partner.id)
          .single();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AdminPartnerDetailScreen(partner: profile),
        ),
      );
      if (mounted) await _load();
    } catch (e, stack) {
      _logger.e('Could not open partner details', error: e, stackTrace: stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open partner details. Please retry.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingPartnerId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: const BrandedAppBar(title: Text('Sales & Member Engagement')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${_date.format(_range.start)} - '
              '${_date.format(_range.end.subtract(const Duration(days: 1)))}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final days in [7, 30, 90])
                  ActionChip(
                    label: Text('Last $days days'),
                    onPressed: () {
                      _range = _lastDays(days);
                      _load();
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: const Text('Custom dates'),
                  onPressed: _pickDates,
                ),
                IconButton(
                  tooltip: 'Refresh report',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null) ...[
              const SizedBox(height: 24),
              Text(_error!, textAlign: TextAlign.center),
              Center(
                child: FilledButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ),
            ] else if (report != null) ...[
              const SizedBox(height: 16),
              _summary(report),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Views count intentional deal-detail or image opens by members, '
                    'not cards displayed. Repeat opens are deduplicated per member/deal '
                    'in 30-minute windows. View tracking started '
                    '${_date.format(report.trackingStartedAt.toLocal())}; earlier views are unavailable.\n\n'
                    'Redemptions and deal sales include completed transactions only. '
                    'Sales use the recorded amount after discounts, not original bill value. '
                    'Redirect clicks are referrals, not verified external sales. '
                    'Requests are created in this period; redemptions are completed in it, '
                    'so these counts are not a conversion funnel.',
                  ),
                ),
              ),
              if (report.missingAmounts > 0)
                Text(
                  '${report.missingAmounts} completed transactions have no recorded amount. '
                  'Sales totals exclude those amounts.',
                  style: TextStyle(color: Colors.orange.shade900),
                ),
              const SizedBox(height: 24),
              Text(
                'Partner & deal performance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Review active deals with no completed redemptions or no redirect clicks. '
                'These are discussion prompts, not a judgement of partner performance. '
                'Use the date range and lowest-views sort to find low engagement.',
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search partners, cities or deals',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _sort,
                decoration: const InputDecoration(labelText: 'Sort partners'),
                items: const [
                  DropdownMenuItem(
                    value: 'review',
                    child: Text('Most deals to review'),
                  ),
                  DropdownMenuItem(
                    value: 'views',
                    child: Text('Lowest views first'),
                  ),
                  DropdownMenuItem(
                    value: 'redemptions',
                    child: Text('Most redemptions first'),
                  ),
                  DropdownMenuItem(
                    value: 'sales',
                    child: Text('Highest sales first'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _sort = value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Only partners needing discussion'),
                subtitle: const Text('Deals to review or no deals listed'),
                value: _reviewOnly,
                onChanged: (value) => setState(() => _reviewOnly = value),
              ),
              if (_partners(report).isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No partners match these filters.'),
                ),
              for (final partner in _partners(report)) _partnerCard(partner),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary(AdminEngagementReport r) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 800 ? 4 : 2;
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metric(
              width,
              'Member signups',
              '${r.memberSignups}',
              '${r.activeMemberSignups} currently active',
            ),
            _metric(
              width,
              'TP signups',
              '${r.partnerSignups}',
              r.readyPartnerSignups == null
                  ? 'Partner terms status unavailable'
                  : '${r.readyPartnerSignups} currently terms accepted',
            ),
            _metric(
              width,
              'Platform payment revenue',
              _currency.format(r.subscriptionSales),
              '${r.subscriptionPayments} completed payment records',
            ),
            _metric(
              width,
              'Completed deal sales',
              _currency.format(r.dealSales),
              '${r.redemptions} redemptions',
            ),
            _metric(
              width,
              'In-app deal sales',
              _currency.format(r.inAppSales),
              'Completed only',
            ),
            _metric(
              width,
              'POS deal sales',
              _currency.format(r.posSales),
              'Completed only',
            ),
            _metric(
              width,
              'Other / unspecified sales',
              _currency.format(r.otherSales),
              'Completed only',
            ),
            _metric(
              width,
              'Deal opens',
              '${r.views}',
              '${r.viewers} unique members',
            ),
          ],
        );
      },
    );
  }

  Widget _metric(double width, String title, String value, String detail) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _partnerCard(PartnerEngagement p) {
    final deals = [...p.deals]
      ..sort((a, b) {
        final review = (b.needsReview ? 1 : 0).compareTo(a.needsReview ? 1 : 0);
        return review == 0 ? a.views.compareTo(b.views) : review;
      });
    return Card(
      child: ExpansionTile(
        key: PageStorageKey(p.id),
        title: Text(p.name),
        subtitle: Text(
          '${p.city.isEmpty ? 'Location not recorded' : p.city}\n'
          '${p.views} opens / ${p.viewers} members | ${p.redemptions} redemptions\n'
          '${_currency.format(p.sales)} sales | ${p.redirectClicks} redirect clicks\n'
          '${p.reviewDealCount} active deals to review',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.email.isNotEmpty) SelectionArea(child: Text(p.email)),
                if (p.contact.isNotEmpty) SelectionArea(child: Text(p.contact)),
                Text('${p.requests} requests created in period'),
                if (p.missingAmounts > 0)
                  Text(
                    '${p.missingAmounts} completed transactions missing amounts',
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Partner details & manage deals'),
                  onPressed: _openingPartnerId == null
                      ? () => _openPartner(p)
                      : null,
                ),
                if (deals.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'No deals listed. Discuss adding a member offer.',
                    ),
                  ),
                for (final deal in deals) _dealCard(deal),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dealCard(DealEngagement d) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: d.needsReview ? Colors.orange : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.name, style: Theme.of(context).textTheme.titleMedium),
          Text(d.engagementSignal),
          const SizedBox(height: 8),
          Text('${d.views} opens | ${d.viewers} unique members'),
          if (d.isRedirect)
            Text(
              '${d.redirectClicks} redirect clicks | External redemptions unavailable',
            )
          else ...[
            Text(
              '${d.redemptions} redemptions | ${d.redeemingMembers} redeeming members',
            ),
            Text('${_currency.format(d.sales)} completed sales'),
            Text(
              '${d.requests} requests | ${d.pending} pending | '
              '${d.approved} approved, not completed | ${d.rejected} rejected',
            ),
          ],
          if (d.missingAmounts > 0)
            Text('${d.missingAmounts} completed transactions missing amounts'),
        ],
      ),
    );
  }
}
