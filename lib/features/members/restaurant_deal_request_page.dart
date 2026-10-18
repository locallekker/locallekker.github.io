import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import '../../models/deal_schedule.dart';
import '../../models/discount.dart';
import '../../models/restaurant_deal.dart';
import '../../services/admin_engagement_service.dart';
import '../../services/deal_authorization_service.dart';
import '../../services/in_app_payment_availability_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/branded_app_bar.dart';
import '../../widgets/restaurant_deal_badge.dart';

/// Member flow for claiming a restaurant deal: enter the bill details, see the
/// discount, choose how to pay, and send the request to the partner.
class RestaurantDealRequestPage extends StatefulWidget {
  final Discount discount;
  final String? partnerName;

  const RestaurantDealRequestPage({
    super.key,
    required this.discount,
    this.partnerName,
  });

  @override
  State<RestaurantDealRequestPage> createState() =>
      _RestaurantDealRequestPageState();
}

class _RestaurantDealRequestPageState extends State<RestaurantDealRequestPage> {
  static const Color _kBrandBlue = Color(0xFF0E5BA0);
  static const Color _kBrandGreen = Color(0xFF3C8C44);
  static const Color _kBrandGreenLight = Color(0xFFE6F2EC);

  static final RegExp _serverErrorPattern = RegExp(
    r'RESTAURANT_DEAL_[A-Z_]+:\s*(.*?)(?:, code:|\)$|$)',
  );

  final Logger _logger = Logger();
  final _billController = TextEditingController();
  final _tipController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  int _qtyA = 0;
  int _qtyB = 0;
  String? _paymentMethod;
  bool? _inAppAvailable;
  bool _submitting = false;
  String? _birthdayBlocker;
  bool _birthdayChecked = false;

  late final RestaurantDealConfig _config;

  RestaurantDealType get _type => _config.type;

  @override
  void initState() {
    super.initState();
    _config = widget.discount.restaurantConfig!;
    unawaited(AdminEngagementService().recordDealOpen(widget.discount.id));
    switch (_type) {
      case RestaurantDealType.bogo:
        _qtyA = _config.integer('buy_qty', 1) + _config.integer('free_qty', 1);
        break;
      case RestaurantDealType.setMenu:
        _qtyA = 1;
        break;
      case RestaurantDealType.kidsFree:
        _qtyA = 1;
        _qtyB = 1;
        break;
      case RestaurantDealType.freeItem:
        _qtyA = 1;
        _qtyB = 1;
        break;
      case RestaurantDealType.group:
        _qtyA = _config.minPartySize;
        break;
      default:
        break;
    }
    for (final c in [_billController, _tipController, _amountController]) {
      c.addListener(() => setState(() {}));
    }
    if (!_config.bogoPriceAtCheckout) unawaited(_loadInAppAvailability());
    if (_type == RestaurantDealType.birthday) unawaited(_checkBirthday());
  }

  @override
  void dispose() {
    _billController.dispose();
    _tipController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadInAppAvailability() async {
    final available = await InAppPaymentAvailabilityService()
        .isAvailableForDiscount(widget.discount.id);
    if (mounted) setState(() => _inAppAvailable = available);
  }

  Future<void> _checkBirthday() async {
    String? blocker;
    try {
      final userId = SupabaseService.instance.getCurrentUser()?.id;
      if (userId != null) {
        final row = await SupabaseService.instance.client
            .from('profiles')
            .select('date_of_birth')
            .eq('id', userId)
            .maybeSingle();
        final raw = row?['date_of_birth'] as String?;
        final dob = raw == null ? null : DateTime.tryParse(raw);
        if (dob == null) {
          blocker =
              'Add your date of birth to your profile to use birthday deals.';
        } else if (!_config.isWithinBirthdayWindow(dob, DateTime.now())) {
          blocker =
              'This deal is only available within ${_config.birthdayWindowDays} days of your birthday.';
        }
      }
    } catch (e) {
      // The server makes the final decision, so don't block on a failed check.
      _logger.w('Birthday pre-check failed: $e');
    }
    if (mounted) {
      setState(() {
        _birthdayBlocker = blocker;
        _birthdayChecked = true;
      });
    }
  }

  double _money(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  RestaurantDealInputs get _inputs => RestaurantDealInputs(
    billTotal: _money(_billController),
    tip: _money(_tipController),
    excludedAmount: _type == RestaurantDealType.foodPercent
        ? _money(_amountController)
        : 0,
    qualifyingAmount: _type == RestaurantDealType.happyHour
        ? _money(_amountController)
        : 0,
    itemQty: _type == RestaurantDealType.bogo ? _qtyA : 0,
    menuQty: _type == RestaurantDealType.setMenu ? _qtyA : 0,
    adultQty: _type == RestaurantDealType.kidsFree ? _qtyA : 0,
    kidQty: _type == RestaurantDealType.kidsFree ? _qtyB : 0,
    qualifyingQty: _type == RestaurantDealType.freeItem ? _qtyA : 0,
    freeQty: _type == RestaurantDealType.freeItem ? _qtyB : 0,
    partySize: _type == RestaurantDealType.group ? _qtyA : 0,
  );

  Future<void> _selectPaymentMethod(String method) async {
    if (method != 'in_app') {
      setState(() => _paymentMethod = method);
      return;
    }
    final available =
        _inAppAvailable ??
        await InAppPaymentAvailabilityService().isAvailableForDiscount(
          widget.discount.id,
        );
    if (!mounted) return;
    if (available) {
      setState(() {
        _inAppAvailable = true;
        _paymentMethod = 'in_app';
      });
    } else {
      await _switchToPayInStore();
    }
  }

  Future<void> _switchToPayInStore() async {
    setState(() {
      _inAppAvailable = false;
      _paymentMethod = 'pos';
    });
    await InAppPaymentAvailabilityService().showUnavailableDialog(
      context,
      discountId: widget.discount.id,
      partnerName: widget.partnerName,
    );
  }

  String _partnerNotes(RestaurantDealQuote quote) {
    final lines = <String>[
      '${_type.label}: ${_config.headline}',
      'Bill ${formatRand(quote.billTotal)} · ${quote.summary}',
      'Discount ${formatRand(quote.discount)}'
          '${quote.tip > 0 ? ' · Tip ${formatRand(quote.tip)}' : ''}'
          ' · Member pays ${formatRand(quote.total)}',
    ];
    if (_type == RestaurantDealType.foodPercent && _inputs.excludedAmount > 0) {
      lines.add('Excluded items: ${formatRand(_inputs.excludedAmount)}');
    }
    if (_type == RestaurantDealType.birthday) {
      lines.add('Birthday deal: please check ID.');
    }
    final memberNote = _notesController.text.trim();
    if (memberNote.isNotEmpty) lines.add('Member note: $memberNote');
    return lines.join('\n');
  }

  void _showMessage(String text, {Color color = Colors.orange}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_config.bogoPriceAtCheckout) {
      _showMessage('Please show your member QR to the partner to redeem in store.');
      return;
    }
    final quote = _config.quote(_inputs);
    if (!quote.isValid) {
      _showMessage(quote.error!);
      return;
    }
    if (_birthdayBlocker != null) {
      _showMessage(_birthdayBlocker!);
      return;
    }
    if (_paymentMethod == null) {
      _showMessage('Please choose how you will pay.');
      return;
    }
    if (_paymentMethod == 'in_app' && quote.total <= 0) {
      _showMessage('Nothing to pay in the app. Please choose Pay in store.');
      return;
    }

    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) {
      _showMessage('Please sign in again.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await DealAuthorizationService().requestDealAuthorization(
        memberId: user.id,
        discountId: widget.discount.id,
        paymentMethod: _paymentMethod!,
        amount: quote.total,
        quantity: 1,
        appliedDiscountAmount: quote.discount,
        dealType: _type.key,
        dealSnapshot: {
          'id': widget.discount.id,
          'name': widget.discount.name,
          'deal_type': _type.key,
          'custom_data': widget.discount.customData,
          'headline': _config.headline,
          'business_name': widget.partnerName,
        },
        notes: _partnerNotes(quote),
        billData: buildRestaurantBillData(
          type: _type,
          inputs: _inputs,
          quote: quote,
        ),
      );
      if (!mounted) return;
      _showMessage('Request sent to the partner!', color: _kBrandGreen);
      Navigator.of(context).pop();
    } catch (e) {
      _logger.e('Restaurant deal request failed: $e');
      if (InAppPaymentAvailabilityService.isUnavailableError(e)) {
        if (mounted) {
          setState(() => _submitting = false);
          await _switchToPayInStore();
        }
        return;
      }
      final match = _serverErrorPattern.firstMatch(e.toString());
      _showMessage(
        match != null && match.group(1)!.trim().isNotEmpty
            ? match.group(1)!.trim()
            : 'Could not send your request. Please try again.',
        color: Colors.red.shade700,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = _config.quote(_inputs);
    final hasBill = _money(_billController) > 0;
    final schedule = widget.discount.scheduleData == null
        ? null
        : DealSchedule.fromJson(widget.discount.scheduleData!);

    if (_config.bogoPriceAtCheckout) {
      return Scaffold(
        appBar: BrandedAppBar(title: Text(_type.label)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _dealCard(schedule),
              const SizedBox(height: 16),
              _sectionTitle('Redeem in store'),
              Text(_config.bogoPricingDescription),
              const SizedBox(height: 12),
              const Text(
                'Show your member QR to the partner at checkout. They will scan '
                'it, select this deal and enter the normal price of each '
                'qualifying item. The app calculates your discount and the '
                'partner confirms the total against the till receipt.\n\n'
                'Pay the partner in store. No price or payment is needed here.',
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: Text(_type.label),
        backgroundColor: _kBrandBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _dealCard(schedule),
            const SizedBox(height: 16),
            if (_type == RestaurantDealType.birthday) _birthdayStatus(),
            _sectionTitle('Your bill'),
            _moneyField(
              _billController,
              'Bill total (before tip)',
              helper: 'The full amount on your bill',
            ),
            ..._typeInputs(),
            const SizedBox(height: 12),
            _moneyField(_tipController, 'Tip (optional)'),
            const SizedBox(height: 16),
            if (hasBill) _breakdown(quote),
            const SizedBox(height: 16),
            _sectionTitle('How will you pay?'),
            _paymentOption(
              'in_app',
              Icons.phone_android,
              'Pay through App',
              _inAppAvailable == false
                  ? 'Not available for this partner yet'
                  : 'Pay securely with card via Paystack',
              enabled: _inAppAvailable != false,
            ),
            const SizedBox(height: 8),
            _paymentOption(
              'pos',
              Icons.store,
              'Pay in store',
              'Pay the partner at the till',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Note for the partner (optional)',
                hintText: 'e.g. table number',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBrandGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    hasBill && quote.isValid
                        ? 'Send request · ${formatRand(quote.total)}'
                        : 'Send request',
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _dealCard(DealSchedule? schedule) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.partnerName != null)
              Text(
                widget.partnerName!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              widget.discount.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (widget.discount.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(widget.discount.description),
            ],
            const SizedBox(height: 10),
            RestaurantDealBadge(
              dealType: widget.discount.dealType,
              customData: widget.discount.customData,
              scheduleData: widget.discount.scheduleData,
            ),
            if (_type == RestaurantDealType.setMenu &&
                _config.text('menu_details').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _config.text('menu_details'),
                style: TextStyle(color: Colors.grey.shade800),
              ),
            ],
            if (_config.maxFree > 0 &&
                {
                  RestaurantDealType.bogo,
                  RestaurantDealType.kidsFree,
                  RestaurantDealType.freeItem,
                }.contains(_type)) ...[
              const SizedBox(height: 6),
              Text(
                'Limit: ${_config.maxFree} free per bill',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _birthdayStatus() {
    if (!_birthdayChecked) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: LinearProgressIndicator(),
      );
    }
    final ok = _birthdayBlocker == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? _kBrandGreenLight : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.cake : Icons.info_outline,
            color: ok ? _kBrandGreen : Colors.orange.shade800,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ok
                  ? 'Happy birthday! The partner may ask to see your ID.'
                  : _birthdayBlocker!,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _typeInputs() {
    switch (_type) {
      case RestaurantDealType.foodPercent:
        final label = _config.text('excluded_label', 'drinks');
        return [
          const SizedBox(height: 12),
          _moneyField(
            _amountController,
            'Excluded items total ($label)',
            helper: 'Items that don\'t get the discount. Leave empty if none.',
          ),
        ];
      case RestaurantDealType.happyHour:
        return [
          const SizedBox(height: 12),
          _moneyField(
            _amountController,
            'Happy hour items total',
            helper:
                'Total of the ${_config.text('item_label', 'happy hour items')} on your bill',
          ),
        ];
      case RestaurantDealType.bogo:
        return [
          _stepper(
            'How many ${_config.text('item_name', 'items')} did you order?',
            _qtyA,
            (v) => _qtyA = v,
          ),
        ];
      case RestaurantDealType.setMenu:
        return [
          _stepper(
            'How many ${_config.text('menu_name', 'set menus')}?',
            _qtyA,
            (v) => _qtyA = v,
            min: 1,
          ),
        ];
      case RestaurantDealType.kidsFree:
        return [
          _stepper('Paying adults', _qtyA, (v) => _qtyA = v),
          _stepper('Kids meals', _qtyB, (v) => _qtyB = v),
        ];
      case RestaurantDealType.freeItem:
        return [
          _stepper(
            '${_config.text('qualifying_label', 'Qualifying items')} ordered',
            _qtyA,
            (v) => _qtyA = v,
          ),
          _stepper(
            'Free ${_config.text('free_item_name', 'items')} claimed',
            _qtyB,
            (v) => _qtyB = v,
          ),
        ];
      case RestaurantDealType.group:
        return [
          _stepper(
            'People at your table (min ${_config.minPartySize})',
            _qtyA,
            (v) => _qtyA = v,
            min: 1,
          ),
        ];
      case RestaurantDealType.birthday:
        return const [];
    }
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
  );

  Widget _moneyField(
    TextEditingController controller,
    String label, {
    String? helper,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,6}([.,]\d{0,2})?')),
      ],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        prefixText: 'R ',
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _stepper(
    String label,
    int value,
    void Function(int) onChanged, {
    int min = 0,
    int max = 50,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          IconButton(
            onPressed: value > min
                ? () => setState(() => onChanged(value - 1))
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            onPressed: value < max
                ? () => setState(() => onChanged(value + 1))
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _breakdown(RestaurantDealQuote quote) {
    if (!quote.isValid) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(quote.error!, style: TextStyle(color: Colors.orange.shade900)),
      );
    }
    Widget row(String label, String value, {bool bold = false, Color? color}) {
      final style = TextStyle(
        fontSize: bold ? 17 : 15,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: color,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: style)),
            Text(value, style: style),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kBrandGreenLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          row('Bill total', formatRand(quote.billTotal)),
          row(
            'Discount${quote.summary.isEmpty ? '' : ' (${quote.summary})'}',
            '- ${formatRand(quote.discount)}',
            color: _kBrandGreen,
          ),
          if (quote.tip > 0) row('Tip', formatRand(quote.tip)),
          const Divider(),
          row('You pay', formatRand(quote.total), bold: true),
          if (quote.discount == 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Your current order doesn\'t qualify for a discount yet.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
              ),
            ),
        ],
      ),
    );
  }

  Widget _paymentOption(
    String method,
    IconData icon,
    String title,
    String subtitle, {
    bool enabled = true,
  }) {
    final selected = _paymentMethod == method;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: _submitting ? null : () => _selectPaymentMethod(method),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _kBrandGreen : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
            color: selected ? _kBrandGreenLight : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? _kBrandGreen : Colors.grey.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle, color: _kBrandGreen),
            ],
          ),
        ),
      ),
    );
  }
}
