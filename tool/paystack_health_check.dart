import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:local_lekker/services/supabase_service.dart';
import 'package:local_lekker/services/paystack_service.dart';

Future<void> main() async {
  await dotenv.load(fileName: '.env');
  await SupabaseService.instance.initialize();

  final email = dotenv.env['HEALTHCHECK_EMAIL'] ?? '';
  final password = dotenv.env['HEALTHCHECK_PASSWORD'] ?? '';

  if (email.isEmpty || password.isEmpty) {
    print('Missing HEALTHCHECK_EMAIL or HEALTHCHECK_PASSWORD in .env');
    return;
  }

  final ok = await SupabaseService.instance.signIn(
    email: email,
    password: password,
  );
  print('signed_in: $ok');

  final res = await PaystackService().runHealthCheck();
  print('health: $res');
}
