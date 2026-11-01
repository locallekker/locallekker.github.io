import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/discount_service.dart';
import '../../services/supabase_service.dart';

class NotificationTestPage extends StatefulWidget {
  const NotificationTestPage({super.key});

  @override
  State<NotificationTestPage> createState() => _NotificationTestPageState();
}

class _NotificationTestPageState extends State<NotificationTestPage> {
  final DiscountService _discountService = DiscountService();
  String _result = 'Not tested yet';

  Future<void> _testNotificationCreation() async {
    try {
      setState(() => _result = 'Testing...');

      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) {
        setState(() => _result = 'No user logged in');
        return;
      }

      // Test the backfill method
      await _discountService
          .createNotificationsForExistingPendingAuthorizations(user.id);

      setState(
        () => _result = 'Notification creation test completed successfully!',
      );
    } catch (e) {
      setState(() => _result = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(title: const Text('Notification Test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_result, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _testNotificationCreation,
              child: const Text('Test Notification Creation'),
            ),
          ],
        ),
      ),
    );
  }
}
