import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminPromoKeyDialog extends StatefulWidget {
  const AdminPromoKeyDialog({super.key});

  @override
  State<AdminPromoKeyDialog> createState() => _AdminPromoKeyDialogState();
}

class _AdminPromoKeyDialogState extends State<AdminPromoKeyDialog> {
  final _logger = Logger();
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  String? _generatedKey;
  int? _selectedDurationMonths; // null = all time
  bool _isGenerating = true;
  bool _isSending = false;

  final List<Map<String, dynamic>> _durationOptions = [
    ...List.generate(12, (i) => {'label': '${i + 1} Month${i > 0 ? 's' : ''}', 'value': i + 1}),
    {'label': 'All Time', 'value': null},
  ];

  @override
  void initState() {
    super.initState();
    _generateKey();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String _generateRandomKey() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(12, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<dynamic> _safeTableCheck(String table, String column, String key) async {
    try {
      return await _supabase.from(table).select('id').eq(column, key).maybeSingle();
    } catch (e) {
      _logger.w('Table check failed for $table (may not exist): $e');
      return null;
    }
  }

  Future<void> _generateKey() async {
    setState(() => _isGenerating = true);
    try {
      String newKey;
      bool keyExists;
      do {
        newKey = _generateRandomKey();
        final results = await Future.wait([
          _safeTableCheck('trusted_partners', 'unique_key', newKey),
          _safeTableCheck('tp_member_keys', 'key', newKey),
          _safeTableCheck('admin_promo_keys', 'key', newKey),
        ]);
        keyExists = results[0] != null || results[1] != null || results[2] != null;
      } while (keyExists);

      if (mounted) {
        setState(() {
          _generatedKey = newKey;
          _isGenerating = false;
        });
      }
    } catch (e) {
      _logger.e('Failed to generate key: $e');
      // Fallback: just generate a key without uniqueness check
      if (mounted) {
        setState(() {
          _generatedKey = _generateRandomKey();
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _sendPromoKey() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_generatedKey == null) return;

    setState(() => _isSending = true);
    try {
      final adminId = _supabase.auth.currentUser?.id;
      final email = _emailController.text.trim().toLowerCase();

      // Store in database
      await _supabase.from('admin_promo_keys').insert({
        'key': _generatedKey,
        'email': email,
        'duration_months': _selectedDurationMonths,
        'created_by': adminId,
      });

      // Send email via edge function
      final durationLabel = _selectedDurationMonths != null
          ? '$_selectedDurationMonths month${_selectedDurationMonths! > 1 ? 's' : ''}'
          : 'lifetime';

      try {
        await _supabase.functions.invoke(
          'send-new-key-email',
          body: {
            'email': email,
            'business_name': 'Member',
            'new_key': _generatedKey,
          },
        );
      } catch (e) {
        _logger.w('Edge function email failed (non-blocking): $e');
      }

      if (mounted) {
        Clipboard.setData(ClipboardData(text: _generatedKey!));
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Promo key sent to $email ($durationLabel access, copied to clipboard)',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _logger.e('Failed to send promo key: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send promo key: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.vpn_key, color: Colors.orange, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Generate Promo Key',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Generate a promo key for a member to bypass subscription payment.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 20),

                // Generated Key display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: _isGenerating
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Text(
                                _generatedKey ?? '',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 20),
                              tooltip: 'Copy key',
                              onPressed: () {
                                if (_generatedKey != null) {
                                  Clipboard.setData(
                                      ClipboardData(text: _generatedKey!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Key copied'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 20),

                // Email field
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Member Email Address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                    hintText: 'member@example.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an email address';
                    }
                    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!emailRegex.hasMatch(value.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Duration selector
                const Text(
                  'Subscription Duration',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  value: _selectedDurationMonths,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.timer),
                  ),
                  hint: const Text('Select duration'),
                  items: _durationOptions
                      .map(
                        (opt) => DropdownMenuItem<int?>(
                          value: opt['value'] as int?,
                          child: Text(opt['label'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedDurationMonths = value);
                  },
                  validator: (value) {
                    // value can be null (All Time), so we check if selection was made
                    // by checking if the dropdown has been interacted with
                    return null; // Allow any selection including "All Time"
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedDurationMonths != null
                      ? 'Member will have access for $_selectedDurationMonths month${_selectedDurationMonths! > 1 ? 's' : ''} before needing to pay.'
                      : 'Member will have lifetime access with no expiry.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 24),

                // Send button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        (_isSending || _isGenerating) ? null : _sendPromoKey,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isSending ? 'Sending...' : 'Send Promo Key'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
