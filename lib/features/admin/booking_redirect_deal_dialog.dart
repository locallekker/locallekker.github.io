import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';

import '../../core/constants/deal_categories.dart';
import '../../models/discount.dart';
import '../../services/discount_service.dart';
import '../../services/supabase_service.dart';
import '../../services/website_redirect_service.dart';

/// Admin-only create/edit dialog for booking-redirect deals (Locally Active
/// category only), e.g. sending members to a partner's Playtomic booking page.
/// Returns `true` when the deal was saved.
class BookingRedirectDealDialog extends StatefulWidget {
  final String trustedPartnerId;
  final Discount? existing;

  const BookingRedirectDealDialog({
    super.key,
    required this.trustedPartnerId,
    this.existing,
  });

  @override
  State<BookingRedirectDealDialog> createState() =>
      _BookingRedirectDealDialogState();
}

class _BookingRedirectDealDialogState
    extends State<BookingRedirectDealDialog> {
  final Logger _logger = Logger();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _bookingUrlController;

  String? _existingImageUrl;
  XFile? _pickedImage;
  Uint8List? _pickedBytes;
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
    _bookingUrlController = TextEditingController(
      text: existing?.bookingUrl ?? '',
    );
    _existingImageUrl = existing?.imageUrl;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _bookingUrlController.dispose();
    super.dispose();
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

    final bookingUri = WebsiteRedirectService.normalizeWebsiteUrl(
      _bookingUrlController.text,
    );
    if (bookingUri == null) {
      _showMessage('Enter a valid booking page URL.');
      return;
    }

    setState(() => _saving = true);
    try {
      var imageUrl = _existingImageUrl;
      if (_pickedBytes != null) imageUrl = await _uploadImage();

      final service = DiscountService();
      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim();
      final customData = {'booking_url': bookingUri.toString()};

      if (_isEdit) {
        await service.updateDiscount(
          widget.existing!.id,
          name: title,
          description: description,
          dealCategory: kLocallyActiveCategory,
          customData: customData,
          imageUrl: imageUrl,
          updateImageUrl: true,
        );
      } else {
        await service.createDiscount(
          trustedPartnerId: widget.trustedPartnerId,
          name: title,
          description: description,
          itemName: 'Booking',
          itemPrice: 0,
          percentage: 0,
          dealType: Discount.bookingRedirectType,
          customData: customData,
          imageUrl: imageUrl,
          dealCategory: kLocallyActiveCategory,
        );
      }
      DiscountService.invalidateActiveDealsCache();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _logger.e('Failed to save booking redirect deal: $e');
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
      title: Text(_isEdit ? 'Edit Booking Deal' : 'New Booking Deal'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _bookingUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Booking page URL (e.g. Playtomic)',
                    hintText: 'https://playtomic.io/...',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter a booking URL'
                      : null,
                ),
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
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Deal Category',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(kLocallyActiveCategory),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image),
                  label: Text(
                    _pickedImage != null || (_existingImageUrl?.isNotEmpty ?? false)
                        ? 'Change image'
                        : 'Add image (optional)',
                  ),
                ),
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
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
