import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'cache_service.dart';
import 'payment_status_service.dart';

enum PasswordResetDelivery { otp }

class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();
  SupabaseClient? _client;
  SupabaseClient get client {
    // If we've already set a client, return it.
    if (_client != null) return _client!;

    // Try to use the globally initialized Supabase client if available.
    try {
      final globalClient = Supabase.instance.client;
      _client = globalClient;
      return globalClient;
    } catch (_) {
      // Fallback: construct a direct client using env values so callers
      // don’t crash with LateInitializationError before init() completes.
      final url = dotenv.env['SUPABASE_URL'] ?? 'http://localhost:54321';
      final anonKey =
          dotenv.env['SUPABASE_ANON_KEY'] ??
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
      _client = SupabaseClient(url, anonKey);
      applyClientCapabilities(_client!);
      return _client!;
    }
  }

  /// Features this app version understands. The database hides newer deal
  /// types from app versions that don't send the matching capability.
  static const String clientCapabilities = 'restaurant_deals_v1';

  /// Only database (REST) requests carry the header; Edge Function calls are
  /// left untouched.
  static void applyClientCapabilities(SupabaseClient client) {
    client.rest.headers['x-ll-capabilities'] = clientCapabilities;
  }

  final Logger _logger = Logger();

  // In-memory cache of member terms acceptance keyed by userId. Set to true
  // immediately after a successful acceptMemberTerms RPC so subsequent
  // navigation checks in the same session can trust the just-written value
  // even if the follow-up SELECT is blocked by RLS, hits replica lag, or the
  // column read fails for any other transient reason. Prevents the loop where
  // the user accepts terms but is bounced back to the terms page.
  final Set<String> _memberTermsAcceptedCache = <String>{};

  // Same idea for the Local Sips 18+ confirmation.
  final Set<String> _ageVerifiedCache = <String>{};

  // In-memory cache of resolved user roles keyed by userId. A user's role does
  // not change within a single app session, so caching it avoids repeating the
  // multi-table/RPC role resolution on every navigation checkpoint. Cleared on
  // sign-out so a different user in the same session never inherits a stale role.
  final Map<String, String> _userRoleCache = <String, String>{};

  Future<void> init() async {
    _logger.i('SupabaseService: init() method called');
    _logger.i('SupabaseService: Initializing Supabase...');
    // Use environment variables
    final url = dotenv.env['SUPABASE_URL'] ?? 'http://localhost:54321';
    final anonKey =
        dotenv.env['SUPABASE_ANON_KEY'] ??
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
    _logger.d('SupabaseService: Using URL: $url');
    await Supabase.initialize(url: url, anonKey: anonKey);
    _client = Supabase.instance.client;
    applyClientCapabilities(_client!);
    _logger.i('SupabaseService: Supabase initialized successfully');

    // Initialize auth state change listener
    _initAuthStateListener();
  }

  // Authentication methods
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? userMetadata,
  }) async {
    // Normalize email to lowercase and trim whitespace
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final resp = await client.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: userMetadata,
      );

      // Log the response for easier debugging of email/otp delivery issues
      try {
        _logger.i('SupabaseService.signUp: response.user=${resp.user}');
        _logger.i('SupabaseService.signUp: response.session=${resp.session}');
      } catch (_) {
        // best-effort logging; do not throw from logging
      }

      return resp;
    } catch (e) {
      // Handle rate limiting
      if (e.toString().contains('over_email_send_rate_limit')) {
        throw Exception(
          'Too many signup attempts. Please wait a moment before trying again.',
        );
      }
      rethrow;
    }
  }

  Future<AuthResponse> signUpWithOtp({
    required String email,
    Map<String, dynamic>? userMetadata,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    try {
      _logger.i('SupabaseService: Signing up with OTP for $normalizedEmail');

      await client.auth.signInWithOtp(
        email: normalizedEmail,
        shouldCreateUser: true,
        data: userMetadata,
      );

      _logger.i('SupabaseService.signUpWithOtp: OTP sent successfully');

      return AuthResponse(
        user: User(
          id: '',
          appMetadata: {},
          userMetadata: userMetadata ?? {},
          aud: '',
          createdAt: DateTime.now().toIso8601String(),
          email: normalizedEmail,
        ),
        session: null,
      );
    } catch (e) {
      _logger.e('SupabaseService.signUpWithOtp: Error: $e');
      if (e.toString().contains('over_email_send_rate_limit')) {
        throw Exception(
          'Too many signup attempts. Please wait a moment before trying again.',
        );
      }
      rethrow;
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    // Normalize email to lowercase and trim whitespace
    final normalizedEmail = email.trim().toLowerCase();

    _logger.i('SupabaseService: Attempting sign in for $normalizedEmail');
    _logger.d(
      'SupabaseService: Build mode: ${const bool.fromEnvironment('dart.vm.product') ? 'RELEASE' : 'DEBUG'}',
    );

    try {
      final isDeactivated = await isEmailDeactivated(normalizedEmail);
      if (isDeactivated) {
        _logger.w(
          'SupabaseService: Sign in blocked - account is deactivated for $normalizedEmail',
        );
        throw Exception(
          'This account has been deactivated. Please reactivate your membership to sign in.',
        );
      }

      final response = await client.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );
      _logger.i(
        'SupabaseService: Sign in successful for $normalizedEmail, user: ${response.user?.id}',
      );
      return response;
    } catch (e) {
      _logger.e('SupabaseService: Sign in failed for $email: $e');
      _logger.e('SupabaseService: Error details: ${e.toString()}');
      _logger.e('SupabaseService: Error runtime type: ${e.runtimeType}');

      // Handle specific token grant errors
      if (e.toString().contains('token') || e.toString().contains('grant')) {
        _logger.w('SupabaseService: Token grant error during sign in: $e');
        throw Exception(
          'Authentication failed. Please try again or check your connection.',
        );
      }

      // Handle network/connectivity issues
      if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        throw Exception(
          'Network error. Please check your internet connection and try again.',
        );
      }

      rethrow;
    }
  }

  /// Sign in (or silently create an account for) a member using their Google
  /// account. Reuses the SAME Supabase auth session/profile pipeline as
  /// email/password sign-in — callers must still route through
  /// NavigationService().getInitialScreen() afterwards so profile-completion,
  /// terms and subscription checks run exactly as they do today.
  Future<AuthResponse> signInWithGoogle() async {
    final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
    if (webClientId == null || webClientId.isEmpty) {
      throw Exception(
        'Google sign-in is not configured yet. Please try another sign-in method.',
      );
    }

    try {
      // clientId is used on Web, serverClientId is used on Android/iOS so the
      // native Google ID token is minted for this same OAuth client's audience
      // (must match the Client ID configured in Supabase's Google provider).
      final googleSignIn = GoogleSignIn(
        clientId: webClientId,
        serverClientId: webClientId,
      );

      // Force the account picker instead of silently reusing a stale session.
      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google sign-in was cancelled.');
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw Exception(
          'Could not retrieve Google credentials. Please try again.',
        );
      }

      _logger.i(
        'SupabaseService: Signing in with Google for ${googleUser.email}',
      );

      final response = await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );

      _logger.i(
        'SupabaseService: Google sign-in successful, user: ${response.user?.id}',
      );
      return response;
    } catch (e) {
      _logger.e('SupabaseService: Google sign-in failed: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    _logger.i('SupabaseService: Signing out, clearing all local caches');
    try {
      // Clear all cached data before signing out
      await CacheService.instance.clearAll();
    } catch (e) {
      _logger.w('SupabaseService: Error clearing cache on signOut: $e');
    }
    try {
      // Clear pending payment data
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        await PaymentStatusService().clearPendingPayment(userId);
      }
    } catch (e) {
      _logger.w('SupabaseService: Error clearing payment status on signOut: $e');
    }
    _memberTermsAcceptedCache.clear();
    _ageVerifiedCache.clear();
    _userRoleCache.clear();
    // A global sign-out makes a network call to revoke the refresh token. If the
    // device is offline (e.g. "Failed host lookup" / SocketException), that call
    // throws and would otherwise block sign-out, forcing the user to tap twice.
    // Fall back to a local-only sign-out so the on-device session is always
    // cleared on the first attempt regardless of connectivity.
    try {
      await client.auth.signOut();
    } catch (e) {
      _logger.w(
        'SupabaseService: global signOut failed ($e); clearing local session only',
      );
      try {
        await client.auth.signOut(scope: SignOutScope.local);
      } catch (e2) {
        _logger.w('SupabaseService: local signOut also failed: $e2');
      }
    }
  }

  Future<PasswordResetDelivery> resetPassword({required String email}) async {
    try {
      final method = await sendPasswordResetOtp(email: email);
      _logger.i('Password reset ${method.name} sent to: $email');
      return method;
    } catch (e) {
      _logger.e('Password reset failed for $email: $e');
      rethrow;
    }
  }

  Future<PasswordResetDelivery> sendPasswordResetOtp({
    required String email,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    try {
      // Use Supabase's password-recovery flow so the Reset password template
      // sends the recovery OTP instead of the Magic link template.
      await client.auth.resetPasswordForEmail(normalizedEmail);
      _logger.i('Password reset OTP sent to: $normalizedEmail');
      return PasswordResetDelivery.otp;
    } catch (e) {
      _logger.e('Password reset OTP failed for $normalizedEmail: $e');
      rethrow;
    }
  }

  Future<void> updatePassword({required String newPassword}) async {
    try {
      await client.auth.updateUser(UserAttributes(password: newPassword));
      _logger.i('Password updated successfully');
    } catch (e) {
      _logger.e('Password update failed: $e');
      rethrow;
    }
  }

  // Verify password reset OTP and update password
  Future<AuthResponse> verifyPasswordResetOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      // Verify the OTP using email type since we used signInWithOtp method
      final response = await client.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.email, // Use email type for signInWithOtp
      );

      if (response.user == null) {
        throw Exception('OTP verification failed');
      }

      _logger.i(
        'Password reset OTP verified for user: ${response.user!.email}',
      );

      // Now update the password
      await updatePassword(newPassword: newPassword);

      _logger.i('Password reset completed successfully for: $email');
      return response;
    } catch (e) {
      _logger.e('Password reset OTP verification failed: $e');
      if (e.toString().contains('expired')) {
        throw Exception('OTP has expired. Please request a new one.');
      } else if (e.toString().contains('invalid')) {
        throw Exception('Invalid OTP code. Please check and try again.');
      }
      throw Exception('Password reset failed. Please try again.');
    }
  }

  /// Verify a password-reset code WITHOUT changing the password.
  ///
  /// On success a recovery session is established so the caller can set the new
  /// password afterwards via [updatePassword]. This avoids writing a throwaway
  /// password during the reset flow (which would otherwise leave the account on
  /// a known temporary password if the user abandons the flow).
  Future<void> verifyPasswordResetCode({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await client.auth.verifyOTP(
        email: email.trim().toLowerCase(),
        token: otp.trim(),
        type: OtpType.recovery,
      );
      if (response.session == null || response.user == null) {
        throw Exception('Verification failed');
      }
      _logger.i('Password reset code verified for: ${response.user!.email}');
    } catch (e) {
      _logger.e('Password reset code verification failed: $e');
      rethrow;
    }
  }

  // Get current user
  User? getCurrentUser() {
    final user = client.auth.currentUser;
    _logger.d(
      'SupabaseService.getCurrentUser: ${user != null ? 'User authenticated: ${user.id}' : 'No authenticated user'}',
    );
    return user;
  }

  /// Fetch the role for the specified user id, or the current user if
  /// [userId] is not provided. Returns the role string (e.g. 'admin') or null.
  Future<String?> getUserRole({String? userId}) async {
    final lookupId = userId ?? client.auth.currentUser?.id;
    if (lookupId == null) return null;

    // Session cache: role is stable for the lifetime of a session.
    final cached = _userRoleCache[lookupId];
    if (cached != null) {
      return cached;
    }

    final resolved = await _resolveUserRole(userId: userId);
    if (resolved != null) {
      _userRoleCache[lookupId] = resolved;
    }
    return resolved;
  }

  Future<String?> _resolveUserRole({String? userId}) async {
    final user = client.auth.currentUser;
    final lookupId = userId ?? user?.id;
    if (lookupId == null) return null;

    _logger.d(
      'SupabaseService.getUserRole: looking up role for userId=$lookupId',
    );

    try {
      // Highest priority: authoritative admin emails. These accounts are the
      // platform owners and must ALWAYS resolve to 'admin', regardless of
      // metadata, RLS recursion, stale sessions, or missing DB rows. Only
      // applied when resolving the *current* user's own role.
      const adminEmails = <String>{
        'admin@locallekker.com',
        'locallekkerclub@gmail.com',
      };
      if ((userId == null || userId == user?.id) &&
          user?.email != null &&
          adminEmails.contains(user!.email!.trim().toLowerCase())) {
        _logger.d(
          'SupabaseService.getUserRole: authoritative admin email match for "${user.email}"',
        );
        return 'admin';
      }

      // First priority: check user metadata (set during signup - most authoritative)
      // NOTE: Only trust metadata for elevated roles (trusted_partner, admin).
      // 'member' is the default set on every signup and should always be
      // confirmed against the DB, because an admin/partner account may have
      // been created with default metadata and later promoted in the DB.
      if (user?.userMetadata != null &&
          user!.userMetadata!.containsKey('user_type')) {
        final userType = user.userMetadata!['user_type']?.toString();
        if (userType != null &&
            userType.isNotEmpty &&
            userType.toLowerCase() != 'member') {
          _logger.d(
            'SupabaseService.getUserRole: using user metadata, user_type="$userType"',
          );
          return userType;
        }
      }

      // Second priority: the SECURITY DEFINER get_my_role() RPC. This is the
      // most reliable source because it bypasses RLS and therefore avoids the
      // "infinite recursion detected in policy" errors that can silently break
      // the direct memberships/profiles table queries below. It resolves the
      // role only for the *currently authenticated* user (auth.uid()), so we
      // only use it when looking up the current user's own role.
      if (userId == null || userId == user?.id) {
        try {
          final rpcRes = await client.rpc('get_my_role');
          String? rpcRole;
          if (rpcRes is String) {
            rpcRole = rpcRes;
          } else if (rpcRes is Map && rpcRes.containsKey('role')) {
            rpcRole = rpcRes['role']?.toString();
          } else if (rpcRes is List && rpcRes.isNotEmpty) {
            final first = rpcRes.first;
            if (first is Map && first.containsKey('role')) {
              rpcRole = first['role']?.toString();
            } else if (first is String) {
              rpcRole = first;
            }
          }
          if (rpcRole != null && rpcRole.isNotEmpty) {
            _logger.d(
              'SupabaseService.getUserRole: resolved role via get_my_role() RPC: "$rpcRole"',
            );
            return rpcRole;
          }
        } catch (e) {
          _logger.w(
            'SupabaseService.getUserRole: get_my_role() RPC unavailable, falling back to direct queries: $e',
          );
        }
      }

      // Third priority: prefer the memberships table (memberships.user_id -> role).
      try {
        final memRes = await client
            .from('memberships')
            .select('role')
            .eq('user_id', lookupId)
            .limit(1)
            .maybeSingle();

        Map<String, dynamic>? memMap;
        if (memRes is Map<String, dynamic>) memMap = memRes;
        if (memMap != null && memMap.containsKey('role')) {
          final role = memMap['role']?.toString();
          _logger.d(
            'SupabaseService.getUserRole: found role in memberships table: "$role"',
          );
          return role;
        } else {
          _logger.d(
            'SupabaseService.getUserRole: no role found in memberships table',
          );
        }
      } catch (e) {
        // Check if this is the infinite recursion error
        if (e.toString().contains('infinite recursion detected in policy')) {
          _logger.w(
            'SupabaseService.getUserRole: Infinite recursion in memberships policy detected, skipping memberships table query',
          );
          // Skip to RPC fallback instead of trying profiles table
        } else {
          // Not fatal — we'll fall back to profiles or RPC below.
          _logger.e(
            'SupabaseService.getUserRole: memberships lookup failed: $e',
          );
        }
      }

      // Third priority: fallback to profiles table (profiles.id -> role).
      try {
        final profRes = await client
            .from('profiles')
            .select('role')
            .eq('id', lookupId)
            .limit(1)
            .maybeSingle();

        Map<String, dynamic>? profMap;
        if (profRes is Map<String, dynamic>) profMap = profRes;
        if (profMap != null && profMap.containsKey('role')) {
          final role = profMap['role']?.toString();
          _logger.d(
            'SupabaseService.getUserRole: found role in profiles table: "$role"',
          );
          return role;
        } else {
          _logger.d(
            'SupabaseService.getUserRole: no role found in profiles table',
          );
        }
      } catch (e) {
        // Check if this is also an infinite recursion error
        if (e.toString().contains('infinite recursion detected in policy')) {
          _logger.w(
            'SupabaseService.getUserRole: Infinite recursion in profiles policy detected, skipping profiles table query',
          );
          // Skip to RPC fallback
        } else {
          _logger.e('SupabaseService.getUserRole: profiles lookup failed: $e');
        }
      }

      // Final fallback: call a secure RPC (e.g. SECURITY DEFINER) that returns
      // the caller's role. Many projects expose `get_my_role()` for this.
      try {
        final rpcRes = await client.rpc('get_my_role');
        if (rpcRes == null) return null;

        if (rpcRes is String) return rpcRes;
        if (rpcRes is Map && rpcRes.containsKey('role')) {
          return rpcRes['role']?.toString();
        }
        if (rpcRes is List && rpcRes.isNotEmpty) {
          final first = rpcRes.first;
          if (first is Map && first.containsKey('role')) {
            return first['role']?.toString();
          }
          if (first is String) return first;
        }
      } catch (e) {
        _logger.e('SupabaseService.getUserRole RPC fallback failed: $e');
        // If the simple get_my_role RPC is not available (or RLS prevents
        // reading memberships), try calling the secure admin dashboard RPC
        // which is implemented as a SECURITY DEFINER function in the
        // backend. If it returns any data for the caller, we can infer
        // the caller is an admin. This is a best-effort fallback to
        // handle RLS-protected setups where memberships can't be selected.
        try {
          dynamic dashRes;
          try {
            dashRes = await client.rpc('secure_get_admin_dashboard').select();
          } catch (_) {
            dashRes = await client.rpc('get_admin_dashboard').select();
          }

          if (dashRes != null) {
            if (dashRes is List && dashRes.isNotEmpty) return 'admin';
            if (dashRes is Map && dashRes.isNotEmpty) return 'admin';
          }
        } catch (e2) {
          _logger.e(
            'SupabaseService.getUserRole admin-dashboard RPC fallback failed: $e2',
          );
        }
      }

      // Last-resort: email-based admin detection as a safety net when all
      // DB/RPC lookups fail (e.g. first boot before memberships row exists).
      if (user?.email == 'admin@locallekker.com' ||
          user?.email == 'locallekkerclub@gmail.com') {
        _logger.w(
          'SupabaseService.getUserRole: all DB lookups failed, falling back to email-based admin detection',
        );
        return 'admin';
      }

      return null;
    } catch (e) {
      // Keep debug print for now; callers will handle null role gracefully.
      _logger.e('Error fetching user role: $e');
      return null;
    }
  }

  // Check if user is authenticated
  bool isAuthenticated() {
    return client.auth.currentUser != null;
  }

  /// Returns true if the resolved role for [userId] (or current user when
  /// omitted) equals 'admin' (case-insensitive). Useful for quick guards.
  Future<bool> isAdmin({String? userId}) async {
    final role = await getUserRole(userId: userId);
    return (role ?? '').toLowerCase() == 'admin';
  }

  /// Returns true if the resolved role for [userId] (or current user when
  /// omitted) equals 'trusted_partner' (case-insensitive). Useful for quick guards.
  /// Trusted partners don't require subscription payments.
  Future<bool> isTrustedPartner({String? userId}) async {
    final role = await getUserRole(userId: userId);
    final result = (role ?? '').toLowerCase() == 'trusted_partner';
    _logger.d(
      'SupabaseService.isTrustedPartner: userId=$userId, role="$role", isTrustedPartner=$result',
    );
    return result;
  }

  // Listen to auth state changes
  Stream<AuthState> get authStateChanges {
    return client.auth.onAuthStateChange;
  }

  // Initialize auth state change listener
  void _initAuthStateListener() {
    _logger.i('SupabaseService: Setting up auth state change listener');
    client.auth.onAuthStateChange.listen(
      (AuthState authState) {
        _logger.d('SupabaseService: Auth state changed: ${authState.event}');
        _logger.d(
          'SupabaseService: Session exists: ${authState.session != null}',
        );
        _logger.d(
          'SupabaseService: User exists: ${authState.session?.user != null}',
        );

        switch (authState.event) {
          case AuthChangeEvent.signedIn:
            _logger.i(
              'SupabaseService: User signed in: ${authState.session?.user.id}',
            );
            _logger.d(
              'SupabaseService: Access token: ${authState.session?.accessToken != null ? "Present" : "Null"}',
            );
            _logger.d(
              'SupabaseService: Refresh token: ${authState.session?.refreshToken != null ? "Present" : "Null"}',
            );
            break;
          case AuthChangeEvent.signedOut:
            _logger.i('SupabaseService: User signed out');
            break;
          case AuthChangeEvent.tokenRefreshed:
            _logger.i('SupabaseService: Token refreshed successfully');
            _logger.d(
              'SupabaseService: New access token: ${authState.session?.accessToken != null ? "Present" : "Null"}',
            );
            break;
          case AuthChangeEvent.userUpdated:
            _logger.i('SupabaseService: User updated');
            break;
          case AuthChangeEvent.passwordRecovery:
            _logger.i('SupabaseService: Password recovery initiated');
            break;
          default:
            _logger.w(
              'SupabaseService: Unknown auth event: ${authState.event}',
            );
        }

        // Handle token refresh errors
        if (authState.session == null &&
            authState.event != AuthChangeEvent.signedOut) {
          _logger.w(
            'SupabaseService: Warning - Auth state changed but no session available',
          );
          _logger.w('SupabaseService: This might indicate a token grant error');
        }

        // Check for token expiration
        if (authState.session?.expiresAt != null) {
          final expiresAt = DateTime.fromMillisecondsSinceEpoch(
            authState.session!.expiresAt! * 1000,
          );
          final now = DateTime.now();
          final timeUntilExpiry = expiresAt.difference(now);
          _logger.d(
            'SupabaseService: Token expires in: ${timeUntilExpiry.inMinutes} minutes',
          );

          if (timeUntilExpiry.isNegative) {
            _logger.w('SupabaseService: Warning - Token has expired!');
          }
        }
      },
      onError: (error) {
        _logger.e('SupabaseService: Auth state change error: $error');
        // Handle token grant errors specifically
        if (error.toString().contains('token') ||
            error.toString().contains('grant')) {
          _logger.e('SupabaseService: Token grant error detected: $error');
          _logger.w('SupabaseService: This may require re-authentication');
        }

        // Handle network errors that might cause token issues
        if (error.toString().contains('network') ||
            error.toString().contains('connection')) {
          if (kDebugMode) {
            print(
              '🔐 SupabaseService: Network error during auth state change: $error',
            );
          }
        }
      },
    );
  }

  // OTP Verification methods
  Future<void> sendOtp({
    required String email,
    String? phone,
    required String method,
    bool isForSignIn = false,
    bool isResumeSignup = false,
    Map<String, dynamic>? userMetadata,
  }) async {
    try {
      if (method == 'sms') {
        final normalizedPhone = _normalizeSmsPhone(phone);
        await client.auth.signInWithOtp(
          phone: normalizedPhone,
          shouldCreateUser: !isForSignIn && !isResumeSignup,
          data: userMetadata,
        );
        _logger.i('SMS OTP sent to: $normalizedPhone');
      } else if (isForSignIn) {
        // For sign-in OTP, use signInWithOtp which sends OTP without creating account
        await client.auth.signInWithOtp(
          email: email,
          shouldCreateUser: false, // Don't create user if they don't exist
        );
        _logger.i('Sign-in OTP sent to: $email');
      } else if (isResumeSignup) {
        // Resume signup: auth user already exists (signup was abandoned),
        // re-send the verification OTP without creating a duplicate user.
        // Pass updated metadata so any edited profile fields propagate.
        await client.auth.signInWithOtp(
          email: email,
          shouldCreateUser: false,
          data: userMetadata,
        );
        _logger.i('Resume-signup OTP sent to: $email');
      } else {
        // For signup OTP, use signInWithOtp which creates account and sends 6-digit OTP
        await client.auth.signInWithOtp(
          email: email,
          shouldCreateUser: true, // Create user if they don't exist
          data: userMetadata,
        );
        _logger.i('Sign-up OTP sent to: $email');
      }
      _logger.i('OTP sent successfully to $email');
    } catch (e) {
      // Print full exception type and value for debugging
      _logger.e('Error sending OTP (${e.runtimeType}): $e');
      if (e.toString().contains('rate_limit') ||
          e.toString().contains('over_email_send_rate_limit') ||
          e.toString().contains('For security purposes')) {
        throw Exception(
          'Too many OTP requests. Please wait before trying again.',
        );
      }
      rethrow;
    }
  }

  String _normalizeSmsPhone(String? phone) {
    final compactPhone = phone?.replaceAll(RegExp(r'[\s()-]'), '') ?? '';
    if (compactPhone.startsWith('+') &&
        RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(compactPhone)) {
      return compactPhone;
    }
    if (RegExp(r'^0\d{9}$').hasMatch(compactPhone)) {
      return '+27${compactPhone.substring(1)}';
    }
    throw Exception(
      'Enter a valid mobile number, for example +27821234567.',
    );
  }

  Future<AuthResponse> verifyOtp({
    required String email,
    String? phone,
    required String otp,
    required String method,
    bool isForSignIn = false,
  }) async {
    try {
      // OTPs are sent via signInWithOtp for both sign-in and signup flows.
      // Verification must therefore use OtpType.email for email delivery,
      // otherwise valid codes can be rejected as the wrong token type.
      final otpType = method == 'email' ? OtpType.email : OtpType.sms;

      final response = method == 'sms'
          ? await client.auth.verifyOTP(
              phone: _normalizeSmsPhone(phone),
              token: otp,
              type: otpType,
            )
          : await client.auth.verifyOTP(
              email: email,
              token: otp,
              type: otpType,
            );

      if (response.user == null) {
        throw Exception('OTP verification failed');
      }

      _logger.i('OTP verified successfully for user: ${response.user!.email}');
      _logger.i('OTP verification response user ID: ${response.user!.id}');
      _logger.i(
        'OTP verification response session: ${response.session != null}',
      );
      _logger.i(
        'OTP verification response user email_confirmed_at: ${response.user!.emailConfirmedAt}',
      );
      _logger.i(
        'OTP verification response user created_at: ${response.user!.createdAt}',
      );

      // Ensure profile exists and email is marked verified; overall verification
      // stays tied to terms acceptance + payment completion.
      try {
        final userId = response.user!.id;
        final userMetadata = response.user!.userMetadata ?? {};

        // First, check if profile exists
        final existingProfile = await client
            .from('profiles')
            .select('id')
            .eq('id', userId)
            .maybeSingle();

        if (existingProfile == null) {
          // Profile doesn't exist, create it from user metadata
          _logger.i(
            'OTP verification: Profile not found, creating from user metadata',
          );

          final profileData = {
            'id': userId,
            'email': response.user!.email,
            'name': userMetadata['name'] ?? '',
            'surname': userMetadata['surname'] ?? '',
            'role': userMetadata['user_type'] ?? 'member',
            // New profiles start unverified until terms + payment are confirmed
            'verified': false,
            'email_verified': true,
            'admin_created': userMetadata['admin_created'] == 'true',
            'password_set': userMetadata['password_set'] == 'true',
            // Add other metadata fields if they exist
            if (userMetadata['date_of_birth'] != null)
              'date_of_birth': userMetadata['date_of_birth'],
            if (userMetadata['gender'] != null)
              'gender': userMetadata['gender'],
            if (userMetadata['ethnicity'] != null)
              'ethnicity': userMetadata['ethnicity'],
            if (userMetadata['province'] != null)
              'province': userMetadata['province'],
            if (userMetadata['street'] != null)
              'street': userMetadata['street'],
            if (userMetadata['suburb'] != null)
              'suburb': userMetadata['suburb'],
            if (userMetadata['city'] != null) 'city': userMetadata['city'],
            if (userMetadata['contact'] != null)
              'contact': userMetadata['contact'],
            if (userMetadata['business_name'] != null)
              'business_name': userMetadata['business_name'],
          };

          await client.from('profiles').upsert(profileData);

          // If this is a trusted partner, create the trusted_partners and memberships records
          if (profileData['role'] == 'trusted_partner') {
            // Create trusted_partners record
            await client.from('trusted_partners').insert({
              'user_id': userId,
              'business_name': userMetadata['business_name'] ?? '',
              'created_by_admin': userMetadata['admin_created'] == 'true',
            });

            // Create memberships record
            await client.from('memberships').insert({
              'user_id': userId,
              'role': 'trusted_partner',
              'gateway': 'admin_creation',
            });
          }

          _logger.i(
            'OTP verification: Created profile and marked email_verified=true for user $userId',
          );
        } else {
          // Profile exists, only ensure email verification flag is set
          await client
              .from('profiles')
              .update({'email_verified': true})
              .eq('id', userId);
          _logger.i(
            'OTP verification: Updated email_verified=true for user $userId',
          );
        }
      } catch (e) {
        // Non-fatal: log the error but don't fail OTP verification
        _logger.w('OTP verification: Failed to update verified status: $e');
      }

      // Best-effort: ensure a matching row exists in `public.users` so
      // subsequent RPCs that reference that table via foreign keys don't
      // fail for newly created auth users. This avoids a race between
      // Supabase Auth and application tables in environments where
      // historical data may be missing.
      try {
        final authUser = response.user!;
        final upsertRow = <String, dynamic>{
          'id': authUser.id,
          'email': authUser.email,
          // created_at column is often timestamptz with default now();
          // include it explicitly as ISO string to be safe when the
          // column exists and is NOT NULL.
          'created_at': DateTime.now().toIso8601String(),
        };

        // Log the raw PostgREST result so we can see if RLS silently
        // blocked the insert or returned an empty response.
        final upsertRes = await client.from('users').upsert(upsertRow).select();
        _logger.i(
          '✅ public.users upsert result for ${authUser.id}: $upsertRes',
        );
      } catch (e) {
        // Non-fatal. Log for observability but don't break OTP flow.
        _logger.w('⚠️ Failed to upsert public.users after OTP: $e');
      }

      return response;
    } catch (e) {
      _logger.e('Error verifying OTP: $e');

      // Handle specific token grant errors
      if (e.toString().contains('token') || e.toString().contains('grant')) {
        _logger.e('Token grant error during OTP verification: $e');
        throw Exception(
          'Verification failed due to authentication error. Please try again.',
        );
      }

      if (e.toString().contains('expired')) {
        throw Exception('OTP has expired. Please request a new one.');
      } else if (e.toString().contains('invalid')) {
        throw Exception('Invalid OTP code. Please check and try again.');
      }
      throw Exception('OTP verification failed. Please try again.');
    }
  }

  // Enhanced OTP sign-in method
  Future<AuthResponse> signInWithOtp({
    required String email,
    String? phone,
    required String method,
  }) async {
    try {
      // Send OTP for sign-in
      await sendOtp(
        email: email,
        phone: phone,
        method: method,
        isForSignIn: true,
      );

      // Return a response indicating OTP was sent
      // The actual verification will happen separately
      return AuthResponse(user: null, session: null);
    } catch (e) {
      _logger.e('Error in OTP sign-in: $e');
      rethrow;
    }
  }

  // Store additional user data after signup
  Future<void> createUserProfile({
    required String userId,
    required Map<String, dynamic> userData,
  }) async {
    try {
      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createUserProfile: Creating profile for userId=$userId',
        );
      }
      if (kDebugMode) {
        print('🔐 SupabaseService.createUserProfile: userData=$userData');
      }

      // Check current authentication state
      final authUser = client.auth.currentUser;
      if (kDebugMode) {
        print('🔐 SupabaseService.createUserProfile: authUser=$authUser');
      }
      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createUserProfile: authUser?.userMetadata=${authUser?.userMetadata}',
        );
      }

      // Use direct table access instead of RPC to avoid permission issues
      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createUserProfile: Using direct table access',
        );
      }

      // Get the user type from metadata to determine the correct role
      final currentUser = client.auth.currentUser;
      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createUserProfile: currentUser: $currentUser',
        );
      }
      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createUserProfile: currentUser.id: ${currentUser?.id}',
        );
      }
      if (kDebugMode) {
        print('🔐 SupabaseService.createUserProfile: userId: $userId');
      }
      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createUserProfile: IDs match: ${currentUser?.id == userId}',
        );
      }

      String? userType = currentUser?.userMetadata?['user_type'] as String?;
      userType ??= 'member';
      final role = userType == 'trusted_partner' ? 'trusted_partner' : 'member';

      final profileData = {
        'id': userId,
        'email': (userData['email'] as String?)?.trim().toLowerCase(),
        'name': userData['name'],
        'surname': userData['surname'],
        'date_of_birth': userData['date_of_birth'] != null
            ? userData['date_of_birth'].toString().split(
                'T',
              )[0] // Extract date part only
            : null,
        'gender': userData['gender'],
        'ethnicity': userData['ethnicity'],
        'province': userData['province'],
        'street': userData['street'],
        'suburb': userData['suburb'],
        'city': userData['city'],
        'contact': userData['contact'],
        'role': role,
        'subscription': role == 'member' ? 'pending' : 'active',
      };

      // Remove null values
      profileData.removeWhere((key, value) => value == null);

      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createUserProfile: profileData: $profileData',
        );
      }

      var profileSaved = false;

      try {
        // Avoid upsert+select here because some RLS/policy combinations
        // allow the write but fail the chained readback.
        await client.from('profiles').upsert(profileData);
        profileSaved = true;
      } catch (upsertError) {
        if (kDebugMode) {
          print(
            '🔐 SupabaseService.createUserProfile: upsert error: $upsertError',
          );
        }

        // Fallback for deployments where profiles policies recurse or block
        // direct writes but allow the security-definer RPC path.
        final errorText = upsertError.toString().toLowerCase();
        final shouldTryRpcFallback =
            _isProfilesRecursionError(upsertError) ||
            errorText.contains('row-level security') ||
            errorText.contains('permission denied') ||
            errorText.contains('not allowed');

        if (shouldTryRpcFallback) {
          try {
            final rpcData = Map<String, dynamic>.from(profileData);

            try {
              await client.rpc(
                'create_user_profile',
                params: {'p_user_id': userId, 'p_user_data': rpcData},
              );
            } catch (rpcError) {
              // Keep compatibility with older deployments where the RPC may
              // still reject date_of_birth parsing.
              final retryData = Map<String, dynamic>.from(rpcData)
                ..remove('date_of_birth');
              await client.rpc(
                'create_user_profile',
                params: {'p_user_id': userId, 'p_user_data': retryData},
              );

              if (kDebugMode) {
                print(
                  '🔐 SupabaseService.createUserProfile: create_user_profile retry succeeded without date_of_birth after initial failure: $rpcError',
                );
              }
            }

            profileSaved = true;

            if (kDebugMode) {
              print(
                '🔐 SupabaseService.createUserProfile: create_user_profile RPC fallback succeeded',
              );
            }
          } catch (rpcError) {
            if (kDebugMode) {
              print(
                '🔐 SupabaseService.createUserProfile: create_user_profile RPC fallback failed: $rpcError',
              );
            }
          }
        }

        if (!profileSaved) {
          rethrow;
        }
      }

      // Try to create membership
      try {
        await client.from('memberships').upsert({
          'user_id': userId,
          'role': role,
          'gateway': 'user_signup',
        });
      } catch (membershipError) {
        if (kDebugMode) {
          print(
            '🔐 SupabaseService.createUserProfile: Membership creation failed: $membershipError',
          );
        }
      }

      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createUserProfile: Profile created successfully via direct access',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createUserProfile: Error creating profile: $e',
        );
      }
      // Continue without failing the signup process
      // The user authentication was successful, which is the main requirement
      rethrow; // Re-throw so the calling code knows it failed
    }
  }

  /// Authorize a user as a trusted partner by inserting/upserting a row in the
  /// `memberships` table (user_id -> role = 'trusted_partner') and attempting to
  /// set the `profiles.role` to 'trusted_partner' as a best-effort step. Returns
  /// true when the operation completed without throwing (it may still be
  /// rejected by DB policies remotely; callers should handle false/throws).
  Future<bool> authorizeTrustedPartner({required String userId}) async {
    try {
      final row = {'user_id': userId, 'role': 'trusted_partner'};

      // Try to upsert into memberships so repeated attempts don't fail.
      try {
        await client.from('memberships').upsert(row).select();
        _logger.i(
          'authorizeTrustedPartner: memberships row upserted for $userId',
        );
      } catch (e) {
        _logger.e('authorizeTrustedPartner: could not upsert memberships: $e');
      }

      // Best-effort: update profiles.role if the table exists and policies
      // allow it for the current principal.
      try {
        await client.from('profiles').upsert({
          'id': userId,
          'role': 'trusted_partner',
        }).select();
        _logger.i(
          'authorizeTrustedPartner: profiles.role upserted for $userId',
        );
      } catch (e) {
        _logger.e('authorizeTrustedPartner: could not upsert profiles: $e');
      }

      return true;
    } catch (e) {
      _logger.e('authorizeTrustedPartner failed: $e');
      return false;
    }
  }

  // Store trusted partner data after signup
  Future<void> createTrustedPartnerProfile({
    required String userId,
    required Map<String, dynamic> trustedPartnerData,
  }) async {
    try {
      // Only include columns that exist in the current `trusted_partners` table to
      // avoid Postgrest errors when sending unknown fields (e.g. 'city').
      // At the moment the table in the database contains at least:
      // - id (uuid)
      // - user_id (uuid)
      // - business_name (text NOT NULL)
      // - created_at (timestamptz default now())
      // Keep this list small and explicit. If you later add columns to the
      // DB, update this list or add migrations to keep the client in sync.
      final allowed = <String>{'user_id', 'business_name', 'created_at'};

      final row = <String, dynamic>{
        'user_id': userId,
        'business_name': trustedPartnerData['business_name'],
        // created_at can be left to the DB default, but include if provided
        if (trustedPartnerData.containsKey('created_at'))
          'created_at': trustedPartnerData['created_at'],
      };

      // Remove null values and any keys not in the allowed set
      row.removeWhere((k, v) => v == null || !allowed.contains(k));

      // Try to insert the trusted partner row. Use insert() so we don't accidentally
      // trigger upsert semantics against the primary key. Do not request
      // fields the DB doesn't have.
      final inserted = await client
          .from('trusted_partners')
          .insert(row)
          .select()
          .maybeSingle();

      if (inserted == null) {
        _logger.w('createTrustedPartnerProfile: insert returned null (no row)');
      } else {
        _logger.i(
          'createTrustedPartnerProfile: trusted partner row created: $inserted',
        );
      }
    } catch (e) {
      // Log the error but do not fail the overall signup flow. The user is
      // already created in Supabase Auth; trusted partner profile can be retried.
      _logger.e('Error creating trusted partner profile: $e');
      // Re-throwing would bubble the error up to the UI; we keep it local so
      // account creation remains successful even if DB insert fails.
    }
  }

  /// Calls a server-side RPC to complete trusted partner signup in one privileged
  /// operation. The RPC `complete_trusted_partner_signup` should be implemented
  /// server-side as a SECURITY DEFINER function that upserts memberships,
  /// profiles and trusted_partners (idempotent). `params` is a plain map of values
  /// expected by the RPC (e.g. first_name, surname, business_name, category,
  /// street, suburb, city, province, contact_email, latitude, longitude).
  Future<dynamic> completeTrustedPartnerSignup(
    Map<String, dynamic> params,
  ) async {
    try {
      // The server-side RPC is defined as complete_trusted_partner_signup(payload jsonb)
      // so PostgREST expects a single argument named `payload` containing the
      // JSON payload. Wrap the provided params map under that key so the
      // request matches the function signature and avoids function-not-found
      // errors caused by mismatched parameter names/types.
      final res = await client.rpc(
        'complete_trusted_partner_signup',
        params: {'payload': params},
      );
      _logger.i('completeTrustedPartnerSignup: rpc returned: $res');
      return res;
    } on PostgrestException catch (e) {
      _logger.e('completeTrustedPartnerSignup PostgrestException: $e');
      rethrow;
    } catch (e) {
      _logger.e('completeTrustedPartnerSignup error: $e');
      rethrow;
    }
  }

  /// Calls the server-side RPC `complete_business_profile(payload jsonb)`
  /// which upserts or updates the caller's business record. Returns the RPC
  /// result (usually a JSON-like Map or string).
  Future<dynamic> completeBusinessProfile(Map<String, dynamic> params) async {
    try {
      _logger.i('completeBusinessProfile: calling rpc with payload: $params');

      final res = await client.rpc(
        'complete_business_profile',
        params: {'payload': params},
      );
      _logger.i('completeBusinessProfile: rpc returned: $res');
      return res;
    } on PostgrestException catch (e) {
      _logger.e('completeBusinessProfile PostgrestException: $e');
      rethrow;
    } catch (e) {
      _logger.e('completeBusinessProfile error: $e');
      rethrow;
    }
  }

  /// Returns true if the trusted partner has a completed business profile.
  /// Business profile is considered complete when a row exists in `businesses`
  /// for the authenticated user (owner_member_id) and has a non-empty name and category.
  Future<bool> isBusinessProfileComplete(String userId) async {
    try {
      final res = await client
          .from('businesses')
          .select('id, name, category')
          .eq('owner_member_id', userId)
          .limit(1)
          .maybeSingle();

      if (res == null) return false;
      final name = (res['name'] as String?)?.trim() ?? '';
      final category = (res['category'] as String?)?.trim() ?? '';
      final complete = name.isNotEmpty && category.isNotEmpty;
      _logger.d('isBusinessProfileComplete for $userId => $complete');
      return complete;
    } catch (e) {
      _logger.w('isBusinessProfileComplete error: $e');
      return false;
    }
  }

  /// Utility method to fix merchant role for existing users
  /// This can be called from debug console or during development
  Future<void> fixMerchantRole(String userId) async {
    try {
      if (kDebugMode) {
        print(
          'SupabaseService.fixMerchantRole: Setting role to merchant for user $userId',
        );
      }
      await client.from('profiles').upsert({
        'id': userId,
        'role': 'merchant',
      }).select();
      if (kDebugMode) {
        print(
          'SupabaseService.fixMerchantRole: Successfully set role for user $userId',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print(
          'SupabaseService.fixMerchantRole: Failed to set role for user $userId: $e',
        );
      }
    }
  }

  /// available or fails. This is useful to ensure `public.users` and
  /// `public.profiles` exist before calling privileged RPCs.
  Future<Map<String, dynamic>> prepareUserContext() async {
    try {
      // Prefer a server-side SECURITY DEFINER RPC named
      // `prepare_user_context(payload jsonb)` which should insert missing
      // rows in a trusted context. If it exists, call it and return the
      // result.
      try {
        final rpcRes = await client.rpc('prepare_user_context');
        if (rpcRes != null) {
          _logger.i('prepareUserContext: server RPC returned: $rpcRes');
          if (rpcRes is Map<String, dynamic>) return rpcRes;
          return {'ok': true, 'result': rpcRes};
        }
      } catch (e) {
        _logger.w('prepareUserContext: server RPC not available or failed: $e');
      }

      // Fallback: perform a best-effort client upsert into `public.users`.
      final uid = client.auth.currentUser?.id;
      final email = client.auth.currentUser?.email;
      if (uid != null && email != null) {
        try {
          final upsertRow = {
            'id': uid,
            'email': email,
            'created_at': DateTime.now().toIso8601String(),
          };
          final upRes = await client.from('users').upsert(upsertRow).select();
          _logger.i('prepareUserContext: client upsert result: $upRes');
          return {'ok': true};
        } catch (e) {
          _logger.e('prepareUserContext: client upsert failed: $e');
          return {'ok': false, 'error': e.toString()};
        }
      }

      return {'ok': false, 'error': 'no_authenticated_user'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  // Debug method to check what profile data exists for current user
  Future<void> debugUserProfile() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) {
        if (kDebugMode) {
          print('🔐 DEBUG: No authenticated user');
        }
        return;
      }

      if (kDebugMode) {
        print(
          '🔐 DEBUG: Checking profile data for user: ${user.email} (${user.id})',
        );
      }

      final response = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response == null) {
        if (kDebugMode) {
          print('🔐 DEBUG: No profile data found for user');
        }
        return;
      }

      if (kDebugMode) {
        print('🔐 DEBUG: Profile data found:');
      }
      response.forEach((key, value) {
        if (kDebugMode) {
          print('🔐 DEBUG: $key = $value (${value?.runtimeType})');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('🔐 DEBUG: Error checking profile data: $e');
      }
    }
  }

  /// Manually refresh the current session tokens
  /// This can be useful for debugging token grant issues
  Future<void> refreshSession() async {
    try {
      if (kDebugMode) {
        print('🔐 SupabaseService: Manually refreshing session tokens');
      }
      final response = await client.auth.refreshSession();
      if (kDebugMode) {
        print('🔐 SupabaseService: Session refresh successful');
      }
      if (kDebugMode) {
        print(
          '🔐 SupabaseService: New access token: ${response.session?.accessToken != null ? "Present" : "Null"}',
        );
      }
      if (kDebugMode) {
        print(
          '🔐 SupabaseService: New refresh token: ${response.session?.refreshToken != null ? "Present" : "Null"}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('🔐 SupabaseService: Session refresh failed: $e');
      }
      if (e.toString().contains('token') || e.toString().contains('grant')) {
        if (kDebugMode) {
          print(
            '🔐 SupabaseService: Token grant error during session refresh: $e',
          );
        }
        throw Exception('Token refresh failed. You may need to sign in again.');
      }
      rethrow;
    }
  }

  /// Check if the current session is valid and tokens are not expired
  Future<bool> isSessionValid() async {
    try {
      final user = client.auth.currentUser;
      final session = client.auth.currentSession;

      if (user == null || session == null) {
        if (kDebugMode) {
          print('🔐 SupabaseService: No active session');
        }
        return false;
      }

      // Check if token is expired
      if (session.expiresAt != null) {
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(
          session.expiresAt! * 1000,
        );
        final now = DateTime.now();
        final isExpired = now.isAfter(expiresAt);

        if (kDebugMode) {
          print('🔐 SupabaseService: Session expires at: $expiresAt');
        }
        if (kDebugMode) {
          print('🔐 SupabaseService: Current time: $now');
        }
        if (kDebugMode) {
          print('🔐 SupabaseService: Session expired: $isExpired');
        }

        if (isExpired) {
          if (kDebugMode) {
            print(
              '🔐 SupabaseService: Session has expired, attempting refresh',
            );
          }
          await refreshSession();
          return true; // If refresh succeeds, session is now valid
        }
      }

      if (kDebugMode) {
        print('🔐 SupabaseService: Session is valid');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('🔐 SupabaseService: Error checking session validity: $e');
      }
      return false;
    }
  }

  /// Check network connectivity and Supabase reachability
  Future<bool> checkConnectivity() async {
    try {
      if (kDebugMode) {
        print('🔐 SupabaseService: Checking connectivity...');
      }

      // Try to make a simple request to Supabase
      await client.from('users').select('count').limit(1).maybeSingle();
      if (kDebugMode) {
        print('🔐 SupabaseService: Connectivity check successful');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('🔐 SupabaseService: Connectivity check failed: $e');
      }

      // Check if it's a network-related error
      if (e.toString().contains('network') ||
          e.toString().contains('connection') ||
          e.toString().contains('timeout') ||
          e.toString().contains('unreachable')) {
        if (kDebugMode) {
          print('🔐 SupabaseService: Network connectivity issue detected');
        }
        return false;
      }

      // Check if it's a permission-related error
      if (e.toString().contains('permission') ||
          e.toString().contains('denied') ||
          e.toString().contains('forbidden')) {
        if (kDebugMode) {
          print(
            '🔐 SupabaseService: Permission issue detected - likely missing INTERNET permission in release build',
          );
        }
        return false;
      }

      return false;
    }
  }

  // Profile management methods
  Future<Map<String, dynamic>?> getUserProfile({String? userId}) async {
    try {
      final user = client.auth.currentUser;
      final lookupId = userId ?? user?.id;
      if (lookupId == null) {
        if (kDebugMode) {
          print('🔐 SupabaseService.getUserProfile: No user ID available');
        }
        throw Exception('User not authenticated');
      }

      if (kDebugMode) {
        print(
          '🔐 SupabaseService.getUserProfile: Fetching profile for userId=$lookupId',
        );
      }

      final response = await client
          .from('profiles')
          .select()
          .eq('id', lookupId)
          .single();

      if (kDebugMode) {
        print(
          '🔐 SupabaseService.getUserProfile: Profile data retrieved successfully',
        );
      }
      if (kDebugMode) {
        print('🔐 SupabaseService.getUserProfile: Retrieved data: $response');
      }

      // Log each field individually for debugging
      if (kDebugMode) {
        print('🔐 SupabaseService.getUserProfile: Individual fields:');
      }
      response.forEach((key, value) {
        if (kDebugMode) {
          print(
            '🔐 SupabaseService.getUserProfile: $key = $value (${value.runtimeType})',
          );
        }
      });

      return response;
    } catch (e) {
      if (kDebugMode) {
        print('🔐 SupabaseService.getUserProfile: Error fetching profile: $e');
      }

      // Check if it's a "no rows" error (profile doesn't exist)
      if (e.toString().contains(
            'Cannot coerce the result to a single JSON object',
          ) ||
          e.toString().contains('0 rows')) {
        if (kDebugMode) {
          print(
            '🔐 SupabaseService.getUserProfile: Profile does not exist yet',
          );
        }
        return null; // This is expected for new users
      }

      // Re-throw other errors with more context
      throw Exception('Database error: ${e.toString()}');
    }
  }

  Future<bool> updateUserProfile({
    required String userId,
    required Map<String, dynamic> profileData,
  }) async {
    try {
      if (kDebugMode) {
        print(
          '🔐 SupabaseService.updateUserProfile: Updating profile for userId=$userId',
        );
      }
      if (kDebugMode) {
        print(
          '🔐 SupabaseService.updateUserProfile: Data to update: $profileData',
        );
      }

      // Remove null values and prepare data for update
      final cleanData = Map<String, dynamic>.from(profileData);
      cleanData.removeWhere((key, value) => value == null);
      if (kDebugMode) {
        print('🔐 SupabaseService.updateUserProfile: Clean data: $cleanData');
      }

      if (cleanData.isEmpty) {
        if (kDebugMode) {
          print(
            '🔐 SupabaseService.updateUserProfile: No non-null profile fields supplied, skipping update',
          );
        }
        return true;
      }

      // Avoid update+select here because some RLS policy combinations recurse
      // when a SELECT is chained to UPDATE on profiles.
      await client.from('profiles').update(cleanData).eq('id', userId);

      if (kDebugMode) {
        print(
          '🔐 SupabaseService.updateUserProfile: Profile updated successfully',
        );
      }
      return true;
    } catch (e) {
      // Fallback for environments where profiles RLS policies recurse (42P17).
      // Use security-definer RPC if available to persist profile updates.
      if (_isProfilesRecursionError(e)) {
        if (kDebugMode) {
          print(
            '🔐 SupabaseService.updateUserProfile: detected profiles recursion, attempting create_user_profile RPC fallback',
          );
        }

        try {
          final fallbackData = Map<String, dynamic>.from(profileData);
          fallbackData.removeWhere((key, value) => value == null);
          fallbackData['email'] ??= client.auth.currentUser?.email;

          try {
            await client.rpc(
              'create_user_profile',
              params: {'p_user_id': userId, 'p_user_data': fallbackData},
            );
          } catch (rpcError) {
            // Keep a safe fallback for environments where the RPC is still on
            // an older deployment that cannot parse date_of_birth.
            final retryData = Map<String, dynamic>.from(fallbackData)
              ..remove('date_of_birth');
            await client.rpc(
              'create_user_profile',
              params: {'p_user_id': userId, 'p_user_data': retryData},
            );
            if (kDebugMode) {
              print(
                '🔐 SupabaseService.updateUserProfile: create_user_profile retry succeeded without date_of_birth after initial failure: $rpcError',
              );
            }
          }

          if (kDebugMode) {
            print(
              '🔐 SupabaseService.updateUserProfile: create_user_profile fallback succeeded',
            );
          }
          return true;
        } catch (rpcError) {
          if (kDebugMode) {
            print(
              '🔐 SupabaseService.updateUserProfile: create_user_profile fallback failed: $rpcError',
            );
          }
        }
      }

      if (kDebugMode) {
        print(
          '🔐 SupabaseService.updateUserProfile: Error updating profile: $e',
        );
      }
      return false;
    }
  }

  bool _isProfilesRecursionError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('42p17') ||
        (message.contains('infinite recursion') &&
            message.contains('relation "profiles"'));
  }

  // Create initial profile for user
  Future<bool> createInitialUserProfile() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) {
        if (kDebugMode) {
          print(
            '🔐 SupabaseService.createInitialUserProfile: No authenticated user',
          );
        }
        throw Exception('User not authenticated');
      }

      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createInitialUserProfile: Creating initial profile for userId=${user.id}',
        );
      }

      // Only use columns that are known to exist in the database
      final profileData = {
        'id': user.id,
        'email': user.email,
        'name': '', // Will be empty initially
        'surname': '', // Added in migration
      };

      await client.from('profiles').upsert(profileData);

      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createInitialUserProfile: Initial profile created successfully',
        );
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print(
          '🔐 SupabaseService.createInitialUserProfile: Error creating initial profile: $e',
        );
      }
      // Re-throw with more context
      throw Exception('Failed to create profile: ${e.toString()}');
    }
  }

  // Temporary method to check role for clydemflan@gmail.com

  /// Test method to verify trigger is working
  Future<Map<String, dynamic>> testTriggerFunctionality() async {
    try {
      // Create a test user with a valid email format that Supabase accepts
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testEmail = 'testuser$timestamp@gmail.com';
      final response = await signUp(
        email: testEmail,
        password: 'TestPass123!',
        userMetadata: {'user_type': 'user', 'name': 'Test User'},
      );

      if (response.user == null) {
        return {'success': false, 'error': 'User creation failed'};
      }

      final userId = response.user!.id;

      // Wait a moment for trigger to execute
      await Future.delayed(const Duration(seconds: 2));

      // Check if profile was created
      final profileCheck = await client
          .from('profiles')
          .select('*')
          .eq('id', userId)
          .maybeSingle();

      // Check if membership was created
      final membershipCheck = await client
          .from('memberships')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();

      return {
        'success': true,
        'user_id': userId,
        'profile_created': profileCheck != null,
        'membership_created': membershipCheck != null,
        'profile_data': profileCheck,
        'membership_data': membershipCheck,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Check if email exists in the database
  Future<bool> checkEmailExists(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    _logger.i('checkEmailExists: Checking email: "$normalizedEmail"');

    // Treat deactivated accounts as non-existent for sign-in flows
    try {
      final isDeactivated = await isEmailDeactivated(normalizedEmail);
      if (isDeactivated) {
        _logger.w(
          'checkEmailExists: Email belongs to deactivated account, treating as not found',
        );
        return false;
      }
    } catch (e) {
      _logger.w('checkEmailExists: Failed deactivation check: $e');
    }

    // Strategy 1: Try RPC function first (bypasses RLS if function uses SECURITY DEFINER)
    try {
      final response = await client.rpc(
        'check_email_exists',
        params: {'user_email': normalizedEmail},
      );
      final result = response as bool;
      _logger.i('checkEmailExists: RPC success - exists: $result');
      return result;
    } catch (rpcError) {
      _logger.w('checkEmailExists: RPC failed: $rpcError');
    }

    // Strategy 2: Try authentication probe - most reliable method
    // Attempt sign-in with impossible password to check if email exists
    _logger.i('checkEmailExists: Trying auth probe method');
    try {
      await client.auth.signInWithPassword(
        email: normalizedEmail,
        password:
            '__impossible_probe_${DateTime.now().millisecondsSinceEpoch}__',
      );
      // Should never reach here
      return false;
    } catch (authError) {
      final errorMsg = authError.toString().toLowerCase();
      _logger.i('checkEmailExists: Auth error: $errorMsg');

      // These errors indicate the email EXISTS in the system
      if (errorMsg.contains('invalid') ||
          errorMsg.contains('credentials') ||
          errorMsg.contains('password') ||
          errorMsg.contains('email not confirmed')) {
        _logger.i('checkEmailExists: ✅ Email exists (wrong password)');
        return true;
      }

      // These errors indicate email DOES NOT exist
      if (errorMsg.contains('not found') ||
          errorMsg.contains('user not found')) {
        _logger.i('checkEmailExists: ❌ Email not found');
        return false;
      }

      // Unknown error - be permissive and return true
      _logger.w('checkEmailExists: Unknown auth error, returning true');
      return true;
    }
  }

  Future<bool> isEmailDeactivated(String email) async {
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final profile = await client
          .from('profiles')
          .select('is_deactivated')
          .eq('email', normalizedEmail)
          .maybeSingle();

      if (profile == null) {
        _logger.d(
          'isEmailDeactivated: No profile found for $normalizedEmail; treating as active',
        );
        return false;
      }

      final deactivated = profile['is_deactivated'] == true;
      if (deactivated) {
        _logger.w(
          'isEmailDeactivated: Account is deactivated for $normalizedEmail',
        );
      } else {
        _logger.d('isEmailDeactivated: Account active for $normalizedEmail');
      }

      return deactivated;
    } catch (e) {
      _logger.w('isEmailDeactivated: Unable to check status for $email: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getProfileByEmail(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    _logger.d('getProfileByEmail: looking up $normalizedEmail');

    // Strategy 1: RPC function (SECURITY DEFINER) for signup prefill lookup.
    // This supports abandoned-signup detection before authentication where
    // direct table reads can be blocked by RLS.
    try {
      final rpcResponse = await client.rpc(
        'get_signup_profile_by_email',
        params: {'user_email': normalizedEmail},
      );

      if (rpcResponse != null) {
        if (rpcResponse is List && rpcResponse.isNotEmpty) {
          final profile = Map<String, dynamic>.from(
            rpcResponse.first as Map,
          );
          _logger.d('getProfileByEmail: RPC profile found for $normalizedEmail');
          return profile;
        }

        if (rpcResponse is Map) {
          final profile = Map<String, dynamic>.from(rpcResponse);
          _logger.d('getProfileByEmail: RPC profile found for $normalizedEmail');
          return profile;
        }
      }
    } catch (rpcError) {
      _logger.w('getProfileByEmail: RPC lookup failed for $normalizedEmail: $rpcError');
    }

    // Strategy 2: direct table read (works when RLS allows it).
    try {
      final profile = await client
          .from('profiles')
          .select(
            'id, email, name, surname, street, suburb, city, province, contact, gender, ethnicity, date_of_birth, is_deactivated, subscription, role, is_tp_member, profile_photo_url',
          )
          .eq('email', normalizedEmail)
          .maybeSingle();

      if (profile == null) {
        _logger.d('getProfileByEmail: no profile found for $normalizedEmail');
        return null;
      }

      _logger.d('getProfileByEmail: profile found for $normalizedEmail');
      return Map<String, dynamic>.from(profile);
    } catch (e) {
      _logger.w('getProfileByEmail: lookup failed for $normalizedEmail: $e');
      return null;
    }
  }

  // Check if user is admin-created and needs password setup
  Future<Map<String, dynamic>> checkAdminCreatedStatus(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      _logger.i('checkAdminCreatedStatus: Checking email: "$normalizedEmail"');

      final response = await client
          .from('profiles')
          .select('admin_created, password_set, email_verified')
          .eq('email', normalizedEmail)
          .maybeSingle();

      if (response == null) {
        _logger.w('checkAdminCreatedStatus: No profile found for email');
        return {
          'admin_created': false,
          'password_set': true,
          'email_verified': true,
        };
      }

      final adminCreated = response['admin_created'] == true;
      final passwordSet = response['password_set'] == true;
      final emailVerified = response['email_verified'] == true;

      _logger.i(
        'checkAdminCreatedStatus: admin_created=$adminCreated, password_set=$passwordSet, email_verified=$emailVerified',
      );

      return {
        'admin_created': adminCreated,
        'password_set': passwordSet,
        'email_verified': emailVerified,
      };
    } catch (e) {
      _logger.e('checkAdminCreatedStatus: Error: $e');
      return {
        'admin_created': false,
        'password_set': true,
        'email_verified': true,
      };
    }
  }

  // Update user password (for admin-created users setting their first password)
  Future<bool> updateUserPassword(String newPassword) async {
    try {
      _logger.i('updateUserPassword: Updating password for current user');

      await client.auth.updateUser(UserAttributes(password: newPassword));

      _logger.i('updateUserPassword: Password updated successfully');
      return true;
    } catch (e) {
      _logger.e('updateUserPassword: Error: $e');
      return false;
    }
  }

  /// Admin creates a trusted partner with password (server-side RPC).
  /// Expects database function `admin_create_trusted_partner(payload jsonb)`.
  Future<Map<String, dynamic>> adminCreateTrustedPartner({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      final payload = {
        'email': email.trim().toLowerCase(),
        'password': password,
        // Ensure admin-created TPs default to allow admin deal creation
        'metadata': {...metadata, 'allow_admin_deal_creation': true},
      };
      _logger.i('adminCreateTrustedPartner: calling RPC with email=$email');
      // The RPC function expects a 'payload' parameter of type jsonb
      final res = await client.rpc(
        'admin_create_trusted_partner',
        params: {'payload': payload},
      );
      _logger.i('adminCreateTrustedPartner response: $res');
      if (res is Map<String, dynamic>) return res;
      return {'ok': true, 'result': res};
    } catch (e) {
      _logger.e('adminCreateTrustedPartner error: $e');
      rethrow;
    }
  }

  /// Record trusted partner terms acceptance in profiles table.
  /// Expects columns: partner_terms_accepted (bool), partner_terms_accepted_at (timestamptz), partner_terms_version (text).
  /// This function calls a PostgreSQL function to ensure RLS is bypassed for setting verified status
  Future<bool> acceptTrustedPartnerTerms({
    required String userId,
    required String version,
  }) async {
    try {
      _logger.i('acceptTrustedPartnerTerms: userId=$userId version=$version');

      // Call the PostgreSQL function which handles both terms acceptance and verification
      // This function has SECURITY DEFINER to bypass RLS for the verified field
      final result = await client.rpc(
        'accept_partner_terms',
        params: {'user_id': userId, 'terms_version': version},
      );

      _logger.i('acceptTrustedPartnerTerms: RPC result=$result');

      if (result == true) {
        _logger.i(
          'acceptTrustedPartnerTerms: Terms accepted and verified status updated',
        );
        return true;
      } else {
        _logger.w('acceptTrustedPartnerTerms: RPC returned false');
        return false;
      }
    } catch (e) {
      _logger.e('acceptTrustedPartnerTerms error: $e');
      return false;
    }
  }

  /// Record trusted partner *payment* terms acceptance via SECURITY DEFINER RPC
  /// so it succeeds regardless of the RLS policy state on profiles (avoids 42P17
  /// infinite-recursion that occurs with a direct client.from('profiles').update()).
  Future<bool> acceptTpPaymentTerms({
    required String userId,
    required String version,
  }) async {
    try {
      _logger.i('acceptTpPaymentTerms: userId=$userId version=$version');
      final result = await client.rpc(
        'accept_tp_payment_terms',
        params: {'p_user_id': userId, 'p_version': version},
      );
      _logger.i('acceptTpPaymentTerms: RPC result=$result');
      return result == true;
    } catch (e) {
      _logger.e('acceptTpPaymentTerms error: $e');
      return false;
    }
  }

  /// Record member terms acceptance via RPC (SECURITY DEFINER) so it succeeds
  /// regardless of the current RLS policy state on the profiles table.
  Future<bool> acceptMemberTerms({
    required String userId,
    required String version,
  }) async {
    try {
      _logger.i('acceptMemberTerms: userId=$userId version=$version');
      final result = await client.rpc(
        'accept_member_terms',
        params: {'p_user_id': userId, 'p_version': version},
      );
      final accepted = result == true;
      if (!accepted) {
        _logger.w('acceptMemberTerms: RPC returned $result for userId=$userId');
        return false;
      }
      // Cache acceptance for the rest of this session so the immediate
      // navigation gate (hasMemberAcceptedTerms) cannot bounce the user back
      // to the terms page if the follow-up SELECT is blocked by RLS or fails.
      _memberTermsAcceptedCache.add(userId);
      await syncVerificationStatus(userId);
      return true;
    } catch (e) {
      _logger.e('acceptMemberTerms error: $e');
      return false;
    }
  }

  /// Lightweight check for member terms acceptance.
  ///
  /// Order of resolution:
  /// 1. In-memory session cache (set by acceptMemberTerms on success). This is
  ///    the single source of truth right after the user accepts, and prevents
  ///    the post-save loop when DB reads are blocked by RLS or transiently
  ///    fail.
  /// 2. SECURITY DEFINER RPC `member_terms_accepted_status` (bypasses RLS).
  /// 3. Direct table SELECT (legacy / fallback when the RPC isn't deployed).
  Future<bool> hasMemberAcceptedTerms(
    String userId, {
    Map<String, dynamic>? profile,
  }) async {
    if (_memberTermsAcceptedCache.contains(userId)) {
      return true;
    }
    // Reuse an already-loaded profile to avoid a redundant DB read. The
    // `member_terms_accepted` column on profiles is the source of truth
    // (written by acceptMemberTerms), so when the caller has just fetched the
    // full profile we can resolve acceptance without another round-trip.
    if (profile != null && profile.containsKey('member_terms_accepted')) {
      final accepted = profile['member_terms_accepted'] == true;
      if (accepted) {
        _memberTermsAcceptedCache.add(userId);
      }
      return accepted;
    }
    try {
      final rpcResult = await client.rpc(
        'member_terms_accepted_status',
        params: {'p_user_id': userId},
      );
      if (rpcResult == true) {
        _memberTermsAcceptedCache.add(userId);
        return true;
      }
      if (rpcResult == false) {
        return false;
      }
      // null / unexpected -> fall through to direct SELECT
    } catch (e) {
      _logger.w('hasMemberAcceptedTerms: RPC fallback to direct SELECT: $e');
    }

    try {
      final res = await client
          .from('profiles')
          .select('member_terms_accepted')
          .eq('id', userId)
          .maybeSingle();

      if (res == null) {
        _logger.w('hasMemberAcceptedTerms: profile missing for userId=$userId');
        return false;
      }
      final value = res['member_terms_accepted'];
      final accepted = value == true; // only explicit true counts
      _logger.d(
        'hasMemberAcceptedTerms: userId=$userId accepted=$accepted raw=$value',
      );
      if (accepted) {
        _memberTermsAcceptedCache.add(userId);
      }
      return accepted;
    } catch (e) {
      _logger.e('hasMemberAcceptedTerms error: $e');
      // On error, be safe and treat as not accepted (forces re-prompt)
      return false;
    }
  }

  /// Record the member's 18+ self-confirmation (Local Sips age gate).
  Future<bool> confirmMemberAge18(String userId) async {
    try {
      final result = await client.rpc(
        'confirm_member_age_18',
        params: {'p_user_id': userId},
      );
      final confirmed = result == true;
      if (confirmed) {
        _ageVerifiedCache.add(userId);
      } else {
        _logger.w('confirmMemberAge18: RPC returned $result for $userId');
      }
      return confirmed;
    } catch (e) {
      _logger.e('confirmMemberAge18 error: $e');
      return false;
    }
  }

  /// True when the member has already confirmed they are 18 or older.
  Future<bool> isMemberAgeVerified(String userId) async {
    if (_ageVerifiedCache.contains(userId)) return true;
    try {
      final res = await client
          .from('profiles')
          .select('age_verified_18')
          .eq('id', userId)
          .maybeSingle();
      final verified = res?['age_verified_18'] == true;
      if (verified) _ageVerifiedCache.add(userId);
      return verified;
    } catch (e) {
      _logger.e('isMemberAgeVerified error: $e');
      return false;
    }
  }

  /// Ensure the `verified` flag reflects terms acceptance and subscription status
  /// so admin tabs only show users who completed required steps.
  Future<bool> syncVerificationStatus(String userId) async {
    try {
      final profile = await client
          .from('profiles')
          .select(
            'role, subscription, member_terms_accepted, partner_terms_accepted, is_tp_member, verified',
          )
          .eq('id', userId)
          .maybeSingle();

      if (profile == null) {
        _logger.w('syncVerificationStatus: profile missing for userId=$userId');
        return false;
      }

      final role = (profile['role'] as String?)?.toLowerCase() ?? 'member';
      final isTpMember = profile['is_tp_member'] == true;
      final memberTermsAccepted = profile['member_terms_accepted'] == true;
      final partnerTermsAccepted = profile['partner_terms_accepted'] == true;
      final currentVerified = profile['verified'] == true;

      _logger.i(
        'syncVerificationStatus: Initial state - role=$role, memberTermsAccepted=$memberTermsAccepted, partnerTermsAccepted=$partnerTermsAccepted, isTpMember=$isTpMember',
      );

      // Subscription is active if profile flag is active OR there is an active subscription row
      var subscriptionActive =
          (profile['subscription'] as String? ?? '').toLowerCase() == 'active';
      try {
        final activeSub = await client
            .from('subscriptions')
            .select('status')
            .eq('user_id', userId)
            .eq('status', 'active')
            .order('created_at', ascending: false)
            .limit(1);
        if (activeSub.isNotEmpty) {
          subscriptionActive = true;
        }
      } catch (e) {
        _logger.w('syncVerificationStatus: subscription lookup failed: $e');
      }

      final memberReady = memberTermsAccepted && subscriptionActive;
      final partnerReady = partnerTermsAccepted;

      _logger.i(
        'syncVerificationStatus: Readiness - memberReady=$memberReady, partnerReady=$partnerReady, subscriptionActive=$subscriptionActive',
      );

      bool shouldVerify;
      if (role == 'trusted_partner') {
        // If the trusted partner is also a member, require member readiness too.
        shouldVerify = partnerReady && (!isTpMember || memberReady);
        _logger.i(
          'syncVerificationStatus: TP logic - partnerReady=$partnerReady && (!isTpMember=$isTpMember || memberReady=$memberReady) = $shouldVerify',
        );
      } else {
        // Default/member flow
        shouldVerify = memberReady;
      }

      _logger.i(
        'syncVerificationStatus: About to update verified=$shouldVerify for userId=$userId',
      );

      // Skip the write entirely when the flag does not change. A fresh member
      // accepting terms (still pending payment) has verified=false and stays
      // false, so the UPDATE is pure overhead and can needlessly trip the
      // profiles verified-flag trigger (observed as 500s during terms accept).
      if (shouldVerify == currentVerified) {
        _logger.i(
          'syncVerificationStatus: verified unchanged ($currentVerified) for userId=$userId - skipping update',
        );
        return shouldVerify;
      }

      await client
          .from('profiles')
          .update({
            'verified': shouldVerify,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      _logger.i(
        'syncVerificationStatus: userId=$userId role=$role verified=$shouldVerify memberReady=$memberReady partnerReady=$partnerReady subscriptionActive=$subscriptionActive',
      );
      return shouldVerify;
    } catch (e) {
      _logger.e('syncVerificationStatus error: $e');
      return false;
    }
  }

  /// Upload an image to Supabase storage and return the public URL
  Future<String> uploadImage({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
  }) async {
    try {
      _logger.i('Uploading image to bucket: $bucket, path: $path');

      // Upload the file
      await client.storage
          .from(bucket)
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(contentType: contentType ?? 'image/jpeg'),
          );

      // Get the public URL
      final publicUrl = client.storage.from(bucket).getPublicUrl(path);

      _logger.i('Image uploaded successfully: $publicUrl');
      return publicUrl;
    } catch (e) {
      _logger.e('Failed to upload image: $e');
      throw Exception('Failed to upload image: $e');
    }
  }
}
