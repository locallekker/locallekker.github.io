import 'package:flutter/material.dart';

import '../../core/constants/deal_categories.dart';
import '../../models/discount.dart';
import '../auth/discount_management_page.dart';
import '../business/restaurant_deal_dialog.dart';
import 'booking_redirect_deal_dialog.dart';
import 'website_redirect_deal_dialog.dart';

class PartnerDealReviewDialog extends StatefulWidget {
  final String partnerId;
  final String? lockedCategory;
  final String website;
  final List<Discount> deals;

  const PartnerDealReviewDialog({
    super.key,
    required this.partnerId,
    required this.lockedCategory,
    required this.website,
    required this.deals,
  });

  @override
  State<PartnerDealReviewDialog> createState() =>
      _PartnerDealReviewDialogState();
}

class _PartnerDealReviewDialogState extends State<PartnerDealReviewDialog> {
  final Map<String, Map<String, dynamic>> _drafts = {};

  Future<void> _review(Discount original) async {
    String? category = widget.lockedCategory;
    String? family;
    final selected = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Review ${original.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.lockedCategory == null)
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Deal category'),
                  items: [
                    for (final item in kDealCategories)
                      DropdownMenuItem(value: item, child: Text(item)),
                  ],
                  onChanged: (value) => update(() {
                    category = value;
                    family = null;
                  }),
                )
              else
                Text('Deal category: ${widget.lockedCategory}'),
              DropdownButtonFormField<String>(
                key: ValueKey(category),
                initialValue: family,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Deal type group'),
                items: [
                  if (category != kLocalEatsCategory)
                    const DropdownMenuItem(value: 'standard', child: Text('Standard deals')),
                  const DropdownMenuItem(value: 'restaurant', child: Text('Restaurant deals')),
                  const DropdownMenuItem(value: 'website', child: Text('Website redirect')),
                  if (widget.lockedCategory == kLocallyActiveCategory)
                    const DropdownMenuItem(value: 'booking', child: Text('Booking redirect')),
                ],
                onChanged: (value) => update(() => family = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: category == null || family == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    if (selected != true || !mounted) return;

    final draft = _drafts[original.id];
    final current = draft == null
        ? original
        : Discount.fromJson({...original.toJson(), ...draft});
    Map<String, dynamic>? details;
    if (family == 'standard') {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => EditDiscountDialog(
          discount: current,
          trustedPartnerId: widget.partnerId,
          lockedDealCategory: category,
          reviewMode: true,
        ),
      );
      if (result != null) {
        details = {
          'name': result['name'],
          'description': result['description'],
          'item_name': result['itemName'],
          'item_price': result['itemPrice'],
          'percentage': result['percentage'],
          'fixed_amount': result['fixedAmount'],
          'deal_type': result['dealType'],
          'custom_data': result['customData'],
          'requires_manual_price': result['requiresManualPrice'],
          'is_weight_based': result['isWeightBased'],
          'is_bill_discount': result['isBillDiscount'],
          'is_once_off': result['isOnceOff'],
          'bill_discount_data': result['billDiscountData'],
          'image_url': result['imageUrl'],
          'schedule_data': result['scheduleData'],
          'deal_category': result['dealCategory'],
          'offers_delivery': result['offersDelivery'],
        };
      }
    } else {
      details = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          if (family == 'restaurant') {
            return RestaurantDealDialog(
              trustedPartnerId: widget.partnerId,
              existing: current,
              lockedDealCategory: category,
              reviewMode: true,
            );
          }
          if (family == 'booking') {
            return BookingRedirectDealDialog(
              trustedPartnerId: widget.partnerId,
              existing: current,
              reviewMode: true,
            );
          }
          return WebsiteRedirectDealDialog(
            trustedPartnerId: widget.partnerId,
            existing: current,
            lockedDealCategory: category,
            websiteForReview: widget.website,
            reviewMode: true,
          );
        },
      );
    }
    if (details != null && mounted) {
      setState(() => _drafts[original.id] = details!);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review existing deals'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Review every deal for the new category. Nothing is saved until '
            'the partner and all deals are saved together. Resolve pending '
            'requests and payments first.',
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final deal in widget.deals)
                  ListTile(
                    title: Text(deal.name),
                    subtitle: Text(_drafts.containsKey(deal.id)
                        ? 'Reviewed'
                        : 'Needs review (${deal.dealType})'),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _review(deal),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      ElevatedButton(
        onPressed: _drafts.length != widget.deals.length
            ? null
            : () => Navigator.pop(context, [
                for (final deal in widget.deals)
                  {
                    'id': deal.id,
                    'updated_at': deal.databaseUpdatedAt,
                    'details': _drafts[deal.id],
                  },
              ]),
        child: const Text('Save partner and deals'),
      ),
    ],
  );
}
