import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../core/constants/sa_locations.dart';
import '../../services/supabase_service.dart';
import 'tp_interest_thank_you_page.dart';

class TpInterestFormPage extends StatefulWidget {
  const TpInterestFormPage({super.key});

  @override
  State<TpInterestFormPage> createState() => _TpInterestFormPageState();
}

class _TpInterestFormPageState extends State<TpInterestFormPage> {
  final Logger _logger = Logger();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _contactController = TextEditingController();

  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedBusinessType;
  bool _sellsFreshProduce = false;
  bool _sellsAlcohol = false;
  bool _offersSportsActivities = false;
  bool _isSubmitting = false;

  final List<String> _businessTypes = [
    'Restaurant',
    'Café',
    'Bakery',
    'Grocery Store',
    'Butchery',
    'Liquor Store',
    'Clothing Store',
    'Hair Salon / Barber',
    'Beauty & Wellness',
    'Automotive',
    'Hardware Store',
    'Electronics',
    'Pharmacy',
    'Pet Store',
    'Gym / Fitness',
    'Other',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _businessNameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _submitInquiry() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final inquiryData = {
        'name': _nameController.text.trim(),
        'surname': _surnameController.text.trim(),
        'city': _selectedCity,
        'business_name': _businessNameController.text.trim(),
        'business_type': _selectedBusinessType,
        'email': _emailController.text.trim().toLowerCase(),
        'contact_number': _contactController.text.trim(),
        'sells_fresh_produce': _sellsFreshProduce,
        'sells_alcohol': _sellsAlcohol,
        'offers_sports_activities': _offersSportsActivities,
      };

      // Store inquiry in Supabase
      await SupabaseService.instance.client
          .from('tp_inquiries')
          .insert(inquiryData);

      _logger.i('TP inquiry submitted successfully');

      // Send email notification to admin via Edge Function
      try {
        await SupabaseService.instance.client.functions.invoke(
          'send-tp-inquiry-email',
          body: inquiryData,
        );
        _logger.i('Admin notification email sent');
      } catch (emailError) {
        // Non-critical - inquiry is already stored in database
        _logger.w('Admin email notification failed: $emailError');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const TpInterestThankYouPage(),
          ),
        );
      }
    } catch (e) {
      _logger.e('Failed to submit TP inquiry: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to submit your information. Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(title: const Text('Become a Trusted Partner')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                'Interested in partnering with Local Lekker?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Complete your details below and our team will be in touch to get you set up.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _surnameController,
                decoration: const InputDecoration(labelText: 'Surname'),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Surname is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedProvince,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Province'),
                items: kProvinces
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (value) => setState(() {
                  _selectedProvince = value;
                  _selectedCity = null;
                }),
                validator: (value) =>
                    value == null ? 'Province is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedProvince),
                initialValue: _selectedCity,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'City'),
                items: (kCitiesByProvince[_selectedProvince] ?? const <String>[])
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedCity = value),
                validator: (value) => value == null ? 'City is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _businessNameController,
                decoration: const InputDecoration(labelText: 'Business Name'),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Business name is required'
                        : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedBusinessType,
                decoration: const InputDecoration(labelText: 'Business Type'),
                items: _businessTypes
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        ))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _selectedBusinessType = value),
                validator: (value) =>
                    value == null ? 'Please select a business type' : null,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _sellsFreshProduce,
                  secondary: Icon(Icons.eco, color: Colors.green.shade700),
                  title: const Text('I sell fresh produce'),
                  subtitle: const Text(
                    'Locally sourced milk, poultry, veg, fruit, meat etc.',
                  ),
                  onChanged: (value) =>
                      setState(() => _sellsFreshProduce = value ?? false),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7EDEF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE0C2C7)),
                ),
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _sellsAlcohol,
                  secondary: const Icon(
                    Icons.wine_bar,
                    color: Color(0xFF722F37),
                  ),
                  title: const Text('I sell locally produced alcohol'),
                  subtitle: const Text(
                    'Wines, craft beers or spirits. A valid liquor licence is required.',
                  ),
                  onChanged: (value) =>
                      setState(() => _sellsAlcohol = value ?? false),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE1F5FE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFB3E5FC)),
                ),
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _offersSportsActivities,
                  secondary: const Icon(
                    Icons.sports_soccer,
                    color: Color(0xFF01579B),
                  ),
                  title: const Text('I offer sport/fitness activities'),
                  subtitle: const Text(
                    'Clubs, coaching, gyms or other active-lifestyle services.',
                  ),
                  onChanged: (value) =>
                      setState(() => _offersSportsActivities = value ?? false),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email Address'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Email is required';
                  }
                  final emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$');
                  if (!emailRegex.hasMatch(value.trim())) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(labelText: 'Contact Number'),
                keyboardType: TextInputType.phone,
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Contact number is required'
                        : null,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submitInquiry,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
