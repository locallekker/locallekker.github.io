Dart example: call the Edge Function to delete an auth user

Use the `http` package (`package:http/http.dart`) and pass the current admin user's access token in the Authorization header.

Example:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<bool> deleteAuthUser(String functionUrl, String adminAccessToken, String userId) async {
  final resp = await http.post(
    Uri.parse(functionUrl),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $adminAccessToken',
    },
    body: jsonEncode({'user_id': userId}),
  );

  if (resp.statusCode == 200) {
    final body = jsonDecode(resp.body);
    return body['success'] == true;
  }

  throw Exception('Failed to delete auth user: ${resp.statusCode} ${resp.body}');
}

// Usage from your AdminService after DB RPC succeeded:
// final functionUrl = 'https://<project>.functions.supabase.co/delete-auth-user';
// await deleteAuthUser(functionUrl, currentAdminAccessToken, tpUserId);
```

Important
- `currentAdminAccessToken` should be the admin user's access token (not the service_role key).
- Ensure the function URL is the deployed function endpoint.
- Handle errors and show appropriate UI messages; log failures for later audit.
