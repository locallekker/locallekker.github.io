import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:logger/logger.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'business_profile_page.dart';
import '../../services/supabase_service.dart';
import 'widgets/otp_verification_dialog.dart';

class TrustedPartnerSignupPage extends StatefulWidget {
  const TrustedPartnerSignupPage({super.key});

  @override
  _TrustedPartnerSignupPageState createState() =>
      _TrustedPartnerSignupPageState();
}

class _TrustedPartnerSignupPageState extends State<TrustedPartnerSignupPage> {
  DateTime? _selectedDob;
  String? _selectedEthnicity;
  String? _selectedGender;
  final Logger _logger = Logger();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _businessNameController = TextEditingController();
  // business fields moved to a dedicated BusinessProfilePage
  final _streetController = TextEditingController();
  final _suburbController = TextEditingController();
  String? _selectedCity;
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Logo upload
  XFile? _selectedLogo;
  final ImagePicker _picker = ImagePicker();

  final List<String> _ethnicities = [
    'Black African',
    'Coloured',
    'Indian/Asian',
    'White',
    'Other',
  ];
  final List<String> _genders = [
    'Male',
    'Female',
    'Other',
    'Prefer not to say',
  ];

  String? _selectedProvince;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  // business category moved to BusinessProfilePage
  // Latitude/longitude removed - not needed for signup
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

  final Map<String, List<String>> _citiesByProvince = {
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

  // For additional addresses
  final List<Map<String, TextEditingController>> _additionalAddresses = [];

  void _addAdditionalAddress() {
    setState(() {
      _additionalAddresses.add({
        'street': TextEditingController(),
        'suburb': TextEditingController(),
        'city': TextEditingController(),
        'province': TextEditingController(),
      });
    });
  }

  Future<void> _pickLogo() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedLogo = image;
        });
      }
    } catch (e) {
      _logger.e('Error picking logo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Widget> _buildAdditionalAddressFields() {
    final widgets = <Widget>[];
    for (var i = 0; i < _additionalAddresses.length; i++) {
      final addr = _additionalAddresses[i];
      widgets.add(const SizedBox(height: 12));
      widgets.add(
        Text(
          'Additional Address ${i + 1}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      widgets.add(
        TextFormField(
          controller: addr['street'],
          decoration: const InputDecoration(labelText: 'Street Address'),
          validator: (value) =>
              value?.isEmpty ?? true ? 'Please enter street address' : null,
        ),
      );
      widgets.add(
        TextFormField(
          controller: addr['suburb'],
          decoration: const InputDecoration(labelText: 'Suburb'),
          validator: (value) =>
              value?.isEmpty ?? true ? 'Please enter suburb' : null,
        ),
      );
      widgets.add(
        DropdownButtonFormField<String>(
          initialValue: addr['province']!.text.isEmpty
              ? null
              : addr['province']!.text,
          decoration: const InputDecoration(labelText: 'Province'),
          items: _provinces
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: (value) {
            setState(() {
              addr['province']!.text = value ?? '';
              addr['city']!.clear();
            });
          },
          validator: (value) =>
              value == null ? 'Please select a province' : null,
        ),
      );
      widgets.add(
        DropdownButtonFormField<String>(
          key: ValueKey('additional_city_${i}_${addr['province']!.text}'),
          initialValue: addr['city']!.text.isEmpty ? null : addr['city']!.text,
          decoration: const InputDecoration(labelText: 'City'),
          items:
              (_citiesByProvince[addr['province']!.text] ?? const <String>[])
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
          onChanged: (value) =>
              setState(() => addr['city']!.text = value ?? ''),
          validator: (value) => value == null ? 'Please select a city' : null,
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final hasMinimumPasswordLength = _passwordController.text.length >= 8;
    // Don't validate on every build - only when user submits or after first attempt
    return Scaffold(
      appBar: BrandedAppBar(title: const Text('Trusted Partner Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          autovalidateMode: _autovalidateMode,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter your name' : null,
              ),
              TextFormField(
                controller: _surnameController,
                decoration: const InputDecoration(labelText: 'Surname'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Please enter your surname' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _selectedGender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: _genders
                    .map(
                      (gender) =>
                          DropdownMenuItem(value: gender, child: Text(gender)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedGender = value),
                validator: (value) => value == null || value.isEmpty
                    ? 'Please select your gender'
                    : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _selectedEthnicity,
                decoration: const InputDecoration(labelText: 'Ethnicity'),
                items: _ethnicities
                    .map(
                      (ethnicity) => DropdownMenuItem(
                        value: ethnicity,
                        child: Text(ethnicity),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _selectedEthnicity = value),
                validator: (value) => value == null || value.isEmpty
                    ? 'Please select your ethnicity'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedDob == null
                          ? 'Select Date of Birth'
                          : 'DOB: ${_selectedDob!.day}/${_selectedDob!.month}/${_selectedDob!.year}',
                      style: TextStyle(
                        color: _selectedDob == null ? Colors.red : Colors.black,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _showDatePicker,
                    child: const Text('Pick Date'),
                  ),
                ],
              ),
              TextFormField(
                controller: _businessNameController,
                decoration: const InputDecoration(labelText: 'Business Name'),
                validator: (value) => value?.isEmpty ?? true
                    ? 'Please enter your business name'
                    : null,
              ),
              const SizedBox(height: 16),
              // Logo upload section
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
                      'Business Logo (Optional)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add your business logo to help members recognize your brand',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedLogo != null)
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_selectedLogo!.path),
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedLogo!.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _selectedLogo = null),
                                  icon: const Icon(Icons.delete, size: 16),
                                  label: const Text('Remove'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: const Text('Add Logo'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                  ],
                ),
              ),
              // Business fields moved to BusinessProfilePage after OTP
              const SizedBox(height: 12),
              const SizedBox(height: 16),
              const Text(
                'Primary Address (kept minimal)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              // keep minimal address on signup; detailed business address
              // moved to the BusinessProfilePage after OTP
              TextFormField(
                controller: _streetController,
                decoration: const InputDecoration(
                  labelText: 'Street Address (optional)',
                ),
              ),
              TextFormField(
                controller: _suburbController,
                decoration: const InputDecoration(
                  labelText: 'Suburb (optional)',
                ),
              ),
              DropdownButtonFormField<String>(
                value: _selectedProvince,
                decoration: const InputDecoration(
                  labelText: 'Province (optional)',
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
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedProvince),
                value: _selectedCity,
                decoration: const InputDecoration(labelText: 'City (optional)'),
                items:
                    (_selectedProvince != null
                            ? _citiesByProvince[_selectedProvince!] ?? []
                            : <String>[])
                        .map((city) {
                          return DropdownMenuItem(
                            value: city,
                            child: Text(city),
                          );
                        })
                        .toList(),
                onChanged: (value) => setState(() => _selectedCity = value),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _addAdditionalAddress,
                child: const Text('Add Additional Address'),
              ),
              ..._buildAdditionalAddressFields(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(
                  labelText: 'Contact Number (optional)',
                ),
                keyboardType: TextInputType.phone,
                // No validator - contact number is optional
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Please enter email';
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value!)) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: '${_passwordController.text.length}/8 characters',
                  helperStyle: TextStyle(
                    color: hasMinimumPasswordLength ? Colors.green : null,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: hasMinimumPasswordLength
                          ? Colors.green
                          : Colors.grey,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: hasMinimumPasswordLength
                          ? Colors.green
                          : Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
                obscureText: true,
                onChanged: (_) => setState(() {
                  if (_passwordController.text.length < 8) {
                    _confirmPasswordController.clear();
                  }
                }),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Please enter a password';
                  if (value!.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                ),
                obscureText: true,
                enabled: hasMinimumPasswordLength,
                validator: (value) {
                  if (value?.trim().isEmpty ?? true) {
                    return 'Please confirm your password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _createAccount,
                child: const Text('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createAccount() async {
    // Enable autovalidation after first submission attempt
    setState(() {
      _autovalidateMode = AutovalidateMode.onUserInteraction;
    });

    if (!(_formKey.currentState?.validate() ?? false) || _selectedDob == null) {
      _logger.w('Form validation failed or DOB missing');
      if (_selectedDob == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select your date of birth'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final response = await SupabaseService.instance.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        userMetadata: {
          'user_type': 'trusted_partner',
          'name': _nameController.text,
          'surname': _surnameController.text,
          'dob': _selectedDob?.toIso8601String(),
          'street': _streetController.text,
          'suburb': _suburbController.text,
          'city': _selectedCity,
          'province': _selectedProvince,
          'contact': _contactController.text,
        },
      );
      _logger.i('Signup response: $response');

      if (!mounted) return;

      // In both cases (response.user present or null) we show the OTP dialog
      // so the user can confirm their email and we can perform authorization.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter the OTP sent to your email'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (c) => OtpVerificationDialog(
          email: _emailController.text.trim(),
          otpAlreadySent: true,
          isForSignIn: false,
          userType: 'trusted_partner',
          onVerificationSuccess: (String? verifiedUserId) async {
            final uid =
                verifiedUserId ??
                SupabaseService.instance.client.auth.currentUser?.id;
            if (uid == null) {
              _logger.e('Could not determine user id after verification');
              return;
            }

            // Use robust profile creation helper (matches member flow)
            final userData = {
              'name': _nameController.text,
              'surname': _surnameController.text,
              'date_of_birth': _selectedDob?.toIso8601String(),
              'gender': _selectedGender,
              'ethnicity': _selectedEthnicity,
              'street': _streetController.text,
              'suburb': _suburbController.text,
              'city': _selectedCity,
              'province': _selectedProvince,
              'contact': _contactController.text,
              'email': _emailController.text.trim(),
              'user_type': 'trusted_partner',
            };
            try {
              await SupabaseService.instance.createUserProfile(
                userId: uid,
                userData: userData,
              );
              _logger.i(
                'Trusted partner profile created successfully via createUserProfile',
              );
            } catch (profileError) {
              _logger.e('Profile creation failed: $profileError');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Profile creation failed: $profileError'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
              return;
            }

            // Create trusted partner record
            try {
              await SupabaseService.instance.client
                  .from('trusted_partners')
                  .insert({'user_id': uid, 'business_name': ''});
              _logger.i('Trusted partner record created successfully');
            } catch (partnerError) {
              _logger.w(
                'Trusted partner record creation failed: $partnerError',
              );
            }

            // Create membership record
            try {
              await SupabaseService.instance.client.from('memberships').insert({
                'user_id': uid,
                'role': 'trusted_partner',
                'gateway': 'trusted_partner_signup',
              });
              _logger.i('Membership record created successfully');
            } catch (membershipError) {
              _logger.w('Membership record creation failed: $membershipError');
            }

            // After OTP verification we navigate to the business profile
            // page so the user can complete the business details.
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (ctx) => BusinessProfilePage(
                  initialBusinessName: _businessNameController.text.trim(),
                  initialName: _nameController.text.trim(),
                  initialAddress: _streetController.text.trim(),
                  initialContactEmail: _emailController.text.trim(),
                  initialContactNumber: _contactController.text.trim(),
                  initialLogoPath: _selectedLogo?.path,
                  // Lat/lng removed - not needed
                ),
              ),
            );
          },
        ),
      );
    } catch (e) {
      _logger.e('Signup error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Signup failed: $e')));
    }
  }

  Future<void> _showDatePicker() async {
    final DateTime now = DateTime.now();
    int selectedDay = _selectedDob?.day ?? (now.day - 1);
    int selectedMonth = _selectedDob?.month ?? now.month;
    int selectedYear = _selectedDob?.year ?? (now.year - 18);

    // Ensure selectedDay is valid for the selected month/year
    int maxDays = _getDaysInMonth(selectedYear, selectedMonth);
    if (selectedDay > maxDays) {
      selectedDay = maxDays;
    }

    await showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              height: 300,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const Text(
                          'Select Date of Birth',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final selectedDate = DateTime(
                              selectedYear,
                              selectedMonth,
                              selectedDay,
                            );
                            this.setState(() => _selectedDob = selectedDate);
                            Navigator.pop(context);
                          },
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        // Day picker
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 40,
                            scrollController: FixedExtentScrollController(
                              initialItem: selectedDay - 1,
                            ),
                            onSelectedItemChanged: (int index) {
                              setState(() {
                                selectedDay = index + 1;
                              });
                            },
                            children: List<Widget>.generate(
                              _getDaysInMonth(selectedYear, selectedMonth),
                              (int index) {
                                return Center(child: Text('${index + 1}'));
                              },
                            ),
                          ),
                        ),
                        // Month picker
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 40,
                            scrollController: FixedExtentScrollController(
                              initialItem: selectedMonth - 1,
                            ),
                            onSelectedItemChanged: (int index) {
                              setState(() {
                                selectedMonth = index + 1;
                                // Adjust day if necessary when month changes
                                int maxDays = _getDaysInMonth(
                                  selectedYear,
                                  selectedMonth,
                                );
                                if (selectedDay > maxDays) {
                                  selectedDay = maxDays;
                                }
                              });
                            },
                            children: List<Widget>.generate(12, (int index) {
                              final monthNames = [
                                'Jan',
                                'Feb',
                                'Mar',
                                'Apr',
                                'May',
                                'Jun',
                                'Jul',
                                'Aug',
                                'Sep',
                                'Oct',
                                'Nov',
                                'Dec',
                              ];
                              return Center(child: Text(monthNames[index]));
                            }),
                          ),
                        ),
                        // Year picker
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 40,
                            scrollController: FixedExtentScrollController(
                              initialItem: selectedYear - 1900,
                            ),
                            onSelectedItemChanged: (int index) {
                              setState(() {
                                selectedYear = 1900 + index;
                                // Adjust day if necessary when year changes (leap year)
                                int maxDays = _getDaysInMonth(
                                  selectedYear,
                                  selectedMonth,
                                );
                                if (selectedDay > maxDays) {
                                  selectedDay = maxDays;
                                }
                              });
                            },
                            children: List<Widget>.generate(125, (int index) {
                              return Center(child: Text('${1900 + index}'));
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  int _getDaysInMonth(int year, int month) {
    if (month == 2) {
      // February - check for leap year
      if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) {
        return 29;
      } else {
        return 28;
      }
    } else if ([4, 6, 9, 11].contains(month)) {
      return 30;
    } else {
      return 31;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _businessNameController.dispose();
    _streetController.dispose();
    _suburbController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    for (var address in _additionalAddresses) {
      for (var controller in address.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }
}
