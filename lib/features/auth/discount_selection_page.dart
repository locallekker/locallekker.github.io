import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../models/discount.dart';
import '../../services/discount_service.dart';
import '../../services/supabase_service.dart';

class DiscountSelectionPage extends StatefulWidget {
  final String userName;
  final String userSurname;

  const DiscountSelectionPage({
    super.key,
    required this.userName,
    required this.userSurname,
  });

  @override
  State<DiscountSelectionPage> createState() => _DiscountSelectionPageState();
}

class _DiscountSelectionPageState extends State<DiscountSelectionPage> {
  final DiscountService _discountService = DiscountService();
  List<Discount> _discounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDiscounts();
  }

  Future<void> _loadDiscounts() async {
    setState(() => _isLoading = true);
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user != null) {
        final discounts = await _discountService.getTrustedPartnerDiscounts(
          user.id,
        );
        setState(() => _discounts = discounts);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load discounts: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyDiscount(Discount discount) {
    // Here you would implement the logic to apply the discount
    // For now, we'll just show a confirmation and go back
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${discount.name} applied to ${widget.userName} ${widget.userSurname}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );

    // Navigate back to the merchant home page
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Apply Discount'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // User info header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.person, size: 32, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.userName} ${widget.userSurname}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Select a discount to apply',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Discount list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _discounts.isEmpty
                ? _buildEmptyState()
                : _buildDiscountList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.discount_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No discounts available',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create discounts in the discount management section',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _discounts.length,
      itemBuilder: (context, index) {
        final discount = _discounts[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(discount.name),
            subtitle: Text(discount.description),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                discount.discountDisplay,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
            onTap: () => _applyDiscount(discount),
          ),
        );
      },
    );
  }
}
