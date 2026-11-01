import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'welcome_page.dart';

class PasswordResetPage extends StatefulWidget {
  final String accessToken;
  final String? refreshToken;

  const PasswordResetPage({
    super.key,
    required this.accessToken,
    this.refreshToken,
  });

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool _isSessionReady = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.refreshToken != null) {
      _isSessionReady = false;
      _restoreSession();
    }
  }

  Future<void> _restoreSession() async {
    try {
      await SupabaseService.instance.client.auth.setSession(
        widget.refreshToken!,
      );
      if (mounted) setState(() => _isSessionReady = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSessionReady = false;
          _errorMessage =
              'This password reset link has expired. Request a new one.';
        });
      }
    }
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (_newPasswordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter a new password');
      return;
    }

    if (_newPasswordController.text.length < 8) {
      setState(() => _errorMessage = 'Password must be at least 8 characters');
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (kDebugMode) {
        print('PasswordResetPage: Resetting password');
      }

      // Note: Session is already established from PKCE code exchange
      // We can directly update the password
      await SupabaseService.instance.updatePassword(
        newPassword: _newPasswordController.text,
      );

      if (kDebugMode) {
        print('PasswordResetPage: Password reset successful');
      }

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Password reset successful! Please sign in.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate to welcome/sign-in page - replace entire stack since it was cleared earlier
      await Future.delayed(
        const Duration(milliseconds: 2000),
      ); // Delay to show snackbar fully
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
    } catch (e) {
      if (kDebugMode) {
        print('PasswordResetPage: Error resetting password: $e');
      }
      setState(() {
        _errorMessage = 'Failed to reset password. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMinimumPasswordLength = _newPasswordController.text.length >= 8;

    return Scaffold(
      appBar: BrandedAppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Icon(Icons.lock_reset, size: 64, color: Colors.blue),
              const SizedBox(height: 32),
              const Text(
                'Set Your New Password',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _newPasswordController,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  hintText: 'Enter your new password',
                  helperText:
                      '${_newPasswordController.text.length}/8 characters',
                  helperStyle: TextStyle(
                    color: hasMinimumPasswordLength ? Colors.green : null,
                  ),
                  border: const OutlineInputBorder(),
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
                  prefixIcon: const Icon(Icons.lock),
                ),
                obscureText: true,
                enabled: !_isLoading && _isSessionReady,
                onChanged: (value) {
                  setState(() {
                    _errorMessage = null;
                    if (_newPasswordController.text.length < 8) {
                      _confirmPasswordController.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmPasswordController,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  hintText: 'Re-enter your new password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: _errorMessage,
                ),
                obscureText: true,
                enabled:
                    !_isLoading && _isSessionReady && hasMinimumPasswordLength,
                onChanged: (value) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
                onSubmitted: (_) => _resetPassword(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed:
                    _isLoading ||
                        !_isSessionReady ||
                        !hasMinimumPasswordLength ||
                        _newPasswordController.text !=
                            _confirmPasswordController.text
                    ? null
                    : _resetPassword,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Reset Password',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
              if (!_isSessionReady)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) =>
                            const WelcomePage(openSignInOnLoad: true),
                      ),
                    );
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Request New Reset Code'),
                ),
              const SizedBox(height: 32), // Extra bottom padding for keyboard
            ],
          ),
        ),
      ),
    );
  }
}
