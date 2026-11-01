import 'package:flutter/material.dart';
import 'package:local_lekker/core/theme/app_colors.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../core/constants/deal_categories.dart';
import '../../services/discount_service.dart';
import '../auth/trusted_partner_shop_page.dart';

/// Member listing of trusted partners in the Locally Active sport/fitness category.
class LocallyActivePartnersPage extends StatefulWidget {
  final String? cityFilter;

  const LocallyActivePartnersPage({super.key, this.cityFilter});

  @override
  State<LocallyActivePartnersPage> createState() =>
      _LocallyActivePartnersPageState();
}

class _LocallyActivePartnersPageState
    extends State<LocallyActivePartnersPage> {
  final DiscountService _discountService = DiscountService();
  List<Map<String, dynamic>> _partners = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPartners();
  }

  Future<void> _loadPartners() async {
    setState(() => _isLoading = true);
    final partners = await _discountService.getLocallyActivePartners(
      city: widget.cityFilter,
    );
    if (!mounted) return;
    setState(() {
      _partners = partners;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BrandedAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_soccer, size: 22),
            SizedBox(width: 8),
            Text(kLocallyActiveCategory),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadPartners,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _partners.isEmpty
            ? _buildEmptyState()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: _partners.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) return _buildIntro();
                  return _buildPartnerCard(_partners[index - 1]);
                },
              ),
      ),
    );
  }

  Widget _buildIntro() {
    return Text(
      'Sport clubs, coaches and fitness partners near you.',
      style: TextStyle(
        fontSize: 13,
        color: AppColors.textSecondary,
        height: 1.4,
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.sports_soccer_outlined,
          size: 64,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 16),
        const Text(
          'No Locally Active partners yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          widget.cityFilter == null
              ? 'Check back soon.'
              : 'No partners in ${widget.cityFilter}. Try changing your area.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildPartnerCard(Map<String, dynamic> partner) {
    final name = (partner['name'] as String?) ?? 'Partner';
    final description = (partner['sports_description'] as String?)?.trim();
    final logoUrl = (partner['logo_url'] as String?)?.trim();
    final city = (partner['city'] as String?)?.trim();
    final dealCount = (partner['deal_count'] as int?) ?? 0;
    final delivers = (partner['offers_delivery'] as bool?) ?? false;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrustedPartnerShopPage(partner: partner),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outline),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLogo(logoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildChip(
                        Icons.local_offer_outlined,
                        dealCount == 1 ? '1 item' : '$dealCount items',
                        AppColors.accent,
                      ),
                      if (city != null && city.isNotEmpty)
                        _buildChip(
                          Icons.location_on_outlined,
                          city,
                          AppColors.primary,
                        ),
                      if (delivers)
                        _buildChip(
                          Icons.delivery_dining,
                          'Delivers',
                          AppColors.success,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(String? logoUrl) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF0288D1).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl == null || logoUrl.isEmpty
          ? const Icon(Icons.storefront_outlined, color: Color(0xFF0288D1))
          : Image.network(
              logoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.storefront_outlined,
                color: Color(0xFF0288D1),
              ),
            ),
    );
  }

  Widget _buildChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
