import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:logger/logger.dart';
import '../../core/constants/deal_categories.dart';
import '../../services/supabase_service.dart';
import 'package:local_lekker/core/theme/app_colors.dart';

/// Screen for admins to create a new Trusted Partner account.
class AdminAddPartnerScreen extends StatefulWidget {
  const AdminAddPartnerScreen({super.key});

  @override
  State<AdminAddPartnerScreen> createState() => _AdminAddPartnerScreenState();
}

class _AdminAddPartnerScreenState extends State<AdminAddPartnerScreen> {
  final _logger = Logger();
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _surnameCtrl = TextEditingController();
  final _businessNameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _produceDescriptionCtrl = TextEditingController();
  final _alcoholDescriptionCtrl = TextEditingController();
  final _sportsDescriptionCtrl = TextEditingController();

  String _selectedCategory = 'Restaurant';
  String? _selectedProvince;
  String? _selectedCity;
  bool _sellsFreshProduce = false;
  bool _sellsAlcohol = false;
  bool _offersSportsActivities = false;
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  static const _provinces = [
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

  static const _categories = [
    'Restaurant',
    'Retail',
    'Health & Beauty',
    'Automotive',
    'Entertainment',
    'Professional Services',
    'Food & Beverage',
    'Other',
  ];

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _surnameCtrl.dispose();
    _businessNameCtrl.dispose();
    _contactCtrl.dispose();
    _produceDescriptionCtrl.dispose();
    _alcoholDescriptionCtrl.dispose();
    _sportsDescriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final metadata = {
        'name': _nameCtrl.text.trim(),
        'surname': _surnameCtrl.text.trim(),
        'business_name': _businessNameCtrl.text.trim(),
        'category': _selectedCategory,
        'contact': _contactCtrl.text.trim(),
        'city': _selectedCity ?? '',
        'role': 'trusted_partner',
        'user_type': 'trusted_partner',
        'admin_created': true,
        'password_set': true,
        'sells_fresh_produce': _sellsFreshProduce,
        'sells_alcohol': _sellsAlcohol,
        'offers_sports_activities': _offersSportsActivities,
      };

      final result = await SupabaseService.instance.adminCreateTrustedPartner(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        metadata: metadata,
      );

      _logger.i('Create TP result: $result');

      if (!mounted) return;

      final ok = result['ok'] == true;
      if (ok) {
        // Account creation only makes the auth user; seed the businesses row so
        // the category and Fresh & Local flag are persisted immediately.
        final newUserId = result['user_id']?.toString();
        if (newUserId != null && newUserId.isNotEmpty) {
          try {
            await SupabaseService.instance.client.rpc(
              'admin_update_trusted_partner',
              params: {
                'payload': {
                  'partner_id': newUserId,
                  'name': _nameCtrl.text.trim(),
                  'surname': _surnameCtrl.text.trim(),
                  'email': _emailCtrl.text.trim().toLowerCase(),
                  'contact': _contactCtrl.text.trim(),
                  'city': _selectedCity ?? '',
                  'business_name': _businessNameCtrl.text.trim(),
                  'category': _selectedCategory,
                  'contact_number': _contactCtrl.text.trim(),
                  'contact_email': _emailCtrl.text.trim().toLowerCase(),
                  'sells_fresh_produce': _sellsFreshProduce,
                  'produce_description': _sellsFreshProduce
                      ? _produceDescriptionCtrl.text.trim()
                      : '',
                  'sells_alcohol': _sellsAlcohol,
                  'alcohol_description': _sellsAlcohol
                      ? _alcoholDescriptionCtrl.text.trim()
                      : '',
                  'offers_sports_activities': _offersSportsActivities,
                  'sports_description': _offersSportsActivities
                      ? _sportsDescriptionCtrl.text.trim()
                      : '',
                },
              },
            );
          } catch (e) {
            _logger.w('Business profile seeding failed for $newUserId: $e');
          }
        }

        var onboardingEmailSent = false;
        try {
          final emailResponse = await SupabaseService.instance.client.functions
              .invoke(
                'send-admin-created-tp-email',
                body: {
                  'email': _emailCtrl.text.trim().toLowerCase(),
                  'name': _nameCtrl.text.trim(),
                  'surname': _surnameCtrl.text.trim(),
                  'business_name': _businessNameCtrl.text.trim(),
                  'category': _selectedCategory,
                  'password': _passwordCtrl.text,
                },
              );
          final responseData = emailResponse.data;
          onboardingEmailSent = responseData is Map &&
              responseData['email_sent'] == true;
          if (!onboardingEmailSent) {
            _logger.w('Trusted Partner onboarding email was not sent: $responseData');
          }
        } catch (e) {
          _logger.w('Trusted Partner onboarding email failed: $e');
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trusted Partner created successfully'),
            backgroundColor: AppColors.primary,
          ),
        );
        if (!onboardingEmailSent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Account created, but the onboarding email could not be sent.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        Navigator.pop(context, true); // Return true to trigger refresh
      } else {
        final error = result['error']?.toString() ?? 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      _logger.e('Error creating TP: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Add Trusted Partner'),
        centerTitle: false,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Account Section ──
              _SectionHeader(title: 'Account Details'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('Email', Icons.email_outlined),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                decoration: _inputDecoration('Password', Icons.lock_outlined).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 6) return 'At least 6 characters';
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // ── Owner Section ──
              _SectionHeader(title: 'Owner Information'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDecoration('First Name', Icons.person_outlined),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _surnameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDecoration('Surname', Icons.person_outlined),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactCtrl,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration('Contact Number', Icons.phone_outlined),
              ),

              const SizedBox(height: 24),

              // ── Business Section ──
              _SectionHeader(title: 'Business Information'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _businessNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration('Business Name', Icons.store_outlined),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Business name is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: _inputDecoration('Category', Icons.category_outlined),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedCategory = v);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedProvince,
                decoration: _inputDecoration('Province', Icons.map_outlined),
                items: _provinces
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedProvince = v;
                    _selectedCity = null;
                  });
                },
                validator: (v) => v == null ? 'Please select a province' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedProvince),
                value: _selectedCity,
                decoration: _inputDecoration('City', Icons.location_city_outlined),
                items: (_selectedProvince != null
                        ? _citiesByProvince[_selectedProvince!] ?? <String>[]
                        : <String>[])
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCity = v),
                validator: (v) => v == null ? 'Please select a city' : null,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _sellsFreshProduce,
                      secondary: Icon(Icons.eco, color: Colors.green.shade700),
                      title: const Text('$kFreshLocalCategory produce'),
                      subtitle: const Text(
                        'Lists this partner under the members\' Fresh & Local tab',
                      ),
                      onChanged: (v) =>
                          setState(() => _sellsFreshProduce = v ?? false),
                    ),
                    if (_sellsFreshProduce)
                      TextFormField(
                        controller: _produceDescriptionCtrl,
                        maxLines: 2,
                        maxLength: 200,
                        decoration: _inputDecoration(
                          'What do they sell?',
                          Icons.shopping_basket_outlined,
                        ),
                        validator: (v) {
                          if (!_sellsFreshProduce) return null;
                          return (v == null || v.trim().isEmpty)
                              ? 'Describe the produce they sell'
                              : null;
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7EDEF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0C2C7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _sellsAlcohol,
                      secondary: const Icon(
                        Icons.wine_bar,
                        color: Color(0xFF722F37),
                      ),
                      title: const Text('$kLocalSipsCategory (alcohol)'),
                      subtitle: const Text(
                        'Locally produced wines, beers and spirits. Age restricted (18+).',
                      ),
                      onChanged: (v) =>
                          setState(() => _sellsAlcohol = v ?? false),
                    ),
                    if (_sellsAlcohol) ...[
                      TextFormField(
                        controller: _alcoholDescriptionCtrl,
                        maxLines: 2,
                        maxLength: 200,
                        decoration: _inputDecoration(
                          'What do they produce?',
                          Icons.liquor_outlined,
                        ),
                        validator: (v) {
                          if (!_sellsAlcohol) return null;
                          return (v == null || v.trim().isEmpty)
                              ? 'Describe the alcohol they produce'
                              : null;
                        },
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            Icons.info_outline,
                            size: 15,
                            color: Color(0xFF722F37),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Upload the national liquor / distribution licence '
                              'documents from Edit Partner once this partner has '
                              'been created.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF722F37),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE1F5FE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFB3E5FC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _offersSportsActivities,
                      secondary: const Icon(
                        Icons.sports_soccer,
                        color: Color(0xFF01579B),
                      ),
                      title: const Text('$kLocallyActiveCategory (sport/fitness)'),
                      subtitle: const Text(
                        'Lists this partner under the members\' Locally Active tab',
                      ),
                      onChanged: (v) =>
                          setState(() => _offersSportsActivities = v ?? false),
                    ),
                    if (_offersSportsActivities)
                      TextFormField(
                        controller: _sportsDescriptionCtrl,
                        maxLines: 2,
                        maxLength: 200,
                        decoration: _inputDecoration(
                          'What do they offer?',
                          Icons.fitness_center_outlined,
                        ),
                        validator: (v) {
                          if (!_offersSportsActivities) return null;
                          return (v == null || v.trim().isEmpty)
                              ? 'Describe the activities they offer'
                              : null;
                        },
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Submit ──
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.person_add),
                  label: Text(_isSubmitting ? 'Creating...' : 'Create Trusted Partner'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade700,
      ),
    );
  }
}
