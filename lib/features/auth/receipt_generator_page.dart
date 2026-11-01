import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../models/virtual_receipt.dart';
import '../../services/discount_service.dart';
import '../../services/supabase_service.dart';
import '../../core/utils/display_name_helpers.dart';
import 'package:flutter/foundation.dart';

class ReceiptGeneratorPage extends StatefulWidget {
  final String dealAuthorizationId;

  const ReceiptGeneratorPage({super.key, required this.dealAuthorizationId});

  @override
  State<ReceiptGeneratorPage> createState() => _ReceiptGeneratorPageState();
}

class _ReceiptGeneratorPageState extends State<ReceiptGeneratorPage> {
  final DiscountService _discountService = DiscountService();
  VirtualReceipt? _virtualReceipt;
  bool _isLoading = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadOrGenerateReceipt();
  }

  Future<void> _loadOrGenerateReceipt() async {
    setState(() => _isLoading = true);
    try {
      // First try to load existing receipt
      final receipts = await _discountService.getVirtualReceiptsForDeal(
        widget.dealAuthorizationId,
      );
      if (receipts.isNotEmpty) {
        setState(() => _virtualReceipt = receipts.first);
      } else {
        // Generate new receipt if none exists
        await _generateReceipt();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading receipt: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _generateReceipt() async {
    setState(() => _isGenerating = true);
    try {
      if (kDebugMode) {

        print('🧾 Fetching deal authorization: ${widget.dealAuthorizationId}');

      }

      // Get deal authorization details
      final dealResponse = await SupabaseService.instance.client
          .from('deal_authorizations')
          .select('''
            *,
            trusted_partner_discounts (
              name,
              business_id,
              businesses (
                name,
                owner_member_id
              )
            ),
            profiles!deal_authorizations_member_id_fkey (
              name,
              surname,
              email
            )
          ''')
          .eq('id', widget.dealAuthorizationId)
          .single();

      if (kDebugMode) {


        print('🧾 Deal response: $dealResponse');


      }

      final dealData = dealResponse;
      final discountData = dealData['trusted_partner_discounts'];
      if (kDebugMode) {

        print('🧾 Discount data: $discountData');

      }

      final businessData = discountData?['businesses'];
      if (kDebugMode) {

        print('🧾 Business data: $businessData');

      }

      final memberData = dealData['profiles'];
      if (kDebugMode) {

        print('🧾 Member data: $memberData');

      }

      // Get business ID for sequential receipt numbering
      final businessId = discountData?['business_id'] as String?;
      if (kDebugMode) {

        print('🧾 Business ID: $businessId');

      }

      // Generate sequential receipt number using database function
      String receiptNumber;
      if (businessId != null) {
        try {
          final result = await SupabaseService.instance.client.rpc(
            'get_next_receipt_number',
            params: {'p_business_id': businessId},
          );
          receiptNumber = result as String;
          if (kDebugMode) {

            print('🧾 Generated sequential receipt number: $receiptNumber');

          }
        } catch (e) {
          if (kDebugMode) {

            print('⚠️ Error generating sequential number, using fallback: $e');

          }
          receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';
        }
      } else {
        receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';
      }

      final qrCode = 'RECEIPT:${widget.dealAuthorizationId}:$receiptNumber';

      // Determine actual payment method from deal data
      String paymentMethod = 'unknown';
      if (dealData['payment_completed_at'] != null) {
        // If payment_completed_at is set, it was paid via in-app payment (Paystack)
        paymentMethod = 'in_app';
      } else if (dealData['payment_method'] != null) {
        paymentMethod = dealData['payment_method'];
      }
      if (kDebugMode) {

        print('🧾 Payment method: $paymentMethod');

      }

      // Resolve names robustly: members may have an empty profile name (fall
      // back to email); the business name falls back to a direct lookup.
      final memberDisplayName = buildMemberDisplayName(
        name: memberData?['name'] as String?,
        surname: memberData?['surname'] as String?,
        email: memberData?['email'] as String?,
      );
      String? resolvedBusinessName = businessData?['name'] as String?;
      if ((resolvedBusinessName ?? '').trim().isEmpty && businessId != null) {
        try {
          final bizRow = await SupabaseService.instance.client
              .from('businesses')
              .select('name')
              .eq('id', businessId)
              .maybeSingle();
          resolvedBusinessName = bizRow?['name'] as String?;
        } catch (_) {}
      }
      final businessDisplayName = buildBusinessDisplayName(resolvedBusinessName);

      final receiptData = {
        'receipt_number': receiptNumber,
        'deal_authorization_id': widget.dealAuthorizationId,
        'business_name': businessDisplayName,
        'business_id': businessId,
        'member_name': memberDisplayName,
        'member_email': memberData?['email'] ?? 'N/A',
        'discount_name': discountData?['name'] ?? 'Unknown Deal',
        'amount': dealData['amount'] ?? 0.0,
        'payment_method': paymentMethod,
        'transaction_date': DateTime.now().toUtc().toIso8601String(),
        'status': 'completed',
      };

      if (kDebugMode) {


        print('🧾 Receipt data prepared: $receiptData');


      }

      // Create virtual receipt
      final virtualReceipt = await _discountService.createVirtualReceipt(
        dealAuthorizationId: widget.dealAuthorizationId,
        receiptNumber: receiptNumber,
        receiptData: receiptData,
        qrCode: qrCode,
      );

      setState(() => _virtualReceipt = virtualReceipt);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt generated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating receipt: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Receipt Generator'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_virtualReceipt != null)
            IconButton(
              onPressed: _shareReceipt,
              icon: const Icon(Icons.share),
              tooltip: 'Share Receipt',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _virtualReceipt != null
          ? _buildReceiptView()
          : _buildGenerationView(),
    );
  }

  Widget _buildGenerationView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'Generate Receipt',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a digital receipt for this completed transaction',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 200,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generateReceipt,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add),
              label: Text(_isGenerating ? 'Generating...' : 'Generate Receipt'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptView() {
    final receiptData = _virtualReceipt!.receiptData;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Receipt Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  Icons.receipt,
                  size: 48,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'OFFICIAL RECEIPT',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  receiptData['receipt_number'] ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Receipt Details
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(
                  'Business',
                  receiptData['business_name'] ?? 'N/A',
                ),
                const Divider(),
                _buildDetailRow(
                  'Customer',
                  receiptData['member_name'] ?? 'N/A',
                ),
                const Divider(),
                _buildDetailRow('Deal', receiptData['discount_name'] ?? 'N/A'),
                const Divider(),
                _buildDetailRow(
                  'Amount',
                  'R${(receiptData['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                ),
                const Divider(),
                _buildDetailRow(
                  'Payment Method',
                  (receiptData['payment_method'] as String?)?.toUpperCase() ??
                      'N/A',
                ),
                const Divider(),
                _buildDetailRow(
                  'Date',
                  _formatDate(
                    DateTime.parse(receiptData['transaction_date']).toLocal(),
                  ),
                ),
                const Divider(),
                _buildDetailRow(
                  'Time',
                  _formatTime(
                    DateTime.parse(receiptData['transaction_date']).toLocal(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // QR Code
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'Scan QR Code',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Members can scan this code to save the receipt',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: _virtualReceipt!.qrCode ?? 'No QR Code',
                    version: QrVersions.auto,
                    size: 200.0,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Receipt ID: ${_virtualReceipt!.id.substring(0, 8)}...',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Action Buttons
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _downloadReceiptAsPdf,
                  icon: const Icon(Icons.download),
                  label: const Text('Download PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _printReceipt,
                      icon: const Icon(Icons.print),
                      label: const Text('Print'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _shareReceipt() {
    // TODO: Implement receipt sharing functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sharing feature coming soon!')),
    );
  }

  void _printReceipt() {
    // TODO: Implement receipt printing functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Printing feature coming soon!')),
    );
  }

  Future<void> _downloadReceiptAsPdf() async {
    try {
      final receiptData = _virtualReceipt!.receiptData;

      // Create PDF document
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Container(
              padding: const pw.EdgeInsets.all(40),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'OFFICIAL RECEIPT',
                          style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          receiptData['receipt_number'] ?? 'N/A',
                          style: const pw.TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 40),

                  // Business Details
                  pw.Text(
                    'Business Details',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Divider(),
                  _buildPdfRow(
                    'Business Name',
                    receiptData['business_name'] ?? 'N/A',
                  ),
                  pw.SizedBox(height: 24),

                  // Customer Details
                  pw.Text(
                    'Customer Details',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Divider(),
                  _buildPdfRow('Customer', receiptData['member_name'] ?? 'N/A'),
                  _buildPdfRow('Email', receiptData['member_email'] ?? 'N/A'),
                  pw.SizedBox(height: 24),

                  // Transaction Details
                  pw.Text(
                    'Transaction Details',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Divider(),
                  _buildPdfRow('Deal', receiptData['discount_name'] ?? 'N/A'),
                  _buildPdfRow(
                    'Amount',
                    'R${(receiptData['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                  ),
                  _buildPdfRow(
                    'Payment Method',
                    (receiptData['payment_method'] as String?)?.toUpperCase() ??
                        'N/A',
                  ),
                  _buildPdfRow(
                    'Date',
                    _formatDate(
                      DateTime.parse(receiptData['transaction_date']),
                    ),
                  ),
                  _buildPdfRow(
                    'Time',
                    _formatTime(
                      DateTime.parse(receiptData['transaction_date']),
                    ),
                  ),
                  pw.SizedBox(height: 40),

                  // Footer
                  pw.Center(
                    child: pw.Text(
                      'Thank you for your business!',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Center(
                    child: pw.Text(
                      'Generated via Local Lekker',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      // Get the app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final receiptNumber = receiptData['receipt_number'] ?? 'receipt';
      final filePath = '${directory.path}/$receiptNumber.pdf';

      // Save the PDF file
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Receipt saved to: $filePath'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }

      if (kDebugMode) {


        print('📄 PDF saved to: $filePath');


      }
    } catch (e) {
      if (kDebugMode) {

        print('❌ Error generating PDF: $e');

      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  pw.Widget _buildPdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 150,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
