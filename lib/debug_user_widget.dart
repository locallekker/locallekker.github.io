import 'package:flutter/material.dart';
import 'services/supabase_service.dart';

/// Temporary debug widget to show current user info
class DebugUserWidget extends StatelessWidget {
  const DebugUserWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('Not logged in'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Logged in as:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('ID: ${user.id}'),
            Text('Email: ${user.email ?? "No email"}'),
          ],
        ),
      ),
    );
  }
}
