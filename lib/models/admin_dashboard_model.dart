/// AdminDashboard model (renamed to clarify purpose).
/// This file was renamed from `admin_dashboard.dart` to
/// `admin_dashboard_model.dart` to avoid confusion with the
/// admin dashboard UI screen.
class AdminDashboard {
  final int totalMembers;
  final int totalTrustedPartners;
  final double totalOnlinePurchases;
  final double totalInStorePurchases;
  final List<Map<String, dynamic>> categorySummary;
  final Map<String, List<Map<String, dynamic>>> categoryDetails;

  AdminDashboard({
    required this.totalMembers,
    required this.totalTrustedPartners,
    required this.totalOnlinePurchases,
    required this.totalInStorePurchases,
    required this.categorySummary,
    required this.categoryDetails,
  });

  factory AdminDashboard.fromMap(Map<String, dynamic> m) {
    final cs =
        (m['category_summary'] as List?)?.map((e) {
          if (e is Map) return Map<String, dynamic>.from(e);
          return <String, dynamic>{};
        }).toList() ??
        <Map<String, dynamic>>[];

    final cdRaw = m['category_details'] as Map?;
    final cd = <String, List<Map<String, dynamic>>>{};
    if (cdRaw != null) {
      cdRaw.forEach((k, v) {
        if (v is List) {
          cd[k.toString()] = v
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      });
    }

    return AdminDashboard(
      totalMembers: (m['total_members'] ?? 0) as int,
      totalTrustedPartners: (m['total_trusted_partners'] ?? 0) as int,
      totalOnlinePurchases: (m['total_online_purchases'] ?? 0).toDouble(),
      totalInStorePurchases: (m['total_in_store_purchases'] ?? 0).toDouble(),
      categorySummary: cs.cast<Map<String, dynamic>>(),
      categoryDetails: cd,
    );
  }
}
