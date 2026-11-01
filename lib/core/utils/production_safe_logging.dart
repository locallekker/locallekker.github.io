import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Production-safe logging mixin
/// Use this to ensure debug statements don't leak into production
mixin ProductionSafeLogging {
  static final Logger _logger = Logger();

  /// Debug log - only shows in debug mode
  void logDebug(String message) {
    if (kDebugMode) {
      _logger.d(message);
    }
  }

  /// Info log - shows in all modes
  void logInfo(String message) {
    _logger.i(message);
  }

  /// Warning log - shows in all modes
  void logWarning(String message) {
    _logger.w(message);
  }

  /// Error log - shows in all modes
  void logError(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }
}
