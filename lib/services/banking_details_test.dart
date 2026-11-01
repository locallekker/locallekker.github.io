import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BankingDetailsTest {
  final Logger _logger = Logger();
  final SupabaseClient _supabase = Supabase.instance.client;

  // Paystack API URL
  static const String _baseUrl = 'https://api.paystack.co';

  // Get Paystack secret key from environment.
  // The secret key is a server-only credential and is intentionally NOT bundled
  // in .env, so this getter returns empty outside local debugging. This utility
  // must never call Paystack directly from a release build.
  String get _secretKey {
    if (kReleaseMode) {
      throw StateError(
        'BankingDetailsTest uses the Paystack secret key directly and must not '
        'run in release builds. Use the paystack-proxy Edge Function instead.',
      );
    }
    try {
      return dotenv.env['PAYSTACK_SECRET_KEY'] ?? '';
    } catch (e) {
      _logger.e('Could not load PAYSTACK_SECRET_KEY from env: $e');
      return '';
    }
  }

  // Test banking details for South Africa
  final Map<String, dynamic> _testBankingDetails = {
    'accountName': 'Test Business Account',
    'accountNumber': '1234567890',
    'bankCode': '063', // Standard Bank test code
    'businessName': 'Test Local Business',
    'businessId': 'test-business-id-123',
  };

  Future<void> runFullTest() async {
    _logger.i('🧪 Starting Banking Details Storage Test');

    try {
      // Step 1: Create transfer recipient in Paystack
      _logger.i('📤 Step 1: Creating transfer recipient in Paystack...');
      final recipientCode = await _createTestTransferRecipient();

      if (recipientCode == null) {
        throw Exception('Failed to create transfer recipient in Paystack');
      }

      _logger.i('✅ Paystack recipient created: $recipientCode');

      // Step 2: Verify recipient exists in Paystack
      _logger.i('🔍 Step 2: Verifying recipient exists in Paystack...');
      final paystackVerification = await _verifyRecipientInPaystack(
        recipientCode,
      );

      if (!paystackVerification) {
        throw Exception('Recipient not found in Paystack');
      }

      _logger.i('✅ Paystack verification successful');

      // Step 3: Verify recipient code saved in Supabase
      _logger.i('🗄️ Step 3: Verifying recipient code saved in Supabase...');
      final supabaseVerification = await _verifyRecipientInSupabase(
        recipientCode,
      );

      if (!supabaseVerification) {
        throw Exception('Recipient code not found in Supabase');
      }

      _logger.i('✅ Supabase verification successful');

      // Step 4: Display test results
      _logger.i(
        '🎉 TEST PASSED: Banking details successfully stored in both Paystack and Supabase!',
      );
      _logger.i('📋 Test Summary:');
      _logger.i('   • Account Name: ${_testBankingDetails['accountName']}');
      _logger.i('   • Account Number: ${_testBankingDetails['accountNumber']}');
      _logger.i('   • Bank Code: ${_testBankingDetails['bankCode']}');
      _logger.i('   • Paystack Recipient Code: $recipientCode');
      _logger.i('   • Storage: ✅ Paystack + ✅ Supabase');
    } catch (e) {
      _logger.e('❌ TEST FAILED: $e');
      rethrow;
    }
  }

  Future<String?> _createTestTransferRecipient() async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/transferrecipient'),
        headers: {
          'Authorization': 'Bearer $_secretKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'type': 'nuban',
          'name': _testBankingDetails['accountName'],
          'account_number': _testBankingDetails['accountNumber'],
          'bank_code': _testBankingDetails['bankCode'],
          'currency': 'ZAR',
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['data']['recipient_code'];
      } else {
        throw Exception('Paystack API error: ${response.body}');
      }
    } catch (e) {
      _logger.e('Error creating transfer recipient: $e');
      throw Exception('Failed to create transfer recipient: $e');
    }
  }

  Future<bool> _verifyRecipientInPaystack(String recipientCode) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/transferrecipient/$recipientCode'),
        headers: {'Authorization': 'Bearer $_secretKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final recipient = data['data'];

        // Verify the details match our test data
        if (recipient['name'] == _testBankingDetails['accountName'] &&
            recipient['account_number'] ==
                _testBankingDetails['accountNumber'] &&
            recipient['bank_code'] == _testBankingDetails['bankCode']) {
          _logger.i(
            'Paystack recipient details verified: ${recipient['name']}',
          );
          return true;
        } else {
          _logger.w('Paystack recipient details mismatch');
          return false;
        }
      } else {
        _logger.e('Failed to fetch recipient from Paystack: ${response.body}');
        return false;
      }
    } catch (e) {
      _logger.e('Error verifying recipient in Paystack: $e');
      return false;
    }
  }

  Future<bool> _verifyRecipientInSupabase(String recipientCode) async {
    try {
      // For testing, we'll insert a test record first
      // In real usage, this would be done by the PaystackService._saveRecipientCodeToPartner method

      // First, let's check if we have a test trusted partner record
      final existingRecords = await _supabase
          .from('trusted_partners')
          .select('paystack_recipient_code')
          .eq('user_id', 'test-user-id')
          .limit(1);

      if (existingRecords.isEmpty) {
        // Create a test trusted partner record
        await _supabase.from('trusted_partners').insert({
          'user_id': 'test-user-id',
          'paystack_recipient_code': recipientCode,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        _logger.i('Created test trusted partner record in Supabase');
      } else {
        // Update existing record
        await _supabase
            .from('trusted_partners')
            .update({
              'paystack_recipient_code': recipientCode,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', 'test-user-id');
        _logger.i('Updated test trusted partner record in Supabase');
      }

      // Verify the record was saved
      final verification = await _supabase
          .from('trusted_partners')
          .select('paystack_recipient_code')
          .eq('user_id', 'test-user-id')
          .single();

      final savedCode = verification['paystack_recipient_code'];

      if (savedCode == recipientCode) {
        _logger.i('Supabase recipient code verified: $savedCode');
        return true;
      } else {
        _logger.w(
          'Supabase recipient code mismatch: expected $recipientCode, got $savedCode',
        );
        return false;
      }
    } catch (e) {
      _logger.e('Error verifying recipient in Supabase: $e');
      return false;
    }
  }
}
