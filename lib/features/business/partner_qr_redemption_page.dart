import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/discount.dart';
import '../../models/restaurant_deal.dart';
import '../../services/partner_qr_redemption_service.dart';

class PartnerQrRedemptionPage extends StatefulWidget {
  final String businessId;
  final String redemptionSessionId;
  final Map<String, dynamic> member;

  const PartnerQrRedemptionPage({
    super.key,
    required this.businessId,
    required this.redemptionSessionId,
    required this.member,
  });

  @override
  State<PartnerQrRedemptionPage> createState() =>
      _PartnerQrRedemptionPageState();
}

class _PartnerQrRedemptionPageState extends State<PartnerQrRedemptionPage> {
  static const _green = Color(0xFF005846);
  final _service = PartnerQrRedemptionService();
  final _billController = TextEditingController();
  final _tipController = TextEditingController(text: '0');
  final _extrasController = TextEditingController(text: '0');
  final _posController = TextEditingController();
  final _manualPriceController = TextEditingController();
  final _adjustmentsController = TextEditingController();
  final Map<String, TextEditingController> _detailControllers = {};
  final String _idempotencyKey = const Uuid().v4();

  List<Discount> _deals = [];
  Discount? _selectedDeal;
  bool _loadingDeals = true;
  bool _submitting = false;
  String? _loadError;
  String? _redemptionId;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    _loadDeals();
    for (final controller in [
      _billController,
      _tipController,
      _extrasController,
      _posController,
      _manualPriceController,
      _adjustmentsController,
    ]) {
      controller.addListener(_refreshQuote);
    }
  }

  @override
  void dispose() {
    _billController.dispose();
    _tipController.dispose();
    _extrasController.dispose();
    _posController.dispose();
    _manualPriceController.dispose();
    _adjustmentsController.dispose();
    for (final controller in _detailControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDeals() async {
    try {
      final deals = await _service.getActiveDeals(widget.businessId);
      if (!mounted) return;
      setState(() {
        _deals = deals;
        _loadingDeals = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDeals = false;
        _loadError = _readableError(e);
      });
    }
  }

  void _refreshQuote() {
    if (mounted) setState(() {});
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;

  TextEditingController _detailController(String key) =>
      _detailControllers.putIfAbsent(key, TextEditingController.new);

  int _detailQuantity(String key) =>
      int.tryParse(_detailController(key).text.trim()) ?? 0;

  double _detailAmount(String key) => _number(_detailController(key));

  RestaurantDealInputs? _restaurantInputs(Discount deal) {
    final config = deal.restaurantConfig;
    if (config == null) return null;
    final type = config.type;
    return RestaurantDealInputs(
      billTotal: _number(_billController),
      tip: _number(_tipController),
      excludedAmount: type == RestaurantDealType.foodPercent
          ? _detailAmount('excluded_amount')
          : 0,
      qualifyingAmount: type == RestaurantDealType.happyHour
          ? _detailAmount('qualifying_amount')
          : 0,
      itemQty: type == RestaurantDealType.bogo
          ? _detailQuantity('item_qty')
          : 0,
      itemPrices: config.bogoPriceAtCheckout
          ? [
              for (var index = 0;
                  index < _detailQuantity('item_qty').clamp(0, 200);
                  index++)
                _detailAmount('bogo_price_$index'),
            ]
          : const [],
      menuQty: type == RestaurantDealType.setMenu
          ? _detailQuantity('menu_qty')
          : 0,
      adultQty: type == RestaurantDealType.kidsFree
          ? _detailQuantity('adult_qty')
          : 0,
      kidQty: type == RestaurantDealType.kidsFree
          ? _detailQuantity('kid_qty')
          : 0,
      qualifyingQty: type == RestaurantDealType.freeItem
          ? _detailQuantity('qualifying_qty')
          : 0,
      freeQty: type == RestaurantDealType.freeItem
          ? _detailQuantity('free_qty')
          : 0,
      partySize: type == RestaurantDealType.group
          ? _detailQuantity('party_size')
          : 0,
    );
  }

  PartnerQrDealQuote? _quoteFor(Discount? deal) {
    if (deal == null) return null;
    return PartnerQrRedemptionService.quote(
      deal: deal,
      billTotal: _number(_billController),
      tip: _number(_tipController),
      quantity: _quantity,
      manualUnitPrice: _number(_manualPriceController),
      excludedAmount: _detailAmount('excluded_amount'),
      extrasAmount: _number(_extrasController),
      restaurantInputs: _restaurantInputs(deal),
    );
  }

  Widget _moneyField(String label, TextEditingController controller) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: 'R ',
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => _refreshQuote(),
      );

  Widget _quantityField(String label, String key) {
    final controller = _detailController(key);
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => _refreshQuote(),
    );
  }

  Widget _dealSelection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose a deal',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_deals.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('There are no active deals to redeem.'),
              ),
            ),
          ..._deals.map((deal) {
            final selected = _selectedDeal?.id == deal.id;
            return Card(
              color: selected ? const Color(0xFFE8F3EF) : Colors.white,
              child: ListTile(
                leading: Icon(
                  deal.isRestaurantDeal
                      ? Icons.restaurant_menu
                      : Icons.local_offer_outlined,
                  color: _green,
                ),
                title: Text(deal.name),
                subtitle: Text(deal.discountDisplay),
                trailing: selected
                    ? const Icon(Icons.check_circle, color: _green)
                    : const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() {
                    _selectedDeal = deal;
                    _quantity = deal.isWeightBased ? 100 : 1;
                    _billController.clear();
                    _tipController.text = '0';
                    _extrasController.text = '0';
                    _posController.clear();
                    _manualPriceController.clear();
                    _adjustmentsController.clear();
                    for (final controller in _detailControllers.values) {
                      controller.clear();
                    }
                    final config = deal.restaurantConfig;
                    if (config != null) {
                      switch (config.type) {
                        case RestaurantDealType.bogo:
                          _detailController('item_qty').text =
                              '${config.integer('buy_qty', 1) + config.integer('free_qty', 1)}';
                          break;
                        case RestaurantDealType.setMenu:
                          _detailController('menu_qty').text = '1';
                          break;
                        case RestaurantDealType.kidsFree:
                          _detailController('adult_qty').text = '1';
                          _detailController('kid_qty').text = '1';
                          break;
                        case RestaurantDealType.freeItem:
                          _detailController('qualifying_qty').text = '1';
                          _detailController('free_qty').text = '1';
                          break;
                        case RestaurantDealType.group:
                          _detailController('party_size').text =
                              '${config.minPartySize}';
                          break;
                        case RestaurantDealType.foodPercent:
                        case RestaurantDealType.happyHour:
                        case RestaurantDealType.birthday:
                          break;
                      }
                    }
                  });
                },
              ),
            );
          }),
        ],
      );

  Widget _restaurantFields(Discount deal) {
    final config = deal.restaurantConfig;
    if (config == null) return const SizedBox.shrink();
    switch (config.type) {
      case RestaurantDealType.foodPercent:
        return _moneyField('Excluded items (e.g. drinks)', _detailController('excluded_amount'));
      case RestaurantDealType.happyHour:
        return _moneyField('Total price of happy-hour items', _detailController('qualifying_amount'));
      case RestaurantDealType.bogo:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(config.bogoPricingDescription),
            const SizedBox(height: 12),
            _quantityField(
              'Number of qualifying items (including free items)',
              'item_qty',
            ),
            if (config.bogoPriceAtCheckout)
              for (var index = 0;
                  index < _detailQuantity('item_qty').clamp(0, 200);
                  index++) ...[
                const SizedBox(height: 12),
                _moneyField(
                  'Qualifying item ${index + 1} - normal price',
                  _detailController('bogo_price_$index'),
                ),
              ],
          ],
        );
      case RestaurantDealType.setMenu:
        return _quantityField('Number of set menus', 'menu_qty');
      case RestaurantDealType.kidsFree:
        return Row(
          children: [
            Expanded(child: _quantityField('Paying adults', 'adult_qty')),
            const SizedBox(width: 12),
            Expanded(child: _quantityField('Children', 'kid_qty')),
          ],
        );
      case RestaurantDealType.freeItem:
        return Row(
          children: [
            Expanded(child: _quantityField('Qualifying items', 'qualifying_qty')),
            const SizedBox(width: 12),
            Expanded(child: _quantityField('Free items claimed', 'free_qty')),
          ],
        );
      case RestaurantDealType.group:
        return _quantityField(
          'Number of people at the table (minimum ${config.minPartySize})',
          'party_size',
        );
      case RestaurantDealType.birthday:
        return const Text('The server will verify the member’s birthday and whether this treat was already redeemed.');
    }
  }

  Widget _dealInputs(Discount deal) {
    final isManualPrice = deal.isPercentItem && deal.requiresManualPrice;
    final showQuantity = !deal.isBillDiscount && deal.restaurantConfig == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _moneyField(
          'Original bill total (before deal, including extras)',
          _billController,
        ),
        const SizedBox(height: 12),
        if (showQuantity) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  deal.isWeightBased
                      ? 'Weight (grams)'
                      : deal.isBuyGet
                          ? 'Number of deal bundles'
                          : 'Quantity',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: _quantity > (deal.isWeightBased ? 100 : 1)
                    ? () => setState(() => _quantity -= deal.isWeightBased ? 100 : 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_quantity'),
              IconButton(
                onPressed: () => setState(
                  () => _quantity = math.min(
                    _quantity + (deal.isWeightBased ? 100 : 1),
                    deal.isWeightBased ? 200000 : 200,
                  ).toInt(),
                ),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (isManualPrice) ...[
            const SizedBox(height: 8),
            _moneyField('Regular price per item', _manualPriceController),
          ],
        ],
        if (deal.isBillDiscount) ...[
          const SizedBox(height: 8),
          _moneyField(
            'Excluded items (optional)',
            _detailController('excluded_amount'),
          ),
        ],
        if (deal.restaurantConfig != null) ...[
          const SizedBox(height: 8),
          _restaurantFields(deal),
        ],
        const SizedBox(height: 12),
        _moneyField('Extras amount (already included above)', _extrasController),
        const SizedBox(height: 12),
        TextField(
          controller: _adjustmentsController,
          maxLines: 2,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Exclusions / adjustments (optional)',
            hintText: 'For example, hash brown excluded',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _refreshQuote(),
        ),
        const SizedBox(height: 12),
        _moneyField('Tip (optional)', _tipController),
      ],
    );
  }

  Widget _summary(PartnerQrDealQuote quote) {
    final enteredPosTotal = _number(_posController);
    final matched = _posController.text.trim().isNotEmpty &&
        (enteredPosTotal - quote.total).abs() <= 0.01;
    return Card(
      color: const Color(0xFFE8F3EF),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Review and confirm',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _summaryRow('Bill before deal', quote.billTotal),
            if (_number(_extrasController) > 0)
              _summaryRow(
                'Extras (included in bill)',
                _number(_extrasController),
              ),
            if (_adjustmentsController.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Adjustments: ${_adjustmentsController.text.trim()}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            _summaryRow('Member savings', -quote.discount),
            if (quote.tip > 0) _summaryRow('Tip', quote.tip),
            const Divider(),
            _summaryRow('Total to match the till', quote.total, bold: true),
            const SizedBox(height: 12),
            _moneyField('Enter the total shown on the till', _posController),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  matched ? Icons.check_circle : Icons.info_outline,
                  color: matched ? _green : Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    matched
                        ? 'Till total matches. You can confirm the redemption.'
                        : 'The till total must match R${quote.total.toStringAsFixed(2)}.',
                    style: TextStyle(
                      color: matched ? _green : Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: matched && !_submitting ? _submit : null,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_outlined),
                label: Text(_submitting ? 'Saving…' : 'Confirm redemption'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, double amount, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Text(
              '${amount < 0 ? '-' : ''}R${amount.abs().toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      );

  Future<void> _submit() async {
    final deal = _selectedDeal;
    final quote = _quoteFor(deal);
    if (deal == null || quote == null || !quote.isValid) return;
    setState(() => _submitting = true);
    try {
      final id = await _service.completeRedemption(
        businessId: widget.businessId,
        redemptionSessionId: widget.redemptionSessionId,
        deal: deal,
        quote: quote,
        posTotal: _number(_posController),
        idempotencyKey: _idempotencyKey,
        extrasAmount: _number(_extrasController),
        checkoutNotes: _adjustmentsController.text,
      );
      if (!mounted) return;
      setState(() {
        _redemptionId = id;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_readableError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  String _readableError(Object error) {
    final text = error.toString();
    final marker = text.indexOf('QR_REDEMPTION_');
    if (marker >= 0) {
      final messageStart = text.indexOf(':', marker);
      if (messageStart >= 0) {
        final messageEnd = text.indexOf(RegExp(r', code:|\)$'), messageStart);
        return text.substring(
          messageStart + 1,
          messageEnd < 0 ? text.length : messageEnd,
        ).trim();
      }
    }
    return text.replaceFirst('Exception: ', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final name = [
      widget.member['name']?.toString() ?? '',
      widget.member['surname']?.toString() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');

    if (_redemptionId != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Redemption complete')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: _green, size: 72),
                const SizedBox(height: 16),
                const Text(
                  'Deal redeemed',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('$name · ${_selectedDeal?.name ?? ''}'),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final quote = _quoteFor(_selectedDeal);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deal redemption'),
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: _loadingDeals
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              (widget.member['profile_photo_url'] as String?)
                                          ?.isNotEmpty ==
                                      true
                                  ? NetworkImage(
                                      widget.member['profile_photo_url'] as String,
                                    )
                                  : null,
                          child:
                              (widget.member['profile_photo_url'] as String?)
                                          ?.isNotEmpty ==
                                      true
                                  ? null
                                  : const Icon(Icons.person),
                        ),
                        title: Text(name.isEmpty ? 'Verified member' : name),
                        subtitle: const Text('Active Local Lekker member'),
                        trailing: const Icon(Icons.verified, color: _green),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _dealSelection(),
                    if (_selectedDeal case final deal?) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                deal.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (deal.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(deal.description),
                              ],
                              _dealInputs(deal),
                            ],
                          ),
                        ),
                      ),
                      if (quote != null) ...[
                        const SizedBox(height: 12),
                        if (!quote.isValid)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              quote.error!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          )
                        else
                          _summary(quote),
                      ],
                    ],
                  ],
                ),
    );
  }
}
