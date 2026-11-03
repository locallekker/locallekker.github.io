import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

import '../../core/theme/app_colors.dart';
import '../../models/guest_conversion_report.dart';
import '../../services/guest_analytics_service.dart';
import '../../widgets/branded_app_bar.dart';

typedef GuestConversionReportLoader =
    Future<GuestConversionReport> Function({
      required DateTime start,
      required DateTime end,
    });

/// Admin view of members browsing without an account: how many browse, which
/// deals they try to request, and how many go on to sign up or sign in.
class AdminGuestConversionScreen extends StatefulWidget {
  final GuestConversionReportLoader? loadReport;

  const AdminGuestConversionScreen({super.key, this.loadReport});

  @override
  State<AdminGuestConversionScreen> createState() =>
      _AdminGuestConversionScreenState();
}

class _AdminGuestConversionScreenState
    extends State<AdminGuestConversionScreen> {
  final _logger = Logger();
  final _currency = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
  final _date = DateFormat('dd MMM yyyy');
  late DateTimeRange _range;
  int _selectedDays = 30;
  GuestConversionReport? _report;
  bool _loading = true;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _range = _lastDays(30);
    _load();
  }

  DateTimeRange _lastDays(int days) {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, now.day - days + 1),
      end: DateTime(now.year, now.month, now.day + 1),
    );
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader =
          widget.loadReport ?? GuestAnalyticsService().fetchAdminReport;
      final report = await loader(start: _range.start, end: _range.end);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e, stack) {
      _logger.e('Guest conversion report unavailable', error: e, stackTrace: stack);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _report = null;
        _error =
            'Guest tracking could not be loaded. Please retry. If this is a '
            'new installation, ensure the guest tracking migration has been applied.';
        _loading = false;
      });
    }
  }

  void _selectDays(int days) {
    _selectedDays = days;
    _range = _lastDays(days);
    _load();
  }

  String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: const BrandedAppBar(title: Text('Guest Browsing & Conversion')),
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
                  ChoiceChip(
                    label: Text('Last $days days'),
                    selected: _selectedDays == days,
                    onSelected: (_) => _selectDays(days),
                  ),
                IconButton(
                  tooltip: 'Refresh guest tracking',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: Text(_error!),
                  trailing: TextButton(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ),
              )
            else if (report != null) ...[
              _summary(report),
              const SizedBox(height: 16),
              _funnel(report),
              const SizedBox(height: 16),
              Text(
                'Deals guests tried to request',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (report.deals.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No guest deal requests in this period yet.',
                    ),
                  ),
                )
              else
                for (final deal in report.deals) _dealTile(deal),
              const SizedBox(height: 12),
              Text(
                'Guests are counted per device. A conversion is recorded when '
                'that device signs up (new account) or signs in (existing '
                'account) after browsing.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary(GuestConversionReport report) {
    final metrics = <(String, String, IconData)>[
      ('Browsing guests', '${report.browsingGuests}', Icons.travel_explore),
      (
        'Guests who requested',
        '${report.requestingGuests}',
        Icons.touch_app_outlined,
      ),
      ('Request attempts', '${report.requestAttempts}', Icons.ads_click),
      (
        'Converted requesters',
        '${report.convertedRequestingGuests} '
            '(${_percent(report.requestConversionRate)})',
        Icons.how_to_reg_outlined,
      ),
      ('New signups', '${report.signupConversions}', Icons.person_add_alt_1),
      ('Existing sign-ins', '${report.signinConversions}', Icons.login),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 3 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, value, icon) in metrics)
              SizedBox(
                width: width,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: AppColors.primary),
                        const SizedBox(height: 8),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(label),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _funnel(GuestConversionReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conversion funnel',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${_percent(report.requestRate)} of browsing guests tried to '
              'request a deal.',
            ),
            Text(
              '${_percent(report.requestConversionRate)} of guests who '
              'requested went on to sign up or sign in.',
            ),
            Text(
              '${report.convertedBrowsingGuests} of ${report.browsingGuests} '
              'browsing guests have converted overall.',
            ),
            Text(
              'Savings shown to guests: '
              '${_currency.format(report.potentialSavingsTotal)}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _dealTile(GuestDealInterest deal) {
    return Card(
      child: ListTile(
        title: Text(deal.dealName),
        subtitle: Text(
          [
            if (deal.businessName != null) deal.businessName!,
            '${deal.guests} guest${deal.guests == 1 ? '' : 's'} · '
                '${deal.convertedGuests} converted '
                '(${_percent(deal.conversionRate)})',
            if (deal.potentialSavings > 0)
              'Savings shown: ${_currency.format(deal.potentialSavings)}',
          ].join('\n'),
        ),
        isThreeLine: deal.businessName != null || deal.potentialSavings > 0,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${deal.attempts}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text('requests'),
          ],
        ),
      ),
    );
  }
}
