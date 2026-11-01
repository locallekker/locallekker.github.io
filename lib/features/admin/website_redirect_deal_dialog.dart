import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

import '../../core/constants/deal_categories.dart';
import '../../models/discount.dart';
import '../../services/discount_service.dart';
import '../../services/supabase_service.dart';
import '../../services/website_redirect_service.dart';

/// Admin-only create/edit dialog for website-redirect deals.
/// Returns `true` when the deal was saved.
class WebsiteRedirectDealDialog extends StatefulWidget {
  final String trustedPartnerId;
  final Discount? existing;
  final String? lockedDealCategory;

  const WebsiteRedirectDealDialog({
    super.key,
    required this.trustedPartnerId,
    this.existing,
    this.lockedDealCategory,
  });

  @override
  State<WebsiteRedirectDealDialog> createState() =>
      _WebsiteRedirectDealDialogState();
}

class _WebsiteRedirectDealDialogState extends State<WebsiteRedirectDealDialog> {
  final Logger _logger = Logger();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _category;

  String? _existingImageUrl;
  XFile? _pickedImage;
  Uint8List? _pickedBytes;

  bool _loadingWebsite = true;
  String? _rawWebsite;
  Uri? _websiteUri;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.name ?? '');
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _category =
        widget.lockedDealCategory ??
        (kDealCategories.contains(existing?.dealCategory)
            ? existing!.dealCategory
            : 'Other');
    _existingImageUrl = existing?.imageUrl;
    _loadWebsite();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadWebsite() async {
    try {
      final business = await SupabaseService.instance.client
          .from('businesses')
          .select('website_url')
          .eq('owner_member_id', widget.trustedPartnerId)
          .maybeSingle();
      _rawWebsite = business?['website_url'] as String?;
      _websiteUri = WebsiteRedirectService.normalizeWebsiteUrl(_rawWebsite);
    } catch (e) {
      _logger.e('Failed to load partner website: $e');
    } finally {
      if (mounted) setState(() => _loadingWebsite = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      setState(() {
        _pickedImage = image;
        _pickedBytes = bytes;
      });
    } catch (e) {
      _showMessage('Failed to pick image: $e');
    }
  }

  Future<String> _uploadImage() async {
    final storage = SupabaseService.instance.client.storage.from(
      'business-bills',
    );
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${_pickedImage!.name}';
    final adminId = SupabaseService.instance.getCurrentUser()?.id;

    Future<String> uploadTo(String path) async {
      await storage.uploadBinary(path, _pickedBytes!);
      return storage.getPublicUrl(path);
    }

    try {
      return await uploadTo('deal_images/${widget.trustedPartnerId}/$fileName');
    } catch (e) {
      // Storage RLS may only allow admins to write under their own folder.
      if (adminId == null || adminId == widget.trustedPartnerId) rethrow;
      _logger.w('Partner-folder upload failed ($e), retrying admin folder');
      return uploadTo('deal_images/$adminId/$fileName');
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (_websiteUri == null) {
      _showMessage('Add a valid website to the partner profile first.');
      return;
    }

    setState(() => _saving = true);
    try {
      var imageUrl = _existingImageUrl;
      if (_pickedBytes != null) imageUrl = await _uploadImage();

      final service = DiscountService();
      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim();

      if (_isEdit) {
        await service.updateDiscount(
          widget.existing!.id,
          name: title,
          description: description,
          dealCategory: _category,
          imageUrl: imageUrl,
          updateImageUrl: true,
        );
      } else {
        await service.createDiscount(
          trustedPartnerId: widget.trustedPartnerId,
          name: title,
          description: description,
          itemName: 'Website',
          itemPrice: 0,
          percentage: 0,
          dealType: Discount.websiteRedirectType,
          imageUrl: imageUrl,
          dealCategory: _category,
        );
      }
      DiscountService.invalidateActiveDealsCache();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _logger.e('Failed to save website redirect deal: $e');
      _showMessage('Failed to save deal: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Website Deal' : 'New Website Deal'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWebsiteInfo(),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Deal title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter a title'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  maxLength: 300,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Short description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.lockedDealCategory != null)
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Deal Category',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(widget.lockedDealCategory!),
                  )
                else
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: 'Deal Category',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in kDealCategories)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() => _category = v ?? 'Other'),
                  ),
                const SizedBox(height: 16),
                _buildImagePicker(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving || _loadingWebsite || _websiteUri == null
              ? null
              : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  Widget _buildWebsiteInfo() {
    if (_loadingWebsite) {
      return const LinearProgressIndicator();
    }
    final ok = _websiteUri != null;
    final color = ok ? Colors.green.shade700 : Colors.red.shade700;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (ok ? Colors.green : Colors.red).shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.language : Icons.error_outline, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ok
                  ? 'Members will be sent to:\n${_websiteUri.toString()}'
                  : (_rawWebsite == null || _rawWebsite!.trim().isEmpty)
                  ? 'This partner has no website saved. Add one on the partner profile first.'
                  : 'The saved website "${_rawWebsite!.trim()}" is not a valid web address. Fix it on the partner profile first.',
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker() {
    Widget? preview;
    if (_pickedBytes != null) {
      preview = Image.memory(_pickedBytes!, height: 120, fit: BoxFit.cover);
    } else if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
      preview = Image.network(
        _existingImageUrl!,
        height: 120,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview != null) ...[
          ClipRRect(borderRadius: BorderRadius.circular(8), child: preview),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickImage,
              icon: const Icon(Icons.image),
              label: Text(preview == null ? 'Add image' : 'Change image'),
            ),
            if (preview != null)
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _pickedImage = null;
                        _pickedBytes = null;
                        _existingImageUrl = null;
                      }),
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
