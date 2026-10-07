import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/supabase_service.dart';
import '../../services/cache_service.dart';
import '../../services/discount_service.dart';
import 'trusted_partner_shop_page.dart' as shop;
import 'package:flutter/foundation.dart';
import '../../services/chat_service.dart';
import '../chat/chat_thread_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:local_lekker/core/theme/app_colors.dart';
import '../../core/constants/deal_categories.dart';

class TrustedPartnersByCategoryPage extends StatefulWidget {
  final String? cityFilter;

  const TrustedPartnersByCategoryPage({super.key, this.cityFilter});

  @override
  State<TrustedPartnersByCategoryPage> createState() =>
      _TrustedPartnersByCategoryPageState();
}

class _TrustedPartnersByCategoryPageState
    extends State<TrustedPartnersByCategoryPage> {
  final _categories = <String>[];
  String? _selectedCategory;
  List<Map<String, dynamic>> _partners = [];
  bool _loading = true;
  String? _error;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Deal category filter
  String? _selectedDealCategory;
  static const List<String> _dealCategories = kDealCategories;

  // City filter
  String? _selectedCityFilter;
  List<String> _availableCities = [];

  @override
  void initState() {
    super.initState();
    _selectedCityFilter = widget.cityFilter;
    _searchController.addListener(_onSearchChanged);
    _loadCategories();
    _loadAvailableCities();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  List<Map<String, dynamic>> get _filteredPartners {
    var results = _partners;
    if (_searchQuery.isNotEmpty) {
      results = results.where((p) {
        final name = (p['name'] as String? ?? '').toLowerCase();
        final ownerName = (p['owner_name'] as String? ?? '').toLowerCase();
        final address = (p['address'] as String? ?? '').toLowerCase();
        return name.contains(_searchQuery) ||
            ownerName.contains(_searchQuery) ||
            address.contains(_searchQuery);
      }).toList();
    }
    if (_selectedDealCategory != null) {
      results = results.where((p) {
        final cats = p['deal_categories'] as Set<String>? ?? <String>{};
        return cats.contains(_selectedDealCategory);
      }).toList();
    }
    return results;
  }

  Future<void> _loadAvailableCities() async {
    try {
      final cities = await DiscountService().getAvailableCities();
      if (mounted) {
        setState(() => _availableCities = cities);
      }
    } catch (e) {
      if (kDebugMode) {
        print('\u274c Error loading cities: $e');
      }
    }
  }

  Future<void> _loadCategories() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      // categories are defined in BusinessProfilePage; here we query distinct business categories
      final res = await SupabaseService.instance.client
          .from('businesses')
          .select('category')
          .order('category', ascending: true);

      final cats = <String>{};
      for (final r in res) {
        final c = (r['category'] as String?)?.trim();
        if (c != null && c.isNotEmpty) cats.add(c);
      }

      setState(() {
        _categories.clear();
        _categories.add('All'); // Add "All" option first
        _categories.addAll(cats.toList()..sort());
        _selectedCategory = 'All'; // Default to "All"
      });

      if (_selectedCategory != null) {
        await _loadPartnersForCategory(_selectedCategory!);
      } else {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load categories: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadPartnersForCategory(String category) async {
    if (!mounted) return;

    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final startTime = DateTime.now();
      final cacheService = CacheService.instance;

      // FORCE: Always fetch fresh data to get new social media fields
      // Clear cache to ensure we get updated schema with social media handles
      await cacheService.clearPartnersCache();
      await cacheService.clearDealsCache();

      if (kDebugMode) {
        print(
          '🔄 Cache cleared, fetching fresh partner data with social media fields',
        );
      }

      // Fetch from database
      final query = SupabaseService.instance.client
          .from('businesses')
          .select(
            'id, owner_member_id, name, category, city, address, logo_url, facebook_handle, instagram_handle, website_url, business_email',
          );

      List<dynamic> businesses = category == 'All'
          ? await query.order('name', ascending: true)
          : await query.eq('category', category).order('name', ascending: true);

      // Fetch all deals in ONE query (include deal_category and city for filtering)
      List<dynamic> allDeals = await SupabaseService.instance.client
          .from('trusted_partner_discounts')
          .select('id, trusted_partner_id, deal_category, city')
          .eq('is_active', true);

      // Collect ALL available cities BEFORE applying the city filter
      // so the dropdown always shows every city that has businesses or deals.
      final citiesFromData = <String>{};
      for (final deal in allDeals) {
        final dealCity = (deal['city'] as String?)?.trim();
        if (dealCity != null && dealCity.isNotEmpty) {
          citiesFromData.add(dealCity);
        }
      }
      for (final b in businesses) {
        final bizCity = (b['city'] as String?)?.trim();
        if (bizCity != null && bizCity.isNotEmpty) {
          citiesFromData.add(bizCity);
        }
      }
      if (mounted && citiesFromData.isNotEmpty) {
        setState(() {
          _availableCities = citiesFromData.toList()..sort();
        });
      }

      // Apply city filter if selected (AFTER collecting all cities)
      if (_selectedCityFilter != null && _selectedCityFilter!.isNotEmpty) {
        businesses = businesses
            .where((b) => (b['city'] as String?)?.trim() == _selectedCityFilter)
            .toList();
        if (kDebugMode) {
          print('\uD83C\uDFD9\uFE0F City filter: $_selectedCityFilter -> ${businesses.length} businesses');
        }
      }

      // Cache for next time
      await cacheService.cacheTrustedPartners(
        businesses.cast<Map<String, dynamic>>(),
      );
      await cacheService.cacheDeals(allDeals.cast<Map<String, dynamic>>());

      // Filter by category if needed
      if (category != 'All') {
        businesses = businesses
            .where((b) => b['category'] == category)
            .toList();
      }

      // Get all owner IDs to batch-fetch profiles
      final ownerIds = businesses.map((b) => b['owner_member_id']).toList();

      // Batch fetch ALL profiles in ONE query
      final profiles = ownerIds.isNotEmpty
          ? await SupabaseService.instance.client
                .from('profiles')
                .select('id, name, surname, street, suburb, city, province')
                .inFilter('id', ownerIds)
          : [];

      // Create profile lookup map for O(1) access
      final profileMap = <String, Map<String, dynamic>>{};
      for (final p in profiles) {
        profileMap[p['id']] = p;
      }

      // Create deal count map and deal categories map
      final dealCountMap = <String, int>{};
      final dealCategoriesMap = <String, Set<String>>{};
      for (final deal in allDeals) {
        final partnerId = deal['trusted_partner_id'];
        dealCountMap[partnerId] = (dealCountMap[partnerId] ?? 0) + 1;
        final cat = deal['deal_category'] as String?;
        if (cat != null && cat.isNotEmpty) {
          dealCategoriesMap.putIfAbsent(partnerId, () => <String>{});
          dealCategoriesMap[partnerId]!.add(cat);
        }
      }

      // Build partners list with cached/batched data
      final partners = <Map<String, dynamic>>[];
      for (final b in businesses) {
        final ownerId = b['owner_member_id'];
        final profile = profileMap[ownerId];

        final ownerName = profile != null
            ? '${profile['name']} ${profile['surname']}'
            : 'Business Owner';

        // Build address from components
        final addressParts = <String>[];
        if (profile != null) {
          if (profile['street'] != null &&
              profile['street'].toString().isNotEmpty) {
            addressParts.add(profile['street']);
          }
          if (profile['suburb'] != null &&
              profile['suburb'].toString().isNotEmpty) {
            addressParts.add(profile['suburb']);
          }
          if (profile['city'] != null &&
              profile['city'].toString().isNotEmpty) {
            addressParts.add(profile['city']);
          }
        }
        final address = addressParts.isNotEmpty
            ? addressParts.join(', ')
            : 'No address available';

        final dealCount = dealCountMap[ownerId] ?? 0;

        // Hide trusted partners that currently have no active deals.
        // Expired deals are auto-deactivated by the scheduled-deal-expiry-worker
        // edge function, so a partner with dealCount == 0 has nothing to offer
        // members right now and should not appear in the listing until they
        // publish a new active deal.
        if (dealCount == 0) {
          continue;
        }

        partners.add({
          ...b,
          'owner_name': ownerName,
          'address': address,
          'deal_count': dealCount,
          'deal_categories': dealCategoriesMap[ownerId] ?? <String>{},
        });
      }

      final duration = DateTime.now().difference(startTime);
      if (kDebugMode) {
        print(
          '✅ Loaded ${partners.length} partners in ${duration.inMilliseconds}ms',
        );
      }

      if (mounted) {
        setState(() {
          _partners = partners;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load partners: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openPartnerChat(Map<String, dynamic> partner) async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) throw Exception('Not authenticated');
      final partnerUserId = partner['owner_member_id'] as String?;
      if (partnerUserId == null || partnerUserId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Partner is missing an owner account.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final convo = await ChatService.instance
          .getOrCreateConversationWithPartner(user.id, partnerUserId);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) {
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 520,
              height: 640,
              child: ChatThreadPage(conversationId: convo.id),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open chat: $e')));
      }
    }
  }

  bool _hasSocialMedia(Map<String, dynamic> partner) {
    return (partner['facebook_handle'] != null &&
            (partner['facebook_handle'] as String).isNotEmpty) ||
        (partner['instagram_handle'] != null &&
            (partner['instagram_handle'] as String).isNotEmpty) ||
        (partner['website_url'] != null &&
            (partner['website_url'] as String).isNotEmpty) ||
        (partner['business_email'] != null &&
            (partner['business_email'] as String).isNotEmpty);
  }

  String _formatFacebookUrl(String handle) {
    if (handle.startsWith('http://') || handle.startsWith('https://')) {
      return handle;
    } else if (handle.startsWith('facebook.com/') ||
        handle.startsWith('www.facebook.com/')) {
      return 'https://$handle';
    } else if (handle.startsWith('@')) {
      return 'https://facebook.com/${handle.substring(1)}';
    } else {
      return 'https://facebook.com/$handle';
    }
  }

  String _formatInstagramUrl(String handle) {
    if (handle.startsWith('http://') || handle.startsWith('https://')) {
      return handle;
    } else if (handle.startsWith('instagram.com/') ||
        handle.startsWith('www.instagram.com/')) {
      return 'https://$handle';
    } else if (handle.startsWith('@')) {
      return 'https://instagram.com/${handle.substring(1)}';
    } else {
      return 'https://instagram.com/$handle';
    }
  }

  Future<void> _launchUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (kDebugMode) {
          print('Could not launch $urlString');
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not open $urlString')));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error launching URL: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening link: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Trusted Partners'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadCategories();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadCategories,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search bar
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by partner name...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Deal category filter
                  const Text(
                    'Filter by deal category',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedDealCategory,
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('All Deal Categories'),
                      ),
                      ..._dealCategories.map(
                        (cat) => DropdownMenuItem(
                          value: cat,
                          child: Text(cat),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _selectedDealCategory = v;
                      });
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(
                        Icons.local_offer,
                        color: _selectedDealCategory != null
                            ? AppColors.primary
                            : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Region Filter
                  const Text(
                    'Filter by region',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedCityFilter,
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('All Regions'),
                      ),
                      ..._availableCities.map(
                        (city) => DropdownMenuItem(
                          value: city,
                          child: Text(city),
                        ),
                      ),
                    ],
                    onChanged: (v) async {
                      setState(() {
                        _selectedCityFilter = v;
                      });
                      await _loadPartnersForCategory(
                        _selectedCategory ?? 'All',
                      );
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(
                        Icons.location_on,
                        color: _selectedCityFilter != null
                            ? AppColors.primary
                            : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _filteredPartners.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isNotEmpty
                                  ? 'No partners match "$_searchQuery"'
                                  : 'No partners found in this category',
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredPartners.length,
                            itemBuilder: (context, index) {
                              final p = _filteredPartners[index];
                              final dealCount = p['deal_count'] ?? 0;
                              final logoUrl = p['logo_url'] as String?;
                              String displayUrl(String url) {
                                // Extract timestamp from logo filename
                                final match = RegExp(
                                  r'logo_(\d+)\.',
                                ).firstMatch(url);
                                final token =
                                    match?.group(1) ??
                                    DateTime.now().millisecondsSinceEpoch
                                        .toString();
                                return url.contains('?')
                                    ? '$url&t=$token'
                                    : '$url?t=$token';
                              }

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  leading: logoUrl != null && logoUrl.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.network(
                                            displayUrl(logoUrl),
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return Container(
                                                    width: 48,
                                                    height: 48,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.blue.shade100,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: const Icon(
                                                      Icons.business,
                                                      color: Colors.blue,
                                                    ),
                                                  );
                                                },
                                          ),
                                        )
                                      : Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade100,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.business,
                                            color: Colors.blue,
                                          ),
                                        ),
                                  title: Text(
                                    p['name'] ?? 'Unknown',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        p['address'] ?? 'No address available',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '$dealCount ${dealCount == 1 ? 'deal' : 'deals'} available',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.green,
                                        ),
                                      ),
                                      // Social media icons
                                      if (_hasSocialMedia(p)) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            if (p['facebook_handle'] != null &&
                                                (p['facebook_handle'] as String)
                                                    .isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: InkWell(
                                                  onTap: () => _launchUrl(
                                                    _formatFacebookUrl(
                                                      p['facebook_handle'],
                                                    ),
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Icon(
                                                    Icons.facebook,
                                                    size: 20,
                                                    color: const Color(
                                                      0xFF1877F2,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (p['instagram_handle'] != null &&
                                                (p['instagram_handle']
                                                        as String)
                                                    .isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: InkWell(
                                                  onTap: () => _launchUrl(
                                                    _formatInstagramUrl(
                                                      p['instagram_handle'],
                                                    ),
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Icon(
                                                    Icons.camera_alt,
                                                    size: 20,
                                                    color: const Color(
                                                      0xFFE4405F,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (p['website_url'] != null &&
                                                (p['website_url'] as String)
                                                    .isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: InkWell(
                                                  onTap: () => _launchUrl(
                                                    p['website_url'],
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Icon(
                                                    Icons.language,
                                                    size: 20,
                                                    color: const Color(
                                                      0xFF4CAF50,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (p['business_email'] != null &&
                                                (p['business_email'] as String)
                                                    .isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: InkWell(
                                                  onTap: () => _launchUrl(
                                                    'mailto:${p['business_email']}',
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Icon(
                                                    Icons.email,
                                                    size: 20,
                                                    color: const Color(
                                                      0xFFFF9800,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Chat',
                                        icon: const Icon(Icons.chat_bubble),
                                        onPressed: () => _openPartnerChat(p),
                                      ),
                                      const Icon(Icons.chevron_right),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            shop.TrustedPartnerShopPage(
                                              partner: p,
                                            ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
