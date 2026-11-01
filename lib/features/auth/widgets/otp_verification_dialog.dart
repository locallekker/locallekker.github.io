import 'package:flutter/material.dart';
import 'dart:async';
import '../../../services/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class OtpVerificationDialog extends StatefulWidget {
  final String email;
  final String? phoneNumber;
  final Function(String? userId) onVerificationSuccess;
  final bool isForSignIn;
  final bool otpAlreadySent;
  final String? userType; // 'member' or 'trusted_partner' or null for generic
  final Map<String, dynamic>? userMetadata; // Passed to signInWithOtp for signup
  // True when resuming a previously abandoned signup: the auth user already
  // exists, so the OTP must be re-sent without creating a duplicate account.
  final bool isResumeSignup;

  const OtpVerificationDialog({
    super.key,
    required this.email,
    this.phoneNumber,
    required this.onVerificationSuccess,
    this.isForSignIn = false,
    this.otpAlreadySent = false,
    this.userType,
    this.userMetadata,
    this.isResumeSignup = false,
  });

  @override
  State<OtpVerificationDialog> createState() => _OtpVerificationDialogState();
}

class _OtpVerificationDialogState extends State<OtpVerificationDialog> {
  final Logger _logger = Logger();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _otpSent = false;
  String? _errorMessage;

  // Timer variables
  Timer? _countdownTimer;
  int _remainingSeconds = 600; // 10 minutes (matches Supabase OTP validity)
  bool _isTimerExpired = false;

  @override
  void initState() {
    super.initState();
    // If the calling flow already triggered an OTP (e.g. signUp returned
    // null and Supabase already emailed the confirmation), show the OTP
    // input immediately and start the timer.
    if (widget.otpAlreadySent) {
      _otpSent = true;
      _startCountdownTimer();
    }
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel(); // Cancel any existing timer
    _remainingSeconds = 600; // Reset to 10 minutes (matches Supabase OTP validity)
    _isTimerExpired = false;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        setState(() {
          _isTimerExpired = true;
        });
        _countdownTimer?.cancel();
      }
    });
  }

  void _stopCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {

      print(
      'DEBUG: Building OTP dialog - _otpSent: $_otpSent, _isLoading: $_isLoading',
    );

    }
    final titleText = widget.userType == 'trusted_partner'
        ? 'Verify Your Business Account'
        : widget.userType == 'user'
        ? 'Verify Your Personal Account'
        : 'Verify Your Account';

    final descriptionText = widget.userType == 'trusted_partner'
      ? 'We\'ll send a verification code to your business account email:'
      : 'We\'ll send a verification code to your email:';
    final destination = widget.email;

    return AlertDialog(
      title: Text(titleText),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(descriptionText, textAlign: TextAlign.center),
            const SizedBox(height: 20),

            // Error message display (before OTP sent)
            if (!_otpSent && _errorMessage != null) ...[              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Selected delivery destination
            if (!_otpSent) ...[
              ListTile(
                leading: Icon(Icons.email, color: Theme.of(context).primaryColor),
                title: Text(destination),
                subtitle: const Text('Verification code will be sent here'),
              ),
            ],

            const SizedBox(height: 20),

            // OTP Input Field
            if (_otpSent) ...[
              TextField(
                controller: _otpController,
                decoration: InputDecoration(
                  labelText: 'Enter 6-digit OTP',
                  hintText: '000000',
                  border: const OutlineInputBorder(),
                  errorText: _errorMessage,
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'OTP sent to $destination',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              // Countdown Timer
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _isTimerExpired
                      ? Colors.red.shade50
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isTimerExpired ? Colors.red : Colors.blue,
                    width: 1,
                  ),
                ),
                child: Text(
                  _isTimerExpired
                      ? 'OTP Expired'
                      : 'Expires in: ${_formatTime(_remainingSeconds)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _isTimerExpired ? Colors.red : Colors.blue,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            // Note: field-level errors are shown via the TextField.errorText
            // to highlight the input in red. Additional messaging is not
            // required here to avoid duplication.
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (!_otpSent)
          ElevatedButton(
            onPressed: _isLoading ? null : _sendOtp,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send OTP'),
          )
        else ...[
          TextButton(
            onPressed: _isLoading ? null : _resendOtp,
            child: const Text('Resend OTP'),
          ),
          ElevatedButton(
            onPressed: (_isLoading || _isTimerExpired) ? null : _verifyOtp,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isTimerExpired ? 'OTP Expired' : 'Verify'),
          ),
        ],
      ],
    );
  }

  Future<void> _sendOtp() async {
    if (kDebugMode) {

      print('DEBUG: _sendOtp called with method: email');

    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (kDebugMode) {

        print('DEBUG: Calling SupabaseService.sendOtp');

      }
      await SupabaseService.instance.sendOtp(
        email: widget.email,
        phone: widget.phoneNumber,
        method: 'email',
        isForSignIn: widget.isForSignIn,
        isResumeSignup: widget.isResumeSignup,
        userMetadata: widget.userMetadata,
      );

      if (kDebugMode) {


        print('DEBUG: OTP sent successfully, setting _otpSent = true');


      }
      setState(() {
        _otpSent = true;
        _isLoading = false;
      });

      // Start the countdown timer
      _startCountdownTimer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OTP sent to ${_deliveryDestination()}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {

        print('DEBUG: Error in _sendOtp: $e');

      }
      final errorMessage = _getErrorMessage(e.toString());
      if (kDebugMode) {

        print('DEBUG: Processed error message: $errorMessage');

      }

      // If it's a rate limiting error, the OTP might still have been sent
      // Allow the user to proceed to input screen
      if (errorMessage.contains('rate_limit') ||
          errorMessage.contains('wait') ||
          errorMessage.contains('Rate limit reached')) {
        if (kDebugMode) {

          print('DEBUG: Rate limiting detected, showing OTP input screen');

        }
        setState(() {
          _otpSent = true;
          _isLoading = false;
          _errorMessage = errorMessage;
        });
        _startCountdownTimer();
      } else {
        if (kDebugMode) {

          print('DEBUG: Non-rate limiting error, staying on method selection');

        }
        setState(() {
          _isLoading = false;
          _errorMessage = errorMessage;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit OTP');
      return;
    }

    if (_isTimerExpired) {
      setState(
        () => _errorMessage = 'OTP has expired. Please request a new one.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final response = await SupabaseService.instance.verifyOtp(
        email: widget.email,
        phone: widget.phoneNumber,
        otp: _otpController.text,
        method: 'email',
        isForSignIn: widget.isForSignIn,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      final verifiedUserId = response.user?.id;

      Navigator.pop(context); // Close dialog

      widget.onVerificationSuccess(
        verifiedUserId,
      ); // Proceed to next screen with userId

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.isForSignIn
                ? 'Sign in successful!'
                : 'Account verified successfully!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = _getErrorMessage(e.toString());
      });
    }
  }

  String _getErrorMessage(String error) {
    _logger.e('OTP error raw: $error');
    if (error.contains('Invalid')) {
      return 'Invalid OTP. Please try again.';
    } else if (error.contains('expired')) {
      return 'OTP has expired. Please request a new one.';
    } else if (error.contains('rate_limit') ||
        error.contains('Too many') ||
        error.contains('over_email_send_rate_limit') ||
        error.contains('For security purposes')) {
      return 'Rate limit reached. If you received an OTP, please enter it below.';
    } else if (error.contains('wait')) {
      return 'Please wait before requesting another OTP.';
    } else if (error.contains('User already registered') ||
        error.contains('already been registered')) {
      return 'This email is already registered. Please sign in instead.';
    } else {
      // Show meaningful part of error for debugging
      final cleanError = error
          .replaceAll('Exception: ', '')
          .replaceAll('AuthException: ', '')
          .replaceAll('AuthApiError: ', '')
          .replaceAll('AuthRetryableFetchError: ', '');
      if (cleanError.length > 100) {
        return 'Failed to send OTP. Please try again shortly.';
      }
      return cleanError;
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _otpController.clear(); // Clear the current OTP input
    });

    try {
      await SupabaseService.instance.sendOtp(
        email: widget.email,
        phone: widget.phoneNumber,
        method: 'email',
        isForSignIn: widget.isForSignIn,
        isResumeSignup: widget.isResumeSignup,
        userMetadata: widget.userMetadata,
      );

      setState(() {
        _isLoading = false;
      });

      // Reset and restart the countdown timer
      _startCountdownTimer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New OTP sent to ${_deliveryDestination()}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      final errorMessage = _getErrorMessage(e.toString());

      // If it's a rate limiting error, the OTP might still have been sent
      // Allow the user to proceed with the existing timer
      if (errorMessage.contains('rate_limit') ||
          errorMessage.contains('wait')) {
        setState(() {
          _isLoading = false;
          _errorMessage = errorMessage;
        });
        // Don't reset timer since OTP might still be valid
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = errorMessage;
        });
      }
    }
  }

  String _deliveryDestination() {
    return widget.email;
  }

  @override
  void dispose() {
    _otpController.dispose();
    _stopCountdownTimer();
    super.dispose();
  }
}
