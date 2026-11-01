import 'package:flutter/material.dart';

import 'fresh_local_banner.dart';
import 'local_eats_banner.dart';
import 'local_sips_banner.dart';
import 'locally_active_banner.dart';
import 'partners_banner.dart';

/// Member-home entry row: Partners is always shown, with Fresh & Local,
/// Local Sips and Locally Active joining it only when qualifying partners
/// exist. One banner fills the full width, others split it evenly.
class MemberCategoryBannerRow extends StatelessWidget {
  final VoidCallback onTapPartners;
  final int partnerCount;
  final int dealCount;

  final bool showFreshLocal;
  final VoidCallback onTapFreshLocal;
  final int freshNewDeals;
  final int freshPartnerCount;
  final int freshDealCount;

  final bool showLocalSips;
  final VoidCallback onTapLocalSips;
  final int sipsNewDeals;
  final int sipsPartnerCount;
  final int sipsDealCount;

  final bool showLocalEats;
  final VoidCallback onTapLocalEats;
  final int eatsNewDeals;
  final int eatsPartnerCount;
  final int eatsDealCount;

  final bool showLocallyActive;
  final VoidCallback onTapLocallyActive;
  final int activeNewDeals;
  final int activePartnerCount;
  final int activeDealCount;

  const MemberCategoryBannerRow({
    super.key,
    required this.onTapPartners,
    this.partnerCount = 0,
    this.dealCount = 0,
    this.showFreshLocal = false,
    required this.onTapFreshLocal,
    this.freshNewDeals = 0,
    this.freshPartnerCount = 0,
    this.freshDealCount = 0,
    this.showLocalSips = false,
    required this.onTapLocalSips,
    this.sipsNewDeals = 0,
    this.sipsPartnerCount = 0,
    this.sipsDealCount = 0,
    this.showLocalEats = false,
    required this.onTapLocalEats,
    this.eatsNewDeals = 0,
    this.eatsPartnerCount = 0,
    this.eatsDealCount = 0,
    this.showLocallyActive = false,
    required this.onTapLocallyActive,
    this.activeNewDeals = 0,
    this.activePartnerCount = 0,
    this.activeDealCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final compact =
      showFreshLocal || showLocalSips || showLocalEats || showLocallyActive;

    final banners = <Widget>[
      PartnersBanner(
        onTap: onTapPartners,
        partnerCount: partnerCount,
        dealCount: dealCount,
        compact: compact,
      ),
      if (showFreshLocal)
        FreshLocalBanner(
          onTap: onTapFreshLocal,
          newDealCount: freshNewDeals,
          partnerCount: freshPartnerCount,
          dealCount: freshDealCount,
          compact: true,
        ),
      if (showLocalSips)
        LocalSipsBanner(
          onTap: onTapLocalSips,
          newDealCount: sipsNewDeals,
          partnerCount: sipsPartnerCount,
          dealCount: sipsDealCount,
          compact: true,
        ),
      if (showLocalEats)
        LocalEatsBanner(
          onTap: onTapLocalEats,
          newDealCount: eatsNewDeals,
          partnerCount: eatsPartnerCount,
          dealCount: eatsDealCount,
          compact: true,
        ),
      if (showLocallyActive)
        LocallyActiveBanner(
          onTap: onTapLocallyActive,
          newDealCount: activeNewDeals,
          partnerCount: activePartnerCount,
          dealCount: activeDealCount,
          compact: true,
        ),
    ];

    if (banners.length > 4) {
      Widget buildBannerRow(int start, int end) => Row(
        children: [
          for (var i = start; i < end; i++) ...[
            if (i > start) const SizedBox(width: 8),
            Expanded(child: banners[i]),
          ],
        ],
      );

      return SizedBox(
        height: 272,
        child: Column(
          children: [
            Expanded(child: buildBannerRow(0, 3)),
            const SizedBox(height: 8),
            Expanded(child: buildBannerRow(3, banners.length)),
          ],
        ),
      );
    }

    if (banners.length == 1) return banners.first;

    return SizedBox(
      height: 132,
      child: Row(
        children: [
          for (var i = 0; i < banners.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: banners[i]),
          ],
        ],
      ),
    );
  }
}
