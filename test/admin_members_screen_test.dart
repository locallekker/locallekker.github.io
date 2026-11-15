import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_lekker/features/admin/admin_members_screen.dart';
import 'package:local_lekker/widgets/profile_photo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://admin-members-test.supabase.co',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final headers = {
          'content-type': 'application/json',
          'content-range': '0-0/1',
        };
        if (request.url.path.endsWith(
          '/rpc/get_admin_member_signup_contact_statuses',
        )) {
          return http.Response('[]', 200, headers: {
            ...headers,
            'content-range': '*/0',
          }, request: request);
        }

        if (request.url.path.endsWith('/profiles')) {
          if (request.url.queryParameters['is_deactivated'] == 'eq.true') {
            return http.Response('[]', 200, headers: {
              ...headers,
              'content-range': '*/0',
            }, request: request);
          }

          return http.Response(
            jsonEncode([
              {
                'id': 'member-1',
                'name': 'Alice',
                'surname': 'Example',
                'email': 'alice@example.test',
                'contact': '',
                'city': 'East London',
                'role': 'member',
                'subscription': 'active',
                'is_deactivated': false,
                'created_at': '2026-11-14T00:00:00Z',
                'profile_photo_url': 'https://example.test/alice.png',
              },
            ]),
            200,
            headers: headers,
            request: request,
          );
        }

        return http.Response('[]', 200, headers: {
          ...headers,
          'content-range': '*/0',
        }, request: request);
      }),
    );
  });

  testWidgets('member profile photo opens a zoomable preview', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AdminMembersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final photo = find.byType(ProfilePhoto);
    expect(photo, findsOneWidget);

    final photoButton = find.ancestor(
      of: photo,
      matching: find.byWidgetPredicate(
        (widget) => widget is InkWell && widget.customBorder is CircleBorder,
      ),
    );
    expect(photoButton, findsOneWidget);

    await tester.tap(photoButton);
    await tester.pumpAndSettle();

    expect(find.text('Alice Example profile photo'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
}
