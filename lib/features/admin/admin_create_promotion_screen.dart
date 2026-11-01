import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import '../../services/supabase_service.dart';
import '../../services/promotion_campaign_service.dart';
import 'package:local_lekker/core/theme/app_colors.dart';

class AdminCreatePromotionScreen extends StatefulWidget {
  const AdminCreatePromotionScreen({super.key});

  @override
  State<AdminCreatePromotionScreen> createState() =>
      _AdminCreatePromotionScreenState();
}

class _AdminCreatePromotionScreenState
    extends State<AdminCreatePromotionScreen> {
  final Logger _logger = Logger();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _emailInputController = TextEditingController();
  final FocusNode _emailInputFocusNode = FocusNode();
  final List<String> _pendingEmails = [];

  String? _selectedImagePath;
  int? _freeMonths; // null = lifetime
  DateTime? _endsAt;
  bool _isSaving = false;
  bool _isIntroCampaign = true;
  final int _initialChargeCents = 100;
  final int _renewalChargeCents = 9900;

  final List<Map<String, dynamic>> _durationOptions = [
    {'label': '1 Month', 'value': 1},
    {'label': '2 Months', 'value': 2},
    {'label': '3 Months', 'value': 3},
    {'label': '6 Months', 'value': 6},
    {'label': '12 Months', 'value': 12},
    {'label': 'All Time (Lifetime)', 'value': null},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _emailInputController.dispose();
    _emailInputFocusNode.dispose();
    super.dispose();
  }

  void _addEmailChip() {
    final email = _emailInputController.text.trim().toLowerCase();
    if (email.isEmpty) return;
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) return;
    if (_pendingEmails.contains(email)) {
      _emailInputController.clear();
      return;
    }
    setState(() {
      _pendingEmails.add(email);
      _emailInputController.clear();
    });
    _emailInputFocusNode.requestFocus();
  }

  void _removeEmailChip(String email) {
    setState(() => _pendingEmails.remove(email));
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _selectedImagePath = picked.path);
    }
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endsAt ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _endsAt = picked);
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImagePath == null) return null;

    try {
      final file = File(_selectedImagePath!);
      final bytes = await file.readAsBytes();
      final fileExt = _selectedImagePath!.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'promotions/$fileName';

      await SupabaseService.instance.client.storage
          .from('promo-images')
          .uploadBinary(filePath, bytes);

      final publicUrl = SupabaseService.instance.client.storage
          .from('promo-images')
          .getPublicUrl(filePath);

      _logger.i('Promo image uploaded: $publicUrl');
      return publicUrl;
    } catch (e) {
      _logger.e('Error uploading promo image: $e');
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) throw Exception('Not logged in');

      // Make sure any email still typed but not yet chipped is included
      _addEmailChip();

      final imageUrl = await _uploadImage();

      final inserted = await SupabaseService.instance.client
          .from('promotions')
          .insert({
            'name': _nameController.text.trim(),
            'description': _descriptionController.text.trim().isNotEmpty
                ? _descriptionController.text.trim()
                : null,
            'image_url': imageUrl,
            'free_months': _freeMonths,
            'is_intro_campaign': _isIntroCampaign,
            'initial_charge_cents': _initialChargeCents,
            'renewal_charge_cents': _renewalChargeCents,
            'ends_at': _endsAt?.toUtc().toIso8601String(),
            'is_active': true,
            'created_by': user.id,
          })
          .select('id')
          .single();

      final newPromotionId = inserted['id'] as String;
      _logger.i('Promotion created: ${_nameController.text} ($newPromotionId)');

      // Import the participant emails the admin entered (if any)
      int emailsAdded = 0;
      if (_pendingEmails.isNotEmpty) {
        final importResult =
            await PromotionCampaignService().importParticipantEmails(
          promotionId: newPromotionId,
          rawInput: _pendingEmails.join('\n'),
        );
        emailsAdded = (importResult['inserted'] as int?) ?? 0;
        _logger.i(
          'Imported participant emails: $emailsAdded inserted of ${_pendingEmails.length} provided',
        );
      }

      if (mounted) {
        final msg = emailsAdded > 0
            ? 'Promotion created with $emailsAdded participant email(s).'
            : 'Promotion created successfully!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _logger.e('Error creating promotion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Create Promotion'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image picker
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _selectedImagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(_selectedImagePath!),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to add a banner image',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Promotion Name *',
                  hintText: 'e.g. Badminton Event',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.campaign),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a promotion name';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Describe the promotion...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 16),

              // Duration dropdown
              DropdownButtonFormField<int?>(
                value: _freeMonths,
                decoration: const InputDecoration(
                  labelText: 'Free Duration *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.card_giftcard),
                ),
                items: _durationOptions.map((opt) {
                  return DropdownMenuItem<int?>(
                    value: opt['value'] as int?,
                    child: Text(opt['label'] as String),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _freeMonths = value);
                },
              ),

              const SizedBox(height: 16),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Intro Billing Campaign'),
                subtitle: const Text(
                  'Eligible participants pay R1.00 now, receive free months, then auto-renew at R99/month.',
                ),
                value: _isIntroCampaign,
                onChanged: (value) {
                  setState(() => _isIntroCampaign = value);
                },
              ),

              if (_isIntroCampaign)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: const Text(
                    'Billing config: Initial charge R1.00 and recurring charge R99.00/month after free months.',
                  ),
                ),

              // End date
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(
                  _endsAt != null
                      ? 'Promo ends: ${_endsAt!.day}/${_endsAt!.month}/${_endsAt!.year}'
                      : 'No end date (runs until deactivated)',
                ),
                subtitle: const Text('Tap to set an end date'),
                trailing: _endsAt != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _endsAt = null),
                      )
                    : null,
                onTap: _pickEndDate,
              ),

              const SizedBox(height: 16),

              // Participant emails input
              const Text(
                'Participant Emails',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Only members whose signup email matches one of these will see this promo.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailInputController,
                focusNode: _emailInputFocusNode,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Add email',
                  hintText: 'member@example.com',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.email),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addEmailChip,
                  ),
                ),
                onSubmitted: (_) => _addEmailChip(),
              ),
              if (_pendingEmails.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _pendingEmails
                      .map(
                        (e) => Chip(
                          label: Text(e),
                          onDeleted: () => _removeEmailChip(e),
                        ),
                      )
                      .toList(),
                ),
              ],

              const SizedBox(height: 24),

              // Save button
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isSaving ? 'Creating...' : 'Create Promotion'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
