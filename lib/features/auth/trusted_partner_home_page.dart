import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io' show Platform;
import 'dart:convert';
import 'dart:async';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/supabase_service.dart';
import '../members/fresh_local_partners_page.dart';
import '../members/local_sips_partners_page.dart';
import '../members/local_eats_partners_page.dart';
import '../members/locally_active_partners_page.dart';
import '../../services/discount_service.dart';
import '../../services/fresh_local_notice.dart';
import '../../services/push_notification_service.dart';
import '../../services/subscription_service.dart';
import '../../services/savings_service.dart';
import '../../models/discount.dart';
import '../../widgets/custom_qr_code.dart';
import '../../widgets/savings_summary_card.dart';
import '../../widgets/age_verification_dialog.dart';
import '../../widgets/member_category_banner_row.dart';
import '../../widgets/profile_photo.dart';
import '../members/member_receipts_page.dart';
import 'welcome_page.dart';
import 'business_profile_page.dart';
import 'discount_management_page.dart';
import 'discount_selection_page.dart';
import 'deal_selection_page.dart';
import 'promotion_detail_page.dart';
import 'member_profile_page.dart';
import '../payments/pending_payments_page.dart';
import '../../services/promotion_campaign_service.dart';
import 'trusted_partners_by_category_page.dart';
import 'admin_chat_page.dart';
import 'widgets/trusted_partner_key_dialog.dart';
import 'trusted_partner_inbox_page.dart';
import 'members_home_page.dart';
import '../../services/chat_service.dart';
import '../business/bill_approval_page.dart';
import 'deal_authorization_dashboard.dart';
import '../business/trusted_partner_analytics_dashboard.dart';
import '../../widgets/trusted_partner_analytics_widget.dart';
import '../../widgets/branded_app_bar.dart';
import 'package:flutter/foundation.dart';

/// Local Lekker brand palette used across the Trusted Partner screen.
const Color kBrandBlue = Color(0xFF001489); // primary navy blue
const Color kBrandGreen = Color(0xFF2E7D32); // success / member toggle
const Color kBrandYellow = Color(0xFFFFB81C); // accent / highlight

class TrustedPartnerHomePage extends StatefulWidget {
  const TrustedPartnerHomePage({super.key});

  @override
  State<TrustedPartnerHomePage> createState() => _TrustedPartnerHomePageState();
}

class _TrustedPartnerHomePageState extends State<TrustedPartnerHomePage>
  with TickerProviderStateMixin, WidgetsBindingObserver {
  final Logger _logger = Logger();
  bool _isMemberView = false;
  MobileScannerController? _scannerController;
  bool _cameraReady = false;
  String? _cameraError;
  bool _isScannerOpen = false;
  final DiscountService _discountService = DiscountService();
  List<Discount> _discounts = [];
  bool _discountsLoading = true;
  DateTime? _lastScanTime;
  static const double _headerToggleSlotWidth = 148;
  static const double _headerActionSlotWidth = 46;
  static const double _headerActionSlotHeight = 74;
  static const double _headerIconButtonFaceSize = 38;
  static const double _headerIconButtonCornerRadius = 12;
  static const double _headerCompactToggleSlotWidth = 60;
  static const double _headerCompactActionSlotWidth = 34;
  static const double _headerCompactActionSlotHeight = 60;
  static const double _headerCompactIconButtonFaceSize = 30;
  static const double _headerCompactGap = 4;
  static const double _headerGridGap = 10;
  String? _businessName;
  String? _businessLogoUrl;
  int _pendingDealRequestsCount = 0;
  int _unreadChatCount = 0;
  bool _hasActiveBanking = false;
  String? _bankName;
  bool _bankingStatusLoading = true;
  bool _isUploadingHeroLogo = false;
  Timer? _periodicRefreshTimer;
  final ImagePicker _heroLogoPicker = ImagePicker();

  // TP-Member dashboard (shown when the trusted partner toggles to Member mode)
  final SubscriptionService _memberSubscriptionService = SubscriptionService();
  final SavingsService _memberSavingsService = SavingsService();
  Map<String, dynamic>? _memberQrData;
  Map<String, dynamic>? _memberSubscriptionStatus;
  Map<String, dynamic>? _memberSavingsStats;
  bool _memberDashboardLoading = false;
  bool _memberDashboardLoaded = false;
  bool _memberQrExpanded = false;
  String? _memberProfilePhotoUrl;
  String? _memberFullName;
  bool _isUploadingMemberPhoto = false;
  String? _memberCity;
  int _memberTrustedPartnersCount = 0;
  int _memberAvailableDealsCount = 0;
  bool _memberCountsLoading = true;
  int _memberPendingPaymentsCount = 0;
  bool _memberHasFreshLocalPartners = false;
  int _memberFreshLocalNewDeals = 0;
  int _memberFreshLocalPartnerCount = 0;
  int _memberFreshLocalDealCount = 0;
  bool _memberHasLocalSipsPartners = false;
  int _memberLocalSipsNewDeals = 0;
  int _memberLocalSipsPartnerCount = 0;
  int _memberLocalSipsDealCount = 0;
  bool _memberHasLocalEatsPartners = false;
  int _memberLocalEatsNewDeals = 0;
  int _memberLocalEatsPartnerCount = 0;
  int _memberLocalEatsDealCount = 0;
  bool _memberHasLocallyActivePartners = false;
  int _memberLocallyActiveNewDeals = 0;
  int _memberLocallyActivePartnerCount = 0;
  int _memberLocallyActiveDealCount = 0;
  List<Map<String, dynamic>> _memberPromotions = [];

  // Realtime subscription for deal_authorizations
  RealtimeChannel? _dealAuthChannel;
  String? _businessId;

  // Realtime subscription for chat_messages (unread badge)
  RealtimeChannel? _chatMessagesChannel;
  final GlobalKey _settingsMenuButtonKey = GlobalKey();

  // Animation for pulsing envelope
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Animation for shutter open/close
  late AnimationController _shutterController;
  late Animation<double> _shutterAnimation;
  bool _isInitializingCamera = false;

  // Check if we're on a mobile platform or mobile browser that supports camera
  bool get _isMobilePlatform {
    if (kIsWeb) {
      return defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android;
    }
    return Platform.isAndroid || Platform.isIOS;
  }

  // Which UI layout to render. OS sniffing via defaultTargetPlatform is
  // unreliable in embedded/in-app browsers (e.g. WhatsApp, some iOS Safari
  // contexts), so on web we fall back to viewport width to decide the
  // layout, ensuring iOS web matches the native Android mobile layout.
  bool get _isMobileLayout {
    if (!kIsWeb) return _isMobilePlatform;
    if (_isMobilePlatform) return true;
    return MediaQuery.of(context).size.width < 700;
  }

  @override
  void initState() {
    super.initState();
    // Observe lifecycle to resume scanner when returning from Settings
    WidgetsBinding.instance.addObserver(this);
    _loadDiscounts();
    _loadBusinessName();
    _loadBankingStatus();
    _loadPendingDealRequestsCount();
    _loadPendingBillApprovalsCount();
    _loadUnreadChatCount();
    _setupRealtimeDealAuthSubscription();
    _setupRealtimeChatSubscription();

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

    // Initialize shutter animation
    _shutterController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shutterAnimation = CurvedAnimation(
      parent: _shutterController,
      curve: Curves.easeInOut,
    );

    // Register callback for notification updates
    PushNotificationService().onNotificationsChanged = () {
      if (kDebugMode) {
        print(
          '[UI] Notifications changed, refreshing pending deal requests count',
        );
      }
      _loadPendingDealRequestsCountFast();
    };
  }

  Future<void> _initializeCamera() async {
    if (!_isMobilePlatform) return;
    if (_isInitializingCamera) return;
    _isInitializingCamera = true;
    try {
      final controller = MobileScannerController(
        detectionTimeoutMs: 1000,
      );
      _scannerController = controller;
      // Let MobileScanner widget handle start() via autoStart (default: true).
      // Setting _cameraReady triggers a rebuild so the widget is placed in the
      // tree and the controller starts the camera automatically.
      if (mounted) {
        setState(() {
          _cameraReady = true;
          _cameraError = null;
        });
      }
    } catch (e) {
      _logger.e('Camera initialization failed: $e');
      if (mounted) {
        setState(() {
          _cameraError = e.toString();
          _cameraReady = false;
        });
      }
    } finally {
      _isInitializingCamera = false;
    }
  }

  Future<void> _restartCamera() async {
    if (!mounted) return;
    setState(() {
      _cameraReady = false;
      _cameraError = null;
    });
    try {
      await _scannerController?.stop();
    } catch (_) {}
    try {
      _scannerController?.dispose();
    } catch (_) {}
    _scannerController = null;
    // Allow native camera resources to fully release before re-creating
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await _ensureCameraPermissionAndInit();
  }

  Future<void> _openScanner() async {
    // Request permission and initialize camera first
    final granted = await _ensureCameraPermissionAndInit();
    if (!granted) {
      // Permission not granted - keep scanner closed and show friendly message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required to scan member QR codes.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isScannerOpen = true);
    _shutterController.forward();
    // Camera initialized by _ensureCameraPermissionAndInit -> _initializeCamera
  }

  /// Attempts to initialize the camera controller. Permission prompts will be
  /// triggered by the native camera APIs when needed; this avoids a dependency
  /// on `permission_handler` which currently conflicts with local Android tooling.
  Future<bool> _ensureCameraPermissionAndInit() async {
    if (!_isMobilePlatform) return false;
    try {
      await _initializeCamera();
      return true;
    } catch (e) {
      _logger.w('Camera permission/init error: $e');
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _resumeScannerIfNeeded();
    } else if (state == AppLifecycleState.paused) {
      // Pause/stop camera to release resources
      try {
        _scannerController?.stop();
      } catch (_) {}
    }
  }

  Future<void> _resumeScannerIfNeeded() async {
    if (!_isScannerOpen) return;
    try {
      if (_scannerController == null) {
        await _initializeCamera();
      } else {
        try {
          await _scannerController?.start();
        } catch (e) {
          _logger.w('Failed to start scanner on resume: $e');
          await _initializeCamera();
        }
      }
    } catch (e) {
      _logger.w('Resume scanner failed: $e');
      if (mounted) {
        setState(() {
          _cameraReady = false;
          _cameraError = e.toString();
        });
      }
    }
  }

  Future<void> _closeScanner() async {
    _shutterController.reverse();
    await Future.delayed(const Duration(milliseconds: 400));
    try {
      await _scannerController?.stop();
    } catch (_) {}
    try {
      _scannerController?.dispose();
    } catch (_) {}
    _scannerController = null;
    if (mounted) {
      setState(() {
        _isScannerOpen = false;
        _cameraReady = false;
        _cameraError = null;
      });
    }
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
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _logger.d('Periodic refresh: updating pending deal requests count');
        _loadPendingDealRequestsCountFast();
        _loadUnreadChatCount();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _loadUnreadChatCount() async {
    try {
      final count = await ChatService.instance.fetchUnreadConversationCount();
      if (!mounted) return;
      if (count != _unreadChatCount) {
        setState(() => _unreadChatCount = count);
      }
    } catch (e) {
      _logger.w('Failed to load unread chat count: $e');
    }
  }

  /// Realtime channel that refreshes the unread chat badge instantly when
  /// any chat_messages row is inserted or updated.
  void _setupRealtimeChatSubscription() {
    try {
      _chatMessagesChannel = ChatService.instance
          .subscribeToChatMessageChanges(onChange: _loadUnreadChatCount);
    } catch (e) {
      _logger.w('Failed to subscribe to chat realtime: $e');
    }
  }

  /// Set up a Supabase Realtime channel on deal_authorizations for this TP's business.
  /// This fires instantly when a member creates a new pending deal request.
  Future<void> _setupRealtimeDealAuthSubscription() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      // Get business ID for this trusted partner
      final businessResponse = await SupabaseService.instance.client
          .from('businesses')
          .select('id')
          .eq('owner_member_id', user.id)
          .maybeSingle();

      if (businessResponse == null) {
        _logger.w('No business found for realtime deal auth subscription');
        return;
      }

      _businessId = businessResponse['id'] as String;

      // Subscribe to INSERT events on deal_authorizations for this business
      _dealAuthChannel = SupabaseService.instance.client
          .channel('deal_auth_realtime_${user.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'deal_authorizations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'business_id',
              value: _businessId!,
            ),
            callback: (payload) {
              if (kDebugMode) {
                print('[REALTIME] New deal authorization detected: ${payload.newRecord}');
              }
              _logger.i('Realtime: New deal authorization received');
              // Immediately refresh the pending count
              _loadPendingDealRequestsCountFast();
              // Also show the push notification service callback
              // (the notification insert will trigger PushNotificationService too,
              //  but this gives us a faster path for the badge count)
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'deal_authorizations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'business_id',
              value: _businessId!,
            ),
            callback: (payload) {
              if (kDebugMode) {
                print('[REALTIME] Deal authorization updated: ${payload.newRecord}');
              }
              // Refresh count when status changes (approve/reject)
              _loadPendingDealRequestsCountFast();
            },
          )
          .subscribe();

      _logger.i('Realtime deal authorization subscription active for business $_businessId');
    } catch (e) {
      _logger.e('Failed to set up realtime deal auth subscription: $e');
    }
  }

  /// Fast path for counting pending deal requests - no backfill, no debug queries.
  /// Used by realtime callbacks and periodic refresh for instant UI updates.
  Future<void> _loadPendingDealRequestsCountFast() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      // Use cached business ID if available, otherwise fetch it
      String? bizId = _businessId;
      if (bizId == null) {
        final businessResponse = await SupabaseService.instance.client
            .from('businesses')
            .select('id')
            .eq('owner_member_id', user.id)
            .maybeSingle();
        if (businessResponse == null) return;
        bizId = businessResponse['id'] as String;
        _businessId = bizId;
      }

      // Simple fast count query - just count pending authorizations
      final pendingResponse = await SupabaseService.instance.client
          .from('deal_authorizations')
          .select('id')
          .eq('business_id', bizId)
          .eq('status', 'pending');

      final pendingCount = pendingResponse.length;

      if (mounted && pendingCount != _pendingDealRequestsCount) {
        if (kDebugMode) {
          print('[FAST_COUNT] Pending deal requests: $pendingCount (was $_pendingDealRequestsCount)');
        }
        setState(() => _pendingDealRequestsCount = pendingCount);
      }
    } catch (e) {
      _logger.e('Fast pending count failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicRefreshTimer?.cancel();
    _dealAuthChannel?.unsubscribe();
    _chatMessagesChannel?.unsubscribe();
    try {
      _scannerController?.stop();
    } catch (_) {}
    try {
      _scannerController?.dispose();
    } catch (_) {}
    _pulseController.dispose();
    _shutterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When in member view, show the MembersHomePage with its own AppBar
    // and add the toggle to switch back to business view
    if (_isMemberView) {
      return _buildMemberViewWithToggle();
    }

    // Business view - show trusted partner's AppBar and content
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: BrandedAppBar(
        toolbarHeight: _isShortLandscapeViewport ? 68 : 100,
        actions: [
          _buildHeaderActionGrid(isMemberMode: false),
        ],
      ),
      body: _isMobileLayout
          ? _buildMobileScannerBody()
          : _buildDesktopScannerBody(),
    );
  }

  Widget _buildMemberViewWithToggle() {
    return MembersHomePage(
      isTrustedPartner: true,
      onBackToBusiness: _toggleMemberView,
    );
  }

  void _toggleMemberView() {
    setState(() => _isMemberView = !_isMemberView);
  }

  Future<void> _loadTpMemberDashboardData() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;
    if (mounted) setState(() => _memberDashboardLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        _memberSubscriptionService.getUserQrCode(user.id).catchError((_) => null),
        _memberSubscriptionService
            .getSubscriptionStatus(user.id)
            .catchError((_) => null),
        _memberSavingsService.getUserSavingsStats(user.id).catchError((_) => null),
        SupabaseService.instance
            .getUserProfile(userId: user.id)
            .catchError((_) => null),
      ]);
      if (!mounted) return;
      final profile = results[3] as Map<String, dynamic>?;
      final String name = (profile?['name']?.toString() ?? '').trim();
      final String surname = (profile?['surname']?.toString() ?? '').trim();
      // Only append surname if it isn't empty and isn't already part of name
      // (some accounts store the full name in the `name` field).
      final String fullName = name.isEmpty
          ? surname
          : (surname.isNotEmpty && !name.contains(surname)
              ? '$name $surname'
              : name);
      setState(() {
        _memberQrData = results[0] as Map<String, dynamic>?;
        _memberSubscriptionStatus = results[1] as Map<String, dynamic>?;
        _memberSavingsStats = results[2] as Map<String, dynamic>?;
        _memberProfilePhotoUrl =
            profile?['profile_photo_url']?.toString().trim();
        _memberFullName = fullName.isNotEmpty ? fullName : null;
        _memberCity = profile?['city']?.toString().trim();
        _memberDashboardLoading = false;
        _memberDashboardLoaded = true;
      });
      unawaited(_loadMemberExtras());
    } catch (e) {
      _logger.e('Failed to load TP-member dashboard data: $e');
      if (mounted) {
        setState(() {
          _memberDashboardLoading = false;
          _memberDashboardLoaded = true;
        });
      }
    }
  }

  // Loads the additional member functions (counts, pending payments, promotions).
  Future<void> _loadMemberExtras() async {
    await Future.wait<void>([
      _loadMemberPartnerDealCounts(),
      _loadMemberPendingPaymentsCount(),
      _loadMemberPromotions(),
      _loadMemberFreshLocalAvailability(),
    ]);
  }

  Future<void> _loadMemberFreshLocalAvailability() async {
    final stopwatch = Stopwatch()..start();
    final results = await Future.wait<FreshLocalSummary>([
      Future(() async => DiscountService().getFreshLocalSummary(
            city: _memberCity,
            since: await FreshLocalNotice.loadLastSeen(),
          )),
      Future(() async => DiscountService().getLocalSipsSummary(
            city: _memberCity,
            since: await LocalSipsNotice.loadLastSeen(),
          )),
      Future(() async => DiscountService().getLocallyActiveSummary(
            city: _memberCity,
            since: await LocallyActiveNotice.loadLastSeen(),
          )),
      Future(() async => DiscountService().getLocalEatsSummary(
        city: _memberCity,
        since: await LocalEatsNotice.loadLastSeen(),
          )),
    ]);
    final summary = results[0];
    final sips = results[1];
    final active = results[2];
    final eats = results[3];
    _logger.i(
      'TP member category tabs loaded in ${stopwatch.elapsedMilliseconds}ms '
      '(city: ${_memberCity ?? 'all'})',
    );
    if (!mounted) return;
    setState(() {
      _memberHasFreshLocalPartners = summary.hasPartners;
      _memberFreshLocalNewDeals = summary.newDealCount;
      _memberFreshLocalPartnerCount = summary.partnerCount;
      _memberFreshLocalDealCount = summary.dealCount;
      _memberHasLocalSipsPartners = sips.hasPartners;
      _memberLocalSipsNewDeals = sips.newDealCount;
      _memberLocalSipsPartnerCount = sips.partnerCount;
      _memberLocalSipsDealCount = sips.dealCount;
      _memberHasLocalEatsPartners = eats.hasPartners;
      _memberLocalEatsNewDeals = eats.newDealCount;
      _memberLocalEatsPartnerCount = eats.partnerCount;
      _memberLocalEatsDealCount = eats.dealCount;
      _memberHasLocallyActivePartners = active.hasPartners;
      _memberLocallyActiveNewDeals = active.newDealCount;
      _memberLocallyActivePartnerCount = active.partnerCount;
      _memberLocallyActiveDealCount = active.dealCount;
    });
  }

  Future<void> _loadMemberPartnerDealCounts() async {
    if (mounted) setState(() => _memberCountsLoading = true);
    try {
      final client = SupabaseService.instance.client;
      final partners = await client
          .from('businesses')
          .select('id, owner_member_id') as List<dynamic>;
      final deals = await client
          .from('trusted_partner_discounts')
          .select('id, business_id, trusted_partner_id, is_active')
          .eq('is_active', true) as List<dynamic>;

      final validBusinessIds = partners.map((b) => b['id']).toSet();
      final validPartnerIds = partners.map((b) => b['owner_member_id']).toSet();
      final validDeals = deals.where((d) {
        final hasBiz = d['business_id'] != null &&
            validBusinessIds.contains(d['business_id']);
        final hasPartner = d['trusted_partner_id'] != null &&
            validPartnerIds.contains(d['trusted_partner_id']);
        return hasBiz || hasPartner;
      }).toList();

      if (!mounted) return;
      setState(() {
        _memberTrustedPartnersCount = partners.length;
        _memberAvailableDealsCount = validDeals.length;
        _memberCountsLoading = false;
      });
    } catch (e) {
      _logger.e('Failed to load member partner/deal counts: $e');
      if (mounted) setState(() => _memberCountsLoading = false);
    }
  }

  Future<void> _loadMemberPendingPaymentsCount() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;
      final pending = await SupabaseService.instance.client
          .from('deal_authorizations')
          .select('id')
          .eq('member_id', user.id)
          .eq('status', 'approved')
          .isFilter('payment_completed_at', null) as List<dynamic>;
      if (!mounted) return;
      setState(() => _memberPendingPaymentsCount = pending.length);
    } catch (e) {
      _logger.e('Failed to load member pending payments: $e');
    }
  }

  Future<void> _loadMemberPromotions() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      final email = user?.email;
      if (user == null || email == null || email.isEmpty) return;

      final eligible = await PromotionCampaignService()
          .getEligiblePromotionsForEmail(email: email);

      if (eligible.isNotEmpty) {
        final signups = await SupabaseService.instance.client
            .from('promotion_signups')
            .select('promotion_id')
            .eq('user_id', user.id) as List<dynamic>;
        final signedUpIds =
            signups.map((s) => s['promotion_id'] as String).toSet();
        eligible.removeWhere((p) => signedUpIds.contains(p['id']));
      }

      if (!mounted) return;
      setState(() => _memberPromotions = eligible);
    } catch (e) {
      _logger.e('Failed to load member promotions: $e');
    }
  }

  Widget _buildTpMemberDashboardBody() {
    // Member-styled TP-member dashboard aligned to the normal member home
    // (members_home_page.dart): blue gradient hero, 3-tile quick-actions row,
    // Today stats, and a Trusted Partners summary card. Profile/Support/
    // Messages/Logout stay reachable via the member-mode app bar grid, and
    // Back-to-Business via the hero toggle.
    return Container(
      color: const Color(0xFFEFF3F8),
      child: RefreshIndicator(
        onRefresh: () async {
          _memberDashboardLoaded = false;
          await _loadTpMemberDashboardData();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTpMemberHero(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_memberPromotions.isNotEmpty) ...[
                      for (final promo in _memberPromotions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildTpMemberPromoBanner(promo),
                        ),
                      const SizedBox(height: 12),
                    ],

                    // Quick actions — 3-tile row (matches member home)
                    _buildTpSectionHeader('Quick actions'),
                    const SizedBox(height: 8),
                    _buildTpMemberQuickActionsRow(),
                    const SizedBox(height: 20),

                    // Today stats — Partners nearby / Active deals
                    _buildTpSectionHeader('Today'),
                    const SizedBox(height: 8),
                    _buildTpMemberTodayStats(),
                    const SizedBox(height: 20),

                    // Pending payments urgent card (conditional)
                    if (_memberPendingPaymentsCount > 0) ...[
                      _buildTpMemberPendingPaymentsCard(),
                      const SizedBox(height: 20),
                    ],

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Quick-actions row mirroring the member home (Find Deals, Receipts), plus
  // the category banner row (Partners, Fresh & Local, Local Sips).
  Widget _buildTpMemberQuickActionsRow() {
    final row = Row(
      children: [
        Expanded(
          child: _buildTpMemberActionTileCompact(
            icon: Icons.local_offer_outlined,
            label: 'Find Deals',
            color: const Color(0xFFF59E0B),
            bgColor: const Color(0x1FF59E0B),
            onTap: _openMemberFindDeals,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildTpMemberActionTileCompact(
            icon: Icons.receipt_long_outlined,
            label: 'Receipts',
            color: const Color(0xFF15803D),
            bgColor: const Color(0x1A15803D),
            onTap: _openMemberReceipts,
          ),
        ),
      ],
    );

    return Column(
      children: [
        row,
        const SizedBox(height: 10),
        MemberCategoryBannerRow(
          onTapPartners: _openMemberBrowseDeals,
          partnerCount: _memberTrustedPartnersCount,
          dealCount: _memberAvailableDealsCount,
          showFreshLocal: _memberHasFreshLocalPartners,
          onTapFreshLocal: _openMemberFreshLocal,
          freshNewDeals: _memberFreshLocalNewDeals,
          freshPartnerCount: _memberFreshLocalPartnerCount,
          freshDealCount: _memberFreshLocalDealCount,
          showLocalSips: _memberHasLocalSipsPartners,
          onTapLocalSips: _openMemberLocalSips,
          sipsNewDeals: _memberLocalSipsNewDeals,
          sipsPartnerCount: _memberLocalSipsPartnerCount,
          sipsDealCount: _memberLocalSipsDealCount,
          showLocalEats: _memberHasLocalEatsPartners,
          onTapLocalEats: _openMemberLocalEats,
          eatsNewDeals: _memberLocalEatsNewDeals,
          eatsPartnerCount: _memberLocalEatsPartnerCount,
          eatsDealCount: _memberLocalEatsDealCount,
          showLocallyActive: _memberHasLocallyActivePartners,
          onTapLocallyActive: _openMemberLocallyActive,
          activeNewDeals: _memberLocallyActiveNewDeals,
          activePartnerCount: _memberLocallyActivePartnerCount,
          activeDealCount: _memberLocallyActiveDealCount,
        ),
      ],
    );
  }

  Widget _buildTpMemberActionTileCompact({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0E5BA0).withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0B2540),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTpMemberHero() {
    final String displayName = _memberFullName?.trim().isNotEmpty == true
        ? _memberFullName!.trim()
        : (_businessName?.trim().isNotEmpty == true
            ? _businessName!.trim()
            : 'Member');
    final stats = _memberSavingsStats;
    final double totalSaved = (stats?['totalSaved'] as num?)?.toDouble() ?? 0.0;
    final double totalTips = (stats?['totalTips'] as num?)?.toDouble() ?? 0.0;
    final double totalPaid = (stats?['totalPaid'] as num?)?.toDouble() ?? 0.0;
    final int totalDeals = (stats?['totalDeals'] as num?)?.toInt() ?? 0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E5BA0), Color(0xFF0A4A8A), Color(0xFF083D73)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _isUploadingMemberPhoto
                          ? null
                          : _pickAndSaveMemberPhoto,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ProfilePhoto(
                            imageUrl: _memberProfilePhotoUrl,
                            displayName: displayName,
                            size: 54,
                            shape: ProfilePhotoShape.circle,
                            borderColor: Colors.white,
                            borderWidth: 2,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.16),
                            foregroundColor: Colors.white,
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: _isUploadingMemberPhoto
                                  ? const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.edit_rounded,
                                      size: 10, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Member account',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.03,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: 'Back to Business Mode',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _toggleMemberView,
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                            child: const Icon(
                              Icons.swap_horiz_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildTpMemberQrStrip(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTpStatTile(
                        label: 'Saved',
                        value: 'R${totalSaved.toStringAsFixed(0)}',
                        icon: Icons.savings_outlined,
                        accentColor: const Color(0xFF7CE39A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTpStatTile(
                        label: 'Tips',
                        value: 'R${totalTips.toStringAsFixed(0)}',
                        icon: Icons.volunteer_activism,
                        accentColor: const Color(0xFFFF7B7B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTpStatTile(
                        label: 'Paid',
                        value: 'R${totalPaid.toStringAsFixed(0)}',
                        icon: Icons.credit_card,
                        accentColor: const Color(0xFF8CC6FF),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTpStatTile(
                        label: 'Deals',
                        value: '$totalDeals',
                        icon: Icons.local_offer_outlined,
                        accentColor: const Color(0xFFFFD56A),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the promo-key dialog so a trusted partner can activate their own
  /// member QR code (same flow members use). The activation field starts empty
  /// on purpose: the TP copies their unique Trusted Partner key from their
  /// Business Profile and pastes it here. Reloads the member dashboard on
  /// success so the new permanent QR appears immediately.
  Future<void> _openTpKeyActivationDialog() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => TrustedPartnerKeyDialog(
        userId: user.id,
        isTrustedPartnerKey: true,
        onSuccess: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Membership activated! Your QR code is now active.',
              ),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
          // Force a fresh load so the new permanent QR shows immediately.
          _memberDashboardLoaded = false;
          _loadTpMemberDashboardData();
        },
      ),
    );
  }

  void _showTpMemberQrPopup() {
    final String? qrString = _memberQrData?['qr_code'] as String?;
    final bool subActive =
        (_memberSubscriptionStatus?['subscription_status']?.toString() ??
                'none') ==
            'active';
    final bool qrActive = _memberQrData?['is_active'] == true &&
        qrString != null &&
        qrString.trim().isNotEmpty;
    final String memberName = _businessName?.trim().isNotEmpty == true
        ? _businessName!.trim()
        : 'Member';
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Your QR Code',
                        style: Theme.of(ctx).textTheme.titleLarge),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _memberDashboardLoading
                      ? const SizedBox(
                          height: 200,
                          width: 200,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : qrActive
                          ? CustomQrCode(
                              data: qrString,
                              logoAssetPath: 'assets/heart_flag.png',
                              size: 220,
                            )
                          : SizedBox(
                              width: 220,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 12),
                                  const Icon(Icons.qr_code_2_rounded,
                                      size: 56, color: Color(0xFF9AA5B1)),
                                  const SizedBox(height: 10),
                                  Text(
                                    subActive
                                        ? 'QR code unavailable'
                                        : 'Activate your membership to get your QR code',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF627D98),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (!subActive) ...[
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 46,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.of(ctx).pop();
                                          _openTpKeyActivationDialog();
                                        },
                                        icon: const Icon(
                                            Icons.vpn_key_rounded,
                                            size: 18),
                                        label: const Text('Insert Promo Key'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF0E5BA0),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                ),
                const SizedBox(height: 14),
                Text(
                  memberName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF102A43),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Show this QR at checkout to redeem member deals',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF627D98),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTpMemberQrStrip() {
    final String? qrString = _memberQrData?['qr_code'] as String?;
    final bool qrActive = _memberQrData?['is_active'] == true &&
        qrString != null &&
        qrString.trim().isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showTpMemberQrPopup,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0E5BA0), Color(0xFF0A4A8A), Color(0xFF08396A)],
            stops: [0.0, 0.58, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0A4A8A).withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.qr_code_2_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Your QR Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    qrActive
                        ? 'Tap to show your QR code'
                        : 'Tap to activate your QR code',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.74),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Gradient-wrapped savings summary, shared across layouts.
  Widget _buildTpMemberSavingsCard() {
    final double totalSpent =
        (_memberSavingsStats?['totalSpent'] as num?)?.toDouble() ?? 0.0;
    final double totalSaved =
        (_memberSavingsStats?['totalSaved'] as num?)?.toDouble() ?? 0.0;
    final double totalPaid =
        (_memberSavingsStats?['totalPaid'] as num?)?.toDouble() ?? 0.0;
    final double totalTips =
        (_memberSavingsStats?['totalTips'] as num?)?.toDouble() ?? 0.0;
    final int totalDeals =
        (_memberSavingsStats?['totalDeals'] as num?)?.toInt() ?? 0;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF15803D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SavingsSummaryCard(
        totalSpent: totalSpent,
        totalSaved: totalSaved,
        totalPaid: totalPaid,
        totalTips: totalTips,
        totalDeals: totalDeals,
        isLoading: _memberDashboardLoading,
        onBrowseDeals: _openMemberBrowseDeals,
        onViewReceipts: _openMemberReceipts,
      ),
    );
  }

  // The three quick-action tiles, shared across layouts.
  List<Widget> _tpMemberActionTiles() {
    return [
      _buildMemberActionTile(
        icon: Icons.local_offer_rounded,
        color: const Color(0xFF2563EB),
        title: 'Find Deals',
        subtitle: 'Browse and redeem member deals',
        onTap: _openMemberFindDeals,
      ),
      _buildMemberActionTile(
        icon: Icons.storefront_rounded,
        color: const Color(0xFF15803D),
        title: 'Trusted Partners',
        subtitle: 'Explore partners by category near you',
        onTap: _openMemberBrowseDeals,
      ),
      _buildMemberActionTile(
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFFB45309),
        title: 'My Receipts & History',
        subtitle: 'View past deals and issued receipts',
        onTap: _openMemberReceipts,
      ),
      _buildMemberActionTile(
        icon: Icons.person_rounded,
        color: const Color(0xFF7C3AED),
        title: 'My Profile',
        subtitle: 'View and edit your member profile',
        onTap: _openMemberProfile,
      ),
      _buildMemberActionTile(
        icon: Icons.pending_actions_rounded,
        color: const Color(0xFFDC2626),
        title: 'Pending Payments',
        subtitle: _memberPendingPaymentsCount > 0
            ? '$_memberPendingPaymentsCount ${_memberPendingPaymentsCount == 1 ? 'deal' : 'deals'} awaiting payment'
            : 'No payments awaiting',
        onTap: _openMemberPendingPayments,
      ),
      _buildMemberActionTile(
        icon: Icons.swap_horiz_rounded,
        color: const Color(0xFF6F7C8B),
        title: 'Back to Business Mode',
        subtitle: 'Return to your trusted partner dashboard',
        onTap: _toggleMemberView,
      ),
    ];
  }

  Widget _tpMemberQuickActionsHeader() {
    return Text(
      'Quick actions',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF102A43),
          ),
    );
  }

  // Promotions, today stats, and pending payments — surfaced between the
  // savings section and the quick actions in every layout.
  List<Widget> _tpMemberExtraSections() {
    final List<Widget> sections = [];

    if (_memberPromotions.isNotEmpty) {
      sections.add(const SizedBox(height: 16));
      for (final promo in _memberPromotions) {
        sections.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildTpMemberPromoBanner(promo),
          ),
        );
      }
    }

    sections.add(const SizedBox(height: 16));
    sections.add(_buildTpMemberTodayStats());

    if (_memberPendingPaymentsCount > 0) {
      sections.add(const SizedBox(height: 16));
      sections.add(_buildTpMemberPendingPaymentsCard());
    }

    return sections;
  }

  Widget _buildTpMemberTodayStats() {
    return Row(
      children: [
        Expanded(
          child: _buildTpMemberStatCard(
            value: _memberCountsLoading ? '—' : '$_memberTrustedPartnersCount',
            label: 'Partners nearby',
            barColor: const Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildTpMemberStatCard(
            value: _memberCountsLoading ? '—' : '$_memberAvailableDealsCount',
            label: 'Active deals',
            barColor: const Color(0xFFF59E0B),
          ),
        ),
      ],
    );
  }

  Widget _buildTpMemberStatCard({
    required String value,
    required String label,
    required Color barColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF102A43),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF627D98)),
          ),
          const SizedBox(height: 10),
          Container(
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                colors: [barColor, barColor.withValues(alpha: 0.5)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTpMemberPendingPaymentsCard() {
    return GestureDetector(
      onTap: _openMemberPendingPayments,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFDC2626)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFDC2626).withValues(alpha: 0.26),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.pending_actions,
                  size: 24, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pending Payments',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_memberPendingPaymentsCount ${_memberPendingPaymentsCount == 1 ? 'deal awaiting payment' : 'deals awaiting payment'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildTpMemberPromoBanner(Map<String, dynamic> promo) {
    final String? imageUrl = promo['image_url'] as String?;
    final freeMonths = promo['free_months'];
    final String durationText =
        freeMonths != null ? '$freeMonths month(s) free' : 'Lifetime access';

    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openMemberPromotion(promo),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 70,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF102A43), Color(0xFF2E7D32)],
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.campaign, size: 34, color: Colors.white),
                  ),
                ),
              )
            else
              Container(
                height: 70,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF102A43), Color(0xFF2E7D32)],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.campaign, size: 34, color: Colors.white),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          promo['name']?.toString() ?? 'Promotion',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF102A43),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.card_giftcard,
                                size: 14, color: Colors.green.shade700),
                            const SizedBox(width: 4),
                            Text(
                              durationText,
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF102A43),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'View',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Android portrait: single scrolling column ──
  // ignore: unused_element
  Widget _buildTpMemberPortraitLayout() {
    final List<Widget> tiles = _tpMemberActionTiles();
    return RefreshIndicator(
      onRefresh: _loadTpMemberDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTpMemberSavingsSection(),
            ..._tpMemberExtraSections(),
            const SizedBox(height: 18),
            _tpMemberQuickActionsHeader(),
            const SizedBox(height: 12),
            for (int i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i < tiles.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  // ── Android landscape: membership card beside savings + actions ──
  // ignore: unused_element
  Widget _buildTpMemberLandscapeLayout(BoxConstraints constraints) {
    final List<Widget> tiles = _tpMemberActionTiles();
    return RefreshIndicator(
      onRefresh: _loadTpMemberDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Savings section with embedded QR toggle (left)
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTpMemberSavingsSection(),
                  ..._tpMemberExtraSections(),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Actions column (right)
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _tpMemberQuickActionsHeader(),
                  const SizedBox(height: 10),
                  for (int i = 0; i < tiles.length; i++) ...[
                    tiles[i],
                    if (i < tiles.length - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Web / desktop: centered, two-column with action grid ──
  // ignore: unused_element
  Widget _buildTpMemberDesktopLayout(BoxConstraints constraints) {
    final List<Widget> tiles = _tpMemberActionTiles();
    final double contentWidth = math.min(1100, constraints.maxWidth - 48);

    return RefreshIndicator(
      onRefresh: _loadTpMemberDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: contentWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Savings section with embedded QR toggle (left)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTpMemberSavingsSection(),
                      ..._tpMemberExtraSections(),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Action grid (right)
                SizedBox(
                  width: 380,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _tpMemberQuickActionsHeader(),
                      const SizedBox(height: 14),
                      for (int i = 0; i < tiles.length; i++) ...[
                        tiles[i],
                        if (i < tiles.length - 1) const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Savings card with a small QR symbol in its top-right corner.
  // Tapping the symbol expands the full membership QR card directly above it.
  Widget _buildTpMemberSavingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTpMemberProfileHeader(),
        const SizedBox(height: 14),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _memberQrExpanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildTpMemberCardExpanded(),
                )
              : const SizedBox(width: double.infinity),
        ),
        Stack(
          children: [
            _buildTpMemberSavingsCard(),
            Positioned(
              top: 10,
              right: 10,
              child: _buildMemberQrToggleIcon(),
            ),
          ],
        ),
      ],
    );
  }

  // Editable member profile picture + name shown above the savings card.
  Widget _buildTpMemberProfileHeader() {
    final String displayName = _memberFullName?.trim().isNotEmpty == true
        ? _memberFullName!.trim()
        : (_businessName?.trim().isNotEmpty == true
            ? _businessName!.trim()
            : 'Member');

    return Row(
      children: [
        GestureDetector(
          onTap: _isUploadingMemberPhoto ? null : _pickAndSaveMemberPhoto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ProfilePhoto(
                imageUrl: _memberProfilePhotoUrl,
                displayName: displayName,
                size: 58,
                shape: ProfilePhotoShape.circle,
                borderColor: Colors.white,
                borderWidth: 2,
                backgroundColor: const Color(0xFFE7EEF6),
                foregroundColor: const Color(0xFF102A43),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: _isUploadingMemberPhoto
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(
                          Icons.edit_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF102A43),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Member account',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF627D98),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndSaveMemberPhoto() async {
    if (_isUploadingMemberPhoto) return;
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;

    try {
      final XFile? image = await _heroLogoPicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (image == null) return;

      if (mounted) setState(() => _isUploadingMemberPhoto = true);

      final rawBytes = await image.readAsBytes();
      const bucketId = 'member-profile-photos';
      final filePath = '${user.id}/profile_photo.jpg';

      await SupabaseService.instance.client.storage.from(bucketId).uploadBinary(
            filePath,
            rawBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      final publicUrlBase = SupabaseService.instance.client.storage
          .from(bucketId)
          .getPublicUrl(filePath);
      final publicUrl =
          '$publicUrlBase?v=${DateTime.now().millisecondsSinceEpoch}';

      await SupabaseService.instance.updateUserProfile(
        userId: user.id,
        profileData: {'profile_photo_url': publicUrl},
      );

      if (!mounted) return;
      setState(() {
        _memberProfilePhotoUrl = publicUrl;
        _isUploadingMemberPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _logger.e('Failed to update member profile photo: $e');
      if (!mounted) return;
      setState(() => _isUploadingMemberPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Small QR symbol button (top-right of savings card) that toggles the QR card.
  Widget _buildMemberQrToggleIcon() {
    final bool subActive =
        (_memberSubscriptionStatus?['subscription_status']?.toString() ??
                'none') ==
            'active';
    final Color statusColor =
        subActive ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Material(
      color: Colors.white.withValues(alpha: 0.22),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => setState(() => _memberQrExpanded = !_memberQrExpanded),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                _memberQrExpanded
                    ? Icons.expand_less_rounded
                    : Icons.qr_code_2_rounded,
                color: Colors.white,
                size: 22,
              ),
              if (!_memberQrExpanded)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Expanded: the full membership card with QR. Tap header to collapse.
  Widget _buildTpMemberCardExpanded() {
    final bool subActive =
        (_memberSubscriptionStatus?['subscription_status']?.toString() ??
                'none') ==
            'active';
    final String? qrString = _memberQrData?['qr_code'] as String?;
    final bool qrActive = _memberQrData?['is_active'] == true &&
        qrString != null &&
        qrString.trim().isNotEmpty;
    final String memberName =
        _businessName?.trim().isNotEmpty == true ? _businessName!.trim() : 'Member';

    return Container(
      key: const ValueKey('tp-member-qr-expanded'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF102A43), Color(0xFF1D3F66), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102A43).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'MEMBERSHIP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (subActive ? const Color(0xFF22C55E) : const Color(0xFFEF4444))
                      .withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  subActive ? 'ACTIVE' : 'INACTIVE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _memberQrExpanded = false),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: _memberDashboardLoading
                ? const SizedBox(
                    height: 180,
                    width: 180,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : qrActive
                    ? CustomQrCode(
                        data: qrString,
                        logoAssetPath: 'assets/heart_flag.png',
                        size: 180,
                      )
                    : SizedBox(
                        height: 180,
                        width: 180,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code_2_rounded,
                                size: 56, color: Color(0xFF9AA5B1)),
                            const SizedBox(height: 8),
                            Text(
                              subActive
                                  ? 'QR code unavailable'
                                  : 'Activate membership to get your QR',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF627D98),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
          const SizedBox(height: 14),
          Text(
            memberName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Show this QR at checkout to redeem member deals',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFD9E2EC),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF102A43),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF627D98),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 16, color: Color(0xFF9AA5B1)),
            ],
          ),
        ),
      ),
    );
  }

  void _openMemberFindDeals() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DealSelectionPage(cityFilter: _memberCity),
      ),
    );
  }

  void _openMemberBrowseDeals() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TrustedPartnersByCategoryPage(cityFilter: _memberCity),
      ),
    );
  }

  void _openMemberReceipts() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MemberReceiptsPage()),
    );
  }

  void _openMemberFreshLocal() async {
    await FreshLocalNotice.markSeen();
    if (!mounted) return;
    setState(() => _memberFreshLocalNewDeals = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FreshLocalPartnersPage(cityFilter: _memberCity),
      ),
    );
  }

  void _openMemberLocalSips() async {
    if (!await ensureMemberIsAgeVerified(context)) return;
    await LocalSipsNotice.markSeen();
    if (!mounted) return;
    setState(() => _memberLocalSipsNewDeals = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LocalSipsPartnersPage(),
      ),
    );
  }

  void _openMemberLocallyActive() async {
    await LocallyActiveNotice.markSeen();
    if (!mounted) return;
    setState(() => _memberLocallyActiveNewDeals = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            LocallyActivePartnersPage(cityFilter: _memberCity),
      ),
    );
  }

  void _openMemberLocalEats() async {
    await LocalEatsNotice.markSeen();
    if (!mounted) return;
    setState(() => _memberLocalEatsNewDeals = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocalEatsPartnersPage(cityFilter: _memberCity),
      ),
    );
  }

  Future<void> _openMemberProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MemberProfilePage()),
    );
    _loadTpMemberDashboardData();
  }

  void _openMemberPendingPayments() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PendingPaymentsPage()),
    ).then((_) => _loadMemberPendingPaymentsCount());
  }

  Future<void> _openMemberPromotion(Map<String, dynamic> promo) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PromotionDetailPage(promotion: promo),
      ),
    );
    _loadMemberPromotions();
  }

  Widget _buildHeaderActionGrid({required bool isMemberMode}) {
    final MediaQueryData media = MediaQuery.of(context);
    final bool isCompactPortrait =
        media.orientation == Orientation.portrait && media.size.width < 600;

    final double toggleSlotWidth = isCompactPortrait
        ? _headerCompactToggleSlotWidth
        : _headerToggleSlotWidth;
    final double actionSlotWidth = isCompactPortrait
        ? _headerCompactActionSlotWidth
        : _headerActionSlotWidth;
    final double actionSlotHeight = isCompactPortrait
        ? _headerCompactActionSlotHeight
        : _headerActionSlotHeight;
    final double buttonFaceSize = isCompactPortrait
        ? _headerCompactIconButtonFaceSize
        : _headerIconButtonFaceSize;
    final double iconSize = isCompactPortrait ? 17 : 21;
    final double gridGap = isCompactPortrait ? _headerCompactGap : _headerGridGap;

    Widget buildActionButton({
      Key? slotKey,
      required String tooltip,
      required VoidCallback onPressed,
      required Widget icon,
    }) {
      return _buildHeader3DIconButton(
        slotKey: slotKey,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
        slotWidth: actionSlotWidth,
        slotHeight: actionSlotHeight,
        buttonFaceSize: buttonFaceSize,
        iconSize: iconSize,
      );
    }

    final List<Widget> slotWidgets = isMemberMode
        ? <Widget>[
            _buildHeaderModeToggle(
              slotWidth: toggleSlotWidth,
              slotHeight: actionSlotHeight,
              isCompactPortrait: isCompactPortrait,
            ),
            buildActionButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MemberProfilePage(),
                  ),
                );
              },
              tooltip: 'My Profile',
            ),
            _buildHeaderMessagesButton(),
            buildActionButton(
              icon: const Icon(Icons.support_agent),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminChatPage(),
                  ),
                );
              },
              tooltip: 'Support',
            ),
            buildActionButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {}),
              tooltip: 'Refresh',
            ),
            buildActionButton(
              icon: const Icon(Icons.logout),
              onPressed: () => _signOut(context),
              tooltip: 'Logout',
            ),
          ]
        : <Widget>[
            _buildHeaderModeToggle(
              slotWidth: toggleSlotWidth,
              slotHeight: actionSlotHeight,
              isCompactPortrait: isCompactPortrait,
            ),
            _buildHeaderMessagesButton(),
            buildActionButton(
              tooltip: 'Manage Discounts',
              onPressed: _navigateToDiscountManagement,
              icon: const Icon(Icons.discount),
            ),
            buildActionButton(
              tooltip: 'Analytics Dashboard',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const TrustedPartnerAnalyticsDashboard(),
                  ),
                );
              },
              icon: const Icon(Icons.analytics),
            ),
            buildActionButton(
              slotKey: _settingsMenuButtonKey,
              tooltip: 'Settings',
              onPressed: _openHeaderSettingsMenu,
              icon: const Icon(Icons.settings),
            ),
            buildActionButton(
              tooltip: 'Sign Out',
              onPressed: () => _signOut(context),
              icon: const Icon(Icons.logout),
            ),
          ];

        final double totalWidth =
        toggleSlotWidth + (actionSlotWidth * 5) + (gridGap * 5);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: totalWidth,
        height: actionSlotHeight,
        child: Row(
          children: [
            for (int i = 0; i < slotWidgets.length; i++) ...[
              slotWidgets[i],
              if (i < slotWidgets.length - 1)
                SizedBox(width: gridGap),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderMessagesButton() {
    return _buildHeader3DIconButton(
      tooltip: 'Messages',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const TrustedPartnerInboxPage(),
          ),
        ).then((_) => _loadUnreadChatCount());
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.chat_bubble_outline),
          if (_unreadChatCount > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                child: Text(
                  _unreadChatCount > 9 ? '9+' : '$_unreadChatCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      slotWidth: _isCompactHeaderLayout ? _headerCompactActionSlotWidth : _headerActionSlotWidth,
      slotHeight:
          _isCompactHeaderLayout ? _headerCompactActionSlotHeight : _headerActionSlotHeight,
      buttonFaceSize: _isCompactHeaderLayout
          ? _headerCompactIconButtonFaceSize
          : _headerIconButtonFaceSize,
      iconSize: _isCompactHeaderLayout ? 17 : 21,
    );
  }

  bool get _isCompactHeaderLayout {
    final MediaQueryData media = MediaQuery.of(context);
    return media.orientation == Orientation.portrait && media.size.width < 600;
  }

  bool get _isShortLandscapeViewport {
    final MediaQueryData media = MediaQuery.of(context);
    return media.orientation == Orientation.landscape && media.size.height <= 640;
  }

  Future<void> _openHeaderSettingsMenu() async {
    final BuildContext? buttonContext = _settingsMenuButtonKey.currentContext;
    if (buttonContext == null) return;

    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final Offset topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final Offset bottomRight =
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay);

    final String? selectedValue = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        bottomRight.dy,
        overlay.size.width - bottomRight.dx,
        overlay.size.height - topLeft.dy,
      ),
      items: _buildHeaderSettingsMenuItems(),
    );

    if (selectedValue != null && mounted) {
      _handleMenuSelection(selectedValue);
    }
  }

  List<PopupMenuEntry<String>> _buildHeaderSettingsMenuItems() {
    return <PopupMenuEntry<String>>[
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
    ];
  }

  Widget _buildHeaderModeToggle({
    required double slotWidth,
    required double slotHeight,
    required bool isCompactPortrait,
  }) {
    final isMember = _isMemberView;
    final trackGradient = isMember
        ? const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)])
        : const LinearGradient(colors: [Color(0xFF6F7C8B), Color(0xFFB0BEC5)]);

    final double trackWidth = isCompactPortrait ? 50 : 64;
    final double trackHeight = isCompactPortrait ? 28 : 34;
    final double knobSize = isCompactPortrait ? 21 : 27;

    return SizedBox(
      width: slotWidth,
      height: slotHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!isCompactPortrait) ...[
            SizedBox(
              width: 56,
              child: Text(
                isMember ? 'Member' : 'Business',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isMember ? kBrandGreen : kBrandBlue,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: _toggleMemberView,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: trackWidth,
              height: trackHeight,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                gradient: trackGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 8,
                    offset: const Offset(2, 3),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.9),
                    blurRadius: 2,
                    offset: const Offset(-1, -1),
                  ),
                ],
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: isMember
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: knobSize,
                  height: knobSize,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, Color(0xFFE6EBF0)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(1, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader3DIconButton({
    Key? slotKey,
    required String tooltip,
    required VoidCallback onPressed,
    required Widget icon,
    required double slotWidth,
    required double slotHeight,
    required double buttonFaceSize,
    required double iconSize,
  }) {
    return SizedBox(
      key: slotKey,
      width: slotWidth,
      height: slotHeight,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          width: buttonFaceSize,
          height: buttonFaceSize,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFE8EFF6)],
            ),
            borderRadius: BorderRadius.circular(_headerIconButtonCornerRadius),
            border: Border.all(
              color: const Color(0xFFD2E0EE),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(2, 3),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.9),
                blurRadius: 2,
                offset: const Offset(-1, -1),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(_headerIconButtonCornerRadius),
            child: Tooltip(
              message: tooltip,
              child: InkWell(
                borderRadius:
                    BorderRadius.circular(_headerIconButtonCornerRadius),
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                onTap: onPressed,
                child: Center(
                  child: IconTheme(
                    data: IconThemeData(color: kBrandBlue, size: iconSize),
                    child: icon,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader3DIconButtonSurface({
    required Widget icon,
  }) {
    return SizedBox(
      width: _headerActionSlotWidth,
      height: _headerActionSlotHeight,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFE8EFF6)],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD2E0EE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(2, 3),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.9),
                blurRadius: 2,
                offset: const Offset(-1, -1),
              ),
            ],
          ),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: IconTheme(
                data: const IconThemeData(color: kBrandBlue, size: 21),
                child: icon,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader3DPlaceholderSlot() {
    return const SizedBox(
      width: _headerActionSlotWidth,
      height: _headerActionSlotHeight,
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

  void _navigateToBusinessProfile({bool openBankingDetailsOnLoad = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BusinessProfilePage(
          openBankingDetailsOnLoad: openBankingDetailsOnLoad,
        ),
      ),
    ).then((_) {
      // Refresh banking status when returning from business profile
      // This ensures the home screen reflects any banking updates
      if (mounted) {
        if (kDebugMode) {
          print('Returned from BusinessProfilePage, refreshing banking status');
        }
        _loadBusinessName();
        _loadBankingStatus();
      }
    });
  }

  void _openBankingDetails() {
    _navigateToBusinessProfile(openBankingDetailsOnLoad: true);
  }

  Future<void> _showBusinessLogoEditor() async {
    Uint8List? selectedLogoBytes;
    String? selectedLogoPath;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: _isUploadingHeroLogo == false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bool isSaving = _isUploadingHeroLogo == true;
            final MediaQueryData media = MediaQuery.of(dialogContext);
            final bool isCompactLandscape =
                media.orientation == Orientation.landscape && media.size.height <= 640;
            final double dialogHorizontalInset = isCompactLandscape ? 12 : 24;
            final double dialogVerticalInset = isCompactLandscape ? 10 : 32;
            final double dialogPadding = isCompactLandscape ? 12 : 20;
            final double headerIconPadding = isCompactLandscape ? 8 : 10;
            final double headerGap = isCompactLandscape ? 10 : 14;
            final double titleDescriptionGap = isCompactLandscape ? 2 : 4;
            final double sectionGap = isCompactLandscape ? 10 : 16;
            final double previewSize = isCompactLandscape ? 116 : 156;
            final double previewPadding = isCompactLandscape ? 6 : 8;
            final double actionButtonVerticalPadding = isCompactLandscape ? 9 : 12;
            final double actionButtonsGap = isCompactLandscape ? 8 : 12;
            final double buttonCornerRadius = isCompactLandscape ? 14 : 16;

            Future<void> pickLogo() async {
              try {
                final XFile? image = await _heroLogoPicker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 512,
                  maxHeight: 512,
                  imageQuality: 85,
                );

                if (image == null) {
                  return;
                }

                final bytes = await image.readAsBytes();
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  selectedLogoBytes = bytes;
                  selectedLogoPath = image.path;
                });
              } catch (e) {
                _logger.e('Failed to pick TP logo: $e');
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to pick logo: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            Future<void> saveLogo() async {
              if (selectedLogoBytes == null || isSaving) {
                return;
              }

              setState(() => _isUploadingHeroLogo = true);
              setDialogState(() {});

              final NavigatorState dialogNavigator = Navigator.of(dialogContext);

              final String? publicUrl = await _uploadBusinessLogoBytes(
                selectedLogoBytes!,
                selectedLogoPath,
              );

              if (!mounted) {
                return;
              }

              setState(() => _isUploadingHeroLogo = false);
              if (dialogNavigator.canPop()) {
                dialogNavigator.pop();
              }

              if (publicUrl != null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Business logo updated'),
                    backgroundColor: kBrandGreen,
                  ),
                );
              }
            }

            return Dialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: dialogHorizontalInset,
                vertical: dialogVerticalInset,
              ),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: media.size.height - (dialogVerticalInset * 2),
                ),
                child: Container(
                  padding: EdgeInsets.all(dialogPadding),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFFCF5), Color(0xFFF2F9FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kBrandBlue.withValues(alpha: 0.18),
                        blurRadius: 30,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(headerIconPadding),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB74D).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.add_photo_alternate_rounded,
                              color: Color(0xFFD97706),
                            ),
                          ),
                          SizedBox(width: headerGap),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Update Trusted Partner Logo',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF102A43),
                                    fontSize: isCompactLandscape ? 20 : null,
                                  ),
                                ),
                                SizedBox(height: titleDescriptionGap),
                                Text(
                                  'Upload a fresh logo and save it straight from your dashboard card.',
                                  style: TextStyle(
                                    color: const Color(0xFF486581),
                                    height: isCompactLandscape ? 1.2 : 1.4,
                                    fontSize: isCompactLandscape ? 14 : null,
                                  ),
                                  maxLines: isCompactLandscape ? 2 : null,
                                  overflow: isCompactLandscape ? TextOverflow.ellipsis : null,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: isSaving
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      SizedBox(height: sectionGap),
                      Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: previewSize,
                          height: previewSize,
                          padding: EdgeInsets.all(previewPadding),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFF0D6), Color(0xFFDFF5FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: const Color(0xFFFFB81C).withValues(alpha: 0.55),
                              width: 1.4,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              color: Colors.white,
                              child: selectedLogoBytes != null
                                  ? Image.memory(
                                      selectedLogoBytes!,
                                      fit: BoxFit.contain,
                                    )
                                  : (_businessLogoUrl != null &&
                                          _businessLogoUrl!.trim().isNotEmpty)
                                      ? Image.network(
                                          _businessLogoUrl!,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) {
                                            return _buildBusinessLogoFallback();
                                          },
                                        )
                                      : _buildBusinessLogoFallback(),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: isCompactLandscape ? 10 : 14),
                      Wrap(
                        spacing: actionButtonsGap,
                        runSpacing: actionButtonsGap,
                        children: [
                          ElevatedButton.icon(
                            onPressed: isSaving ? null : pickLogo,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Choose Logo'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompactLandscape ? 14 : 18,
                                vertical: actionButtonVerticalPadding,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(buttonCornerRadius),
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: isSaving || selectedLogoBytes == null
                                ? null
                                : () {
                                    setDialogState(() {
                                      selectedLogoBytes = null;
                                      selectedLogoPath = null;
                                    });
                                  },
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Reset'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kBrandBlue,
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompactLandscape ? 14 : 18,
                                vertical: actionButtonVerticalPadding,
                              ),
                              side: BorderSide(
                                color: kBrandBlue.withValues(alpha: 0.25),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(buttonCornerRadius),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: sectionGap),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          SizedBox(width: actionButtonsGap),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: selectedLogoBytes == null || isSaving
                                  ? null
                                  : saveLogo,
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_rounded),
                              label: Text(isSaving ? 'Saving...' : 'Save Logo'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  vertical: actionButtonVerticalPadding,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(buttonCornerRadius),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _uploadBusinessLogoBytes(
    Uint8List bytes,
    String? sourcePath,
  ) async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) {
        throw Exception('No authenticated user');
      }

      final String extension = _extractImageExtension(sourcePath);
      final String filePath =
          '${user.id}/tp-home-${DateTime.now().millisecondsSinceEpoch}.$extension';

      await SupabaseService.instance.client.storage
          .from('partner-logos')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentTypeForExtension(extension),
            ),
          );

      final String publicUrl = SupabaseService.instance.client.storage
          .from('partner-logos')
          .getPublicUrl(filePath);

      await SupabaseService.instance.client
          .from('businesses')
          .update({'logo_url': publicUrl})
          .eq('owner_member_id', user.id);

      if (mounted) {
        setState(() {
          _businessLogoUrl = publicUrl;
        });
      }
      await _loadBusinessName();
      return publicUrl;
    } catch (e) {
      _logger.e('Failed to upload TP logo from hero card: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save logo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  String _extractImageExtension(String? sourcePath) {
    final String normalized = sourcePath?.trim() ?? '';
    if (!normalized.contains('.')) {
      return 'jpg';
    }

    final String extension = normalized.split('.').last.toLowerCase();
    switch (extension) {
      case 'png':
      case 'webp':
      case 'gif':
      case 'jpg':
      case 'jpeg':
        return extension == 'jpeg' ? 'jpg' : extension;
      default:
        return 'jpg';
    }
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }

  void _showDesktopScannerDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('QR scanner lives on mobile'),
          content: const Text(
            'Member QR scanning is available in the mobile app where the camera can open instantly. Use this desktop dashboard for profile, banking, deals, and approvals.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBusinessLogoFallback({double iconSize = 48}) {
    return Container(
      color: const Color(0xFFF6F0E7),
      child: Center(
        child: Icon(
          Icons.storefront_rounded,
          size: iconSize,
          color: const Color(0xFFD97706),
        ),
      ),
    );
  }

  Widget _buildDesktopTrustedPartnerHeroCard() {
    final theme = Theme.of(context);
    final bool hasBusinessName = _businessName != null && _businessName!.trim().isNotEmpty;
    final String businessName = hasBusinessName ? _businessName!.trim() : 'Trusted Partner';
    final Color bankingColor = _hasActiveBanking
        ? const Color(0xFF15803D)
        : const Color(0xFFDC2626);
    final String bankingLabel = _hasActiveBanking
        ? (_bankName?.trim().isNotEmpty == true ? _bankName!.trim() : 'Active')
        : 'Setup Needed';
    final String pendingLabel = _pendingDealRequestsCount == 0
        ? 'All clear'
        : '$_pendingDealRequestsCount pending';
    final String scanHint = _isMobilePlatform
        ? 'Open scanner'
        : 'Mobile camera only';

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < 980;
        final double logoSize = isNarrow ? 86 : 102;

        final Widget identityPanel = Container(
          padding: EdgeInsets.all(isNarrow ? 16 : 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: _showBusinessLogoEditor,
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: logoSize,
                  height: logoSize,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFC857), Color(0xFFFF8A3D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      color: Colors.white,
                      child: _businessLogoUrl != null &&
                              _businessLogoUrl!.trim().isNotEmpty
                          ? Image.network(
                              _businessLogoUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildBusinessLogoFallback(iconSize: 34),
                            )
                          : _buildBusinessLogoFallback(iconSize: 34),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF102A43),
                        fontWeight: FontWeight.w900,
                        fontSize: isNarrow ? 24 : 28,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your TP command center for deals, payouts, analytics, and scanning.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF486581),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _navigateToBusinessProfile,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Edit Profile'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF102A43),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openBankingDetails,
                          icon: Icon(
                            _hasActiveBanking
                                ? Icons.verified_user_rounded
                                : Icons.account_balance_wallet_outlined,
                            color: bankingColor,
                          ),
                          label: Text(
                            _hasActiveBanking
                                ? 'Banking Active'
                                : 'Setup Banking',
                            style: TextStyle(color: bankingColor),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: bankingColor.withValues(alpha: 0.45)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        final Widget insightsStrip = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _desktopStatChip(
              icon: Icons.approval_rounded,
              label: 'Deal Queue',
              value: pendingLabel,
              color: _pendingDealRequestsCount > 0
                  ? const Color(0xFFB91C1C)
                  : const Color(0xFF15803D),
            ),
            _desktopStatChip(
              icon: Icons.account_balance_rounded,
              label: 'Payout Channel',
              value: bankingLabel,
              color: bankingColor,
            ),
            _desktopStatChip(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Unread Messages',
              value: _unreadChatCount == 0 ? 'None' : '$_unreadChatCount',
              color: const Color(0xFF0E7490),
            ),
          ],
        );

        final double scannerStageHeight = isNarrow ? 104 : 126;
        final double scannerStagePadding = isNarrow ? 10 : 12;
        final double scannerTopGap = isNarrow ? 8 : 10;
        final double scannerIconBox = isNarrow ? 34 : 38;
        final double scannerIconSize = isNarrow ? 20 : 22;
        final bool ultraCompactScanner = scannerStageHeight <= 130;

        final Widget scannerStage = Container(
          constraints: BoxConstraints(
            minHeight: scannerStageHeight,
            maxHeight: scannerStageHeight,
          ),
          padding: EdgeInsets.all(scannerStagePadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF073B4C), Color(0xFF0A6E89), Color(0xFF06D6A0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF06D6A0).withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: InkWell(
            onTap: _isMobilePlatform
                ? () async {
                    if (_isScannerOpen) return;
                    await _openScanner();
                  }
                : _showDesktopScannerDialog,
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  if (ultraCompactScanner)
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: scannerIconBox,
                            height: scannerIconBox,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.qr_code_scanner_rounded,
                              color: Colors.white,
                              size: scannerIconSize,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'QR scanner',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC857),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              scanHint,
                              style: const TextStyle(
                                color: Color(0xFF102A43),
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'SCAN ZONE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    SizedBox(height: scannerTopGap),
                    Container(
                      width: scannerIconBox,
                      height: scannerIconBox,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Colors.white,
                        size: scannerIconSize,
                      ),
                    ),
                    SizedBox(height: isNarrow ? 10 : 14),
                    Text(
                      'Member QR Scanner',
                      style: (isNarrow
                              ? theme.textTheme.titleMedium
                              : theme.textTheme.titleLarge)
                          ?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: isNarrow ? 6 : 8),
                    Text(
                      _isMobilePlatform
                          ? 'Tap to open scanner instantly and process member codes.'
                          : 'Camera scanning runs in mobile app. Tap for desktop guidance.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.35,
                        fontSize: isNarrow ? 12 : null,
                      ),
                      maxLines: isNarrow ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC857),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            scanHint,
                            style: const TextStyle(
                              color: Color(0xFF102A43),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                      ],
                    ),
                  ],
              ],
            ),
          ),
        );

        final Widget actionWall = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _desktopActionButton(
              icon: Icons.approval_rounded,
              label: 'Deal Authorizations',
              description: 'Approve or reject incoming member requests.',
              onTap: _navigateToDealRequests,
              highlight: _pendingDealRequestsCount > 0,
              badgeCount: _pendingDealRequestsCount,
            ),
            _desktopActionButton(
              icon: Icons.discount_rounded,
              label: 'Manage Discounts',
              description: 'Create and maintain active deal inventory.',
              onTap: _navigateToDiscountManagement,
            ),
            _desktopActionButton(
              icon: Icons.analytics_rounded,
              label: 'Analytics Dashboard',
              description: 'Track redemptions, trends, and performance.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TrustedPartnerAnalyticsDashboard(),
                  ),
                );
              },
            ),
            _desktopActionButton(
              icon: Icons.account_balance_wallet_rounded,
              label: 'Banking Details',
              description: 'Review payout account and settlement state.',
              onTap: _openBankingDetails,
              highlight: !_hasActiveBanking,
            ),
          ],
        );

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFCF7), Color(0xFFF7FBFF), Color(0xFFFDFBF8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: const Color(0xFFE7D9C7).withValues(alpha: 0.85),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF102A43).withValues(alpha: 0.08),
                blurRadius: 20,
                spreadRadius: 1,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Stack(
              children: [
                Positioned(
                  top: -60,
                  right: -40,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF06D6A0).withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -80,
                  left: -50,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF118AB2).withValues(alpha: 0.08),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: EdgeInsets.all(isNarrow ? 14 : 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      identityPanel,
                      const SizedBox(height: 12),
                      insightsStrip,
                      const SizedBox(height: 14),
                      if (isNarrow) ...[
                        scannerStage,
                        const SizedBox(height: 12),
                        actionWall,
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: actionWall),
                            const SizedBox(width: 14),
                            SizedBox(width: 300, child: scannerStage),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

  Future<void> _navigateToDiscountManagement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DiscountManagementPage()),
    );
    // Reload discounts when returning from discount management
    _loadDiscounts();
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
            .select('name, logo_url')
            .eq('owner_member_id', user.id)
            .maybeSingle();
        if (business != null) {
          setState(() {
            _businessName = business['name'];
            _businessLogoUrl = business['logo_url'];
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load business name: $e');
      }
    }
  }

  Future<void> _loadBankingStatus() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      // Check for banking details in trusted_partner_bank_accounts table
      // Query by user_id (not member_id) and check is_active flag
      final bankingData = await SupabaseService.instance.client
          .from('trusted_partner_bank_accounts')
          .select('subaccount_code, subaccount_active, bank_name, is_active')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (bankingData != null && bankingData['is_active'] == true) {
            // Banking is active if:
            // 1. is_active flag is true
            // 2. AND (subaccount_active is true OR subaccount_code exists)
            final hasSubaccount = (bankingData['subaccount_code'] ?? '')
                .toString()
                .isNotEmpty;
            _hasActiveBanking =
                (bankingData['is_active'] == true) &&
                ((bankingData['subaccount_active'] == true) || hasSubaccount);
            _bankName = bankingData['bank_name'] as String?;
          } else {
            _hasActiveBanking = false;
            _bankName = null;
          }
          _bankingStatusLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading banking status: $e');
      }
      if (mounted) {
        setState(() {
          _bankingStatusLoading = false;
        });
      }
    }
  }

  Future<void> _loadPendingDealRequestsCount() async {
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
    }
  }

  Future<void> _loadPendingBillApprovalsCount() async {
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
          // Note: Not displaying bill approvals count in current UI
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load processed bill approvals count: $e');
      }
      if (kDebugMode) {
        print('Error details: ${e.toString()}');
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Discount ${discount.isActive ? 'deactivated' : 'activated'}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update discount status'),
            duration: Duration(seconds: 2),
          ),
        );
      }
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
            ..._discounts.map(
              (discount) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    // Deal Image (if available)
                    if (discount.imageUrl != null &&
                        discount.imageUrl!.isNotEmpty)
                      Container(
                        width: 50,
                        height: 50,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            discount.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey.shade200,
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                  size: 24,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    // Deal details
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              discount.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                discount.discountDisplay,
                                style: TextStyle(
                                  color: discount.isActive
                                      ? kBrandGreen
                                      : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Switch(
                                value: discount.isActive,
                                onChanged: (value) =>
                                    _toggleDiscountActive(discount),
                                activeThumbColor: kBrandGreen,
                                activeTrackColor: kBrandGreen.withValues(alpha: 0.4),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Add bottom padding so content doesn't overlap with version ribbon
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildBankingStatusCard() {
    if (_bankingStatusLoading) {
      return const SizedBox.shrink();
    }

    final statusColor = _hasActiveBanking ? kBrandGreen : Colors.red;
    final statusIcon = _hasActiveBanking ? Icons.check_circle : Icons.warning;
    final statusText = _hasActiveBanking
        ? 'Banking Active'
        : 'Banking Setup Required';
    final bankText = _hasActiveBanking && _bankName != null
        ? _bankName!
        : 'Tap to configure banking details';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 4,
        child: InkWell(
          onTap: _navigateToBusinessProfile,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [statusColor.withValues(alpha: 0.05), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        bankText,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: statusColor, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileScannerBody() {
    // Member-styled TP business dashboard: blue gradient hero (logo + name +
    // QR scanner strip + 4 stat tiles), quick-action tiles, analytics + banking
    // cards. The live camera opens as a full-screen overlay while scanning.
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: const Color(0xFFEFF3F8),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTpBusinessHero(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTpSectionHeader('Quick actions'),
                        const SizedBox(height: 8),
                        _buildTpQuickActions(),
                        const SizedBox(height: 20),
                        _buildTpSectionHeader('Analytics'),
                        const SizedBox(height: 8),
                        _buildTpAnalyticsCard(),
                        const SizedBox(height: 20),
                        _buildTpSectionHeader('Banking'),
                        const SizedBox(height: 8),
                        _buildTpBankingCard(),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isScannerOpen)
          Positioned.fill(child: _buildMobileScannerOverlay()),
      ],
    );
  }

  Widget _buildTpSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.6,
        color: Color(0xFF64748B),
      ),
    );
  }

  Widget _buildTpBusinessHero() {
    final String displayName =
        (_businessName != null && _businessName!.trim().isNotEmpty)
            ? _businessName!.trim()
            : 'Trusted Partner';
    final int activeDeals = _discounts.where((d) => d.isActive).length;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E5BA0), Color(0xFF0A4A8A), Color(0xFF083D73)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: (_businessLogoUrl != null &&
                              _businessLogoUrl!.isNotEmpty)
                          ? Image.network(
                              _businessLogoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.storefront_rounded,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.storefront_rounded,
                              color: Colors.white,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trusted Partner',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.03,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildTpScannerStrip(),
                const SizedBox(height: 12),
                _buildTpStatsRow(activeDeals),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTpScannerStrip() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _isMobilePlatform
          ? () {
              if (!_isScannerOpen) _openScanner();
            }
          : _showDesktopScannerDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A6E89), Color(0xFF0A4A8A), Color(0xFF06D6A0)],
            stops: [0.0, 0.6, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF06D6A0).withValues(alpha: 0.24),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'QR Scanner',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isMobilePlatform
                        ? 'Tap to scan a member QR code'
                        : 'Camera scanning runs in the mobile app',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTpStatsRow(int activeDeals) {
    return Row(
      children: [
        Expanded(
          child: _buildTpStatTile(
            label: 'Pending',
            value: '$_pendingDealRequestsCount',
            icon: Icons.approval_rounded,
            accentColor: const Color(0xFFFFD56A),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildTpStatTile(
            label: 'Deals',
            value: '$activeDeals',
            icon: Icons.discount_rounded,
            accentColor: const Color(0xFF7CE39A),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildTpStatTile(
            label: 'Messages',
            value: '$_unreadChatCount',
            icon: Icons.forum_rounded,
            accentColor: const Color(0xFF8CC6FF),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildTpStatTile(
            label: 'Banking',
            value: _hasActiveBanking ? 'On' : 'Off',
            icon: Icons.account_balance_rounded,
            accentColor: _hasActiveBanking
                ? const Color(0xFF7CE39A)
                : const Color(0xFFFF7B7B),
          ),
        ),
      ],
    );
  }

  Widget _buildTpStatTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: accentColor),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.03,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTpQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _buildTpActionTile(
            icon: Icons.add_circle_outline,
            label: 'Add Deal',
            color: const Color(0xFFEA8C00),
            bgColor: const Color(0xFFEA8C00).withValues(alpha: 0.12),
            onTap: _navigateToDiscountManagement,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildTpActionTile(
            icon: Icons.approval_outlined,
            label: 'Authorizations',
            color: const Color(0xFF2E7D32),
            bgColor: const Color(0xFF2E7D32).withValues(alpha: 0.10),
            onTap: _navigateToDealRequests,
            badgeCount: _pendingDealRequestsCount,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildTpActionTile(
            icon: Icons.discount_outlined,
            label: 'Discounts',
            color: const Color(0xFF0E5BA0),
            bgColor: const Color(0xFF0E5BA0).withValues(alpha: 0.08),
            onTap: _navigateToDiscountManagement,
          ),
        ),
      ],
    );
  }

  Widget _buildTpActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE6EAF0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0E5BA0).withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Center(
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0B2540),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTpAnalyticsCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const TrustedPartnerAnalyticsDashboard(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF118AB2), Color(0xFF06D6A0)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF06D6A0).withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.analytics_rounded,
                  size: 28, color: Colors.white),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analytics Dashboard',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Track redemptions, trends & performance',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildTpBankingCard() {
    final bool active = _hasActiveBanking;
    final Color accent =
        active ? const Color(0xFF15803D) : const Color(0xFFDC2626);
    final String title = active ? 'Banking Active' : 'Banking Setup Required';
    final String sub = active
        ? (_bankName != null && _bankName!.trim().isNotEmpty
            ? _bankName!.trim()
            : 'Payout account ready')
        : 'Tap to configure payout details';
    return GestureDetector(
      onTap: _openBankingDetails,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                active
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color: accent,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF334155)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: accent, size: 26),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileScannerOverlay() {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Scan member QR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _closeScanner,
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Close scanner',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _buildActiveScannerView(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildLegacyMobileScannerBody() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Business Name with Logo
          if (_businessName != null && _businessName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Business Logo
                  if (_businessLogoUrl != null && _businessLogoUrl!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundImage: NetworkImage(_businessLogoUrl!),
                        onBackgroundImageError: (exception, stackTrace) {
                          if (kDebugMode) {
                            print('Failed to load business logo: $exception');
                          }
                        },
                        child: _businessLogoUrl == null
                            ? const Icon(Icons.business, size: 30)
                            : null,
                      ),
                    ),
                  // Business Name
                  Flexible(
                    child: Text(
                      _businessName!,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

          // Banking Status Card
          _buildBankingStatusCard(),

          // Quick action: Add Deal (mirrors Android CTA)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _navigateToDiscountManagement,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Deal'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Deal Authorizations Card - Always show
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              color: _pendingDealRequestsCount > 0
                  ? kBrandYellow.withValues(alpha: 0.15)
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
                                    color: kBrandYellow,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: _pendingDealRequestsCount > 0
                                        ? [
                                            BoxShadow(
                                              color: kBrandYellow.withValues(
                                                alpha: 0.45,
                                              ),
                                              blurRadius: 14,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: const Icon(
                                    Icons.mail_outline,
                                    color: kBrandBlue,
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
                        icon: const Icon(Icons.refresh, color: kBrandBlue),
                        tooltip: 'Refresh Count',
                      ),
                      const Icon(Icons.arrow_forward_ios, color: kBrandBlue),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Approval History card removed
          const SizedBox.shrink(),

          // Analytics Widget - Shows key business metrics
          const TrustedPartnerAnalyticsWidget(),

          // QR Scanner Section - Shutter Style
          _buildScannerShutter(),

          // Discount Summary Section
          Container(
            margin: const EdgeInsets.all(16),
            child: _buildDiscountSummary(),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerShutter() {
    return AnimatedBuilder(
      animation: _shutterAnimation,
      builder: (context, child) {
        final double scannerCardWidth = math.max(
          220,
          MediaQuery.of(context).size.width - 48,
        );
        final double scannerCardCollapsedHeight = scannerCardWidth * 0.4;
        final double scannerCardExpandedHeight = scannerCardWidth;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFF073B4C), Color(0xFF118AB2), Color(0xFF06D6A0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF118AB2).withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: InkWell(
            onTap: () async {
              if (_isScannerOpen) return;
              await _openScanner();
            },
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: scannerCardWidth,
              height: _isScannerOpen
                  ? scannerCardExpandedHeight
                  : scannerCardCollapsedHeight,
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _isScannerOpen
                    ? _buildActiveScannerView()
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.qr_code_scanner_rounded,
                            color: Colors.white,
                            size: 46,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'QR Scanner',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap to expand and scan',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildClosedShutterView() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey.shade700,
            Colors.grey.shade800,
          ],
        ),
      ),
      child: Stack(
        children: [
          // Shutter blade lines
          ...List.generate(5, (i) {
            final top = (i * 20.0) + 2;
            return Positioned(
              left: 0,
              right: 0,
              top: top,
              child: Container(
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade600.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
          // Center icon overlay
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveScannerView() {
    if (_cameraError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 36),
            const SizedBox(height: 8),
            const Text(
              'Camera Error',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _cameraError!,
                style: const TextStyle(color: Colors.grey, fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _restartCamera,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: kBrandBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!_cameraReady || _scannerController == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: kBrandBlue,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Starting camera...',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController!,
          onDetect: _onQrCodeDetected,
          errorBuilder: (context, error) {
            final msg = error.errorDetails?.message ?? 'Camera error';
            _logger.e('MobileScanner error: $msg');
            // Propagate error to state so the error card is shown consistently
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _cameraError == null) {
                setState(() => _cameraError = msg);
              }
            });
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    msg,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _restartCamera,
                    child: const Text(
                      'Tap to retry',
                      style: TextStyle(color: kBrandBlue, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // Corner brackets overlay
        Positioned(
          top: 16, left: 16,
          child: _buildCornerBracket(topLeft: true),
        ),
        Positioned(
          top: 16, right: 16,
          child: _buildCornerBracket(topRight: true),
        ),
        Positioned(
          bottom: 16, left: 16,
          child: _buildCornerBracket(bottomLeft: true),
        ),
        Positioned(
          bottom: 16, right: 16,
          child: _buildCornerBracket(bottomRight: true),
        ),
        // Close button — lets the TP exit the scanner without a successful scan.
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _closeScanner,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCornerBracket({
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(
        painter: _CornerBracketPainter(
          topLeft: topLeft,
          topRight: topRight,
          bottomLeft: bottomLeft,
          bottomRight: bottomRight,
        ),
      ),
    );
  }

  Widget _buildDesktopScannerBody() {
    final bool isCompactHeight = _isShortLandscapeViewport;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrowViewport = constraints.maxWidth < 600;
        final double horizontalPadding = isNarrowViewport ? 8 : (isCompactHeight ? 12 : 28);
        final double verticalPadding = isCompactHeight ? 4 : 20;
        final double availableHeight = math.max(
          240,
          constraints.maxHeight - (verticalPadding * 2),
        );
        final double heroWidth = isNarrowViewport
            ? constraints.maxWidth - (horizontalPadding * 2)
            : math.max(
                isCompactHeight ? 680 : 720,
                math.min(
                  isCompactHeight ? 1020 : 1100,
                  constraints.maxWidth - (horizontalPadding * 2),
                ),
              );

        return Container(
          width: double.infinity,
          color: Colors.white,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: SizedBox(
                width: double.infinity,
                height: availableHeight,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: heroWidth,
                    child: _buildDesktopTrustedPartnerHeroCard(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _desktopStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _desktopActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? description,
    bool highlight = false,
    int badgeCount = 0,
  }) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return SizedBox(
      width: 250,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: highlight ? 8 : 3,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: highlight
                        ? primary.withValues(alpha: 0.14)
                        : Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: highlight ? primary : Colors.grey.shade800,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade900,
                              ),
                            ),
                          ),
                          if (badgeCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badgeCount > 99 ? '99+' : '$badgeCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Open',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.arrow_forward, size: 16, color: primary),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
      if (barcode.rawValue == null) continue;
      String qrData = barcode.rawValue!.trim();

      Map<String, dynamic>? data;
      // Try direct JSON
      try {
        final dynamic decoded = jsonDecode(qrData);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}

      // Try if the QR is a URL containing a data/query param
      if (data == null) {
        try {
          final uri = Uri.tryParse(qrData);
          if (uri != null && uri.queryParameters.isNotEmpty) {
            final possible = uri.queryParameters['qr'] ?? uri.queryParameters['data'] ?? uri.queryParameters['payload'];
            if (possible != null) {
              try {
                final dynamic decoded = jsonDecode(possible);
                if (decoded is Map<String, dynamic>) data = decoded;
              } catch (_) {
                // try base64
                try {
                  final decodedBytes = base64Decode(possible);
                  final decodedString = utf8.decode(decodedBytes);
                  final dynamic decoded = jsonDecode(decodedString);
                  if (decoded is Map<String, dynamic>) data = decoded;
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }

      // Try base64-encoded JSON as a last resort
      if (data == null) {
        try {
          final decodedBytes = base64Decode(qrData);
          final decodedString = utf8.decode(decodedBytes);
          final dynamic decoded = jsonDecode(decodedString);
          if (decoded is Map<String, dynamic>) data = decoded;
        } catch (_) {}
      }

      if (data == null) {
        _showErrorDialog('Invalid QR code format.');
        break;
      }

      final type = data['type']?.toString();
      // Accept both legacy and ephemeral member QR types
      final allowed = {'user_qr', 'user_qr_v2'};
      if (!allowed.contains(type)) {
        _showErrorDialog('Invalid QR code: This is not a member QR code.');
        break;
      }

      final userId = data['user_id']?.toString();
      final qrName = data['name']?.toString() ?? 'Unknown';
      final qrSurname = data['surname']?.toString() ?? 'Unknown';

      if (userId == null || userId.isEmpty) {
        _showErrorDialog('Invalid QR code: No member ID found.');
        break;
      }

      // Valid member QR - proceed
      _closeScanner();
      _showMemberDetailsPopup(
        userId: userId,
        qrName: qrName,
        qrSurname: qrSurname,
      );
      break; // Process only the first barcode
    }
  }

  /// Fetches member details from Supabase and shows a rich popup
  void _showMemberDetailsPopup({
    required String userId,
    required String qrName,
    required String qrSurname,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _MemberDetailsSheet(
          userId: userId,
          qrName: qrName,
          qrSurname: qrSurname,
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

/// Bottom-sheet style widget that loads and displays member details from Supabase
class _MemberDetailsSheet extends StatefulWidget {
  final String userId;
  final String qrName;
  final String qrSurname;

  const _MemberDetailsSheet({
    required this.userId,
    required this.qrName,
    required this.qrSurname,
  });

  @override
  State<_MemberDetailsSheet> createState() => _MemberDetailsSheetState();
}

class _MemberDetailsSheetState extends State<_MemberDetailsSheet> {
  final Logger _logger = Logger();
  bool _isLoading = true;
  String? _error;

  // Profile data
  String _name = '';
  String _surname = '';
  String _email = '';
  String _subscriptionStatus = 'unknown';
  String? _memberSince;

  // QR validity
  bool _qrIsActive = false;
  String? _qrExpiresAt;
  bool _qrIsExpired = false;

  @override
  void initState() {
    super.initState();
    _fetchMemberDetails();
  }

  Future<void> _fetchMemberDetails() async {
    try {
      final client = SupabaseService.instance.client;

      // Fetch profile and QR code data in parallel
      final results = await Future.wait<dynamic>([
        client
            .from('profiles')
            .select('name, surname, email, subscription, role, created_at')
            .eq('id', widget.userId)
            .maybeSingle(),
        client
            .from('user_qr_codes')
            .select('is_active, expires_at, created_at')
            .eq('user_id', widget.userId)
            .eq('is_active', true)
            .order('created_at', ascending: false)
            .limit(1),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final qrCodes = results[1] as List<dynamic>;

      if (!mounted) return;

      if (profile == null) {
        setState(() {
          _error = 'Member not found in database';
          _isLoading = false;
          // Fall back to QR data
          _name = widget.qrName;
          _surname = widget.qrSurname;
        });
        return;
      }

      // Parse profile
      _name = profile['name'] as String? ?? widget.qrName;
      _surname = profile['surname'] as String? ?? widget.qrSurname;
      _email = profile['email'] as String? ?? '';
      _subscriptionStatus = (profile['subscription'] as String? ?? 'unknown').toLowerCase();
      final createdAt = profile['created_at'] as String?;
      if (createdAt != null) {
        try {
          final dt = DateTime.parse(createdAt);
          _memberSince = '${dt.day}/${dt.month}/${dt.year}';
        } catch (_) {}
      }

      // Parse QR code validity
      if (qrCodes.isNotEmpty) {
        final qr = qrCodes[0] as Map<String, dynamic>;
        _qrIsActive = qr['is_active'] == true;
        _qrExpiresAt = qr['expires_at'] as String?;
        if (_qrExpiresAt != null) {
          try {
            final expiryDate = DateTime.parse(_qrExpiresAt!);
            _qrIsExpired = expiryDate.isBefore(DateTime.now());
            final daysLeft = expiryDate.difference(DateTime.now()).inDays;
            _qrExpiresAt = daysLeft > 0 ? '$daysLeft days' : 'Expired';
          } catch (_) {}
        }
      } else {
        _qrIsActive = false;
        _qrExpiresAt = null;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      _logger.e('Error fetching member details: $e');
      if (!mounted) return;
      setState(() {
        // Fall back to QR data on error
        _name = widget.qrName;
        _surname = widget.qrSurname;
        _isLoading = false;
        // Don't set _error - still show what we have from QR
      });
    }
  }

  bool get _isMemberActive =>
      _subscriptionStatus == 'active' && _qrIsActive && !_qrIsExpired;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: _isLoading ? _buildLoading() : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(height: 20),
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Verifying member...', style: TextStyle(fontSize: 16, color: Colors.grey)),
        SizedBox(height: 20),
      ],
    );
  }

  Widget _buildContent() {
    final statusColor = _isMemberActive ? kBrandGreen : Colors.red;
    final statusIcon = _isMemberActive ? Icons.verified : Icons.cancel;
    final statusText = _isMemberActive ? 'Active Member' : 'Inactive / Expired';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, color: statusColor, size: 24),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Member avatar and name
        CircleAvatar(
          radius: 36,
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Text(
            '${_name.isNotEmpty ? _name[0].toUpperCase() : '?'}${_surname.isNotEmpty ? _surname[0].toUpperCase() : '?'}',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '$_name $_surname',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),

        if (_email.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            _email,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],

        const SizedBox(height: 20),

        // Details grid
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _detailRow(
                Icons.credit_card,
                'Subscription',
                _subscriptionStatus == 'unknown' ? 'Not verified' : _subscriptionStatus.capitalize(),
                _subscriptionStatus == 'active' ? kBrandGreen : kBrandYellow,
              ),
              const Divider(height: 20),
              _detailRow(
                Icons.qr_code,
                'QR Code',
                _qrIsActive && !_qrIsExpired ? 'Valid' : 'Invalid / Expired',
                _qrIsActive && !_qrIsExpired ? kBrandGreen : Colors.red,
              ),
              if (_qrExpiresAt != null && _qrIsActive && !_qrIsExpired) ...[
                const Divider(height: 20),
                _detailRow(
                  Icons.timer_outlined,
                  'Expires in',
                  _qrExpiresAt!,
                  kBrandBlue,
                ),
              ],
              if (_memberSince != null) ...[
                const Divider(height: 20),
                _detailRow(
                  Icons.calendar_today,
                  'Member since',
                  _memberSince!,
                  Colors.grey.shade700,
                ),
              ],
            ],
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kBrandYellow.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBrandYellow.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: kBrandBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 13, color: kBrandBlue),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Close button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: statusColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color valueColor) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade500),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: valueColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for scanner corner brackets
class _CornerBracketPainter extends CustomPainter {
  final bool topLeft;
  final bool topRight;
  final bool bottomLeft;
  final bool bottomRight;

  _CornerBracketPainter({
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kBrandYellow
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final len = size.width * 0.8;

    if (topLeft) {
      canvas.drawLine(Offset.zero, Offset(len, 0), paint);
      canvas.drawLine(Offset.zero, Offset(0, len), paint);
    }
    if (topRight) {
      canvas.drawLine(Offset(size.width, 0), Offset(size.width - len, 0), paint);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), paint);
    }
    if (bottomLeft) {
      canvas.drawLine(Offset(0, size.height), Offset(len, size.height), paint);
      canvas.drawLine(Offset(0, size.height), Offset(0, size.height - len), paint);
    }
    if (bottomRight) {
      canvas.drawLine(Offset(size.width, size.height), Offset(size.width - len, size.height), paint);
      canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - len), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// Extension to capitalize first letter
extension _StringCapitalize on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
