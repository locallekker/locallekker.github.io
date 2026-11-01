import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';

class MemberReceiptsPage extends StatefulWidget {
  const MemberReceiptsPage({super.key});

  @override
  State<MemberReceiptsPage> createState() => _MemberReceiptsPageState();
}

class _MemberReceiptsPageState extends State<MemberReceiptsPage> {
  final Logger _logger = Logger();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _receipts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReceipts();
  }

  Future<void> _loadReceipts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      _logger.i('Loading receipts for user: ${user.id}');

      final response = await _supabase
          .from('deal_receipts')
          .select()
          .eq('member_id', user.id)
          .order('created_at', ascending: false);

      _logger.i('Loaded ${response.length} receipts');

      setState(() {
        _receipts = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      _logger.e('Error loading receipts: $e');
      setState(() {
        _errorMessage = 'Failed to load receipts: $e';
        _isLoading = false;
      });
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateString).toLocal();
      return DateFormat('dd MMM yyyy, HH:mm').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return 'R0.00';
    try {
      final double value = amount is String
          ? double.parse(amount)
          : amount.toDouble();
      return 'R${value.toStringAsFixed(2)}';
    } catch (e) {
      return 'R0.00';
    }
  }

  void _showReceiptDetails(Map<String, dynamic> receipt) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: Colors.green),
            const SizedBox(width: 8),
            const Text('Receipt Details'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                'Receipt Number',
                receipt['receipt_number'] ?? 'N/A',
              ),
              const Divider(),
              _buildDetailRow('Business', receipt['business_name'] ?? 'N/A'),
              _buildDetailRow(
                'Business Contact',
                receipt['business_contact'] ?? 'N/A',
              ),
              _buildDetailRow(
                'Business Email',
                receipt['business_email'] ?? 'N/A',
              ),
              _buildDetailRow('Discount', receipt['discount_name'] ?? 'N/A'),
              const Divider(),
              _buildDetailRow('Amount', _formatAmount(receipt['amount'])),
              _buildDetailRow(
                'Payment Method',
                receipt['payment_method'] ?? 'N/A',
              ),
              if (receipt['payment_method'] == 'pos') ...[
                _buildDetailRow('Note', 'in-store payment'),
              ],
              const Divider(),
              _buildDetailRow('Date', _formatDate(receipt['created_at'])),
              const Divider(),
              _buildDetailRow('Member', receipt['member_name'] ?? 'N/A'),
              _buildDetailRow('Email', receipt['member_email'] ?? 'N/A'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('My Receipts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReceipts,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadReceipts,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _receipts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Receipts Yet',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your receipts will appear here after\ntrusted partners issue them',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadReceipts,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _receipts.length,
                itemBuilder: (context, index) {
                  final receipt = _receipts[index];
                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: Colors.green,
                        child: const Icon(Icons.receipt, color: Colors.white),
                      ),
                      title: Text(
                        receipt['business_name'] ?? 'Business',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            'Receipt: ${receipt['receipt_number'] ?? 'N/A'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Discount: ${receipt['discount_name'] ?? 'N/A'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(receipt['created_at']),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatAmount(receipt['amount']),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                      onTap: () => _showReceiptDetails(receipt),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
