import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/liquor_license_service.dart';

const Color _wineDark = Color(0xFF722F37);

/// Admin-only management of a Local Sips partner's liquor licence documents.
class LiquorLicenseUploader extends StatefulWidget {
  final String partnerId;
  final bool initiallyVerified;
  final ValueChanged<bool>? onVerifiedChanged;

  const LiquorLicenseUploader({
    super.key,
    required this.partnerId,
    this.initiallyVerified = false,
    this.onVerifiedChanged,
  });

  @override
  State<LiquorLicenseUploader> createState() => _LiquorLicenseUploaderState();
}

class _LiquorLicenseUploaderState extends State<LiquorLicenseUploader> {
  final LiquorLicenseService _service = LiquorLicenseService();

  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  bool _busy = false;
  late bool _verified = widget.initiallyVerified;
  String _docType = kLiquorLicenseDocTypes.keys.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final docs = await _service.listLicenses(widget.partnerId);
    if (!mounted) return;
    setState(() {
      _docs = docs;
      _loading = false;
    });
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null || file.bytes == null) return;

    setState(() => _busy = true);
    final uploaded = await _service.uploadLicense(
      partnerId: widget.partnerId,
      bytes: file.bytes!,
      fileName: file.name,
      docType: _docType,
      mimeType: _mimeTypeFor(file.extension),
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (uploaded == null) {
      _showMessage('Upload failed. Please try again.');
      return;
    }
    await _load();
  }

  Future<void> _open(Map<String, dynamic> doc) async {
    final url = await _service.signedUrl(doc['file_path'] as String);
    if (!mounted) return;
    if (url == null) {
      _showMessage('Could not open this document.');
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _delete(Map<String, dynamic> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('${doc['file_name']} will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final ok = await _service.deleteLicense(
      id: doc['id'] as String,
      filePath: doc['file_path'] as String,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _showMessage('Could not delete this document.');
      return;
    }
    await _load();
  }

  Future<void> _setVerified(bool value) async {
    setState(() => _busy = true);
    final ok = await _service.setVerified(
      partnerId: widget.partnerId,
      verified: value,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _verified = value;
    });
    if (!ok) {
      _showMessage('Could not update the verification status.');
      return;
    }
    widget.onVerifiedChanged?.call(value);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _mimeTypeFor(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          'Liquor licence documents',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: _wineDark,
          ),
        ),
        const Text(
          'National liquor / distribution licences. Visible to admins only.',
          style: TextStyle(fontSize: 11.5, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_docs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No documents uploaded yet.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          )
        else
          ..._docs.map(_buildDocTile),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _docType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Document type',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final entry in kLiquorLicenseDocTypes.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _docType = value ?? _docType),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _wineDark,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy ? null : _pickAndUpload,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: _wineDark,
          value: _verified,
          onChanged: _busy ? null : _setVerified,
          title: const Text(
            'Licence verified',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'Confirms the documents above have been checked',
            style: TextStyle(fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  Widget _buildDocTile(Map<String, dynamic> doc) {
    final name = (doc['file_name'] as String?) ?? 'Document';
    final type = kLiquorLicenseDocTypes[doc['doc_type']] ?? 'Document';
    final uploadedAt = DateTime.tryParse('${doc['uploaded_at']}')?.toLocal();
    final isPdf = (doc['mime_type'] as String?) == 'application/pdf';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE0C2C7)),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          isPdf ? Icons.picture_as_pdf : Icons.image_outlined,
          color: _wineDark,
        ),
        title: Text(name, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          uploadedAt == null
              ? type
              : '$type · ${uploadedAt.day}/${uploadedAt.month}/${uploadedAt.year}',
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Open',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: _busy ? null : () => _open(doc),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: _busy ? null : () => _delete(doc),
            ),
          ],
        ),
      ),
    );
  }
}
