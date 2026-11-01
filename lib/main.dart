import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'dart:async';
import 'core/theme/theme.dart';
import 'features/auth/welcome_page.dart';
import 'features/auth/password_reset_page.dart';
import 'features/auth/members_signup_page.dart';
import 'widgets/creator_ribbon.dart';
import 'services/supabase_service.dart';
import 'services/navigation_service.dart';
import 'services/deep_link_service.dart';
import 'services/app_fallback_system.dart';
import 'services/subscription_service.dart';
import 'services/cache_service.dart';
import 'widgets/loading_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final logger = Logger();

  // Load environment variables with error handling
  try {
    await dotenv.load(fileName: '.env');
    logger.i('Environment variables loaded successfully');
  } catch (e) {
    logger.w('Warning: Could not load .env file: $e');
    logger.w('Using default environment values');
  }

  logger.i('Initializing Supabase...');
  try {
    await SupabaseService.instance.init().timeout(const Duration(seconds: 10));
  } catch (e) {
    logger.w('Supabase initialization failed: $e');
  }
  logger.i('Supabase initialized');

  // Initialize cache service
  logger.i('Initializing cache service...');
  try {
    await CacheService.instance.init().timeout(const Duration(seconds: 5));
  } catch (e) {
    logger.w('Cache initialization failed: $e');
  }
  logger.i('Cache service initialized');

  runApp(const LocalLekkerApp());

  // Initialize deep link service
  logger.i('Initializing deep link service...');
  DeepLinkService().init();

  // Initialize slower fallback services after the first frame can render.
  logger.i('Initializing app fallback system...');
  unawaited(
    AppFallbackSystem().initialize().then((_) {
      logger.i('App fallback system initialized');
    }),
  );

  // Initialize Firebase (required for FCM push notifications)
  // TEMPORARILY DISABLED: Push notifications turned off
  // logger.i('Initializing Firebase...');
  // try {
  //   await Firebase.initializeApp();
  //   // Register the background message handler (must be a top-level function)
  //   FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  //   logger.i('Firebase initialized');
  // } catch (e) {
  //   logger.w('Firebase initialization failed (push notifications when app is closed will not work): $e');
  // }

  // Initialize push notifications
  // TEMPORARILY DISABLED: Push notifications turned off
  // logger.i('Initializing push notifications...');
  // await PushNotificationService().initialize();
  // logger.i('Push notifications initialized');

  logger.i('LocalLekkerApp startup services initialized');
}

class LocalLekkerApp extends StatefulWidget {
  const LocalLekkerApp({super.key});

  @override
  State<LocalLekkerApp> createState() => _LocalLekkerAppState();
}

class _LocalLekkerAppState extends State<LocalLekkerApp>
    with WidgetsBindingObserver {
  final logger = Logger();
  StreamSubscription<String?>? _deepLinkSubscription;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupDeepLinkListener();
    // Check for active password recovery session
    _checkForActiveRecoverySession();
  }

  void _checkForActiveRecoverySession() async {
    try {
      // Query recovery_sessions table to see if this user has an active recovery
      final response = await SupabaseService.instance.client
          .from('recovery_sessions')
          .select()
          .eq('used', false)
          .gt('expires_at', DateTime.now().toIso8601String())
          .limit(1);

      if (response.isNotEmpty) {
        logger.i(
          'Active recovery session found - navigating to password reset',
        );
        final recoveryData = response[0];
        final token = recoveryData['token'] ?? '';

        // Navigate to password reset page
        navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(
            builder: (context) =>
                PasswordResetPage(accessToken: token, refreshToken: null),
          ),
        );

        // Mark as used
        await SupabaseService.instance.client
            .from('recovery_sessions')
            .update({'used': true})
            .eq('id', recoveryData['id']);
      }
    } catch (e) {
      logger.d('No active recovery session: $e');
    }
  }

  void _setupDeepLinkListener() {
    _deepLinkSubscription = DeepLinkService().linkStream.listen((link) {
      if (link != null && link.startsWith('password_reset_pkce:')) {
        // PKCE flow - exchange code for session
        final code = link.split(':')[1];
        _handlePasswordResetPKCE(code);
      } else if (link != null && link.startsWith('password_reset:')) {
        final parts = link.split(':');
        if (parts.length >= 2) {
          final accessToken = parts[1];
          final refreshToken = parts.length > 2 ? parts[2] : null;
          _handlePasswordResetLink(accessToken, refreshToken);
        }
      } else if (link == 'signup_completion') {
        _handleSignupCompletionLink();
      }
    });
  }

  void _handleSignupCompletionLink() {
    logger.i('Handling signup completion deep link');
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MembersSignupPage()),
      (route) => false,
    );
  }

  Future<void> _handlePasswordResetPKCE(String code) async {
    logger.i('Handling password reset PKCE flow with code');
    try {
      // Exchange the code for a session using Supabase
      final response = await SupabaseService.instance.client.auth
          .exchangeCodeForSession(code);

      logger.i('PKCE exchange successful, navigating to password reset page');
      // Navigate to password reset page - clear entire navigation stack
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => PasswordResetPage(
            accessToken: response.session.accessToken,
            refreshToken: response.session.refreshToken,
          ),
        ),
        (route) => false, // Remove all previous routes
      );
    } catch (e) {
      logger.e('Error exchanging PKCE code: $e');

      // Wait briefly to let auth state settle (session might be coming via auth listener)
      await Future.delayed(const Duration(milliseconds: 500));

      // Check if the user is already authenticated (code might have been used before)
      final currentUser = SupabaseService.instance.client.auth.currentUser;
      final currentSession =
          SupabaseService.instance.client.auth.currentSession;

      if (currentUser != null && currentSession != null) {
        logger.i(
          'User already authenticated (${currentUser.id}), navigating to password reset page',
        );
        // Navigate to password reset page with current session tokens
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => PasswordResetPage(
              accessToken: currentSession.accessToken,
              refreshToken: currentSession.refreshToken,
            ),
          ),
          (route) => false, // Remove all previous routes
        );
      } else {
        logger.e('PKCE exchange failed and no authenticated user found');
        // User is not signed in - let them return to signin page naturally
      }
    }
  }

  void _handlePasswordResetLink(String accessToken, String? refreshToken) {
    logger.i('Handling password reset deep link with accessToken');
    // Navigate to password reset page - clear entire navigation stack
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => PasswordResetPage(
          accessToken: accessToken,
          refreshToken: refreshToken,
        ),
      ),
      (route) => false, // Remove all previous routes
    );
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    logger.i('App lifecycle state changed to: $state');

    switch (state) {
      case AppLifecycleState.paused:
        // App is in background
        logger.i('App paused (background) - preparing for potential sign-out');
        break;

      case AppLifecycleState.detached:
        // App is being terminated
        logger.i('App detached (terminating) - signing out user');
        await _performAutomaticSignOut();
        break;

      case AppLifecycleState.resumed:
        // App is back to foreground
        logger.i('App resumed (foreground)');
        // Check for expired subscriptions when app resumes
        await _checkExpiredSubscription();
        break;

      case AppLifecycleState.inactive:
        // App is inactive
        logger.i('App inactive');
        break;

      case AppLifecycleState.hidden:
        // App is hidden (iOS specific)
        logger.i('App hidden');
        break;
    }
  }

  Future<void> _checkExpiredSubscription() async {
    try {
      final currentUser = SupabaseService.instance.getCurrentUser();
      if (currentUser != null) {
        logger.i('Checking subscription expiry for user: ${currentUser.id}');
        await SubscriptionService().checkAndHandleExpiredSubscription(
          currentUser.id,
        );
      }
    } catch (e) {
      logger.e('Error checking subscription expiry: $e');
    }
  }

  Future<void> _performAutomaticSignOut() async {
    try {
      final currentUser = SupabaseService.instance.getCurrentUser();
      if (currentUser != null) {
        logger.i('Automatically signing out user: ${currentUser.email}');
        await SupabaseService.instance.signOut();
        logger.i('Automatic sign-out completed successfully');
      } else {
        logger.i('No user to sign out');
      }
    } catch (e) {
      logger.e('Error during automatic sign-out: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Local Lekker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AppInitializer(),
      // Global builder to show the creator ribbon below every screen
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: const TextScaler.linear(1.0),
          ),
          child: Column(
            children: [
              Expanded(child: child),
              const CreatorRibbon(height: AppTheme.creatorRibbonHeight),
            ],
          ),
        );
      },
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  late Future<Widget> _initialScreenFuture;

  @override
  void initState() {
    super.initState();
    _initialScreenFuture = _determineInitialScreen();
  }

  Future<Widget> _determineInitialScreen() async {
    // First, check if app was opened from a password reset link
    final resetData = await DeepLinkService().checkForPasswordResetLink();

    if (resetData != null) {
      final logger = Logger();

      // Check if this is PKCE flow (code parameter) or token flow
      if (resetData.containsKey('code')) {
        // PKCE flow - exchange code for session
        final code = resetData['code']!;
        logger.i('App opened with PKCE password reset code');

        try {
          // Exchange the code for a session
          final response = await SupabaseService.instance.client.auth
              .exchangeCodeForSession(code);

          logger.i(
            'PKCE exchange successful - navigating to password reset page',
          );
          return PasswordResetPage(
            accessToken: response.session.accessToken,
            refreshToken: response.session.refreshToken,
          );
        } catch (e) {
          logger.e('Error exchanging PKCE code on app launch: $e');
        }
      } else if (resetData.containsKey('accessToken')) {
        // Direct token flow (legacy)
        logger.i('App opened with password reset link');
        return PasswordResetPage(
          accessToken: resetData['accessToken']!,
          refreshToken: resetData['refreshToken'],
        );
      }
    }

    if (await DeepLinkService().checkForSignupCompletionLink()) {
      return const MembersSignupPage();
    }

    // Otherwise, use normal navigation flow
    return await NavigationService().getInitialScreen();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _initialScreenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show splash only while initial route is being resolved.
          return const LoadingScreen(showMinimumDuration: true);
        } else if (snapshot.hasError) {
          // Fail-safe: if bootstrap fails, land on welcome instead of looping on splash.
          return const WelcomePage();
        } else {
          // Route directly to the resolved initial screen.
          // This avoids a secondary splash->navigation hop that can stall on web.
          return snapshot.data ?? const WelcomePage();
        }
      },
    );
  }
}
