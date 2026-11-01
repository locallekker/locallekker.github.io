import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:logger/logger.dart';

/// LocationService - Handles live location tracking and city detection
/// Uses geolocator for GPS coordinates and geocoding for reverse geocoding
class LocationService {
  static final LocationService _instance = LocationService._internal();

  factory LocationService() => _instance;
  LocationService._internal();

  final Logger _logger = Logger();
  String? _cachedCity;
  DateTime? _lastLocationUpdate;

  // Cache duration in minutes
  static const int _cacheDurationMinutes = 5;

  /// Request location permissions from user
  Future<bool> requestLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        _logger.w(
          'Location permission denied forever. User needs to enable it in app settings.',
        );
        return false;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        _logger.i('✅ Location permission granted');
        return true;
      }

      return false;
    } catch (e) {
      _logger.e('Error requesting location permission: $e');
      return false;
    }
  }

  /// Get user's current city
  /// Returns cached city if available and fresh, otherwise fetches new location
  Future<String?> getCurrentCity() async {
    try {
      // Return cached city if it's still fresh
      if (_cachedCity != null && _lastLocationUpdate != null) {
        final timeDiff = DateTime.now().difference(_lastLocationUpdate!);
        if (timeDiff.inMinutes < _cacheDurationMinutes) {
          _logger.i('📍 Returning cached city: $_cachedCity');
          return _cachedCity;
        }
      }

      // Request permission if needed
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        _logger.w('Location permission not granted');
        return null;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      _logger.i('📍 Got position: ${position.latitude}, ${position.longitude}');

      // Reverse geocode to get city name
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        // Try to get city, fallback to locality or administrative area
        final city =
            placemark.locality ??
            placemark.administrativeArea ??
            placemark.thoroughfare ??
            'Unknown';

        _cachedCity = city;
        _lastLocationUpdate = DateTime.now();
        _logger.i('🏙️ Current city: $city');
        return city;
      }

      return null;
    } catch (e) {
      _logger.e('Error getting current city: $e');
      return null;
    }
  }

  /// Get latitude and longitude
  Future<({double? latitude, double? longitude})> getCurrentPosition() async {
    try {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        _logger.w('Location permission not granted');
        return (latitude: null, longitude: null);
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      return (latitude: position.latitude, longitude: position.longitude);
    } catch (e) {
      _logger.e('Error getting current position: $e');
      return (latitude: null, longitude: null);
    }
  }

  /// Get city for specific coordinates
  Future<String?> getCityForCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final city =
            placemark.locality ??
            placemark.administrativeArea ??
            placemark.thoroughfare ??
            'Unknown';
        _logger.i('🏙️ City for coordinates: $city');
        return city;
      }

      return null;
    } catch (e) {
      _logger.e('Error reverse geocoding: $e');
      return null;
    }
  }

  /// Refresh cached city immediately (forces new location lookup)
  Future<String?> refreshCurrentCity() async {
    _cachedCity = null;
    _lastLocationUpdate = null;
    return getCurrentCity();
  }

  /// Clear cached location data
  void clearCache() {
    _cachedCity = null;
    _lastLocationUpdate = null;
    _logger.i('📍 Location cache cleared');
  }

  /// Check if device has location services enabled
  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  /// Open location settings (Android/iOS)
  Future<bool> openLocationSettings() async {
    return Geolocator.openLocationSettings();
  }
}
