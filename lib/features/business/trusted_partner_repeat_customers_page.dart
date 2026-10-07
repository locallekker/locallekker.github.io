import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../../services/supabase_service.dart';
import '../../widgets/branded_app_bar.dart';

class TrustedPartnerRepeatCustomersPage extends StatefulWidget {
  const TrustedPartnerRepeatCustomersPage({super.key});

  @override
  State<TrustedPartnerRepeatCustomersPage> createState() =>
      _TrustedPartnerRepeatCustomersPageState();
}

class _TrustedPartnerRepeatCustomersPageState
    extends State<TrustedPartnerRepeatCustomersPage> {
  final Logger _logger = Logger();
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _customers = [];

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) {
        throw Exception('No authenticated user');
      }

      final business = await SupabaseService.instance.client
          .from('businesses')
          .select('id')
          .eq('owner_member_id', user.id)
          .maybeSingle();

      if (business == null) {
        throw Exception('No business found for this user');
      }

      final businessId = business['id'] as String;

      final response = await SupabaseService.instance.client
          .from('deal_authorizations')
          .select('member_id, profiles(name, surname, email)')
          .eq('business_id', businessId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(500);

      final memberCounts = <String, int>{};
      final memberProfiles = <String, Map<String, dynamic>>{};
      
      for (final row in response) {
        final memberId = row['member_id'] as String?;
        if (memberId == null) continue;
        final profile = row['profiles'] as Map<String, dynamic>?;
        
        memberCounts[memberId] = (memberCounts[memberId] ?? 0) + 1;
        memberProfiles[memberId] = {
          'name': profile?['name'] ?? 'Unknown',
          'surname': profile?['surname'] ?? '',
          'email': profile?['email'] ?? 'No email',
        };
      }
      
      final customers = <Map<String, dynamic>>[];
      for (final memberId in memberCounts.keys) {
        if (memberCounts[memberId]! >= 2) {
          final profile = memberProfiles[memberId]!;
          customers.add({
            'member_id': memberId,
            'name': profile['name'],
            'surname': profile['surname'],
            'email': profile['email'],
            'count': memberCounts[memberId],
          });
        }
      }
      customers.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      setState(() {
        _customers = customers;
        _isLoading = false;
      });
    } catch (e, st) {
      _logger.e('Failed to load repeat customers: $e', error: e, stackTrace: st);
      setState(() {
        _errorMessage = 'Failed to load repeat customers: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Repeat Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCustomers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildError()
          : _customers.isEmpty
          ? _buildEmpty()
          : _buildList(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadCustomers,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('No repeat customers yet'),
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      itemCount: _customers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final c = _customers[index];
        final name = '${c['name'] ?? ''} ${c['surname'] ?? ''}'.trim();
        final email = c['email'] ?? 'No email';
        final count = c['count'] ?? 0;

        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(name.isEmpty ? 'Unknown' : name),
          subtitle: Text('$email • $count purchases'),
          trailing: IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Chat with $name'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
