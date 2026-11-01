import 'package:flutter_test/flutter_test.dart';
import 'package:local_lekker/services/paystack_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  // Required so plugins (shared_preferences) used by Supabase can be mocked
  // in the unit-test VM where no native side exists.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaystackService Banking Details Tests', () {
    late PaystackService paystackService;

    setUp(() async {
      // Provide an in-memory SharedPreferences implementation so
      // Supabase.initialize can persist its session storage during tests.
      SharedPreferences.setMockInitialValues({});

      // Load environment variables
      await dotenv.load();

      // Initialize Supabase for testing
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );

      paystackService = PaystackService();
    });

    test('Check trusted_partners table structure and data', () async {
      // Test to verify the table structure and check for existing data
      try {
        final response = await Supabase.instance.client
            .from('trusted_partners')
            .select('user_id, paystack_recipient_code, business_name')
            .limit(10);

        print('Trusted partners table data: $response');
        print('Number of trusted_partners records: ${response.length}');

        // Check if paystack_recipient_code column exists
        final columns = await Supabase.instance.client
            .from('information_schema.columns')
            .select('column_name')
            .eq('table_name', 'trusted_partners')
            .eq('column_name', 'paystack_recipient_code');

        print('Columns in trusted_partners: $columns');

        expect(columns.isNotEmpty, true);
      } catch (e) {
        print('Error checking trusted_partners table: $e');
        fail('Failed to check trusted_partners table: $e');
      }
    });

    test('Test banking details retrieval logic', () async {
      // Test the logic of getBankingDetails with a mock scenario
      // This will help us understand if the issue is in the query logic

      // First, let's check if there are any businesses
      final businesses = await Supabase.instance.client
          .from('businesses')
          .select('id, owner_member_id, name')
          .limit(5);

      print('Businesses in database: $businesses');

      // Check all trusted_partners records
      final allTrustedPartners = await Supabase.instance.client
          .from('trusted_partners')
          .select('user_id, paystack_recipient_code, business_name')
          .limit(10);

      print('All trusted_partners records: $allTrustedPartners');

      // First, let's check if there are any trusted_partners records with recipient codes
      final trustedPartners = await Supabase.instance.client
          .from('trusted_partners')
          .select('user_id, paystack_recipient_code')
          .not('paystack_recipient_code', 'is', null)
          .limit(1);

      print('Found trusted partners with recipient codes: $trustedPartners');

      if (trustedPartners.isNotEmpty) {
        final testUserId = trustedPartners[0]['user_id'];
        print('Testing with user ID: $testUserId');

        // Check if this user has a business
        final userBusinesses = await Supabase.instance.client
            .from('businesses')
            .select('id')
            .eq('owner_member_id', testUserId)
            .limit(1);

        print('Businesses for user: $userBusinesses');

        if (userBusinesses.isNotEmpty) {
          print('Testing getBankingDetailsForUser with user ID: $testUserId');

          // This should work if the data is properly saved
          final result = await paystackService.getBankingDetailsForUser(
            testUserId,
          );
          print('getBankingDetailsForUser result: $result');
        }
      } else {
        print('No trusted partners with recipient codes found in database');
      }
    });

    test(
      'Get banking details returns null when no recipient code exists',
      () async {
        // Test with a non-existent user ID
        final result = await paystackService.getBankingDetailsForUser(
          'non-existent-user-id',
        );
        expect(result, isNull);
      },
    );
  });
}
