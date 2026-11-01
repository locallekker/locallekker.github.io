import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/location_service.dart';
import '../../services/discount_service.dart';
import '../../models/discount.dart';

/// Example Widget: City-Based Deal Filtering
/// This widget demonstrates how to integrate city-specific deal filtering
/// into the Members Home Page or any deal browsing screen.
///
/// Features:
/// - Real-time location detection
/// - Displays current city
/// - Shows only deals available in the current city
/// - Manual city selection option
/// - Refresh location button
/// - Handles loading and error states

class CityBasedDealsWidget extends StatefulWidget {
  const CityBasedDealsWidget({super.key});

  @override
  State<CityBasedDealsWidget> createState() => _CityBasedDealsWidgetState();
}

class _CityBasedDealsWidgetState extends State<CityBasedDealsWidget> {
  final LocationService _locationService = LocationService();
  final DiscountService _discountService = DiscountService();
  final Logger _logger = Logger();

  String? _currentCity;
  List<Discount> _cityDeals = [];
  bool _isLoadingLocation = true;
  bool _isLoadingDeals = false;
  String? _errorMessage;

  // List of available cities for manual selection
  static const List<String> availableCities = [
    'East London',
    'Port Elizabeth',
    'Gqeberhia',
    'King William\'s Town',
    'Mthatha',
    'Umtata',
  ];

  @override
  void initState() {
    super.initState();
    _initializeLocationAndDeals();
  }

  /// Initialize location detection and load deals on widget startup
  Future<void> _initializeLocationAndDeals() async {
    try {
      // Check if location services are enabled
      final locationEnabled = await _locationService.isLocationServiceEnabled();

      if (!locationEnabled) {
        if (mounted) {
          setState(() {
            _errorMessage =
                'Location services disabled. Please enable location to see nearby deals.';
            _isLoadingLocation = false;
          });
        }
        _logger.w('Location services disabled');
        return;
      }

      // Get user's current city
      final city = await _locationService.getCurrentCity();

      if (mounted) {
        if (city != null) {
          setState(() {
            _currentCity = city;
            _errorMessage = null;
          });

          // Load deals for this city
          await _loadDealsForCity(city);
        } else {
          setState(() {
            _errorMessage = 'Could not detect your location. Please try again.';
            _isLoadingLocation = false;
          });
          _logger.w('Could not detect location');
        }
      }
    } catch (e) {
      _logger.e('Error initializing location: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Error detecting location. Please check your permissions.';
          _isLoadingLocation = false;
        });
      }
    }
  }

  /// Load deals for a specific city
  Future<void> _loadDealsForCity(String city) async {
    if (!mounted) return;

    setState(() => _isLoadingDeals = true);

    try {
      final deals = await _discountService.getActiveDealsInCity(city);

      if (mounted) {
        setState(() {
          _cityDeals = deals;
          _isLoadingDeals = false;
          _errorMessage = null;
          _logger.i('🏙️ Loaded ${deals.length} deals for $city');
        });
      }
    } catch (e) {
      _logger.e('Error loading deals for $city: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load deals. Please try again.';
          _isLoadingDeals = false;
        });
      }
    }
  }

  /// Refresh location (forces new location lookup)
  Future<void> _refreshLocation() async {
    try {
      setState(() {
        _isLoadingLocation = true;
        _errorMessage = null;
      });

      final city = await _locationService.refreshCurrentCity();

      if (mounted && city != null) {
        setState(() => _currentCity = city);
        await _loadDealsForCity(city);
      }
    } catch (e) {
      _logger.e('Error refreshing location: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to refresh location. Please try again.';
          _isLoadingLocation = false;
        });
      }
    }
  }

  /// Allow user to manually select a city
  void _showCitySelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select City'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: availableCities.map((city) {
              return ListTile(
                title: Text(city),
                leading: _currentCity == city
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  setState(() => _currentCity = city);
                  await _loadDealsForCity(city);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: _buildAppBarTitle(),
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoadingLocation || _isLoadingDeals
                ? null
                : _refreshLocation,
            tooltip: 'Refresh Location',
          ),
          // Change city button
          if (_currentCity != null)
            IconButton(
              icon: const Icon(Icons.location_city),
              onPressed: _showCitySelector,
              tooltip: 'Change City',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  /// Build app bar title with location info
  Widget _buildAppBarTitle() {
    if (_isLoadingLocation) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Getting location...'),
        ],
      );
    }

    if (_currentCity != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Deals Near You'),
          Text(
            '📍 $_currentCity',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    return const Text('Local Lekker');
  }

  /// Build main body with deals or error state
  Widget _buildBody() {
    // Show error message if any
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refreshLocation,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _showCitySelector,
              icon: const Icon(Icons.location_city),
              label: const Text('Select City Manually'),
            ),
          ],
        ),
      );
    }

    // Show loading spinner
    if (_isLoadingLocation || _isLoadingDeals) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show empty state if no deals
    if (_cityDeals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.local_offer_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No deals available in $_currentCity',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check back soon!',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _showCitySelector,
              icon: const Icon(Icons.location_city),
              label: const Text('Browse Other Cities'),
            ),
          ],
        ),
      );
    }

    // Show deals list
    return RefreshIndicator(
      onRefresh: _refreshLocation,
      child: ListView.builder(
        itemCount: _cityDeals.length + 1, // +1 for header
        itemBuilder: (context, index) {
          // Header showing deal count
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    '${_cityDeals.length} Deals',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Chip(
                    label: Text(_currentCity ?? 'Unknown'),
                    avatar: const Icon(Icons.location_on, size: 16),
                  ),
                ],
              ),
            );
          }

          // Deal tile
          final deal = _cityDeals[index - 1];
          return _buildDealTile(deal);
        },
      ),
    );
  }

  /// Build individual deal tile
  Widget _buildDealTile(Discount deal) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: deal.imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  deal.imageUrl!,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.image_not_supported),
                    );
                  },
                ),
              )
            : Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_offer),
              ),
        title: Text(deal.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(deal.description),
            const SizedBox(height: 4),
            if (deal.city != null)
              Text(
                '📍 ${deal.city}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              deal.discountDisplay,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            Text(
              'Save R${deal.savings.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        onTap: () {
          // Handle deal tap - navigate to deal details
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${deal.name} tapped')));
        },
      ),
    );
  }
}
