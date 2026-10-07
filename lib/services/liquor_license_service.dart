import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Liquor / distribution licence document types an admin can file for a
/// Local Sips trusted partner.
const Map<String, String> kLiquorLicenseDocTypes = {
  'national_liquor_licence': 'National liquor licence',
  'distribution_licence': 'Distribution licence',
  'micro_manufacturer': 'Micro-manufacturer licence',
  'provincial_licence': 'Provincial licence',
  'other': 'Other supporting document',
};

/// Admin-managed liquor licence documents stored in the private
/// `partner-liquor-licenses` bucket. Members and partners never read the files.
class LiquorLicenseService {
  static const String bucket = 'partner-liquor-licenses';

  static final LiquorLicenseService _instance =
      LiquorLicenseService._internal();
  factory LiquorLicenseService() => _instance;
  LiquorLicenseService._internal();

  final Logger _logger = Logger();
  SupabaseClient get _client => SupabaseService.instance.client;

  Future<List<Map<String, dynamic>>> listLicenses(String partnerId) async {
    try {
      final rows = await _client
          .from('partner_liquor_licenses')
          .select()
          .eq('trusted_partner_id', partnerId)
          .order('uploaded_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      _logger.e('listLicenses error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> uploadLicense({
    required String partnerId,
    required Uint8List bytes,
    required String fileName,
    required String docType,
    String? mimeType,
  }) async {
    try {
      final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path =
          '$partnerId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );

      final inserted = await _client
          .from('partner_liquor_licenses')
          .insert({
            'trusted_partner_id': partnerId,
            'file_path': path,
            'file_name': fileName,
            'mime_type': mimeType,
            'doc_type': docType,
            'uploaded_by': _client.auth.currentUser?.id,
          })
          .select()
          .single();

      _logger.i('Uploaded liquor licence for $partnerId: $path');
      return Map<String, dynamic>.from(inserted);
    } catch (e) {
      _logger.e('uploadLicense error: $e');
      return null;
    }
  }

  Future<bool> deleteLicense({
    required String id,
    required String filePath,
  }) async {
    try {
      await _client.storage.from(bucket).remove([filePath]);
      await _client.from('partner_liquor_licenses').delete().eq('id', id);
      return true;
    } catch (e) {
      _logger.e('deleteLicense error: $e');
      return false;
    }
  }

  /// Short-lived signed URL — the bucket is private, so public URLs never work.
  Future<String?> signedUrl(String filePath, {int expiresInSeconds = 300}) async {
    try {
      return await _client.storage
          .from(bucket)
          .createSignedUrl(filePath, expiresInSeconds);
    } catch (e) {
      _logger.e('signedUrl error: $e');
      return null;
    }
  }

  Future<bool> setVerified({
    required String partnerId,
    required bool verified,
  }) async {
    try {
      await _client
          .from('businesses')
          .update({
            'liquor_license_verified': verified,
            'liquor_license_verified_at': verified
                ? DateTime.now().toUtc().toIso8601String()
                : null,
            'liquor_license_verified_by': verified
                ? _client.auth.currentUser?.id
                : null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('owner_member_id', partnerId);
      return true;
    } catch (e) {
      _logger.e('setVerified error: $e');
      return false;
    }
  }
}
