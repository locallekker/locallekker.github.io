import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

/// App Fallback System
/// Provides comprehensive error handling, offline mode, and data caching
class AppFallbackSystem {
  static final AppFallbackSystem _instance = AppFallbackSystem._internal();
  factory AppFallbackSystem() => _instance;
  AppFallbackSystem._internal();

  final Logger _logger = Logger();
  late final SharedPreferences _prefs;

  // Fallback states
  bool _isOfflineMode = false;
  bool _isSupabaseAvailable = true;
  Map<String, dynamic> _cachedUserData = {};
  Map<String, dynamic> _cachedAppData = {};

  // Stream controllers for state changes
  final StreamController<bool> _offlineModeController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _supabaseStatusController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _fallbackDataController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Connectivity monitoring
  Timer? _connectivityCheckTimer;

  // Getters for streams
  Stream<bool> get offlineModeStream => _offlineModeController.stream;
  Stream<bool> get supabaseStatusStream => _supabaseStatusController.stream;
  Stream<Map<String, dynamic>> get fallbackDataStream =>
      _fallbackDataController.stream;

  // Getters for current state
  bool get isOfflineMode => _isOfflineMode;
  bool get isSupabaseAvailable => _isSupabaseAvailable;
  Map<String, dynamic> get cachedUserData => Map.from(_cachedUserData);
  Map<String, dynamic> get cachedAppData => Map.from(_cachedAppData);

  /// Initialize the fallback system
  Future<void> initialize() async {
    _logger.i('🔄 Initializing App Fallback System...');

    try {
      _prefs = await SharedPreferences.getInstance();

      // Load cached data
      await _loadCachedData();

      // Setup periodic connectivity monitoring
      _setupConnectivityMonitoring();

      // Check initial connectivity
      await _checkConnectivity();

      _logger.i('✅ App Fallback System initialized successfully');
    } catch (e) {
      _logger.e('❌ Failed to initialize App Fallback System: $e');
      // Continue with limited functionality
    }
  }

  /// Setup periodic connectivity monitoring
  void _setupConnectivityMonitoring() {
    // Check connectivity every 30 seconds
    _connectivityCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkConnectivity(),
    );
  }

  /// Check connectivity status
  Future<void> _checkConnectivity() async {
    try {
      final wasOffline = _isOfflineMode;
      final wasSupabaseAvailable = _isSupabaseAvailable;

      // Check basic internet connectivity
      final isOnline = await _checkBasicConnectivity();
      _isOfflineMode = !isOnline;

      if (isOnline) {
        // Check if Supabase is actually reachable
        _isSupabaseAvailable = await _checkSupabaseConnectivity();
      } else {
        _isSupabaseAvailable = false;
      }

      // Notify listeners if state changed
      if (wasOffline != _isOfflineMode) {
        _offlineModeController.add(_isOfflineMode);
        _logger.i('📴 Offline mode: $_isOfflineMode');
      }

      if (wasSupabaseAvailable != _isSupabaseAvailable) {
        _supabaseStatusController.add(_isSupabaseAvailable);
        _logger.i('🔗 Supabase available: $_isSupabaseAvailable');
      }
    } catch (e) {
      _logger.e('❌ Error checking connectivity: $e');
      _isOfflineMode = true;
      _isSupabaseAvailable = false;
    }
  }

  /// Check basic internet connectivity
  Future<bool> _checkBasicConnectivity() async {
    if (kIsWeb) {
      return true;
    }
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Check if Supabase is reachable
  Future<bool> _checkSupabaseConnectivity() async {
    if (kIsWeb) {
      return true;
    }
    try {
      // Simple connectivity check - in production, you might want to ping Supabase
      final result = await InternetAddress.lookup(
        'supabase.co',
      ).timeout(const Duration(seconds: 5));

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      _logger.w('⚠️ Supabase connectivity check failed: $e');
      return false;
    }
  }

  /// Load cached data from SharedPreferences
  Future<void> _loadCachedData() async {
    try {
      final cachedUserData = _prefs.getString('cached_user_data');
      final cachedAppData = _prefs.getString('cached_app_data');

      if (cachedUserData != null) {
        _cachedUserData = json.decode(cachedUserData);
        _logger.i('📦 Loaded cached user data');
      }

      if (cachedAppData != null) {
        _cachedAppData = json.decode(cachedAppData);
        _logger.i('📦 Loaded cached app data');
      }
    } catch (e) {
      _logger.e('❌ Error loading cached data: $e');
    }
  }

  /// Cache user data
  Future<void> cacheUserData(Map<String, dynamic> data) async {
    try {
      _cachedUserData = Map.from(data);
      await _prefs.setString('cached_user_data', json.encode(data));
      _logger.i('💾 User data cached successfully');
    } catch (e) {
      _logger.e('❌ Error caching user data: $e');
    }
  }

  /// Cache app data
  Future<void> cacheAppData(Map<String, dynamic> data) async {
    try {
      _cachedAppData = Map.from(data);
      await _prefs.setString('cached_app_data', json.encode(data));
      _logger.i('💾 App data cached successfully');
    } catch (e) {
      _logger.e('❌ Error caching app data: $e');
    }
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    try {
      _cachedUserData.clear();
      _cachedAppData.clear();
      await _prefs.remove('cached_user_data');
      await _prefs.remove('cached_app_data');
      _logger.i('🗑️ Cache cleared successfully');
    } catch (e) {
      _logger.e('❌ Error clearing cache: $e');
    }
  }

  /// Execute operation with fallback
  Future<T?> executeWithFallback<T>(
    Future<T> Function() primaryOperation,
    T? Function()? fallbackOperation, {
    String operationName = 'operation',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      if (_isOfflineMode && fallbackOperation != null) {
        _logger.i('🔄 Executing $operationName with offline fallback');
        return fallbackOperation();
      }

      if (!_isSupabaseAvailable && fallbackOperation != null) {
        _logger.i('🔄 Executing $operationName with Supabase fallback');
        return fallbackOperation();
      }

      // Execute primary operation with timeout
      final result = await primaryOperation().timeout(timeout);
      _logger.i('✅ $operationName completed successfully');
      return result;
    } catch (e) {
      _logger.w('⚠️ $operationName failed: $e');

      if (fallbackOperation != null) {
        try {
          _logger.i('🔄 Executing fallback for $operationName');
          final fallbackResult = fallbackOperation();
          _logger.i('✅ $operationName fallback completed');
          return fallbackResult;
        } catch (fallbackError) {
          _logger.e('❌ $operationName fallback also failed: $fallbackError');
        }
      }

      return null;
    }
  }

  /// Get fallback UI widget
  Widget getFallbackWidget({
    required Widget child,
    Widget? offlineWidget,
    Widget? errorWidget,
    String? offlineMessage,
    String? errorMessage,
  }) {
    if (_isOfflineMode && offlineWidget != null) {
      return offlineWidget;
    }

    if (!_isSupabaseAvailable && errorWidget != null) {
      return errorWidget;
    }

    return child;
  }

  /// Show fallback dialog
  Future<void> showFallbackDialog(
    BuildContext context, {
    String? title,
    String? message,
    List<Widget>? actions,
  }) async {
    final defaultTitle = _isOfflineMode
        ? 'Offline Mode'
        : 'Service Unavailable';
    final defaultMessage = _isOfflineMode
        ? 'You are currently offline. Some features may be limited.'
        : 'Supabase services are currently unavailable. Using cached data where available.';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title ?? defaultTitle),
        content: Text(message ?? defaultMessage),
        actions:
            actions ??
            [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
      ),
    );
  }

  /// Force offline mode (for testing)
  void forceOfflineMode(bool offline) {
    _isOfflineMode = offline;
    _offlineModeController.add(_isOfflineMode);
    _logger.i('🔧 Offline mode ${offline ? 'enabled' : 'disabled'} (forced)');
  }

  /// Force Supabase unavailable (for testing)
  void forceSupabaseUnavailable(bool unavailable) {
    _isSupabaseAvailable = !unavailable;
    _supabaseStatusController.add(_isSupabaseAvailable);
    _logger.i(
      '🔧 Supabase ${unavailable ? 'unavailable' : 'available'} (forced)',
    );
  }

  /// Get system status
  Map<String, dynamic> getSystemStatus() {
    return {
      'isOfflineMode': _isOfflineMode,
      'isSupabaseAvailable': _isSupabaseAvailable,
      'hasCachedUserData': _cachedUserData.isNotEmpty,
      'hasCachedAppData': _cachedAppData.isNotEmpty,
      'cachedUserDataKeys': _cachedUserData.keys.toList(),
      'cachedAppDataKeys': _cachedAppData.keys.toList(),
    };
  }

  /// Dispose resources
  void dispose() {
    _connectivityCheckTimer?.cancel();
    _offlineModeController.close();
    _supabaseStatusController.close();
    _fallbackDataController.close();
    _logger.i('🗑️ App Fallback System disposed');
  }
}

/// Extension methods for easy integration
extension FallbackExtensions on BuildContext {
  AppFallbackSystem get fallback => AppFallbackSystem();
}

/// Fallback-aware widget wrapper
class FallbackWrapper extends StatefulWidget {
  final Widget child;
  final Widget? offlineWidget;
  final Widget? errorWidget;
  final VoidCallback? onOfflineDetected;
  final VoidCallback? onErrorDetected;

  const FallbackWrapper({
    super.key,
    required this.child,
    this.offlineWidget,
    this.errorWidget,
    this.onOfflineDetected,
    this.onErrorDetected,
  });

  @override
  State<FallbackWrapper> createState() => _FallbackWrapperState();
}

class _FallbackWrapperState extends State<FallbackWrapper> {
  final AppFallbackSystem _fallback = AppFallbackSystem();

  @override
  void initState() {
    super.initState();

    // Listen for state changes
    _fallback.offlineModeStream.listen((isOffline) {
      if (isOffline && widget.onOfflineDetected != null) {
        widget.onOfflineDetected!();
      }
      if (mounted) setState(() {});
    });

    _fallback.supabaseStatusStream.listen((isAvailable) {
      if (!isAvailable && widget.onErrorDetected != null) {
        widget.onErrorDetected!();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return _fallback.getFallbackWidget(
      child: widget.child,
      offlineWidget: widget.offlineWidget,
      errorWidget: widget.errorWidget,
    );
  }
}

/// Default offline widget
class DefaultOfflineWidget extends StatelessWidget {
  final String? message;

  const DefaultOfflineWidget({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              message ?? 'You are currently offline',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Some features may be limited',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Default error widget
class DefaultErrorWidget extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const DefaultErrorWidget({super.key, this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message ?? 'Service temporarily unavailable',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Using cached data where available',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
