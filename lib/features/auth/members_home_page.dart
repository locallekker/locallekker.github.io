import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:image_picker/image_picker.dart';
import '../../services/supabase_service.dart';
import '../../services/subscription_service.dart';
import '../../services/deal_approval_popup_service.dart';
import '../../services/savings_service.dart';
import '../../services/cache_service.dart';
import '../../services/qr_code_service.dart';
import '../../services/discount_service.dart';
import '../../services/fresh_local_notice.dart';
import '../../models/notification.dart';
import '../../widgets/custom_qr_code.dart';
import '../../widgets/savings_summary_card.dart';
import '../payments/payments_feature.dart';
import 'member_profile_page.dart';
import '../chat/chat_list_page.dart';
import '../../services/chat_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'deal_selection_page.dart';
import '../members/member_receipts_page.dart';
import '../members/fresh_local_partners_page.dart';
import '../members/local_sips_partners_page.dart';
import '../members/local_eats_partners_page.dart';
import '../members/locally_active_partners_page.dart';
import 'trusted_partners_by_category_page.dart';
import '../payments/pending_payments_page.dart';
import 'widgets/trusted_partner_key_dialog.dart';
import 'promotion_detail_page.dart';
import '../../services/promotion_campaign_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_lekker/core/theme/app_colors.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, RealtimeChannel;
import '../../widgets/profile_photo.dart';
import '../../widgets/age_verification_dialog.dart';
import '../../widgets/member_category_banner_row.dart';
import 'welcome_page.dart';

class MembersHomePage extends StatefulWidget {
  final bool hideAppBar;
  final bool isTrustedPartner;
  final double embeddedTopPadding;
  final bool hideEmbeddedHero;
  final VoidCallback? onBackToBusiness;

  const MembersHomePage({
    super.key,
    this.hideAppBar = false,
    this.isTrustedPartner = false,
    this.embeddedTopPadding = 0,
    this.hideEmbeddedHero = false,
    this.onBackToBusiness,
  });

  @override
  State<MembersHomePage> createState() => _MembersHomePageState();
}

class _MemberHomeSnapshot {
  final DateTime capturedAt;
  final Map<String, dynamic>? userProfile;
  final Map<String, dynamic>? subscriptionStatus;
  final Map<String, dynamic>? userQrData;
  final Map<String, dynamic>? savingsStats;
  final bool isSubscriptionExpired;
  final bool isTrustedPartner;

  const _MemberHomeSnapshot({
    required this.capturedAt,
    required this.userProfile,
    required this.subscriptionStatus,
    required this.userQrData,
    required this.savingsStats,
    required this.isSubscriptionExpired,
    required this.isTrustedPartner,
  });
}

class _MembersHomePageState extends State<MembersHomePage>
  with WidgetsBindingObserver {
  static final Map<String, _MemberHomeSnapshot> _sessionSnapshots = {};
  static const Duration _snapshotTtl = Duration(minutes: 5);

  final SubscriptionService _subscriptionService = SubscriptionService();
  final DealApprovalPopupService _dealApprovalService =
      DealApprovalPopupService();
  final SavingsService _savingsService = SavingsService();
  final CacheService _cacheService = CacheService.instance;
  final ImagePicker _profilePhotoPicker = ImagePicker();
  StreamSubscription<List<NotificationModel>>? _notificationSubscription;
  Map<String, dynamic>? _userQrData;
  Duration _timeUntilPayment = Duration.zero;

  Map<String, dynamic>? _subscriptionStatus;
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _savingsStats;
  bool _isSubscriptionExpired = false;

  bool _isSavingsLoading = true;
  int _trustedPartnersCount = 0;
  int _availableDealsCount = 0;
  bool _isLoadingPartnersCount = true;
  int _pendingPaymentsCount = 0;
  bool _isLoadingPendingPayments = true;
  bool _isTrustedPartner = false;
  bool _isUploadingProfilePhoto = false;
  bool _obscureSensitiveContent = false;
  bool _isRotatingQr = false;
  DateTime? _lastApprovalSyncAt;
  bool _isResubscribingApprovals = false;
  final ScrollController _homeScrollController = ScrollController();

  // Promotions
  List<Map<String, dynamic>> _activePromotions = [];

  // Unread chat count for AppBar badge
  int _unreadChatCount = 0;
  Timer? _unreadChatTimer;

  // Bottom nav
  int _selectedNavIndex = 0;
  Timer? _qrRotationTimer;
  Timer? _countdownTimer;
  RealtimeChannel? _chatMessagesChannel;

  // City/Area filter
  String? _selectedProvince;
  String? _selectedCity;
  bool _isLoadingCities = true;
  bool _hasFreshLocalPartners = false;
  int _freshLocalNewDeals = 0;
  int _freshLocalPartnerCount = 0;
  int _freshLocalDealCount = 0;
  bool _hasLocalSipsPartners = false;
  int _localSipsNewDeals = 0;
  int _localSipsPartnerCount = 0;
  int _localSipsDealCount = 0;
  bool _hasLocalEatsPartners = false;
  int _localEatsNewDeals = 0;
  int _localEatsPartnerCount = 0;
  int _localEatsDealCount = 0;
  bool _hasLocallyActivePartners = false;
  int _locallyActiveNewDeals = 0;
  int _locallyActivePartnerCount = 0;
  int _locallyActiveDealCount = 0;

  static const Map<String, List<String>> _citiesByProvince = {
    'Eastern Cape': [
      'Bhisho',
      'Butterworth',
      'Cradock',
      'East London',
      'Graaff-Reinet',
      'Grahamstown (Makhanda)',
      'Jeffreys Bay',
      'King William\'s Town',
      'Mthatha',
      'Port Elizabeth (Gqeberha)',
      'Queenstown',
      'Uitenhage',
    ],
    'Free State': [
      'Bethlehem',
      'Bloemfontein',
      'Kroonstad',
      'Parys',
      'Phuthaditjhaba',
      'Sasolburg',
      'Virginia',
      'Welkom',
    ],
    'Gauteng': [
      'Alberton',
      'Benoni',
      'Boksburg',
      'Brakpan',
      'Carletonville',
      'Centurion',
      'Germiston',
      'Johannesburg',
      'Krugersdorp',
      'Midrand',
      'Pretoria',
      'Randburg',
      'Roodepoort',
      'Sandton',
      'Soweto',
      'Springs',
      'Vanderbijlpark',
      'Vereeniging',
    ],
    'KwaZulu-Natal': [
      'Ballito',
      'Durban',
      'Empangeni',
      'Eshowe',
      'Ladysmith',
      'Margate',
      'Newcastle',
      'Pietermaritzburg',
      'Pinetown',
      'Port Shepstone',
      'Richards Bay',
      'Ulundi',
      'Umhlanga',
    ],
    'Limpopo': [
      'Bela-Bela',
      'Giyani',
      'Lephalale',
      'Louis Trichardt (Makhado)',
      'Mokopane',
      'Musina',
      'Phalaborwa',
      'Polokwane',
      'Thohoyandou',
      'Tzaneen',
    ],
    'Mpumalanga': [
      'Barberton',
      'Bethal',
      'Ermelo',
      'Middelburg',
      'Nelspruit (Mbombela)',
      'Secunda',
      'Standerton',
      'Witbank (Emalahleni)',
    ],
    'Northern Cape': [
      'De Aar',
      'Kathu',
      'Kimberley',
      'Kuruman',
      'Springbok',
      'Upington',
    ],
    'North West': [
      'Brits',
      'Klerksdorp',
      'Lichtenburg',
      'Mahikeng',
      'Potchefstroom',
      'Rustenburg',
    ],
    'Western Cape': [
      'Beaufort West',
      'Cape Town',
      'George',
      'Hermanus',
      'Knysna',
      'Mossel Bay',
      'Oudtshoorn',
      'Paarl',
      'Saldanha',
      'Somerset West',
      'Stellenbosch',
      'Swellendam',
      'Worcester',
    ],
  };

  static const List<String> _provinces = [
    'Eastern Cape',
    'Free State',
    'Gauteng',
    'KwaZulu-Natal',
    'Limpopo',
    'Mpumalanga',
    'Northern Cape',
    'North West',
    'Western Cape',
  ];

  @override
  void initState() {
    super.initState();
    _seedProfileFromSession();
    WidgetsBinding.instance.addObserver(this);
    final usedSnapshot = _restoreFromSessionSnapshot();
    if (!usedSnapshot) {
      _loadUserData();
    }
    _loadTrustedPartnersCount();
    _loadPendingPaymentsCount();
    _loadMemberCityProvince();
    _loadFreshLocalAvailability();
    _loadActivePromotions();
    _subscribeToApprovalNotifications();
    _loadUnreadChatCount();
    _unreadChatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadUnreadChatCount(),
    );
    try {
      _chatMessagesChannel = ChatService.instance
          .subscribeToChatMessageChanges(onChange: _loadUnreadChatCount);
    } catch (_) {}

    _enableSecureScreenProtection();
    _startQrRotation();
  }

  Future<void> _pickAndSaveProfilePhoto() async {
    if (_isUploadingProfilePhoto) return;

    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You need to be signed in to update your profile photo.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final XFile? image = await _profilePhotoPicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );

      if (image == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No image selected.')),
          );
        }
        return;
      }

      if (mounted) {
        setState(() => _isUploadingProfilePhoto = true);
      }

      final rawBytes = await image.readAsBytes();
      const bucketId = 'member-profile-photos';
      const ext = 'jpg';
      final filePath = '${user.id}/profile_photo.$ext';

      await SupabaseService.instance.client.storage
          .from(bucketId)
          .uploadBinary(
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

      final refreshedProfile = await SupabaseService.instance.getUserProfile(
        userId: user.id,
      );
      final persistedPhotoUrl =
          refreshedProfile?['profile_photo_url']?.toString().trim();

      if (persistedPhotoUrl == null || persistedPhotoUrl.isEmpty) {
        await SupabaseService.instance.client.rpc(
          'create_user_profile',
          params: {
            'p_user_id': user.id,
            'p_user_data': {
              'email': user.email,
              'profile_photo_url': publicUrl,
            },
          },
        );
      }

      if (mounted) {
        setState(() {
          _userProfile = {
            ...?_userProfile,
            'profile_photo_url': publicUrl,
          };
        });
        _saveSessionSnapshot();
      }

      await _loadUserData();

      if (!mounted) return;
      setState(() => _isUploadingProfilePhoto = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error updating profile photo: $e');
      }
      if (!mounted) return;
      setState(() => _isUploadingProfilePhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showProfilePhotoEditor(String displayName, String? profilePhotoUrl) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Profile Photo',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                ProfilePhoto(
                  imageUrl: profilePhotoUrl,
                  displayName: displayName,
                  size: 88,
                  shape: ProfilePhotoShape.roundedRect,
                  borderRadius: 24,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  fit: BoxFit.contain,
                  adaptiveBox: true,
                  minAdaptiveWidthFactor: 0.45,
                  maxAdaptiveWidthFactor: 1.13,
                  minAdaptiveHeightFactor: 0.45,
                  maxAdaptiveHeightFactor: 0.95,
                  adaptiveTargetAreaFactor: 0.48,
                  adaptiveMinAspectRatio: 0.6,
                  adaptiveMaxAspectRatio: 1.8,
                  adaptiveCornerRadiusFactor: 0.26,
                ),
                const SizedBox(height: 12),
                Text(
                  profilePhotoUrl?.trim().isNotEmpty == true
                      ? 'Change your homepage profile photo.'
                      : 'Upload a photo for your homepage profile block.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isUploadingProfilePhoto
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop();
                            _pickAndSaveProfilePhoto();
                          },
                    icon: _isUploadingProfilePhoto
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.photo_camera_outlined),
                    label: Text(
                      _isUploadingProfilePhoto
                          ? 'Uploading...'
                          : profilePhotoUrl?.trim().isNotEmpty == true
                              ? 'Change Profile Photo'
                              : 'Upload Profile Photo',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _enableSecureScreenProtection() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    try {
      await ScreenProtector.preventScreenshotOn();
      if (kDebugMode) {
        print('🔒 Enabled screenshot protection for member QR view');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to enable secure window protection: $e');
      }
    }
  }

  Future<void> _disableSecureScreenProtection() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    try {
      await ScreenProtector.preventScreenshotOff();
      if (kDebugMode) {
        print('🔓 Cleared screenshot protection for member QR view');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to clear secure window protection: $e');
      }
    }
  }

  void _startQrRotation() {
    _qrRotationTimer?.cancel();
    _qrRotationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _rotateQrCodeIfNeeded(),
    );
    unawaited(_rotateQrCodeIfNeeded(force: true));
  }

  Future<void> _rotateQrCodeIfNeeded({bool force = false}) async {
    if (_isRotatingQr || _obscureSensitiveContent) {
      return;
    }

    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) {
      return;
    }

    final hasActiveQr = _userQrData?['is_active'] == true;
    if (!hasActiveQr) {
      return;
    }

    final existingQr = _userQrData?['qr_code'] as String?;
    if (!force && existingQr != null) {
      try {
        final decoded = jsonDecode(existingQr);
        if (decoded is Map<String, dynamic>) {
          final exp = decoded['exp'];
          if (exp is int) {
            final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
            final secondsLeft = exp - nowEpoch;
            if (secondsLeft > 15) {
              return;
            }
          }
        }
      } catch (_) {
        // Legacy payloads should be rotated.
      }
    }

    _isRotatingQr = true;
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    try {
      final newQr = await QrCodeService().generateEphemeralQrCode(user.id);
      await SupabaseService.instance.client
          .from('user_qr_codes')
          .update({'qr_code': newQr, 'updated_at': updatedAt})
          .eq('user_id', user.id)
          .eq('is_active', true);

      if (mounted) {
        setState(() {
          _userQrData = {
            ...?_userQrData,
            'qr_code': newQr,
            'updated_at': updatedAt,
          };
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ QR rotation failed: $e');
      }
    } finally {
      _isRotatingQr = false;
    }
  }

  void _seedProfileFromSession() {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final firstName = (metadata['name'] as String?)?.trim();
    final lastName = (metadata['surname'] as String?)?.trim();
    final fallbackName = (user.email ?? 'User').split('@').first;

    if (_userProfile == null) {
      _userProfile = {
        'name': (firstName != null && firstName.isNotEmpty)
            ? firstName
            : fallbackName,
        'surname': (lastName != null && lastName.isNotEmpty) ? lastName : '',
      };
    }
  }

  bool _restoreFromSessionSnapshot() {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return false;

    final snapshot = _sessionSnapshots[user.id];
    if (snapshot == null) return false;

    final age = DateTime.now().difference(snapshot.capturedAt);
    if (age > _snapshotTtl) {
      _sessionSnapshots.remove(user.id);
      return false;
    }

    _userProfile = snapshot.userProfile;
    _subscriptionStatus = snapshot.subscriptionStatus;
    _userQrData = snapshot.userQrData;
    _savingsStats = snapshot.savingsStats;
    _isSubscriptionExpired = snapshot.isSubscriptionExpired;
    _isSavingsLoading = false;
    _isTrustedPartner = snapshot.isTrustedPartner;

    if (kDebugMode) {
      print('⚡ Restored member-home snapshot (${age.inSeconds}s old)');
    }
    return true;
  }

  void _saveSessionSnapshot() {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;

    _sessionSnapshots[user.id] = _MemberHomeSnapshot(
      capturedAt: DateTime.now(),
      userProfile: _userProfile,
      subscriptionStatus: _subscriptionStatus,
      userQrData: _userQrData,
      savingsStats: _savingsStats,
      isSubscriptionExpired: _isSubscriptionExpired,
      isTrustedPartner: _isTrustedPartner,
    );
  }

  Future<void> _loadUnreadChatCount() async {
    try {
      final count = await ChatService.instance.fetchUnreadConversationCount();
      if (!mounted) return;
      if (count != _unreadChatCount) {
        setState(() => _unreadChatCount = count);
      }
    } catch (_) {}
  }

  Future<void> _loadActivePromotions() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      final email = user.email;
      if (email == null || email.isEmpty) return;

      // Only show promotions the admin has registered this member's email for
      final eligiblePromos = await PromotionCampaignService()
          .getEligiblePromotionsForEmail(email: email);

      // Filter out promos the member has already signed up for
      if (eligiblePromos.isNotEmpty) {
        final signups = await SupabaseService.instance.client
            .from('promotion_signups')
            .select('promotion_id')
            .eq('user_id', user.id);

        final signedUpIds = (signups as List)
            .map((s) => s['promotion_id'] as String)
            .toSet();

        eligiblePromos.removeWhere((p) => signedUpIds.contains(p['id']));
      }

      if (mounted) {
        setState(() {
          _activePromotions = eligiblePromos;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading promotions: $e');
      }
    }
  }

  void _subscribeToApprovalNotifications() {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;

    _notificationSubscription?.cancel();

    if (kDebugMode) {
      print('🔔 Subscribing to real-time approval notifications');
    }
    _notificationSubscription = _dealApprovalService
        .subscribeToApprovalNotifications(user.id)
        .listen(
          (approvalNotifications) {
            if (approvalNotifications.isNotEmpty && mounted) {
              if (kDebugMode) {
                print('🎉 New approval notification received in real-time!');
              }
              // Show popup for the first unread approval
              _dealApprovalService.checkAndShowApprovalPopup(context, user.id);
            }
          },
          onError: (error) {
            if (kDebugMode) {
              print('❌ Approval notification stream error: $error');
            }
            unawaited(_refreshApprovalNotificationsOnResume());
          },
          onDone: () {
            if (kDebugMode) {
              print('⚠️ Approval notification stream closed');
            }
            unawaited(_refreshApprovalNotificationsOnResume());
          },
        );
  }

  Future<void> _refreshApprovalNotificationsOnResume() async {
    if (_isResubscribingApprovals) return;

    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;

    final now = DateTime.now();
    final shouldThrottle =
        _lastApprovalSyncAt != null &&
        now.difference(_lastApprovalSyncAt!).inSeconds < 3;
    if (shouldThrottle) return;

    _isResubscribingApprovals = true;
    _lastApprovalSyncAt = now;

    try {
      _subscribeToApprovalNotifications();

      // Fallback query path in case realtime events were missed while backgrounded.
      if (mounted) {
        await _dealApprovalService.checkAndShowApprovalPopup(context, user.id);
      }
    } finally {
      _isResubscribingApprovals = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final shouldObscure = state != AppLifecycleState.resumed;
    if (mounted && shouldObscure != _obscureSensitiveContent) {
      setState(() {
        _obscureSensitiveContent = shouldObscure;
      });
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(_rotateQrCodeIfNeeded(force: true));
      unawaited(_refreshApprovalNotificationsOnResume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _homeScrollController.dispose();
    _notificationSubscription?.cancel();
    _unreadChatTimer?.cancel();
    _qrRotationTimer?.cancel();
    _countdownTimer?.cancel();
    _chatMessagesChannel?.unsubscribe();
    _disableSecureScreenProtection();
    super.dispose();
  }

  // _activateTpMemberFromDialog removed – TP key activation is only available
  // on the Trusted Partner flow, not for normal members.

  // Placeholder to keep the file compiling if any dead references remain.
  // (none expected)

  Future<void> _signOut(BuildContext context) async {
    try {
      await SupabaseService.instance.signOut();

      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed: $e')),
      );
    }
  }

  Future<void> _confirmAndSignOut(BuildContext context) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to access your membership.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (shouldSignOut == true && context.mounted) {
      await _signOut(context);
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user != null) {
        if (kDebugMode) {
          print('🔄 Loading user data for user: ${user.id}');
        }

        // Run slower operations in parallel so member details render quickly.
        final wasExpiredFuture = _subscriptionService
          .checkAndHandleExpiredSubscription(user.id)
          .catchError((_) => false);
        final tpCheckFuture = SupabaseService.instance.client
          .from('trusted_partners')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle()
          .catchError((_) => null);
        final statusFuture = _subscriptionService
          .getSubscriptionStatus(user.id)
          .catchError((_) => null);
        final qrFuture = _subscriptionService
          .getUserQrCode(user.id)
          .catchError((_) => null);
        final savingsFuture = _savingsService
          .getUserSavingsStats(user.id)
          .catchError((_) => null);

        // Fetch profile first and paint immediately (name/surname in header).
        final profileResponse = await SupabaseService.instance.client
          .from('profiles')
          .select('name, surname, is_tp_member, city, province, profile_photo_url')
          .eq('id', user.id)
          .single();

        if (kDebugMode) {
          print('👤 User profile result: $profileResponse');
        }
        if (kDebugMode) {
          print(
            '👤 Profile name: ${profileResponse['name']}, surname: ${profileResponse['surname']}',
          );
        }

        if (mounted) {
          setState(() {
            _userProfile = profileResponse;
          });
        }

        final wasExpired = await wasExpiredFuture;
        if (wasExpired == true && kDebugMode) {
          print('🚨 Subscription was expired - QR codes deactivated');
        }

        // Check if user is a trusted partner (has record in trusted_partners table)
        final tpCheck = await tpCheckFuture;
        _isTrustedPartner = tpCheck != null;

        // Get comprehensive subscription status
        final status = await statusFuture;
        if (kDebugMode) {
          print('📊 Subscription status result: $status');
        }

        // Check if subscription is expired
        bool expired = false;
        if (status != null && status['current_period_end'] != null) {
          try {
            final renewalDate = DateTime.parse(
              status['current_period_end'],
            ).toLocal();
            if (renewalDate.isBefore(DateTime.now())) {
              expired = true;
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error parsing current_period_end: $e');
            }
          }
        }
        setState(() {
          _userProfile = profileResponse;
          _subscriptionStatus = status;
          _isSubscriptionExpired = expired;
        });

        // Also get QR code data for display
        final qrData = await qrFuture;
        if (kDebugMode) {
          print('📱 QR code data result: $qrData');
        }

        // Load savings statistics
        setState(() => _isSavingsLoading = true);
        final savingsData = await savingsFuture;
        if (kDebugMode) {
          print('💰 Savings stats result: $savingsData');
        }

        setState(() {
          _userProfile = profileResponse;
          _subscriptionStatus = status;
          _userQrData = qrData;
          _savingsStats = savingsData;
          _isSavingsLoading = false;
        });
        unawaited(_rotateQrCodeIfNeeded(force: true));
        _saveSessionSnapshot();

        // Check for pending approval notifications and show popup
        if (mounted) {
          await _dealApprovalService.checkAndShowApprovalPopup(
            context,
            user.id,
          );
        }

        // Show renewal popup if subscription was expired
        if (wasExpired && status != null) {
          final hasActiveQr = status['has_active_qr'] ?? false;
          final subscriptionStatus = status['subscription_status'] ?? 'none';

          // Only show popup if no active QR and subscription is expired
          if (!hasActiveQr && subscriptionStatus == 'expired') {
            if (kDebugMode) {
              print('💬 Scheduling renewal popup display');
            }
            // Delay to ensure UI is built
            Future.delayed(Duration(milliseconds: 500), () {
              if (mounted) {
                _showRenewalPopup();
              }
            });
          }
        }

        // Start countdown timer for manual payments that are due
        if (status != null &&
            status['subscription_status'] == 'active' &&
            !(status['auto_renew'] ?? false) &&
            (status['days_until_renewal'] ?? 0) <= 3) {
          _startCountdownTimer();
        }

        // (duplicate checkAndShowApprovalPopup call removed — already called above)
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading user data: $e');
      }
      setState(() {
        _subscriptionStatus = null;
        _userQrData = null;
        _savingsStats = null;
        _isSavingsLoading = false;
      });
    }
  }

  Future<void> _loadTrustedPartnersCount() async {
    setState(() => _isLoadingPartnersCount = true);

    try {
      // Try to get from cache first
      final cachedDeals = _cacheService.getCachedDeals();
      final cachedPartners = _cacheService.getCachedTrustedPartners();

      List<dynamic> partnersResponse;
      List<dynamic> dealsResponse;

      if (cachedPartners != null && cachedDeals != null) {
        // Use cached data for instant display
        partnersResponse = cachedPartners['partners'];
        dealsResponse = cachedDeals['deals'];
        if (kDebugMode) {
          print('⚡ Using cached deals and partners');
        }
      } else {
        // Fetch from database
        partnersResponse =
            await SupabaseService.instance.client
                    .from('businesses')
                    .select(
                      'id, owner_member_id, name, category, address, logo_url',
                    )
                as List<dynamic>;

        dealsResponse =
            await SupabaseService.instance.client
                    .from('trusted_partner_discounts')
                    .select(
                      'id, name, is_active, business_id, trusted_partner_id',
                    )
                    .eq('is_active', true)
                as List<dynamic>;

        // Cache the results
        await _cacheService.cacheTrustedPartners(
          partnersResponse.cast<Map<String, dynamic>>(),
        );
        await _cacheService.cacheDeals(
          dealsResponse.cast<Map<String, dynamic>>(),
        );
      }

      if (kDebugMode) {
        print('🔍 Found ${dealsResponse.length} active deals in database');
      }

      // Create a set of valid business IDs and partner IDs
      final validBusinessIds = partnersResponse.map((b) => b['id']).toSet();
      final validPartnerIds = partnersResponse
          .map((b) => b['owner_member_id'])
          .toSet();

      // Filter deals to only include those linked to existing businesses
      final validDeals = dealsResponse.where((deal) {
        final hasValidBusinessId =
            deal['business_id'] != null &&
            validBusinessIds.contains(deal['business_id']);
        final hasValidPartnerId =
            deal['trusted_partner_id'] != null &&
            validPartnerIds.contains(deal['trusted_partner_id']);
        return hasValidBusinessId || hasValidPartnerId;
      }).toList();

      if (kDebugMode) {
        print('🔢 Valid deals count: ${validDeals.length}');
      }
      if (kDebugMode) {
        print('� Valid active deals:');
      }
      for (var deal in validDeals) {
        if (kDebugMode) {
          print('   ✓ ${deal['name']}');
        }
      }

      if (validDeals.length != dealsResponse.length) {
        if (kDebugMode) {
          print(
            '⚠️ Found ${dealsResponse.length - validDeals.length} orphaned deals:',
          );
        }
        for (var deal in dealsResponse) {
          if (!validDeals.contains(deal)) {
            if (kDebugMode) {
              print(
                '   ✗ ${deal['name']} (business_id: ${deal['business_id']}, partner_id: ${deal['trusted_partner_id']})',
              );
            }
          }
        }
      }

      setState(() {
        _trustedPartnersCount = partnersResponse.length;
        _availableDealsCount = validDeals.length;
        _isLoadingPartnersCount = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading trusted partners count: $e');
      }
      setState(() {
        _trustedPartnersCount = 0;
        _availableDealsCount = 0;
        _isLoadingPartnersCount = false;
      });
    }
  }

  Future<void> _loadPendingPaymentsCount() async {
    setState(() => _isLoadingPendingPayments = true);

    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) {
        setState(() {
          _pendingPaymentsCount = 0;
          _isLoadingPendingPayments = false;
        });
        return;
      }

      final pendingResponse = await SupabaseService.instance.client
          .from('deal_authorizations')
          .select('id')
          .eq('member_id', user.id)
          .eq('status', 'approved')
          .isFilter('payment_completed_at', null);

      if (kDebugMode) {
        print('💳 Found ${(pendingResponse as List).length} pending payments');
      }

      setState(() {
        _pendingPaymentsCount = (pendingResponse as List).length;
        _isLoadingPendingPayments = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading pending payments count: $e');
      }
      setState(() {
        _pendingPaymentsCount = 0;
        _isLoadingPendingPayments = false;
      });
    }
  }

  Future<void> _loadFreshLocalAvailability() async {
    final stopwatch = Stopwatch()..start();
    final results = await Future.wait<FreshLocalSummary>([
      Future(() async => DiscountService().getFreshLocalSummary(
            city: _selectedCity,
            since: await FreshLocalNotice.loadLastSeen(),
          )),
      Future(() async => DiscountService().getLocalSipsSummary(
            city: _selectedCity,
            since: await LocalSipsNotice.loadLastSeen(),
          )),
      Future(() async => DiscountService().getLocallyActiveSummary(
            city: _selectedCity,
            since: await LocallyActiveNotice.loadLastSeen(),
          )),
      Future(() async => DiscountService().getLocalEatsSummary(
        city: _selectedCity,
        since: await LocalEatsNotice.loadLastSeen(),
          )),
    ]);
    final summary = results[0];
    final sips = results[1];
    final active = results[2];
    final eats = results[3];
    if (kDebugMode) {
      debugPrint(
        'Member category tabs loaded in ${stopwatch.elapsedMilliseconds}ms '
        '(city: ${_selectedCity ?? 'all'})',
      );
    }
    if (!mounted) return;
    setState(() {
      _hasFreshLocalPartners = summary.hasPartners;
      _freshLocalNewDeals = summary.newDealCount;
      _freshLocalPartnerCount = summary.partnerCount;
      _freshLocalDealCount = summary.dealCount;
      _hasLocalSipsPartners = sips.hasPartners;
      _localSipsNewDeals = sips.newDealCount;
      _localSipsPartnerCount = sips.partnerCount;
      _localSipsDealCount = sips.dealCount;
      _hasLocalEatsPartners = eats.hasPartners;
      _localEatsNewDeals = eats.newDealCount;
      _localEatsPartnerCount = eats.partnerCount;
      _localEatsDealCount = eats.dealCount;
      _hasLocallyActivePartners = active.hasPartners;
      _locallyActiveNewDeals = active.newDealCount;
      _locallyActivePartnerCount = active.partnerCount;
      _locallyActiveDealCount = active.dealCount;
    });
  }

  Future<void> _openLocallyActive() async {
    await LocallyActiveNotice.markSeen();
    if (!mounted) return;
    setState(() => _locallyActiveNewDeals = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocallyActivePartnersPage(cityFilter: _selectedCity),
      ),
    );
  }

  Future<void> _openFreshLocal() async {
    await FreshLocalNotice.markSeen();
    if (!mounted) return;
    setState(() => _freshLocalNewDeals = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FreshLocalPartnersPage(cityFilter: _selectedCity),
      ),
    );
  }

  Future<void> _openLocalSips() async {
    if (!await ensureMemberIsAgeVerified(context)) return;
    await LocalSipsNotice.markSeen();
    if (!mounted) return;
    setState(() => _localSipsNewDeals = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalSipsPartnersPage(cityFilter: _selectedCity),
      ),
    );
  }

  Future<void> _openLocalEats() async {
    await LocalEatsNotice.markSeen();
    if (!mounted) return;
    setState(() => _localEatsNewDeals = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalEatsPartnersPage(cityFilter: _selectedCity),
      ),
    );
  }

  Future<void> _loadMemberCityProvince() async {
    setState(() => _isLoadingCities = true);
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      // Restore from SharedPreferences first for fast display
      final prefs = await SharedPreferences.getInstance();
      final savedProvince = prefs.getString('selected_province');
      final savedCity = prefs.getString('selected_city');

      if (savedProvince != null && _citiesByProvince.containsKey(savedProvince)) {
        final cities = _citiesByProvince[savedProvince]!;
        if (mounted) {
          setState(() {
            _selectedProvince = savedProvince;
            _selectedCity = (savedCity != null && cities.contains(savedCity)) ? savedCity : null;
            _isLoadingCities = false;
          });
        }
        return;
      }

      // Fall back to profile data
      final profile = await SupabaseService.instance.client
          .from('profiles')
          .select('city, province')
          .eq('id', user.id)
          .single();

      final profileProvince = profile['province'] as String?;
      final profileCity = profile['city'] as String?;

      if (mounted) {
        setState(() {
          if (profileProvince != null && _citiesByProvince.containsKey(profileProvince)) {
            _selectedProvince = profileProvince;
            final cities = _citiesByProvince[profileProvince]!;
            _selectedCity = (profileCity != null && cities.contains(profileCity)) ? profileCity : null;
          }
          _isLoadingCities = false;
        });

        // Persist to SharedPreferences
        if (_selectedProvince != null) {
          prefs.setString('selected_province', _selectedProvince!);
        }
        if (_selectedCity != null) {
          prefs.setString('selected_city', _selectedCity!);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading member city/province: $e');
      }
      if (mounted) {
        setState(() => _isLoadingCities = false);
      }
    }
  }

  Future<void> _updateMemberCityProvince(String? province, String? city) async {
    setState(() {
      _selectedProvince = province;
      _selectedCity = city;
    });

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    if (province != null) {
      prefs.setString('selected_province', province);
    } else {
      prefs.remove('selected_province');
    }
    if (city != null) {
      prefs.setString('selected_city', city);
    } else {
      prefs.remove('selected_city');
    }

    // Update profile in database
    final user = SupabaseService.instance.getCurrentUser();
    if (user != null) {
      await SupabaseService.instance.updateUserProfile(
        userId: user.id,
        profileData: {
          'province': province,
          'city': city,
        },
      );
    }

    await _loadFreshLocalAvailability();
  }

  void _showCityFilterBottomSheet() {
    String? tempProvince = _selectedProvince;
    String? tempCity = _selectedCity;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final cities = tempProvince != null
                ? _citiesByProvince[tempProvince!] ?? <String>[]
                : <String>[];

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: AppColors.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Select Province & City',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: DropdownButtonFormField<String>(
                        value: tempProvince,
                        decoration: const InputDecoration(
                          labelText: 'Province',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        items: _provinces.map((province) {
                          return DropdownMenuItem(
                            value: province,
                            child: Text(province),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setSheetState(() {
                            tempProvince = value;
                            tempCity = null;
                          });
                        },
                      ),
                    ),
                    if (tempProvince != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(tempProvince),
                          value: tempCity,
                          decoration: const InputDecoration(
                            labelText: 'City',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                          items: cities.map((city) {
                            return DropdownMenuItem(
                              value: city,
                              child: Text(city),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setSheetState(() {
                              tempCity = value;
                            });
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _updateMemberCityProvince(null, null);
                                Navigator.pop(context);
                              },
                              child: const Text('Clear'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: tempCity != null
                                  ? () {
                                      _updateMemberCityProvince(tempProvince, tempCity);
                                      Navigator.pop(context);
                                    }
                                  : null,
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    if (_subscriptionStatus != null &&
        _subscriptionStatus?['subscription_end_date'] != null) {
      final subscriptionEndDate = DateTime.parse(
        _subscriptionStatus?['subscription_end_date'] ?? '',
      );
      _timeUntilPayment = _subscriptionService.getTimeUntilNextPayment(
        subscriptionEndDate,
      );

      // Update timer every second
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _timeUntilPayment = _subscriptionService.getTimeUntilNextPayment(
            subscriptionEndDate,
          );
        });
      });
    }
  }

  void _handleManualRenewal() {
    _navigateToPaymentScreen();
  }

  void _showQrCodePopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final viewInsets = MediaQuery.of(context).viewInsets.bottom;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: viewInsets > 0 ? 10 : 0),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Your QR Code',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Use the existing QR code content logic
                    _buildQrCodeContent(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Show renewal popup when subscription is expired
  void _showRenewalPopup() {
    if (kDebugMode) {
      print('🔔 Showing renewal popup for expired subscription');
    }

    showDialog(
      context: context,
      barrierDismissible: false, // User must tap a button
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Subscription Expired',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your subscription has expired and your QR code has been deactivated.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                Text(
                  'Renew now to:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                _buildBenefitRow('✓ Reactivate your QR code'),
                _buildBenefitRow('✓ Continue receiving instant discounts'),
                _buildBenefitRow('✓ Access exclusive local deals'),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.local_offer, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'R99.00 for 30 days',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (kDebugMode) {
                  print('❌ User dismissed renewal popup');
                }
                Navigator.of(context).pop();
              },
              child: Text('Not Now', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (kDebugMode) {
                  print('✅ User clicked Renew Subscription');
                }
                Navigator.of(context).pop();
                _navigateToPaymentScreen();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text('Renew Subscription', style: TextStyle(fontSize: 15)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBenefitRow(String text) {
    return Padding(
      padding: EdgeInsets.only(left: 8, bottom: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
      ),
    );
  }

  Widget _buildPromoBanner(Map<String, dynamic> promo) {
    final imageUrl = promo['image_url'] as String?;
    final freeMonths = promo['free_months'];
    final durationText =
        freeMonths != null ? '$freeMonths month(s) free' : 'Lifetime access';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PromotionDetailPage(promotion: promo),
              ),
            );
            _loadActivePromotions();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                Image.network(
                  imageUrl,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 80,
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                    ),
                    child: const Center(
                      child: Icon(Icons.campaign, size: 36, color: Colors.white),
                    ),
                  ),
                )
              else
                Container(
                  height: 80,
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                  ),
                  child: const Center(
                    child: Icon(Icons.campaign, size: 36, color: Colors.white),
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
                            promo['name'] ?? 'Promotion',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
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
                                  fontWeight: FontWeight.w500,
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
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'View Details',
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
      ),
    );
  }

  Future<void> _navigateToPaymentScreen() async {
    if (kDebugMode) {
      print('🚀 Navigating to payment screen...');
    }
    if (kDebugMode) {
      print('📊 Current subscription data: $_userQrData');
    }

    // If user is a trusted partner, show the TP key dialog instead of payment screen
    final isTpMember = _userProfile?['is_tp_member'] ?? false;
    if (isTpMember || _isTrustedPartner) {
      final user = SupabaseService.instance.client.auth.currentUser;
      if (user != null) {
        showDialog(
          context: context,
          builder: (context) => TrustedPartnerKeyDialog(
            userId: user.id,
            isTrustedPartnerKey: true,
            onSuccess: () {
              _loadUserData();
            },
          ),
        );
        return;
      }
    }

    if (_userQrData?['subscriptions']?.first != null) {
      final subscription = _userQrData?['subscriptions']?.first;
      if (subscription != null) {
        if (kDebugMode) {
          print('📋 Subscription plan: ${subscription['plan_name']}');
        }
        if (kDebugMode) {
          print('🔄 Auto renew: ${subscription['auto_renew']}');
        }
      }
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentOptionsScreen(
          selectedPlan: 'renewal',
          planDetails: {
            'name': 'Subscription Renewal',
            'price': 99,
            'currency': 'ZAR',
            'frequency': 1, // Monthly renewal
            'description': 'Monthly subscription',
          },
        ),
      ),
    );

    if (result == true) {
      // Payment successful, reload data
      _loadUserData();
    }
  }

  @override
  Widget build(BuildContext context) {
    // When embedded by TP page (hideAppBar=true), use a compact version without the hero.
    if (widget.hideAppBar) {
      return _buildCompactMemberBody(context);
    }

    final String displayName = () {
      final name = _userProfile?['name'] ?? 'User';
      final surname = _userProfile?['surname'] ?? '';
      if (surname.isNotEmpty && !name.contains(surname)) return '$name $surname';
      return name;
    }();

    final double totalSaved = _savingsStats?['totalSaved']?.toDouble() ?? 0.0;
    final double totalTips = _savingsStats?['totalTips']?.toDouble() ?? 0.0;
    final double totalPaid = _savingsStats?['totalPaid']?.toDouble() ?? 0.0;
    final double totalInAppPayments =
      _savingsStats?['totalInAppPayments']?.toDouble() ?? 0.0;
    final double totalPosPayments =
      _savingsStats?['totalPosPayments']?.toDouble() ?? 0.0;
    final int totalDeals = _savingsStats?['totalDeals'] ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: _buildBottomNav(context),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          controller: _homeScrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Hero ────────────────────────────────────────────────────
              _buildMemberHero(
                context,
                displayName,
                totalSaved,
                totalTips,
                totalPaid,
                totalInAppPayments,
                totalPosPayments,
                totalDeals,
              ),

              // ── Promo banners ────────────────────────────────────────────
              if (_activePromotions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: _activePromotions
                        .map((p) => _buildPromoBanner(p))
                        .toList(),
                  ),
                ),

              // ── Body ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quick actions
                    _buildSectionHeader('Quick actions'),
                    const SizedBox(height: 8),
                    _buildQuickActions(context),
                    const SizedBox(height: 20),

                    // City filter
                    if (!_isLoadingCities) ...[
                      _buildSectionHeader('Your area'),
                      const SizedBox(height: 8),
                      _buildCityFilterCard(),
                      const SizedBox(height: 20),
                    ],

                    // Pending payments urgent card
                    if (_pendingPaymentsCount > 0) ...[
                      _buildPendingPaymentsCard(context),
                      const SizedBox(height: 20),
                    ],

                    const SizedBox(height: 16), // clearance for bottom nav
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────────────────────

  Widget _buildMemberHero(
    BuildContext context,
    String displayName,
    double totalSaved,
    double totalTips,
    double totalPaid,
    double totalInAppPayments,
    double totalPosPayments,
    int totalDeals,
  ) {
    final profilePhotoUrl = _userProfile?['profile_photo_url'] as String?;

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
          // Subtle radial glow
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
                    AppColors.sky.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo + greeting + chat
                Row(
                  children: [
                    // Profile photo / initials
                    Tooltip(
                      message: 'Upload profile photo',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _isUploadingProfilePhoto
                              ? null
                              : () {
                                  _showProfilePhotoEditor(
                                    displayName,
                                    profilePhotoUrl,
                                  );
                                },
                          child: _isUploadingProfilePhoto
                              ? Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      width: 1.5,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white.withValues(alpha: 0.92),
                                      ),
                                    ),
                                  ),
                                )
                              : ProfilePhoto(
                                  imageUrl: profilePhotoUrl,
                                  displayName: displayName,
                                  size: 76,
                                  shape: ProfilePhotoShape.roundedRect,
                                  borderRadius: 20,
                                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                                  foregroundColor: Colors.white,
                                  fit: BoxFit.contain,
                                  adaptiveBox: true,
                                  minAdaptiveWidthFactor: 0.45,
                                  maxAdaptiveWidthFactor: 1.13,
                                  minAdaptiveHeightFactor: 0.45,
                                  maxAdaptiveHeightFactor: 0.95,
                                  adaptiveTargetAreaFactor: 0.48,
                                  adaptiveMinAspectRatio: 0.6,
                                  adaptiveMaxAspectRatio: 1.8,
                                  adaptiveCornerRadiusFactor: 0.26,
                                  borderColor: Colors.white.withValues(alpha: 0.18),
                                  borderWidth: 1.5,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Greeting
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getGreeting(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.78),
                              letterSpacing: 0.04,
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
                    const SizedBox(width: 8),
                    // Messages & Support (with unread badge)
                    if (widget.onBackToBusiness != null) ...[
                      Tooltip(
                        message: 'Back to Business Mode',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: widget.onBackToBusiness,
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 1.2,
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
                      const SizedBox(width: 8),
                    ],
                    _buildHeroMessagesButton(context),
                    const SizedBox(width: 8),
                    // Sign out
                    Tooltip(
                      message: 'Sign out',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _confirmAndSignOut(context),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                                width: 1.2,
                              ),
                            ),
                            child: const Icon(
                              Icons.logout_rounded,
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 720;

                    final statsPanel = _buildHeroStatsPanel(
                      totalSaved: totalSaved,
                      totalTips: totalTips,
                      totalInAppPayments: totalInAppPayments,
                      totalPosPayments: totalPosPayments,
                    );

                    final qrBlock = _buildHeroQrBlock(
                      context,
                      totalPaid: totalPaid,
                      totalDeals: totalDeals,
                    );

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: statsPanel),
                          const SizedBox(width: 14),
                          SizedBox(width: 248, child: qrBlock),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        qrBlock,
                        const SizedBox(height: 12),
                        statsPanel,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStatsPanel({
    required double totalSaved,
    required double totalTips,
    required double totalInAppPayments,
    required double totalPosPayments,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildHeroStatTile(
            label: 'Saved',
            value: 'R${totalSaved.toStringAsFixed(0)}',
            icon: Icons.savings_outlined,
            accentColor: const Color(0xFF7CE39A),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildHeroStatTile(
            label: 'Tips',
            value: 'R${totalTips.toStringAsFixed(0)}',
            icon: Icons.volunteer_activism,
            accentColor: const Color(0xFFFF7B7B),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildHeroStatTile(
            label: 'In-App',
            value: 'R${totalInAppPayments.toStringAsFixed(0)}',
            icon: Icons.credit_card,
            accentColor: const Color(0xFF8CC6FF),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildHeroStatTile(
            label: 'POS',
            value: 'R${totalPosPayments.toStringAsFixed(0)}',
            icon: Icons.storefront_outlined,
            accentColor: const Color(0xFFFFD56A),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroStatTile({
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
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1,
        ),
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

  Widget _buildHeroQrBlock(
    BuildContext context, {
    required double totalPaid,
    required int totalDeals,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showQrCodePopup,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, Color(0xFF0A4A8A), Color(0xFF08396A)],
            stops: [0.0, 0.58, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.30),
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
                    'Tap to show your QR code',
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

  // ── Quick actions ────────────────────────────────────────────────────────

  /// Messages & Support entry point for the hero header.
  ///
  /// Opens [ChatListPage] (member conversations + the "Chat with Admin"
  /// support button) and shows an unread badge so members can see new
  /// message notifications directly from Home.
  Widget _buildHeroMessagesButton(BuildContext context) {
    return Tooltip(
      message: 'Messages & Support',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatListPage()),
            );
            // Refresh the badge after returning so read messages clear.
            _loadUnreadChatCount();
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1.2,
                  ),
                ),
                child: const Icon(
                  Icons.forum_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              if (_unreadChatCount > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: const Color(0xFF0A4A8A),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _unreadChatCount > 9 ? '9+' : '$_unreadChatCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      children: [
        _buildActionTile(
          icon: Icons.local_offer_outlined,
          label: 'Find Deals',
          color: AppColors.accent,
          bgColor: AppColors.accent.withValues(alpha: 0.12),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DealSelectionPage(cityFilter: _selectedCity),
            ),
          ),
        ),
        const SizedBox(height: 10),
        MemberCategoryBannerRow(
          onTapPartners: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  TrustedPartnersByCategoryPage(cityFilter: _selectedCity),
            ),
          ),
              partnerCount: _trustedPartnersCount,
              dealCount: _availableDealsCount,
          showFreshLocal: _hasFreshLocalPartners,
          onTapFreshLocal: _openFreshLocal,
          freshNewDeals: _freshLocalNewDeals,
          freshPartnerCount: _freshLocalPartnerCount,
          freshDealCount: _freshLocalDealCount,
          showLocalSips: _hasLocalSipsPartners,
          onTapLocalSips: _openLocalSips,
          sipsNewDeals: _localSipsNewDeals,
          sipsPartnerCount: _localSipsPartnerCount,
          sipsDealCount: _localSipsDealCount,
          showLocalEats: _hasLocalEatsPartners,
          onTapLocalEats: _openLocalEats,
          eatsNewDeals: _localEatsNewDeals,
          eatsPartnerCount: _localEatsPartnerCount,
          eatsDealCount: _localEatsDealCount,
          showLocallyActive: _hasLocallyActivePartners,
          onTapLocallyActive: _openLocallyActive,
          activeNewDeals: _locallyActiveNewDeals,
          activePartnerCount: _locallyActivePartnerCount,
          activeDealCount: _locallyActiveDealCount,
        ),
      ],
    );
  }

  Widget _buildActionTile({
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
          border: Border.all(color: AppColors.outline, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06),
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

  // ── Today stats ──────────────────────────────────────────────────────────

  Widget _buildTodayStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            value: _isLoadingPartnersCount ? '—' : '$_trustedPartnersCount',
            label: 'Partners nearby',
            barColor: AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            value: _isLoadingPartnersCount ? '—' : '$_availableDealsCount',
            label: 'Active deals',
            barColor: AppColors.accent,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String value,
    required String label,
    required Color barColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
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
              letterSpacing: -0.04,
              color: Color(0xFF0B2540),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
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

  // ── City filter card ─────────────────────────────────────────────────────

  Widget _buildCityFilterCard() {
    return GestureDetector(
      onTap: _showCityFilterBottomSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline, width: 1),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              color: _selectedCity != null ? AppColors.primary : Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedProvince != null)
                    Text(
                      _selectedProvince!,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  Text(
                    _selectedCity ?? 'All Areas',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _selectedCity != null
                          ? AppColors.primarySwatch.shade800
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (_selectedCity != null)
              GestureDetector(
                onTap: () => _updateMemberCityProvince(null, null),
                child: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
              ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  // ── Pending payments card ────────────────────────────────────────────────

  Widget _buildPendingPaymentsCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PendingPaymentsPage()),
      ).then((_) => _loadPendingPaymentsCount()),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.28),
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
              child: const Icon(Icons.pending_actions, size: 24, color: Colors.white),
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
                    _isLoadingPendingPayments
                        ? 'Loading...'
                        : '$_pendingPaymentsCount ${_pendingPaymentsCount == 1 ? 'deal awaiting payment' : 'deals awaiting payment'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
          ],
        ),
      ),
    );
  }

  // ── Bottom navigation bar ────────────────────────────────────────────────

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.outline, width: 1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.location_on_outlined,
                activeIcon: Icons.location_on,
                label: 'Home',
                onTap: () => setState(() => _selectedNavIndex = 0),
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long,
                label: 'Receipts',
                onTap: () {
                  setState(() => _selectedNavIndex = 1);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MemberReceiptsPage()),
                  ).then((_) => setState(() => _selectedNavIndex = 0));
                },
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
                onTap: () async {
                  setState(() => _selectedNavIndex = 2);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MemberProfilePage()),
                  );
                  _loadUserData();
                  if (mounted) setState(() => _selectedNavIndex = 0);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required VoidCallback onTap,
  }) {
    final bool isActive = _selectedNavIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 24,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            if (isActive)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Section helpers ──────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.06,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildSeeAll(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: const Text(
        'See all',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.sky,
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ── Compact body (used by TP member-view embed) ──────────────────────────

  Widget _buildCompactMemberBody(BuildContext context) {
    final String displayName = () {
      final name = _userProfile?['name'] ?? 'User';
      final surname = _userProfile?['surname'] ?? '';
      if (surname.isNotEmpty && !name.contains(surname)) return '$name $surname';
      return name;
    }();
    final double totalSaved = _savingsStats?['totalSaved']?.toDouble() ?? 0.0;
    final double totalTips = _savingsStats?['totalTips']?.toDouble() ?? 0.0;
    final double totalPaid = _savingsStats?['totalPaid']?.toDouble() ?? 0.0;
    final double totalInAppPayments =
      _savingsStats?['totalInAppPayments']?.toDouble() ?? 0.0;
    final double totalPosPayments =
      _savingsStats?['totalPosPayments']?.toDouble() ?? 0.0;
    final int totalDeals = _savingsStats?['totalDeals'] ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _homeScrollController,
          child: Column(
            children: [
              if (widget.embeddedTopPadding > 0)
                SizedBox(height: widget.embeddedTopPadding),
              if (!widget.hideEmbeddedHero)
                _buildMemberHero(
                  context,
                  displayName,
                  totalSaved,
                  totalTips,
                  totalPaid,
                  totalInAppPayments,
                  totalPosPayments,
                  totalDeals,
                ),
              if (_activePromotions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: _activePromotions.map((p) => _buildPromoBanner(p)).toList(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('Quick actions'),
                    const SizedBox(height: 8),
                    _buildQuickActions(context),
                    const SizedBox(height: 20),
                    _buildSectionHeader('Today'),
                    const SizedBox(height: 8),
                    _buildTodayStats(),
                    const SizedBox(height: 20),
                    if (_pendingPaymentsCount > 0) ...[
                      _buildPendingPaymentsCard(context),
                      const SizedBox(height: 20),
                    ],
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SavingsSummaryCard(
                        totalSpent: _savingsStats?['totalSpent']?.toDouble() ?? 0.0,
                        totalSaved: totalSaved,
                        totalPaid: _savingsStats?['totalPaid']?.toDouble() ?? 0.0,
                        totalTips: _savingsStats?['totalTips']?.toDouble() ?? 0.0,
                        totalDeals: totalDeals,
                        isLoading: _isSavingsLoading,
                        onBrowseDeals: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DealSelectionPage(cityFilter: _selectedCity),
                          ),
                        ),
                        onViewReceipts: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MemberReceiptsPage()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrCodeContent() {
    // Don't check _isLoading here - this is called from a dialog after data is loaded
    // If we get here, the user clicked the QR icon, so data should already be available

    if (_isSubscriptionExpired) {
      if (kDebugMode) {
        print(
          '📱 UI State: Subscription expired - show inactive QR and renewal prompt',
        );
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Icon(Icons.qr_code, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Subscription expired',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Renew your subscription to reactivate your QR code',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  if (kDebugMode) {
                    print('🔘 Approve Renewal button pressed (expired case)');
                  }
                  _navigateToPaymentScreen();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Approve Renewal'),
              ),
            ],
          ),
        ),
      );
    }

    // Check if user has QR code but no subscription (TP member case)
    if (_subscriptionStatus == null && _userQrData != null) {
      if (kDebugMode) {
        print('📱 UI State: TP member with QR code but no subscription');
      }
      final hasActiveQr = _userQrData?['is_active'] ?? false;
      if (hasActiveQr) {
        // TP member with active QR code
        return _buildActiveQrCode();
      }
    }

    if (_subscriptionStatus == null) {
      if (kDebugMode) {
        print(
          '📱 UI State: _subscriptionStatus is null',
        );
      }

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Icon(Icons.qr_code, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'No active subscription found',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  if (kDebugMode) {
                    print(
                      '🔘 Renew Subscription button pressed (no subscription data case)',
                    );
                  }
                  _navigateToPaymentScreen();
                },
                child: Text(widget.isTrustedPartner ? 'Enter TP key to activate' : 'Renew Subscription / Enter Promo Code'),
              ),
            ],
          ),
        ),
      );
    }

    final hasActiveQr = _subscriptionStatus?['has_active_qr'] ?? false;
    final autoRenew = _subscriptionStatus?['auto_renew'] ?? false;
    final daysUntilRenewal = _subscriptionStatus?['days_until_renewal'];
    final subscriptionStatus =
        _subscriptionStatus?['subscription_status'] ?? 'none';

    if (kDebugMode) {
      print('📊 UI State Debug:');
    }
    if (kDebugMode) {
      print('  - has_active_qr: $hasActiveQr');
    }
    if (kDebugMode) {
      print('  - auto_renew: $autoRenew');
    }
    if (kDebugMode) {
      print('  - days_until_renewal: $daysUntilRenewal');
    }
    if (kDebugMode) {
      print('  - subscription_status: $subscriptionStatus');
    }

    // Show Renew Subscription button for inactive QR with manual payments
    if (!hasActiveQr && !autoRenew) {
      if (kDebugMode) {
        print(
          '📱 UI State: Inactive QR for manual payment user - showing "Renew Subscription" button',
        );
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Icon(Icons.qr_code, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Subscription expired',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Renew your subscription to reactivate your QR code',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  if (kDebugMode) {
                    print(
                      '🔘 Renew Subscription button pressed (inactive QR case)',
                    );
                  }
                  _navigateToPaymentScreen();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Renew Subscription'),
              ),
            ],
          ),
        ),
      );
    }

    // Show countdown for manual payments near renewal date
    if (!autoRenew && daysUntilRenewal != null && daysUntilRenewal <= 3) {
      if (kDebugMode) {
        print('📱 UI State: Showing QR with countdown');
      }
      return _buildQrWithCountdown();
    }

    // Show active QR code
    if (kDebugMode) {
      print('📱 UI State: Showing active QR code');
    }
    return _buildActiveQrCode();
  }

  Widget _buildQrWithCountdown() {
    // Check if subscription has expired
    final isExpired =
        _timeUntilPayment.isNegative || _timeUntilPayment == Duration.zero;
    final daysLeft = isExpired ? 0 : _timeUntilPayment.inDays;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  CustomQrCode(
                    data: _userQrData?['qr_code'] ?? 'No QR Code Available',
                    size: 200.0,
                    logoAssetPath: 'assets/heart_flag.png',
                  ),
                  if (_obscureSensitiveContent) _buildSensitiveContentMask(),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isExpired ? 'Subscription Expired' : 'Payment Due Soon',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isExpired ? Colors.red : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isExpired
                    ? 'Renew now to continue using QR code'
                    : 'Time remaining: ${daysLeft}d',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isExpired ? Colors.red : null,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _handleManualRenewal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isExpired
                      ? Colors.red
                      : Theme.of(context).primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: Text(isExpired ? 'Renew Subscription' : 'Renew Now'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveQrCode() {
    // Check if user is TP member (permanent QR code, no renewal needed)
    final isTpMember = _userProfile?['is_tp_member'] ?? false;

    // Get the subscription renewal date (current_period_end)
    final renewalDate = _subscriptionStatus?['current_period_end'];
    String validityText = 'Valid until renewal';

    if (isTpMember) {
      validityText = 'Permanent - No renewal needed';
    } else if (renewalDate != null) {
      try {
        final endDate = DateTime.parse(renewalDate);
        validityText =
            'Valid until ${endDate.day} ${_getMonthName(endDate.month)} ${endDate.year}';
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing renewal date: $e');
        }
      }
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  CustomQrCode(
                    data: _userQrData?['qr_code'] ?? 'No QR Code Available',
                    size: 200.0,
                    logoAssetPath: 'assets/heart_flag.png',
                  ),
                  if (_obscureSensitiveContent) _buildSensitiveContentMask(),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Active QR Code',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(validityText, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  Widget _buildSensitiveContentMask() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Text(
        'Hidden while app is inactive',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
