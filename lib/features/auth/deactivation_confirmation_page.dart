import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';

class DeactivationConfirmationPage extends StatefulWidget {
  final String userType; // 'member' or 'trusted_partner'
  final Function(String reason) onConfirm;

  const DeactivationConfirmationPage({
    super.key,
    required this.userType,
    required this.onConfirm,
  });

  @override
  State<DeactivationConfirmationPage> createState() =>
      _DeactivationConfirmationPageState();
}

class _DeactivationConfirmationPageState
    extends State<DeactivationConfirmationPage> {
  final Logger _logger = Logger();
  String? _selectedReason;
  bool _agreedToDeactivation = false;
  bool _isLoading = false;

  final List<String> _deactivationReasons = [
    'No longer using the service',
    'Switching to a different service',
    'Too expensive',
    'Not satisfied with the service',
    'Business/partnership ended',
    'Personal reasons',
    'Other (specify below)',
  ];

  final TextEditingController _otherReasonController = TextEditingController();

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  void _handleDeactivation() async {
    if (!_agreedToDeactivation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm that you want to deactivate'),
        ),
      );
      return;
    }

    if (_selectedReason == null || _selectedReason!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a reason')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      String reason = _selectedReason!;
      if (reason == 'Other (specify below)') {
        reason = _otherReasonController.text.isEmpty
            ? 'Other (not specified)'
            : _otherReasonController.text;
      }

      _logger.i('User initiating deactivation with reason: $reason');

      // Call the callback with the reason
      await widget.onConfirm(reason);

      if (mounted) {
        Navigator.of(context).pop(true); // Pop with success
      }
    } catch (e) {
      _logger.e('Error during deactivation: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMember = widget.userType == 'member';
    final title = isMember
        ? 'Deactivate Member Account'
        : 'Deactivate Business';

    final bottomInset = MediaQuery.of(context).padding.bottom;
    // Add extra bottom padding so action buttons stay above any footer/nav overlays.
    final bottomPadding = bottomInset + 140;

    return Scaffold(
      appBar: BrandedAppBar(title: Text(title), centerTitle: true),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning Card
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Account Deactivation',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isMember
                          ? 'Deactivating your account will:\n'
                                '• Disable your membership and remove access to discounts\n'
                                '• Stop your QR codes from working\n'
                                '• Cancel your subscription\n'
                                '• Remove your visibility from trusted partner apps'
                          : 'Deactivating your business will:\n'
                                '• Disable your business profile\n'
                                '• Make your discounts invisible to members\n'
                                '• Stop QR code payments\n'
                                '• Cancel all active agreements',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.red.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Reason Selection
            Text(
              'Why are you deactivating?',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...List.generate(_deactivationReasons.length, (index) {
              final reason = _deactivationReasons[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: RadioListTile<String>(
                  title: Text(reason),
                  value: reason,
                  groupValue: _selectedReason,
                  onChanged: (value) {
                    setState(() => _selectedReason = value);
                  },
                  toggleable: true,
                ),
              );
            }),

            // Other reason text field
            if (_selectedReason == 'Other (specify below)')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: TextField(
                  controller: _otherReasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Please specify your reason',
                    hintText: 'Tell us why you are deactivating...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Confirmation Checkbox
            CheckboxListTile(
              title: Text(
                isMember
                    ? 'I understand that my account will be deactivated and I will lose access to all benefits'
                    : 'I understand that my business will be deactivated and no longer visible to members',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: _agreedToDeactivation,
              onChanged: (value) {
                setState(() => _agreedToDeactivation = value ?? false);
              },
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading || !_agreedToDeactivation
                        ? null
                        : _handleDeactivation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Deactivate'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
