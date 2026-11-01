import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'package:logger/logger.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../services/supabase_service.dart';
import 'business_profile_page.dart';

class SetInitialPasswordPage extends StatefulWidget {
  const SetInitialPasswordPage({super.key});

  @override
  State<SetInitialPasswordPage> createState() => _SetInitialPasswordPageState();
}

class _SetInitialPasswordPageState extends State<SetInitialPasswordPage> {
  final Logger _logger = Logger();
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _otpSent = false;
  bool _passwordSet = false;
  String? _userEmail;
  String? _pendingPassword; // Store password temporarily until OTP verification

  // Timer variables for OTP expiration
  Timer? _countdownTimer;
  int _remainingSeconds = 120; // 2 minutes
  bool _isTimerExpired = false;

  @override
  void initState() {
    super.initState();
    final user = SupabaseService.instance.getCurrentUser();
    _userEmail = user?.email;
    _checkExistingPasswordStatus();

    // Add a fallback check after a short delay in case the initial check fails
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_passwordSet && !_otpSent) {
        _logger.i('Fallback password status check triggered');
        _checkExistingPasswordStatus();
      }
    });
  }

  Future<void> _checkExistingPasswordStatus() async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) {
        _logger.w('No current user found during password status check');
        return;
      }

      _logger.i(
        'Checking password status for user: ${user.email} (ID: ${user.id})',
      );

      // Check if password is already set in profile
      final profileResponse = await SupabaseService.instance.client
          .from('profiles')
          .select('password_set')
          .eq('id', user.id)
          .single();

      final passwordSet = profileResponse['password_set'] as bool? ?? false;

      _logger.i(
        'Password status check result: password_set = $passwordSet for user ${user.email}',
      );

      if (passwordSet) {
        // Password already set, go directly to OTP verification
        _logger.i(
          'Password already set, proceeding to OTP verification for ${user.email}',
        );
        setState(() {
          _passwordSet = true;
        });
        await _sendOtp();
      } else {
        _logger.i(
          'Password not set, showing password creation form for ${user.email}',
        );
      }
    } catch (e) {
      _logger.e('Failed to check existing password status: $e');
      // If we can't check, default to password creation flow
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    _stopCountdownTimer();
    super.dispose();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel(); // Cancel any existing timer
    _remainingSeconds = 120; // Reset to 2 minutes
    _isTimerExpired = false;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        setState(() {
          _isTimerExpired = true;
          // Clear pending password when timer expires for security
          _pendingPassword = null;
        });
        _countdownTimer?.cancel();
      }
    });
  }

  void _stopCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _resetToPasswordEntry() {
    setState(() {
      _passwordSet = false;
      _otpSent = false;
      _isTimerExpired = false;
      _otpController.clear();
      _pendingPassword = null;
      _stopCountdownTimer();
    });
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _setPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      // Store password temporarily
      _pendingPassword = _passwordController.text.trim();

      // Immediately update password in Supabase Auth to overwrite any previous password
      final user = SupabaseService.instance.getCurrentUser();
      if (user != null) {
        await SupabaseService.instance.client.auth.updateUser(
          UserAttributes(password: _pendingPassword!),
        );
        _logger.i(
          'Password immediately updated in Supabase Auth for user ${user.id}',
        );
      }

      _logger.i(
        'Password stored and updated for user - now sending OTP verification',
      );

      setState(() {
        _passwordSet = true;
        _isLoading = false;
      });

      // Send OTP for verification AFTER password is set
      await _sendOtp();
    } catch (e) {
      _logger.e('Failed to prepare password setup: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to prepare password setup: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendOtp() async {
    if (_userEmail == null) {
      throw Exception('User email not available');
    }

    // If timer expired and we're resending, check if we still have the password
    if (_isTimerExpired && _pendingPassword == null && !_passwordSet) {
      // Password was cleared, need to go back to password entry
      setState(() {
        _passwordSet = false;
        _otpSent = false;
        _isTimerExpired = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session expired. Please enter your password again.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // For admin-created users who need email verification, use resend with signup type
      // This sends a proper verification email for existing users who haven't completed signup
      await SupabaseService.instance.client.auth.resend(
        type: OtpType.signup,
        email: _userEmail!,
      );

      _logger.i('Signup verification email sent to $_userEmail using resend');

      if (mounted) {
        setState(() {
          _otpSent = true;
          _isLoading = false;
          _otpController.clear(); // Clear any existing OTP input
        });

        // Start the countdown timer
        _startCountdownTimer();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isTimerExpired
                  ? 'New verification code sent to your email!'
                  : 'Verification code sent to your email!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _logger.e('Failed to send verification email: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send verification code: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    final otpCode = _otpController.text.trim();
    if (otpCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the verification code'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isTimerExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification code expired. Please request a new one.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_userEmail == null) throw Exception('User email not available');

      // Verify OTP
      await SupabaseService.instance.client.auth.verifyOTP(
        email: _userEmail!,
        token: otpCode,
        type: OtpType.signup, // Use signup type for resend verification
      );

      _logger.i('OTP verified successfully for $_userEmail');

      // Password was already set before OTP, now just update the profile
      final user = SupabaseService.instance.getCurrentUser();
      if (user != null) {
        // Update profile to mark password as set
        await SupabaseService.instance.client
            .from('profiles')
            .update({
              'password_set': true,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', user.id);

        _logger.i(
          'Profile updated successfully after OTP verification for user ${user.id}',
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Email verified and password saved! Please complete your profile.',
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to BusinessProfilePage for profile completion
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const BusinessProfilePage(
              requireCompletion:
                  true, // Require profile completion before home access
            ),
          ),
        );
      }
    } catch (e) {
      _logger.e('Failed to verify OTP: $e');
      if (mounted) {
        String errorMessage = 'Invalid verification code';
        if (e.toString().contains('expired')) {
          errorMessage = 'Verification code expired. Please request a new one.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: Text(
          _passwordSet && _otpSent ? 'Verify Email' : 'Set Your Password',
        ),
        automaticallyImplyLeading: false, // Prevent back navigation
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Debug info for development
              if (kDebugMode) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 16),
                  color: Colors.yellow.shade100,
                  child: Text(
                    'DEBUG: passwordSet=$_passwordSet, otpSent=$_otpSent, userEmail=$_userEmail',
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                  ),
                ),
              ],
              _passwordSet && _otpSent
                  ? _buildOtpVerificationForm()
                  : _buildPasswordForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.lock_outline,
            size: 80,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 24),
          const Text(
            'Welcome!',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            _otpSent
                ? 'Your account was created by an administrator. You started setting up your password but didn\'t complete verification. Please set your password again to continue.'
                : 'Your account was created by an administrator. Please set your password to continue.',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'New Password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              helperText: 'At least 8 characters',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a password';
              }
              if (value.length < 8) {
                return 'Password must be at least 8 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() => _obscureConfirm = !_obscureConfirm);
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _setPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'Set Password & Continue',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpVerificationForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.email_outlined,
          size: 80,
          color: Theme.of(context).primaryColor,
        ),
        const SizedBox(height: 24),
        const Text(
          'Verify Your Email',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'We\'ve sent a verification code to\n$_userEmail',
          style: const TextStyle(fontSize: 14, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _otpController,
          decoration: const InputDecoration(
            labelText: 'Verification Code',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock_open),
            helperText: 'Enter the 6-digit code from your email',
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
        ),
        const SizedBox(height: 16),
        // Countdown Timer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isTimerExpired
                ? (_pendingPassword == null
                      ? Colors.orange.shade50
                      : Colors.red.shade50)
                : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isTimerExpired
                  ? (_pendingPassword == null ? Colors.orange : Colors.red)
                  : Colors.blue,
              width: 1,
            ),
          ),
          child: Text(
            _isTimerExpired
                ? (_pendingPassword == null
                      ? 'Session Expired - Enter Password Again'
                      : 'Code Expired - Request New Code')
                : 'Expires in: ${_formatTime(_remainingSeconds)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _isTimerExpired
                  ? (_pendingPassword == null ? Colors.orange : Colors.red)
                  : Colors.blue,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading
                ? null
                : (_isTimerExpired && _pendingPassword == null
                      ? _resetToPasswordEntry
                      : (_isTimerExpired ? null : _verifyOtp)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isTimerExpired
                  ? (_pendingPassword == null ? Colors.orange : Colors.grey)
                  : Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(
                    _isTimerExpired
                        ? (_pendingPassword == null
                              ? 'Enter Password Again'
                              : 'Code Expired')
                        : 'Verify & Continue',
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _isLoading
              ? null
              : (_pendingPassword == null ? _resetToPasswordEntry : _sendOtp),
          style: TextButton.styleFrom(
            foregroundColor: _isTimerExpired
                ? (_pendingPassword == null
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).primaryColor)
                : Colors.grey,
          ),
          child: Text(
            _isTimerExpired
                ? (_pendingPassword == null
                      ? 'Enter Password'
                      : 'Send New Code')
                : 'Resend Code',
            style: TextStyle(
              fontWeight: _isTimerExpired ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
