import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io' show Platform;
import 'dart:convert';
import 'dart:async';
import '../../services/supabase_service.dart';
import '../../services/discount_service.dart';
import '../../services/push_notification_service.dart';
import '../../models/discount.dart';
import 'welcome_page.dart';
import 'business_profile_page.dart';
import 'discount_management_page.dart';
import 'discount_selection_page.dart';
import '../business/bill_approval_page.dart';
import 'deal_authorization_dashboard.dart';
import '../../widgets/branded_app_bar.dart';
import 'package:flutter/foundation.dart';

class TrustedPartnerHomePage extends StatefulWidget {
  const TrustedPartnerHomePage({super.key});

  @override
  State<TrustedPartnerHomePage> createState() => _TrustedPartnerHomePageState();
}

class _TrustedPartnerHomePageState extends State<TrustedPartnerHomePage>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _scannerController = MobileScannerController();
  final DiscountService _discountService = DiscountService();
  List<Discount> _discounts = [];
  bool _discountsLoading = true;
  bool _isLoading = false;
  DateTime? _lastScanTime;
  String? _businessName;
  int _pendingDealRequestsCount = 0;
  int _pendingBillApprovalsCount = 0;

  // Animation for pulsing envelope
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Check if we're on a mobile platform or mobile browser that supports camera
  bool get _isMobilePlatform {
    if (kIsWeb) {
      return defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android;
    }
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void initState() {
    super.initState();
    _loadDiscounts();
    _loadBusinessName();
    _loadPendingDealRequestsCount();
    _loadPendingBillApprovalsCount();

    // Ensure push notification listener is active for the logged-in TP user
    // TEMPORARILY DISABLED: Push notifications turned off
    // PushNotificationService().reinitializeForCurrentUser();

    // Initialize pulsing animation
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Register callback for notification updates
    PushNotificationService().onNotificationsChanged = () {
      if (kDebugMode) {
        print(
          '[UI] Notifications changed, refreshing pending deal requests count',
        );
      }
      _loadPendingDealRequestsCount();
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when page becomes visible
    if (kDebugMode) {
      print('TrustedPartnerHomePage became visible, refreshing data');
    }
    _loadPendingDealRequestsCount();
    _loadPendingBillApprovalsCount();

    // Also set up a periodic refresh
    _setupPeriodicRefresh();
  }

  void _setupPeriodicRefresh() {
    // Refresh every 30 seconds
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        if (kDebugMode) {
          print('Periodic refresh: updating pending deal requests count');
        }
        _loadPendingDealRequestsCount();
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        toolbarHeight: 100,
        title: Image.asset('assets/locallekker_logo.png', height: 200),
        actions: [
          IconButton(
            tooltip: 'Manage Discounts',
            onPressed: _navigateToDiscountManagement,
            icon: const Icon(Icons.discount),
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuSelection,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'deal_requests',
                child: ListTile(
                  leading: Icon(Icons.approval),
                  title: Text('Deal Authorizations'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person),
                  title: Text('Business Profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
          IconButton(
            tooltip: 'Sign Out',
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _isMobilePlatform
          ? _buildMobileScannerBody()
          : _buildDesktopScannerBody(),
    );
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'deal_requests':
        _navigateToDealRequests();
        break;
      case 'approvals':
        _navigateToBillApprovals();
        break;
      case 'profile':
        _navigateToBusinessProfile();
        break;
    }
  }

  void _navigateToBusinessProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BusinessProfilePage()),
    );
  }

  void _navigateToDealRequests() {
    // Await the navigation so we can refresh counts when the user returns
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DealAuthorizationDashboard(),
      ),
    ).then((_) async {
      // Refresh counts after returning from the Deal Authorizations screen
      try {
        if (mounted) {
          await _loadPendingDealRequestsCount();
          await _loadPendingBillApprovalsCount();
        }
      } catch (e) {
        if (kDebugMode) {
          print(
            'Error refreshing counts after returning from deal requests: $e',
          );
        }
      }
    });
  }

  void _navigateToBillApprovals() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BillApprovalPage()),
    );
  }

  void _navigateToDiscountManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DiscountManagementPage()),
    );
  }

  void _navigateToDiscountSelection(String name, String surname) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DiscountSelectionPage(userName: name, userSurname: surname),
      ),
    );
  }

  Future<void> _loadDiscounts() async {
    setState(() => _discountsLoading = true);
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user != null) {
        final discounts = await _discountService.getAllTrustedPartnerDiscounts(
          user.id,
        );
        setState(() => _discounts = discounts);
      }
    } catch (e) {
      // Silently fail for now - don't show error on main screen
      if (kDebugMode) {
        print('Failed to load discounts: $e');
      }
    } finally {
      setState(() => _discountsLoading = false);
    }
  }

  Future<void> _loadBusinessName() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user != null) {
        final business = await SupabaseService.instance.client
            .from('businesses')
            .select('name')
            .eq('owner_member_id', user.id)
            .maybeSingle();
        if (business != null) {
          setState(() => _businessName = business['name']);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load business name: $e');
      }
    }
  }

  Future<void> _loadPendingDealRequestsCount() async {
    setState(() => _isLoading = true);
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (kDebugMode) {
        print('Loading pending deal requests for user: ${user?.id}');
      }
      if (kDebugMode) {
        print('User email: ${user?.email}');
      }
      if (user != null) {
        // Debug: Check database state first
        await _discountService.debugDatabaseState(user.id);

        // First, ensure notifications exist for existing pending authorizations
        await _discountService
            .createNotificationsForExistingPendingAuthorizations(user.id);

        // Force a refresh of the count after backfill
        if (kDebugMode) {
          print('Forcing refresh after backfill');
        }
        await Future.delayed(
          const Duration(milliseconds: 500),
        ); // Small delay for DB consistency

        final authorizations = await _discountService
            .getTrustedPartnerDealAuthorizations(user.id);
        if (kDebugMode) {
          print('Found ${authorizations.length} total authorizations');
        }
        var pendingCount = authorizations
            .where((auth) => auth.status == 'pending')
            .length;
        if (kDebugMode) {
          print('Found $pendingCount pending authorizations');
        }
        if (kDebugMode) {
          print('Setting state: _pendingDealRequestsCount = $pendingCount');
        }
        setState(() => _pendingDealRequestsCount = pendingCount);
        if (kDebugMode) {
          print('State updated successfully');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load pending deal requests count: $e');
      }
      if (kDebugMode) {
        print('Error details: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadPendingBillApprovalsCount() async {
    setState(() => _isLoading = true);
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (kDebugMode) {
        print('Loading processed bill approvals for user: ${user?.id}');
      }
      if (user != null) {
        // Get business ID for this trusted partner
        final businessResponse = await SupabaseService.instance.client
            .from('businesses')
            .select('id')
            .eq('owner_member_id', user.id)
            .maybeSingle();

        if (businessResponse != null) {
          final businessId = businessResponse['id'];
          // Query deal_authorizations for approved/rejected statuses
          final approvals = await SupabaseService.instance.client
              .from('deal_authorizations')
              .select('id')
              .eq('business_id', businessId)
              .inFilter('status', ['approved', 'rejected']);
          if (kDebugMode) {
            print('Found ${approvals.length} processed bill approvals');
          }
          setState(() => _pendingBillApprovalsCount = approvals.length);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load processed bill approvals count: $e');
      }
      if (kDebugMode) {
        print('Error details: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleDiscountActive(Discount discount) async {
    try {
      await _discountService.updateDiscount(
        discount.id,
        isActive: !discount.isActive,
      );

      // Update local state
      setState(() {
        final index = _discounts.indexWhere((d) => d.id == discount.id);
        if (index != -1) {
          _discounts[index] = Discount(
            id: discount.id,
            trustedPartnerId: discount.trustedPartnerId,
            name: discount.name,
            description: discount.description,
            itemName: discount.itemName,
            itemPrice: discount.itemPrice,
            percentage: discount.percentage,
            fixedAmount: discount.fixedAmount,
            isActive: !discount.isActive,
            createdAt: discount.createdAt,
            updatedAt: DateTime.now(),
          );
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Discount ${discount.isActive ? 'deactivated' : 'activated'}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update discount status'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildDiscountSummary() {
    if (_discountsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_discounts.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.discount_outlined, color: Colors.grey),
              const SizedBox(height: 8),
              const Text(
                'No discounts yet',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _navigateToDiscountManagement,
                icon: const Icon(Icons.add),
                label: const Text('Create Discount'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your Discounts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: _navigateToDiscountManagement,
                  child: const Text('Manage'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._discounts
                .take(3)
                .map(
                  (discount) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            discount.name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              discount.discountDisplay,
                              style: TextStyle(
                                color: discount.isActive
                                    ? Colors.green
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Switch(
                              value: discount.isActive,
                              onChanged: (value) =>
                                  _toggleDiscountActive(discount),
                              activeThumbColor: Colors.green,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            if (_discounts.length > 3)
              Text(
                '+${_discounts.length - 3} more',
                style: const TextStyle(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileScannerBody() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Business Name
          if (_businessName != null && _businessName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _businessName!,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // Deal Authorizations Card - Always show
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              color: _pendingDealRequestsCount > 0
                  ? Colors.orange.shade50
                  : Colors.grey.shade100,
              child: InkWell(
                onTap: _navigateToDealRequests,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _pendingDealRequestsCount > 0
                                    ? _pulseAnimation.value
                                    : 1.0,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: _pendingDealRequestsCount > 0
                                        ? [
                                            BoxShadow(
                                              color: Colors.orange.withValues(
                                                alpha: 0.28,
                                              ),
                                              blurRadius: 14,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: const Icon(
                                    Icons.mail_outline,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                              );
                            },
                          ),

                          if (_pendingDealRequestsCount > 0)
                            Positioned(
                              // Slight overlap outside the icon box for emphasis
                              right: -6,
                              top: -6,
                              child: ScaleTransition(
                                scale: _pulseAnimation,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  child: Center(
                                    child: Text(
                                      _pendingDealRequestsCount > 99
                                          ? '99+'
                                          : '$_pendingDealRequestsCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Deal Authorizations',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_pendingDealRequestsCount authorization(s) pending',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          if (kDebugMode) {
                            print('Manual refresh button pressed');
                          }
                          final user = SupabaseService.instance
                              .getCurrentUser();
                          if (user != null) {
                            await _discountService.debugDatabaseState(user.id);
                          }
                          _loadPendingDealRequestsCount();
                        },
                        icon: const Icon(Icons.refresh, color: Colors.orange),
                        tooltip: 'Refresh Count',
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.orange),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bill Approvals Card (History) - Always show
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              color: _pendingBillApprovalsCount > 0
                  ? Colors.blue.shade50
                  : Colors.grey.shade100,
              child: InkWell(
                onTap: _navigateToBillApprovals,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.history,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Approval History',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_pendingBillApprovalsCount processed request(s)',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.blue),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // QR Scanner Section - 200x200 square viewer
          Container(
            height: 200, // 200x200 square viewer
            width: 200,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: MobileScanner(
                controller: _scannerController,
                onDetect: _onQrCodeDetected,
              ),
            ),
          ),

          // Instructions and Status
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(Icons.qr_code_scanner, size: 48, color: Colors.blue),
                const SizedBox(height: 16),
                const Text(
                  'Scan Member QR Code',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Point your camera at a member\'s QR code to process their information',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Discount Summary Section
          Container(
            margin: const EdgeInsets.all(16),
            child: _buildDiscountSummary(),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopScannerBody() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // Business Name Header
          if (_businessName != null && _businessName!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                _businessName!,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // Scanner Unavailable Notice - Centered Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_scanner,
                      size: 72,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'QR Scanner Unavailable',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Camera scanning is only available on mobile devices (Android/iOS).',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'On desktop, you can still access business features through the menu.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _navigateToBusinessProfile,
                      icon: const Icon(Icons.person, size: 20),
                      label: const Text('Business Profile'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Tab Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey.shade700,
              indicator: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              dividerColor: Colors.transparent,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.pending_actions, size: 20),
                      const SizedBox(width: 8),
                      const Text('Pending'),
                      if (_pendingDealRequestsCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _pendingDealRequestsCount > 99
                                ? '99+'
                                : '$_pendingDealRequestsCount',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, size: 20),
                      const SizedBox(width: 8),
                      const Text('Approved'),
                      if (_pendingBillApprovalsCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$_pendingBillApprovalsCount',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.discount, size: 20),
                      SizedBox(width: 8),
                      Text('My Deals'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              children: [
                // Pending Tab
                _buildPendingTab(),
                // Approved Tab
                _buildApprovedTab(),
                // My Deals Tab
                _buildDealsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pendingDealRequestsCount == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No Pending Requests',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'New deal authorization requests will appear here',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPendingDealRequestsCount,
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: _pendingDealRequestsCount,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.shopping_cart,
                      color: Colors.orange.shade700,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Deal Authorization Request',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pending approval',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _navigateToDealRequests,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('View'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildApprovedTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pendingBillApprovalsCount == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No Approval History',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Processed requests will appear here',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPendingBillApprovalsCount,
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: _pendingBillApprovalsCount,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade700,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Processed Request',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'View approval history',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _navigateToBillApprovals,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('View'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDealsTab() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: _buildDiscountSummary(),
    );
  }

  void _onQrCodeDetected(BarcodeCapture capture) async {
    // Debounce multiple detections of the same QR code
    final now = DateTime.now();
    if (_lastScanTime != null && now.difference(_lastScanTime!).inSeconds < 3) {
      return; // Ignore if scanned within 3 seconds
    }
    _lastScanTime = now;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final qrData = barcode.rawValue!;
        try {
          // Parse QR data as JSON
          final Map<String, dynamic> data = jsonDecode(qrData);
          final name = data['name'] as String? ?? 'Unknown';
          final surname = data['surname'] as String? ?? 'Unknown';
          _showUserDialog(name, surname);
        } catch (e) {
          _showErrorDialog('Invalid QR code format: $e');
        }
        break; // Process only the first barcode
      }
    }
  }

  void _showUserDialog(String name, String surname) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent, // Remove black fade background
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person, size: 48, color: Colors.blue),
                const SizedBox(height: 16),
                const Text(
                  'User Scanned',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Name: $name\nSurname: $surname',
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).pop(); // Close the current dialog
                          _navigateToDiscountSelection(name, surname);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Apply Discount'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await SupabaseService.instance.signOut();
      if (!context.mounted) return;

      // Navigate to welcome page after sign out
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
        (route) => false, // Remove all previous routes
      );
    } catch (e) {
      if (!context.mounted) return;

      // Show error if sign out fails
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sign out failed: $e')));
    }
  }
}
