import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/supabase_service.dart';
import 'trusted_partner_shop_page.dart';
import 'package:flutter/foundation.dart';

class TrustedPartnersPage extends StatefulWidget {
  const TrustedPartnersPage({super.key});

  @override
  State<TrustedPartnersPage> createState() => _TrustedPartnersPageState();
}

class _TrustedPartnersPageState extends State<TrustedPartnersPage> {
  List<Map<String, dynamic>> _trustedPartners = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrustedPartners();
  }

  Future<void> _loadTrustedPartners() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      if (kDebugMode) {
        print('🔍 Loading trusted partners...');
      }

      // Get all businesses (trusted partners)
      final businesses = await SupabaseService.instance.client
          .from('businesses')
          .select('id, owner_member_id, name, category, address, created_at')
          .order('name', ascending: true);

      if (kDebugMode) {
        print('📊 Found ${businesses.length} businesses in database');
      }

      // Get profile information for each business owner
      final trustedPartners = <Map<String, dynamic>>[];
      for (final business in businesses) {
        if (kDebugMode) {
          print(
            '🏢 Processing business: ${business['name']} (owner: ${business['owner_member_id']})',
          );
        }

        final profile = await SupabaseService.instance.client
            .from('profiles')
            .select('name, surname')
            .eq('id', business['owner_member_id'])
            .maybeSingle();

        // Always add the business, even if owner profile doesn't exist
        final ownerName = profile != null
            ? '${profile['name']} ${profile['surname']}'
            : 'Business Owner';

        trustedPartners.add({...business, 'owner_name': ownerName});

        if (profile != null) {
          if (kDebugMode) {
            print(
              '✅ Added trusted partner: ${business['name']} - ${profile['name']} ${profile['surname']}',
            );
          }
        } else {
          if (kDebugMode) {
            print(
              '⚠️ No profile found for business owner: ${business['owner_member_id']}, showing as "Business Owner"',
            );
          }
        }
      }

      if (kDebugMode) {
        print(
          '📋 Final trusted partners list: ${trustedPartners.length} partners',
        );
      }

      setState(() {
        _trustedPartners = trustedPartners;
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading trusted partners: $e');
      }
      setState(() {
        _error = 'Failed to load trusted partners: $e';
        _isLoading = false;
      });
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
            onPressed: _loadTrustedPartners,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadTrustedPartners,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _trustedPartners.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.business, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No trusted partners found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _trustedPartners.length,
              itemBuilder: (context, index) {
                final partner = _trustedPartners[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(
                      partner['name'] ?? 'Unknown Business',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Owner: ${partner['owner_name']}'),
                        if (partner['category'] != null &&
                            partner['category'].toString().isNotEmpty)
                          Text('Category: ${partner['category']}'),
                        if (partner['address'] != null &&
                            partner['address'].toString().isNotEmpty)
                          Text(
                            partner['address'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to trusted partner shop page
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              TrustedPartnerShopPage(partner: partner),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
