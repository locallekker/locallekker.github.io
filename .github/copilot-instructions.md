# Local Lekker - AI Agent Instructions

## Workspace Preset (Default)

Preset name: Local Lekker Hybrid Mode (4-Agent)

Apply this preset by default whenever this workspace is opened.

### Agent Mix

1. GPT-5.4 - Primary Builder
- Default model for all tasks.
- Use for Flutter, Dart, SQL, Supabase RPC, RLS, UI generation, refactors, and multi-file scaffolding.
- This is the main model for Local Lekker development.

2. Claude Opus 4.8 - Deep Analysis
- Auto-switch only when the task clearly requires long-context reasoning, repo-wide analysis, dependency mapping, or architecture review.
- Use this for reading the entire Local Lekker project, scanning migrations, or understanding complex flows.

3. Gemini 2.5 Pro - Schema & Type Validator
- Auto-switch only when the task clearly involves SQL validation, type-checking, API contract verification, or JSON schema correctness.
- Use this for validating Supabase migrations, RPC signatures, and Dart type alignment.

4. GPT-5.5 - Creative Mode
- Auto-switch only when the task clearly involves creative ideation, naming, UX copywriting, branding, conceptual exploration, or narrative design.

### Switching Rules

- Auto-switch only when the intent is unambiguous.
- Manual overrides always take priority.
- After switching, stay on that model until I say otherwise.
- All agents share the same session and workspace context.
- Never reset context when switching.
- Maintain full awareness of Local Lekker architecture, schema, RPCs, RLS, and Flutter module structure.
- Apply this routing behavior to every new chat inside this workspace.

### Schema Awareness (Supabase)

Always maintain awareness of the Local Lekker Supabase schema.
Continuously reference the following schema sources inside this workspace:

- `supabase/migrations/**` (canonical schema source)
- `supabase/functions/**` (RPCs, edge functions)
- `supabase/seed.sql` (if present)
- `lib/services/**` (Dart-side API wrappers)
- `lib/models/**` (Dart data models)
- `supabase/types/**` (generated types, if present)

Schema Rules:
- Treat the migrations folder as the single source of truth for tables, columns, relationships, constraints, triggers, enums, and policies.
- When generating SQL, Dart models, RPC calls, or RLS policies, always align with the latest migration state.
- When analyzing or validating code, automatically infer table structures, foreign keys, and relationships from the migrations.
- When generating queries or Supabase client code, ensure column names, types, and relationships match the schema.
- When the schema changes (new migration added), automatically update internal schema awareness for all agents.
- Treat migrations as the single source of truth for schema behavior.
- Apply schema awareness to all agents:
  - GPT-5.4 (Primary Builder)
  - Claude Opus 4.8 (Deep Analysis)
  - Gemini 2.5 Pro (Schema & Type Validator)
  - GPT-5.5 (Creative Mode)

### Payment Flow Awareness

Always maintain awareness of the Local Lekker payment system:

- Payment provider logic
- Dart payment services
- Webhook flow
- Supabase payment tables
- Subscription lifecycle logic

Validate all payment-related code for correctness and safety before finalizing.

### App Architecture Awareness

Always maintain awareness of:

- Folder structure
- Navigation flows
- Service patterns
- Model patterns
- Business rules
- Critical logic that must never break

## Project Overview
Local Lekker is a Flutter mobile app for **smart receipt scanning and local business payments** with instant discounts. It's a **subscription-based platform** connecting members with local businesses through QR code payments and OCR-powered receipt processing.

## Architecture & Key Flows

### Core Architecture Pattern
- **Singleton services** (`_instance` pattern) - All services (SupabaseService, SubscriptionService, QrCodeService, etc.) use singleton pattern with factory constructors
- **Feature-based organization** - `lib/features/` divided by user roles: `auth/`, `admin/`, `business/`, `payments/`, `chat/`
- **Role-based navigation** - Three roles drive app flow: `member`, `trusted_partner`, `admin`

### Authentication & Role Management
```dart
// Role determination happens in SupabaseService.getUserRole()
// Checks: profiles.role -> memberships.role -> admin_dashboard -> defaults to 'member'
final role = await SupabaseService.instance.getUserRole(userId: userId);
```

**Critical**: Never hardcode role strings. Use role checks consistently:
- Members: Regular users with subscriptions and QR codes
- Trusted Partners: Businesses that accept payments and scan receipts
- Admin: Platform management via `admin_dashboard` table

### Payment & Subscription Flow
1. **Signup** → `PaymentRequiredScreen` → `PaymentOptionsScreen` (Paystack integration)
2. **Payment success** → `SubscriptionService.createInitialSubscription()` creates:
   - Entry in `subscriptions` table (30-day period)
   - QR code in `user_qr_codes` table via `QrCodeService`
3. **Renewal**: Auto-renew (Paystack) or manual payment with countdown timer
4. **Offline handling**: `PaymentStatusService` uses `SharedPreferences` for pending payments

### Receipt Processing Pipeline
```dart
// Receipt scanning uses BusinessBillService + ReceiptParserService
// Flow: Camera → Image → ML Kit OCR → Template matching → Supabase storage
ReceiptData data = await ReceiptParserService().parseReceipt(imageBytes, template);
```

**Templates**: `ReceiptTemplate` enum supports: generic, thermal, woolworths, pickNPay, spar, checkers, businessBill

### Database & Security (Supabase)
- **RLS (Row Level Security)** enabled on all tables - policies in `unified_schema_rls_policies.sql`
- **Key tables**: `profiles`, `subscriptions`, `user_qr_codes`, `businesses`, `deal_authorizations`, `processed_bills`, `trusted_partner_discounts`, `notifications`
- **Storage buckets**: `business-bills`, `receipt-images` with RLS policies
- **Foreign keys**: Use `add_foreign_keys.sql` pattern for relationships

## Development Conventions

### Logging Pattern
Always use Logger (not print) with semantic levels:
```dart
import 'package:logger/logger.dart';

final Logger _logger = Logger();
_logger.i('Info message');  // Info
_logger.w('Warning');       // Warning
_logger.e('Error: $e');     // Error
_logger.d('Debug detail');  // Debug
```

### Navigation Pattern
Use `Navigator.pushReplacement` for role-based flows, avoid back button traps:
```dart
Navigator.pushReplacement(
  context,
  MaterialPageRoute(builder: (context) => MembersHomePage()),
);
```

For deep links: `DeepLinkService` handles auth callbacks from Supabase (`auth/callback`)

### Error Handling Pattern
```dart
try {
  // Supabase operation
} catch (e) {
  if (e.toString().contains('over_email_send_rate_limit')) {
    throw Exception('Too many attempts. Please wait...');
  }
  if (e.toString().contains('token') || e.toString().contains('grant')) {
    throw Exception('Authentication failed. Please try again...');
  }
  rethrow;
}
```

### State Management
- Primarily **StatefulWidget** with local state
- Use `setState()` for UI updates after async operations
- No external state management (Redux/Bloc) - keep it simple

## Critical Integration Points

### Environment Variables (.env)
```env
SUPABASE_URL=https://qdrotavcmmevhgveodcp.supabase.co
SUPABASE_ANON_KEY=...
PAYSTACK_PUBLIC_KEY=pk_live_...
PAYSTACK_SECRET_KEY=sk_live_...
PAYSTACK_SANDBOX=false  # Production mode
```

**Never commit real credentials** - use `.env.template` for examples

### QR Code Security
- `QrCodeService.buildSecureQrCode()` includes screenshot protection
- QR codes expire after 30 days (tracked in `user_qr_codes.expires_at`)
- Security warning dialog on first QR view

### ML Kit Integration
- **Text recognition**: `google_mlkit_text_recognition` for OCR
- **Image labeling**: `google_mlkit_image_labeling` for receipt classification
- **Permissions**: Camera + storage via `permission_handler`

## Build & Deploy

### Development
```bash
flutter pub get
flutter run  # Debug mode
```

### Production Build
```bash
./build_production.sh  # Runs tests, analysis, builds APK + AAB
# Outputs:
# - build/app/outputs/flutter-apk/app-release.apk
# - build/app/outputs/bundle/release/app-release.aab
```

### Testing
```bash
flutter test              # Unit tests
flutter analyze           # Static analysis
```

Tests in `test/` - primarily widget tests and flow validation

## Database Migrations

SQL files in root are **migration scripts**, not application code:
- `unified_schema_rls_policies.sql` - Complete schema with RLS
- `check_*.sql` - Diagnostic queries
- `add_*.sql` - Incremental changes
- `fix_*.sql` - Production hotfixes

**Always test RLS policies** with role-specific queries before deploying.

## Common Pitfalls

1. **Role checks**: Always use `getUserRole()`, never assume role from session
2. **QR code regeneration**: Only on subscription renewal, not on every view
3. **Payment status**: Check both Supabase (`subscriptions`) AND SharedPreferences (pending)
4. **Supabase client**: Use `SupabaseService.instance.client`, never create new instances
5. **Image uploads**: Use `business-bills` bucket for bills, `receipt-images` for user receipts
6. **Deep links**: Must handle both initial launch and runtime in `DeepLinkService`

## Key Files to Reference

- **Main entry**: `lib/main.dart` - App initialization sequence
- **Auth flow**: `lib/features/auth/welcome_page.dart` - Entry point for unauthenticated users
- **Service layer**: `lib/services/supabase_service.dart` - 1331 lines, core data operations
- **Receipt parsing**: `lib/services/receipt_parser_service.dart` - OCR + template logic
- **Subscription logic**: `lib/services/subscription_service.dart` - QR + payment lifecycle
- **Schema reference**: `unified_schema_rls_policies.sql` - Complete database structure

## When Making Changes

1. **Adding features**: Follow role-based structure in `lib/features/{role}/`
2. **New services**: Use singleton pattern, add to `lib/services/`
3. **Database changes**: Write SQL migration + RLS policies, test with all roles
4. **UI changes**: Maintain consistent Material Design theme from `lib/core/theme/`
5. **Payment flows**: Always update both Supabase tables AND SharedPreferences cache
