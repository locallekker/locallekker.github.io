import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import '../../services/supabase_service.dart';
import '../../services/paystack_service.dart';
import '../../services/admin_service.dart';
import '../../services/chat_service.dart';
import '../../services/cache_service.dart';
import '../../services/navigation_service.dart';
import '../../services/web_checkout.dart';
import '../chat/chat_thread_page.dart';
import 'change_password_page.dart';
import 'payment_method_webview_page.dart';
import 'receipt_book_page.dart';
import 'notifications_page.dart';
import 'deactivation_confirmation_page.dart';
import 'widgets/trusted_partner_key_dialog.dart';
import 'package:flutter/foundation.dart';
import '../../widgets/profile_photo.dart';

// Custom input formatter for expiry date (MM/YY)
class ExpiryDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Remove any existing slashes
    final cleanText = text.replaceAll('/', '');

    // Only allow digits
    final digitsOnly = cleanText.replaceAll(RegExp(r'[^0-9]'), '');

    // Limit to 4 digits (MMYY)
    final limitedDigits = digitsOnly.length > 4
        ? digitsOnly.substring(0, 4)
        : digitsOnly;

    // Add slash after month (MM/YY)
    final formattedText = limitedDigits.length >= 2
        ? '${limitedDigits.substring(0, 2)}/${limitedDigits.substring(2)}'
        : limitedDigits;

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}

class _MemberProfileSnapshot {
  final DateTime capturedAt;
  final String? profilePhotoUrl;
  final String name;
  final String surname;
  final String email;
  final String street;
  final String suburb;
  final String contact;
  final String? gender;
  final String? ethnicity;
  final String? province;
  final String? city;
  final DateTime? dateOfBirth;
  final bool isTpMember;
  final List<Map<String, dynamic>> trustedPartners;

  const _MemberProfileSnapshot({
    required this.capturedAt,
    required this.profilePhotoUrl,
    required this.name,
    required this.surname,
    required this.email,
    required this.street,
    required this.suburb,
    required this.contact,
    required this.gender,
    required this.ethnicity,
    required this.province,
    required this.city,
    required this.dateOfBirth,
    required this.isTpMember,
    required this.trustedPartners,
  });
}

class MemberProfilePage extends StatefulWidget {
  const MemberProfilePage({super.key});

  @override
  State<MemberProfilePage> createState() => _MemberProfilePageState();
}

class _MemberProfilePageState extends State<MemberProfilePage> {
  static final Map<String, _MemberProfileSnapshot> _sessionSnapshots = {};
  static const Duration _snapshotTtl = Duration(minutes: 5);

  final Logger _logger = Logger();
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  // Personal Information Controllers
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _emailController = TextEditingController();

  // Address Information Controllers
  final _streetController = TextEditingController();
  final _suburbController = TextEditingController();

  // Contact Information Controllers
  final _contactController = TextEditingController();

  // Security: in-app password removed; use Change Password with OTP

  // Personal Details
  DateTime? _selectedDate;
  String? _selectedGender;
  String? _selectedEthnicity;
  String? _selectedProvince;
  String? _selectedCity;

  // Dropdown Options (matching signup page)
  final List<String> _genders = ['Male', 'Female', 'Other'];
  final List<String> _ethnicities = [
    'Black',
    'White',
    'Coloured',
    'Indian',
    'Other',
  ];
  final List<String> _provinces = [
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

  static const _citiesByProvince = <String, List<String>>{
    'Eastern Cape': [
      'Bhisho', 'Butterworth', 'Cradock', 'East London', 'Graaff-Reinet',
      'Grahamstown (Makhanda)', 'Jeffreys Bay', 'King William\'s Town',
      'Mthatha', 'Port Elizabeth (Gqeberha)', 'Queenstown', 'Uitenhage',
    ],
    'Free State': [
      'Bethlehem', 'Bloemfontein', 'Kroonstad', 'Parys',
      'Phuthaditjhaba', 'Sasolburg', 'Virginia', 'Welkom',
    ],
    'Gauteng': [
      'Alberton', 'Benoni', 'Boksburg', 'Brakpan', 'Carletonville',
      'Centurion', 'Germiston', 'Johannesburg', 'Krugersdorp', 'Midrand',
      'Pretoria', 'Randburg', 'Roodepoort', 'Sandton', 'Soweto',
      'Springs', 'Vanderbijlpark', 'Vereeniging',
    ],
    'KwaZulu-Natal': [
      'Ballito', 'Durban', 'Empangeni', 'Eshowe', 'Ladysmith',
      'Margate', 'Newcastle', 'Pietermaritzburg', 'Pinetown',
      'Port Shepstone', 'Richards Bay', 'Ulundi', 'Umhlanga',
    ],
    'Limpopo': [
      'Bela-Bela', 'Giyani', 'Lephalale', 'Louis Trichardt (Makhado)',
      'Mokopane', 'Musina', 'Phalaborwa', 'Polokwane', 'Thohoyandou',
      'Tzaneen',
    ],
    'Mpumalanga': [
      'Barberton', 'Bethal', 'Ermelo', 'Middelburg',
      'Nelspruit (Mbombela)', 'Secunda', 'Standerton',
      'Witbank (Emalahleni)',
    ],
    'Northern Cape': [
      'De Aar', 'Kathu', 'Kimberley', 'Kuruman', 'Springbok', 'Upington',
    ],
    'North West': [
      'Brits', 'Klerksdorp', 'Lichtenburg', 'Mahikeng',
      'Potchefstroom', 'Rustenburg',
    ],
    'Western Cape': [
      'Beaufort West', 'Cape Town', 'George', 'Hermanus', 'Knysna',
      'Mossel Bay', 'Oudtshoorn', 'Paarl', 'Saldanha', 'Somerset West',
      'Stellenbosch', 'Swellendam', 'Worcester',
    ],
  };

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTpMember = false;
  bool _showDobValidationError = false;
  String? _profilePhotoUrl;
  Uint8List? _profilePhotoBytes;

  // Trusted partners linked to this member (via past authorizations)
  List<Map<String, dynamic>> _trustedPartners = [];
  bool _isLoadingPartners = false;

  @override
  void initState() {
    super.initState();
    final restored = _restoreFromSessionSnapshot();
    if (restored) {
      unawaited(_loadUserProfile(showLoading: false));
    } else {
      _loadUserProfile();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _streetController.dispose();
    _suburbController.dispose();
    _contactController.dispose();
    super.dispose();
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

    _nameController.text = snapshot.name;
    _surnameController.text = snapshot.surname;
    _emailController.text = snapshot.email;
    _profilePhotoUrl = snapshot.profilePhotoUrl;
    _profilePhotoBytes = null;
    _streetController.text = snapshot.street;
    _suburbController.text = snapshot.suburb;
    _contactController.text = snapshot.contact;
    _selectedGender = snapshot.gender;
    _selectedEthnicity = snapshot.ethnicity;
    _selectedProvince = snapshot.province;
    _selectedCity = snapshot.city;
    _selectedDate = snapshot.dateOfBirth;
    _isTpMember = snapshot.isTpMember;
    _trustedPartners = snapshot.trustedPartners;
    _isLoading = false;

    if (kDebugMode) {
      print('⚡ Restored member-profile snapshot (${age.inSeconds}s old)');
    }
    return true;
  }

  void _saveSessionSnapshot() {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) return;

    _sessionSnapshots[user.id] = _MemberProfileSnapshot(
      capturedAt: DateTime.now(),
      profilePhotoUrl: _profilePhotoUrl,
      name: _nameController.text,
      surname: _surnameController.text,
      email: _emailController.text,
      street: _streetController.text,
      suburb: _suburbController.text,
      contact: _contactController.text,
      gender: _selectedGender,
      ethnicity: _selectedEthnicity,
      province: _selectedProvince,
      city: _selectedCity,
      dateOfBirth: _selectedDate,
      isTpMember: _isTpMember,
      trustedPartners: List<Map<String, dynamic>>.from(_trustedPartners),
    );
  }

  Future<void> _loadUserProfile({bool showLoading = true}) async {
    try {
      if (showLoading) {
        setState(() => _isLoading = true);
      }

      // First check if user is authenticated
      final currentUser = SupabaseService.instance.getCurrentUser();
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please sign in to access your profile'),
            ),
          );
          Navigator.of(context).pop(); // Go back to previous screen
        }
        return;
      }

      if (kDebugMode) {
        print('Loading profile for user: ${currentUser.email}');
      }
      if (kDebugMode) {
        print('User ID: ${currentUser.id}');
      }
      if (kDebugMode) {
        print(
          'User role from auth metadata: ${currentUser.userMetadata?['user_type']}',
        );
      }

      // Debug: Check what profile data exists
      await SupabaseService.instance.debugUserProfile();

      final supabaseService = SupabaseService.instance;
      final profileData = await supabaseService.getUserProfile();

      if (kDebugMode) {
        print('Raw profile data from database: $profileData');
      }

      if (profileData != null) {
        // Profile exists, load all the data that matches signup fields
        if (kDebugMode) {
          print('Profile found, loading data...');
        }
        if (kDebugMode) {
          print('Profile data: $profileData');
        }

        // Update all form fields with loaded data
        setState(() {
          // Personal Information
          _profilePhotoUrl = profileData['profile_photo_url'] as String?;
          _profilePhotoBytes = null;
          _nameController.text = profileData['name'] ?? '';
          _surnameController.text = profileData['surname'] ?? '';
          _emailController.text = profileData['email'] ?? '';

          // Security Information - in_app_password removed

          // Address Information
          _streetController.text = profileData['street'] ?? '';
          _suburbController.text = profileData['suburb'] ?? '';

          // Contact Information
          _contactController.text = profileData['contact'] ?? '';

          // Trusted Partner Member Information
          _isTpMember = profileData['is_tp_member'] ?? false;

          // Personal Details - ensure values are valid for dropdowns
          _selectedGender = _validateDropdownValue(
            profileData['gender'],
            _genders,
          );
          _selectedEthnicity = _validateDropdownValue(
            profileData['ethnicity'],
            _ethnicities,
          );
          _selectedProvince = _validateDropdownValue(
            profileData['province'],
            _provinces,
          );

          // Initialize city from profile data
          final loadedCity = profileData['city'] as String?;
          if (loadedCity != null && loadedCity.isNotEmpty) {
            if (_selectedProvince != null &&
                (_citiesByProvince[_selectedProvince!] ?? []).contains(loadedCity)) {
              _selectedCity = loadedCity;
            } else {
              // Province might not match, try to find the right province
              for (final entry in _citiesByProvince.entries) {
                if (entry.value.contains(loadedCity)) {
                  _selectedProvince = entry.key;
                  _selectedCity = loadedCity;
                  break;
                }
              }
            }
          }

          // Parse date of birth if it exists
          if (profileData['date_of_birth'] != null) {
            try {
              _selectedDate = DateTime.parse(profileData['date_of_birth']);
            } catch (e) {
              if (kDebugMode) {
                print('Error parsing date of birth: $e');
              }
              _selectedDate = null;
            }
          }
        });

        // Ensure form rebuilds with new data
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _formKey.currentState?.reset();
          }
        });

        if (kDebugMode) {
          print(
            'Profile data successfully loaded and prefilled in form fields',
          );
        }
        if (kDebugMode) {
          print(
            'Name: ${_nameController.text}, Email: ${_emailController.text}',
          );
        }
        if (kDebugMode) {
          print('Gender: $_selectedGender, Province: $_selectedProvince');
        }
        // Load trusted partners after profile data
        await _loadMemberPartners(currentUser.id);
        _saveSessionSnapshot();
      } else {
        // Profile doesn't exist, create initial profile
        if (kDebugMode) {
          print('Profile not found, creating initial profile...');
        }
        final created = await supabaseService.createInitialUserProfile();

        if (created) {
          if (kDebugMode) {
            print('Initial profile created, loading data...');
          }
          // Try loading again after creation
          final newProfileData = await supabaseService.getUserProfile();
          if (newProfileData != null) {
            setState(() {
              // Personal Information
              _profilePhotoUrl = newProfileData['profile_photo_url'] as String?;
              _profilePhotoBytes = null;
              _nameController.text = newProfileData['name'] ?? '';
              _surnameController.text = newProfileData['surname'] ?? '';
              _emailController.text = newProfileData['email'] ?? '';

              // Address Information
              _streetController.text = newProfileData['street'] ?? '';
              _suburbController.text = newProfileData['suburb'] ?? '';

              // Contact Information
              _contactController.text = newProfileData['contact'] ?? '';

              // Personal Details - ensure values are valid for dropdowns
              _selectedGender = _validateDropdownValue(
                newProfileData['gender'],
                _genders,
              );
              _selectedEthnicity = _validateDropdownValue(
                newProfileData['ethnicity'],
                _ethnicities,
              );
              _selectedProvince = _validateDropdownValue(
                newProfileData['province'],
                _provinces,
              );

              // Initialize city from profile data
              final newCity = newProfileData['city'] as String?;
              if (newCity != null && newCity.isNotEmpty) {
                if (_selectedProvince != null &&
                    (_citiesByProvince[_selectedProvince!] ?? []).contains(newCity)) {
                  _selectedCity = newCity;
                } else {
                  for (final entry in _citiesByProvince.entries) {
                    if (entry.value.contains(newCity)) {
                      _selectedProvince = entry.key;
                      _selectedCity = newCity;
                      break;
                    }
                  }
                }
              }

              // Parse date of birth if it exists
              if (newProfileData['date_of_birth'] != null) {
                try {
                  _selectedDate = DateTime.parse(
                    newProfileData['date_of_birth'],
                  );
                } catch (e) {
                  if (kDebugMode) {
                    print('Error parsing date of birth: $e');
                  }
                  _selectedDate = null;
                }
              }
            });

            // Ensure form rebuilds with new data
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _formKey.currentState?.reset();
              }
            });

            if (kDebugMode) {
              print('Initial profile data successfully loaded and prefilled');
            }
            if (kDebugMode) {
              print(
                'Name: ${_nameController.text}, Email: ${_emailController.text}',
              );
            }
            _saveSessionSnapshot();
          } else {
            if (kDebugMode) {
              print('Failed to load profile after creation');
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to load profile after creation'),
                ),
              );
            }
          }
        } else {
          if (kDebugMode) {
            print('Failed to create initial profile');
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to create profile')),
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading user profile: $e');
      }
      _logger.e('Error loading user profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMemberPartners(String userId) async {
    try {
      setState(() => _isLoadingPartners = true);
      final cacheService = CacheService.instance;

      // Try to get from cache first for instant display
      final cachedPartners = cacheService.getCachedMemberPartners(userId);
      if (cachedPartners != null) {
        if (kDebugMode) {
          print(
            '⚡ Using cached partners for member: $userId (${cachedPartners.length} partners)',
          );
        }
        if (mounted) {
          setState(() {
            _trustedPartners = cachedPartners;
          });
        }
        // Continue loading in background to refresh cache
      }

      final client = SupabaseService.instance.client;

      if (kDebugMode) {
        print('🔄 Loading trusted partners for member: $userId');
      }
      final startTime = DateTime.now();

      // Optimized: Use a single query with JOIN to get businesses directly
      // This replaces two sequential queries (deal_authorizations then businesses)
      final bizRows = await client
          .from('deal_authorizations')
          .select('businesses!inner(id,name,owner_member_id,logo_url)')
          .eq('member_id', userId);

      final duration = DateTime.now().difference(startTime);
      if (kDebugMode) {
        print(
          '✅ Loaded ${bizRows.length} partner authorizations in ${duration.inMilliseconds}ms',
        );
      }

      // Extract unique businesses from the results
      final uniqueBusinesses = <String, Map<String, dynamic>>{};
      for (final row in (bizRows as List<dynamic>)) {
        final m = row as Map<String, dynamic>;
        final biz = m['businesses'] as Map<String, dynamic>?;
        if (biz != null) {
          final bizId = biz['id'] as String?;
          if (bizId != null && bizId.isNotEmpty) {
            uniqueBusinesses[bizId] = biz;
          }
        }
      }

      final partners = uniqueBusinesses.values.toList();

      // Cache the results for next time
      cacheService.cacheMemberPartners(userId, partners);

      if (kDebugMode) {
        print('📊 Found ${partners.length} unique trusted partners');
      }

      if (mounted) {
        setState(() {
          _trustedPartners = partners;
        });
        _saveSessionSnapshot();
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to load member partners: $e');
      }
      _logger.e('Failed to load member partners: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingPartners = false);
      }
    }
  }

  Future<void> _openPartnerChat(Map<String, dynamic> business) async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) throw Exception('Not authenticated');
      final partnerUserId = business['owner_member_id'] as String?;
      if (partnerUserId == null || partnerUserId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Partner account is not yet linked.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final convo = await ChatService.instance
          .getOrCreateConversationWithPartner(user.id, partnerUserId);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) {
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 520,
              height: 640,
              child: ChatThreadPage(conversationId: convo.id),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open chat: $e')));
      }
    }
  }

  // Helper method to validate dropdown values
  String? _validateDropdownValue(String? value, List<String> validOptions) {
    if (value == null || value.isEmpty) return null;
    return validOptions.contains(value) ? value : null;
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _selectedDate ??
          DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _showDobValidationError = false;
      });
    }
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1200,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (!mounted) return;

      setState(() {
        _profilePhotoBytes = bytes;
      });
    } catch (e) {
      _logger.e('Error picking profile photo: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load selected image: $e')),
      );
    }
  }

  Future<String?> _uploadProfilePhoto(String userId) async {
    if (_profilePhotoBytes == null || _profilePhotoBytes!.isEmpty) {
      return _profilePhotoUrl;
    }

    final path = '$userId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return SupabaseService.instance.uploadImage(
      bucket: 'member-profile-photos',
      path: path,
      bytes: _profilePhotoBytes!,
      contentType: 'image/jpeg',
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDate == null) {
      setState(() => _showDobValidationError = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please complete required field: Date of Birth'),
          ),
        );
      }
      return;
    }

    setState(() => _showDobValidationError = false);

    try {
      setState(() => _isSaving = true);

      final supabaseService = SupabaseService.instance;
      final currentUser = supabaseService.client.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      final uploadedProfilePhotoUrl = await _uploadProfilePhoto(currentUser.id);

      // Save ALL profile fields that match what is stored in Supabase during signup
      final profileData = {
        // Personal Information (matches signup)
        'name': _nameController.text.trim(),
        'surname': _surnameController.text.trim(),
        'profile_photo_url': uploadedProfilePhotoUrl,

        // Security Information removed: in_app_password deprecated

        // Address Information (matches signup)
        'street': _streetController.text.trim(),
        'suburb': _suburbController.text.trim(),
        'city': _selectedCity ?? '',

        // Contact Information (matches signup)
        'contact': _contactController.text.trim(),

        // Personal Details (matches signup)
        'gender': _selectedGender,
        'ethnicity': _selectedEthnicity,
        'province': _selectedProvince,
        'date_of_birth': _selectedDate?.toIso8601String().split('T').first,

        // Note: TP member banking details are NOT needed here
        // Payment method will be saved to Paystack after first purchase
      };

      if (kDebugMode) {
        print(
          'Saving complete profile data (matching signup fields): $profileData',
        );
      }

      final updated = await supabaseService.updateUserProfile(
        userId: currentUser.id,
        profileData: profileData,
      );

      if (!updated) {
        throw Exception('Profile update failed');
      }

      final refreshedProfile = await supabaseService.getUserProfile();
      if (refreshedProfile == null) {
        throw Exception('Profile update did not persist to the database');
      }

      final expectedProfile = <String, String?>{
        'name': profileData['name']?.toString(),
        'surname': profileData['surname']?.toString(),
        'street': profileData['street']?.toString(),
        'suburb': profileData['suburb']?.toString(),
        'city': profileData['city']?.toString(),
        'contact': profileData['contact']?.toString(),
        'gender': profileData['gender']?.toString(),
        'ethnicity': profileData['ethnicity']?.toString(),
        'province': profileData['province']?.toString(),
        'date_of_birth': profileData['date_of_birth']?.toString(),
      };
      final mismatches = <String>[];
      expectedProfile.forEach((field, expected) {
        final actual = refreshedProfile[field]?.toString().trim();
        final normalizedExpected = expected?.trim();

        if (normalizedExpected == null || normalizedExpected.isEmpty) {
          // If no value was expected for this field, do not enforce empty.
          // Update payloads may intentionally omit nullable fields, in which
          // case the database can retain a previous non-empty value.
          return;
        }

        if (field == 'date_of_birth') {
          final actualDate = actual?.split('T').first;
          if (actualDate == null || actualDate.isEmpty) {
            // In fallback mode, DOB may be skipped by server-side profile RPC.
            // Do not fail the entire save if other fields persisted.
            return;
          }
          if (actualDate != normalizedExpected) {
            mismatches.add('$field expected "$normalizedExpected" but was "$actual"');
          }
          return;
        }

        if (actual != normalizedExpected) {
          mismatches.add('$field expected "$normalizedExpected" but was "$actual"');
        }
      });

      if (mismatches.isNotEmpty) {
        throw Exception(
          'Some profile fields did not persist: ${mismatches.join(', ')}',
        );
      }

      _saveSessionSnapshot();
  _profilePhotoUrl = uploadedProfilePhotoUrl;
  _profilePhotoBytes = null;

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );

        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop(true);
        } else {
          // When this page is the root route (e.g. first-run profile completion),
          // popping would leave a blank/black screen. Route to the proper home flow.
          await NavigationService().navigateToHomeAfterAuth(context);
        }
      }
    } catch (e) {
      _logger.e('Error saving user profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: BrandedAppBar(title: const Text('User Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('User Profile'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildSectionHeader('Profile Photo'),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _isSaving ? null : _pickProfilePhoto,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        ProfilePhoto(
                          imageUrl: _profilePhotoUrl,
                          memoryBytes: _profilePhotoBytes,
                          displayName:
                              '${_nameController.text} ${_surnameController.text}'.trim(),
                          size: 88,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Upload a square or portrait photo so it fits the member header area cleanly.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isSaving ? null : _pickProfilePhoto,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: Text(
                              _profilePhotoUrl?.trim().isNotEmpty == true ||
                                      _profilePhotoBytes != null
                                  ? 'Change Profile Photo'
                                  : 'Upload Profile Photo',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Debug info (remove in production)
              if (_nameController.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Profile loaded for: ${_emailController.text}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

              // Personal Information Section
              _buildSectionHeader('Personal Information'),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter your name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _surnameController,
                decoration: const InputDecoration(
                  labelText: 'Surname',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter your surname' : null,
              ),
              const SizedBox(height: 16),

              // Personal Details Section
              _buildSectionHeader('Personal Details'),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Date of Birth',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedDate == null
                                ? 'No date selected'
                                : 'Selected: ${_selectedDate!.toLocal().toString().split(' ')[0]}',
                          ),
                        ),
                        TextButton(
                          onPressed: _selectDate,
                          child: const Text('Pick Date'),
                        ),
                      ],
                    ),
                    if (_showDobValidationError)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Please select your date of birth',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedGender,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  border: OutlineInputBorder(),
                ),
                items: _genders.map((gender) {
                  return DropdownMenuItem(value: gender, child: Text(gender));
                }).toList(),
                onChanged: (value) => setState(() => _selectedGender = value),
                validator: (value) =>
                    value == null ? 'Please select your gender' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedEthnicity,
                decoration: const InputDecoration(
                  labelText: 'Ethnicity',
                  border: OutlineInputBorder(),
                ),
                items: _ethnicities.map((ethnicity) {
                  return DropdownMenuItem(
                    value: ethnicity,
                    child: Text(ethnicity),
                  );
                }).toList(),
                onChanged: (value) =>
                    setState(() => _selectedEthnicity = value),
                validator: (value) =>
                    value == null ? 'Please select your ethnicity' : null,
              ),
              const SizedBox(height: 16),

              // Address Information Section
              _buildSectionHeader('Address Information'),
              DropdownButtonFormField<String>(
                initialValue: _selectedProvince,
                decoration: const InputDecoration(
                  labelText: 'Province',
                  border: OutlineInputBorder(),
                ),
                items: _provinces.map((province) {
                  return DropdownMenuItem(
                    value: province,
                    child: Text(province),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedProvince = value;
                    _selectedCity = null;
                  });
                },
                validator: (value) =>
                    value == null ? 'Please select your province' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedProvince),
                initialValue: _selectedCity,
                decoration: const InputDecoration(
                  labelText: 'City',
                  border: OutlineInputBorder(),
                ),
                items: (_selectedProvince != null
                        ? _citiesByProvince[_selectedProvince!] ?? <String>[]
                        : <String>[])
                    .map((city) {
                  return DropdownMenuItem(
                    value: city,
                    child: Text(city),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedCity = value),
                validator: (value) =>
                    value == null ? 'Please select your city' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _suburbController,
                decoration: const InputDecoration(
                  labelText: 'Suburb',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter your suburb' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _streetController,
                decoration: const InputDecoration(
                  labelText: 'Street Address',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty ?? true
                    ? 'Please enter your street address'
                    : null,
              ),
              const SizedBox(height: 16),

              // Contact Information Section
              _buildSectionHeader('Contact Information'),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(
                  labelText: 'Contact Number',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) => value?.isEmpty ?? true
                    ? 'Please enter your contact number'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                readOnly: true, // Email is not editable
                enabled: false,
              ),
              const SizedBox(height: 24),

              // Security Section (Change Password via OTP)
              _buildSectionHeader('Security'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Update your account password. You\'ll verify with a one-time code sent to your email before changing it.',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const ChangePasswordPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.lock_reset),
                        label: const Text('Change Password'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Theme.of(context).primaryColor,
                          ),
                          foregroundColor: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Receipt Book Section
              _buildSectionHeader('Receipt Management'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chat directly with your trusted partners you\'ve interacted with.',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const ReceiptBookPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('Open Receipt Book'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Theme.of(context).primaryColor,
                          ),
                          foregroundColor: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Promo Key Activation Section
              if (!_isTpMember) ...[  
                _buildSectionHeader('Promo Key'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'If you have a promo key, activate your membership for free. '
                        'Your QR code will be activated immediately and you can start making purchases.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final user = SupabaseService.instance.getCurrentUser();
                            if (user == null) return;
                            showDialog(
                              context: context,
                              builder: (context) => TrustedPartnerKeyDialog(
                                userId: user.id,
                                onSuccess: () {
                                  setState(() => _isTpMember = true);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Membership activated! Your QR code is now active.'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                          icon: const Icon(Icons.vpn_key),
                          label: const Text('Insert Promo Key'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Trusted Partners Section
              _buildSectionHeader('Trusted Partners'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Chat directly with your trusted partners you've interacted with.",
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    if (_isLoadingPartners)
                      const Center(child: CircularProgressIndicator())
                    else if (_trustedPartners.isEmpty)
                      const Text(
                        'No partners yet. Complete a deal to connect.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      )
                    else
                      Column(
                        children: _trustedPartners.map((biz) {
                          final name = (biz['name'] as String?) ?? 'Partner';
                          final logo = biz['logo_url'] as String?;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: logo != null && logo.isNotEmpty
                                ? CircleAvatar(
                                    backgroundImage: NetworkImage(logo),
                                  )
                                : const CircleAvatar(child: Icon(Icons.store)),
                            title: Text(name),
                            trailing: IconButton(
                              tooltip: 'Chat',
                              icon: const Icon(Icons.chat_bubble),
                              onPressed: () => _openPartnerChat(biz),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Payment Methods Section
              _buildSectionHeader('Banking Details'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manage your banking details for payments and refunds.',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: OutlinedButton.icon(
                        onPressed: () => _showBankingDetailsDialog(context),
                        icon: const Icon(Icons.account_balance),
                        label: const Text('Edit Banking Details'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Theme.of(context).primaryColor,
                          ),
                          foregroundColor: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'View notifications about your deal authorizations and payments.',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const NotificationsPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.notifications),
                        label: const Text('View Notifications'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Theme.of(context).primaryColor,
                          ),
                          foregroundColor: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Profile Changes'),
                ),
              ),
              const SizedBox(height: 24),

              // Deactivate Account Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.red.shade50,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Deactivate Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Deactivate your membership to stop receiving discounts and disable your QR codes.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: OutlinedButton.icon(
                        onPressed: _showDeactivationConfirmation,
                        icon: Icon(Icons.block, color: Colors.red.shade700),
                        label: Text(
                          'Deactivate Account',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.red.shade700),
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

  Future<void> _showDeactivationConfirmation() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => DeactivationConfirmationPage(
          userType: 'member',
          onConfirm: _deactivateMemberAccount,
        ),
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deactivated successfully'),
          backgroundColor: Colors.green,
        ),
      );
      // Navigate to welcome page (user is now logged out)
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  Future<void> _deactivateMemberAccount(String reason) async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) throw Exception('No authenticated user');

      final adminService = AdminService();
      await adminService.deactivateMember(user.id, reason: reason);

      _logger.i(
        'Member account deactivated for user: ${user.id} with reason: $reason',
      );

      // Sign out the user immediately after deactivation
      await SupabaseService.instance.signOut();
      _logger.i('User signed out after deactivation');
    } catch (e) {
      _logger.e('Error deactivating member: $e');
      rethrow;
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  void _showBankingDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => MemberBankingDetailsDialog(
        onDetailsSaved: () {
          // Refresh profile data if needed
          _loadUserProfile();
        },
      ),
    );
  }
}

class MemberBankingDetailsDialog extends StatefulWidget {
  final VoidCallback? onDetailsSaved;

  const MemberBankingDetailsDialog({super.key, this.onDetailsSaved});

  @override
  State<MemberBankingDetailsDialog> createState() =>
      _MemberBankingDetailsDialogState();
}

class _MemberBankingDetailsDialogState
    extends State<MemberBankingDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;

  // Payment method selection
  String _selectedPaymentMethod = 'credit_card'; // 'credit_card' or 'banking'

  // Credit Card fields
  final _cardNumberController = TextEditingController();
  final _cardExpiryController = TextEditingController();
  final _cardCvvController = TextEditingController();
  final _cardHolderNameController = TextEditingController();

  // Banking fields
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _branchCodeController = TextEditingController();
  String? _selectedAccountType;

  final List<String> _banks = [
    'Absa Bank',
    'Access Bank',
    'African Bank',
    'African Business Bank',
    'Albaraka Bank',
    'Bank of China',
    'Bank Zero',
    'Bidvest Bank',
    'Capitec Bank',
    'Capitec Business',
    'CitiBank',
    'Discovery Bank',
    'Finbond EPE',
    'Finbond Mutual Bank',
    'FNB',
    'FirstRand Bank',
    'HBZ Bank',
    'HSBC',
    'Investec',
    'JP Morgan',
    'Nedbank',
    'Olympus Mobile',
    'OM Bank',
    'Rand Merchant Bank',
    'RMB Private Bank',
    'SASFIN Bank',
    'Société Générale',
    'South African Bank of Athens',
    'Standard Bank',
    'Standard Chartered',
    'TymeBank',
    'Ubank',
    'VBS Mutual Bank',
    'Other',
  ];

  final List<String> _accountTypes = ['savings', 'checking'];

  @override
  void initState() {
    super.initState();
    _loadExistingDetails();
  }

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    _cardHolderNameController.dispose();
    _accountNameController.dispose();
    _accountNumberController.dispose();
    _bankNameController.dispose();
    _branchCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingDetails() async {
    try {
      setState(() => _isLoading = true);

      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      // Load existing banking details from members_bank_accounts
      final bankingResponse = await SupabaseService.instance.client
          .from('members_bank_accounts')
          .select(
            'account_holder_name, bank_name, account_type, account_number, branch_code, paystack_recipient_code',
          )
          .eq('user_id', user.id)
          .eq('is_active', true)
          .maybeSingle();

      if (bankingResponse != null && mounted) {
        setState(() {
          _selectedPaymentMethod = 'banking';
          _accountNameController.text =
              bankingResponse['account_holder_name'] ?? '';
          _bankNameController.text = bankingResponse['bank_name'] ?? '';
          _accountNumberController.text =
              bankingResponse['account_number'] ?? '';
          _branchCodeController.text = bankingResponse['branch_code'] ?? '';
          _selectedAccountType = bankingResponse['account_type'] ?? 'savings';
        });
      } else {
        // Check for credit card details from members_card_details table
        final cardResponse = await SupabaseService.instance.client
            .from('members_card_details')
            .select('last4, brand, exp_month, exp_year, bank, is_primary')
            .eq('user_id', user.id)
            .eq('is_active', true)
            .order('is_primary', ascending: false)
            .limit(1)
            .maybeSingle();

        if (cardResponse != null && mounted) {
          setState(() {
            _selectedPaymentMethod = 'credit_card';
            _cardNumberController.text =
                '**** **** **** ${cardResponse['last4'] ?? '****'}';
            // Note: Full card details are stored in Paystack, not locally
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading banking details: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AlertDialog(
      title: const Text('Banking Details'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose your preferred payment method for subscriptions and purchases.',
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 16),

              // Payment Method Selection
              const Text(
                'Payment Method',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Credit Card'),
                      value: 'credit_card',
                      groupValue: _selectedPaymentMethod,
                      onChanged: (value) {
                        setState(() {
                          _selectedPaymentMethod = value!;
                        });
                      },
                      toggleable: true,
                      dense: true,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Banking Details'),
                      value: 'banking',
                      groupValue: _selectedPaymentMethod,
                      onChanged: (value) {
                        setState(() {
                          _selectedPaymentMethod = value!;
                        });
                      },
                      toggleable: true,
                      dense: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Credit Card Fields
              if (_selectedPaymentMethod == 'credit_card') ...[
                const Text(
                  'Add Credit/Debit Card',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'To add a card for payments and renewals, use the secure Paystack payment page.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    // Initialize Paystack payment for card tokenization
                    try {
                      final user = SupabaseService.instance.getCurrentUser();
                      if (user == null) {
                        throw Exception('No authenticated user');
                      }

                      setState(() => _isSaving = true);

                      final paystackService = PaystackService();

                      // Enforce the saved-cards limit BEFORE initializing the
                      // R1 tokenization charge, so members at the limit aren't
                      // charged for a card that then fails to save.
                      final cardCount = await paystackService
                          .getActiveCardCount(user.id);
                      if (cardCount >= PaystackService.maxSavedCards) {
                        setState(() => _isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'You can only save up to '
                                '${PaystackService.maxSavedCards} cards. '
                                'Delete a card first to add a new one.',
                              ),
                              backgroundColor: Colors.orange.shade800,
                            ),
                          );
                        }
                        return;
                      }

                      final authUrl = await paystackService
                          .initializePaymentMethod(
                            userId: user.id,
                            userEmail: user.email ?? '',
                            amount: 100, // R1.00 for tokenization
                          );

                      setState(() => _isSaving = false);

                      if (authUrl != null) {
                        if (kIsWeb) {
                          final opened = await openWebCheckout(authUrl);
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not open the secure payment page. Please try again.',
                                ),
                              ),
                            );
                          }
                          return;
                        }

                        Navigator.of(context).pop(); // Close current dialog
                        if (!mounted) return;
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PaymentMethodWebViewPage(
                              authorizationUrl: authUrl,
                              userId: user.id,
                              userEmail: user.email ?? '',
                            ),
                          ),
                        );
                        if (result == true && widget.onDetailsSaved != null) {
                          widget.onDetailsSaved!();
                        }
                      } else {
                        throw Exception('Failed to initialize payment');
                      }
                    } catch (e) {
                      setState(() => _isSaving = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to initialize card setup: $e',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.credit_card),
                  label: Text(
                    _isSaving ? 'Initializing...' : 'Add Card via Secure Page',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This opens Paystack\'s secure payment page for 3D Secure verification.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black45,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                /*
                // OLD DIRECT INPUT - Commented out as it doesn't support 3D Secure
                TextFormField(
                  controller: _cardHolderNameController,
                  decoration: const InputDecoration(
                    labelText: 'Card Holder Name',
                    hintText: 'Name on card',
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Please enter card holder name'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cardNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Card Number',
                    hintText: '1234 5678 9012 3456',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => v == null || v.isEmpty
                      ? 'Please enter card number'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cardExpiryController,
                        decoration: const InputDecoration(
                          labelText: 'Expiry Date',
                          hintText: 'MM/YY',
                        ),
                        inputFormatters: [ExpiryDateInputFormatter()],
                        keyboardType: TextInputType.number,
                        validator: (v) => v == null || v.isEmpty
                            ? 'Please enter expiry date'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _cardCvvController,
                        decoration: const InputDecoration(
                          labelText: 'CVV',
                          hintText: '123',
                        ),
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Please enter CVV' : null,
                      ),
                    ),
                  ],
                ),
                */
              ],

              // Banking Fields
              if (_selectedPaymentMethod == 'banking') ...[
                const Text(
                  'Banking Details',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accountNameController,
                  decoration: const InputDecoration(
                    labelText: 'Account Holder Name',
                    hintText: 'Business account holder name',
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Please enter account holder name'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _bankNameController.text.isEmpty
                      ? null
                      : _bankNameController.text,
                  decoration: const InputDecoration(labelText: 'Bank Name'),
                  items: _banks
                      .map(
                        (bank) =>
                            DropdownMenuItem(value: bank, child: Text(bank)),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _bankNameController.text = value ?? '';
                    });
                  },
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Please select your bank' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedAccountType,
                  decoration: const InputDecoration(labelText: 'Account Type'),
                  items: _accountTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(
                            type == 'savings'
                                ? 'Savings Account'
                                : 'Checking Account',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedAccountType = value;
                    });
                  },
                  validator: (v) => v == null || v.isEmpty
                      ? 'Please select account type'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accountNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Account Number',
                    hintText: 'Your account number',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => v == null || v.isEmpty
                      ? 'Please enter account number'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _branchCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Branch Code',
                    hintText: '6-digit branch code',
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please enter branch code';
                    }
                    if (v.length != 6) return 'Branch code must be 6 digits';
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isSaving ? null : _testVerifyStoredCard,
          child: const Text('Test Cards'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveBankingDetails,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save Details'),
        ),
      ],
    );
  }

  Future<void> _saveBankingDetails() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) throw Exception('No authenticated user');

      if (_selectedPaymentMethod == 'credit_card') {
        // Handle credit card setup via Paystack
        await _saveCreditCardDetails(user.id);
      } else {
        // Handle banking details setup
        await _saveBankingDetailsToDatabase(user.id);
      }

      widget.onDetailsSaved?.call();

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Banking details saved successfully')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving banking details: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save banking details: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveCreditCardDetails(String userId) async {
    final paystackService = PaystackService();

    // Parse expiry date
    final expiryParts = _cardExpiryController.text.split('/');
    if (expiryParts.length != 2) {
      throw Exception('Invalid expiry date format. Use MM/YY');
    }

    final expMonth = expiryParts[0].trim();
    final expYear = expiryParts[1].trim();

    // Tokenize the card with Paystack
    final tokenizationResult = await paystackService.tokenizeCard(
      cardNumber: _cardNumberController.text.trim(),
      expiryMonth: expMonth,
      expiryYear: expYear,
      cvv: _cardCvvController.text.trim(),
      cardHolderName: _cardHolderNameController.text.trim(),
      userEmail: SupabaseService.instance.getCurrentUser()?.email ?? '',
      userId: userId,
    );

    if (tokenizationResult != null) {
      // Check if user already has a primary card
      final existingCard = await SupabaseService.instance.client
          .from('members_card_details')
          .select()
          .eq('user_id', userId)
          .eq('is_primary', true)
          .maybeSingle();

      final cardData = {
        'user_id': userId,
        'authorization_code': tokenizationResult['authorization_code'],
        'card_type': tokenizationResult['card_type'] ?? 'card',
        'last4': tokenizationResult['last4'],
        'exp_month': tokenizationResult['exp_month'],
        'exp_year': tokenizationResult['exp_year'],
        'bank': tokenizationResult['bank'] ?? '',
        'brand': tokenizationResult['brand'] ?? '',
        'is_primary': true, // Set as primary for now
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existingCard != null) {
        // Update existing primary card
        await SupabaseService.instance.client
            .from('members_card_details')
            .update(cardData)
            .eq('id', existingCard['id']);
      } else {
        // Insert new primary card
        cardData['created_at'] = DateTime.now().toIso8601String();
        await SupabaseService.instance.client
            .from('members_card_details')
            .insert(cardData);
      }

      if (kDebugMode) {
        print('Credit card tokenized and saved successfully');
      }
    } else {
      throw Exception('Failed to tokenize credit card');
    }
  }

  Future<void> _saveBankingDetailsToDatabase(String userId) async {
    // Create or update banking details for members
    final paystackService = PaystackService();

    // Get bank code from bank name
    final bankCode = _getBankCode(_bankNameController.text);

    if (kDebugMode) {
      print('Creating transfer recipient for member banking details...');
    }

    final recipientCode = await paystackService.createTransferRecipient(
      businessId:
          userId, // Use userId for members (no business association needed)
      businessName: _accountNameController.text,
      bankCode: bankCode,
      accountNumber: _accountNumberController.text.trim(),
      accountName: _accountNameController.text.trim(),
      accountType: _selectedAccountType ?? 'savings',
      isMember: true, // Flag to indicate this is for a member, not a business
    );

    if (recipientCode != null) {
      // Mask account number for security
      final maskedAccountNumber = _maskAccountNumber(
        _accountNumberController.text.trim(),
      );

      // Check if user already has an active bank account
      final existingAccount = await SupabaseService.instance.client
          .from('members_bank_accounts')
          .select()
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle();

      final accountData = {
        'user_id': userId,
        'account_holder_name': _accountNameController.text.trim(),
        'bank_name': _bankNameController.text,
        'account_type': _selectedAccountType,
        'account_number': maskedAccountNumber, // Store masked version
        'branch_code': _branchCodeController.text.trim(),
        'paystack_recipient_code': recipientCode,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existingAccount != null) {
        // Update existing active account
        await SupabaseService.instance.client
            .from('members_bank_accounts')
            .update(accountData)
            .eq('id', existingAccount['id']);
      } else {
        // Insert new active account
        accountData['created_at'] = DateTime.now().toIso8601String();
        await SupabaseService.instance.client
            .from('members_bank_accounts')
            .insert(accountData);
      }

      if (kDebugMode) {
        print(
          'Member banking details saved to members_bank_accounts successfully',
        );
      }
    } else {
      throw Exception('Failed to create transfer recipient');
    }
  }

  String _maskAccountNumber(String accountNumber) {
    if (accountNumber.length <= 4) {
      return accountNumber;
    }
    final lastFour = accountNumber.substring(accountNumber.length - 4);
    final maskedLength = accountNumber.length - 4;
    final mask = 'x' * maskedLength;
    return '$mask$lastFour';
  }

  String _getBankCode(String bankName) {
    switch (bankName.toLowerCase()) {
      case 'absa bank':
        return '632005';
      case 'access bank':
        return '410506';
      case 'african bank':
        return '430000';
      case 'african business bank':
        return '584000';
      case 'albaraka bank':
        return '800000';
      case 'bank of china':
        return '686000';
      case 'bank zero':
        return '888000';
      case 'bidvest bank':
        return '462005';
      case 'capitec bank':
        return '470010';
      case 'capitec business':
        return '450105';
      case 'citibank':
        return '350005';
      case 'discovery bank':
        return '679000';
      case 'finbond epe':
        return '591000';
      case 'finbond mutual bank':
        return '589000';
      case 'fnb':
        return '250655';
      case 'firstrand bank':
        return '201419';
      case 'hbz bank':
        return '570226';
      case 'hsbc':
        return '587000';
      case 'investec':
        return '580105';
      case 'jp morgan':
        return '432000';
      case 'nedbank':
        return '198765';
      case 'olympus mobile':
        return '585001';
      case 'om bank':
        return '352000';
      case 'rand merchant bank':
        return '261251';
      case 'rmb private bank':
        return '222026';
      case 'sasfin bank':
        return '683000';
      case 'société générale':
        return '351005';
      case 'south african bank of athens':
        return '410105';
      case 'standard bank':
        return '051001';
      case 'standard chartered':
        return '730020';
      case 'tymebank':
        return '678910';
      case 'ubank':
        return '431010';
      case 'vbs mutual bank':
        return '588000';
      default:
        return '632005'; // Default to Absa
    }
  }

  /// Test method to verify that stored card details are accessible in Paystack
  Future<void> _testVerifyStoredCard() async {
    try {
      final userId = SupabaseService.instance.getCurrentUser()?.id;
      if (userId == null) {
        if (kDebugMode) {
          print('No user ID available for testing card verification');
        }
        return;
      }

      // Query stored card details from database
      final response = await SupabaseService.instance.client
          .from('members_card_details')
          .select(
            'id, authorization_code, last4, card_type, brand, exp_month, exp_year',
          )
          .eq('user_id', userId)
          .eq('is_active', true);

      if (response.isEmpty) {
        if (kDebugMode) {
          print('No stored cards found for verification test');
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No stored cards found to test')),
        );
        return;
      }

      if (kDebugMode) {
        print('Found ${response.length} stored cards for verification');
      }

      // Test verification for each stored card
      for (final card in response) {
        final authCode = card['authorization_code'] as String?;
        if (authCode != null && authCode.isNotEmpty) {
          if (kDebugMode) {
            print('Testing verification for card ending in ${card['last4']}');
          }
          final paystackService = PaystackService();
          final isValid = await paystackService.testVerifyStoredCard(authCode);
          if (kDebugMode) {
            print(
              'Card verification result for ****${card['last4']}: $isValid',
            );
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Card verification test completed - check logs'),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error testing card verification: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error testing verification: $e')));
    }
  }
}
