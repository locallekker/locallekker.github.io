import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

void main() {
  group('Database State Check', () {
    late SupabaseClient supabase;

    setUp(() async {
      // Initialize Supabase client directly without shared_preferences
      supabase = SupabaseClient(
        'https://qdrotavcmmevhgveodcp.supabase.co',
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFkcm90YXZjbW1ldmhndmVvZGNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc1MjAxMzUsImV4cCI6MjA3MzA5NjEzNX0.dbEFbk8StiMbldSjvlMrFs8X3mCpNpGG3wdgxXg8mqo',
      );
    });

    test('Check trusted_partners table state', () async {
      try {
        // Check trusted_partners table
        final trustedPartners = await supabase
            .from('trusted_partners')
            .select(
              'user_id, business_name, paystack_recipient_code, created_at',
            )
            .limit(10);

        print('Trusted partners records: $trustedPartners');

        // Check businesses table
        final businesses = await supabase
            .from('businesses')
            .select('id, owner_member_id, name, created_at')
            .limit(5);

        print('Businesses records: $businesses');

        // Check profiles table
        final profiles = await supabase
            .from('profiles')
            .select('id, email, role, created_at')
            .limit(5);

        print('Profiles records: $profiles');
      } catch (e) {
        print('Error checking database: $e');
        fail('Database check failed: $e');
      }
    });
  });
}
