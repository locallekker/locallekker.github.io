import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/supabase_service.dart';

/// Signed-out "Forgot Password" flow handled entirely in-app.
///
/// Three steps on a single screen:
///   1. Enter email and send a verification code.
///   2. Enter the 6-digit code (verified server-side, establishes a session).
///   3. Set a new password (written to Supabase auth.users).
///
/// This is the in-app code flow. The separate [PasswordResetPage] handles the
/// case where a user instead opens the emailed recovery link (deep link).
class ForgotPasswordPage extends StatefulWidget {
  final String? prefillEmail;

  const ForgotPasswordPage({super.key, this.prefillEmail});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final Logger _logger = Logger();

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _codeSent = false;
  bool _codeVerified = false;
  bool _isSending = false;
  bool _isVerifying = false;
  bool _isUpdating = false;
  String? _codeErrorMessage;

  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    if (widget.prefillEmail != null) {
      _emailController.text = widget.prefillEmail!.trim();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ---- Validation helpers -------------------------------------------------

  bool get _isEmailValid {
    final email = _emailController.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool get _isCodeValid {
    final code = _codeController.text.trim();
    return code.length == 6 && int.tryParse(code) != null;
  }

  bool get _passwordsMatch =>
      _newPasswordController.text.isNotEmpty &&
      _newPasswordController.text == _confirmPasswordController.text;

  bool get _isPasswordValid =>
      _newPasswordController.text.length >= 8 && _passwordsMatch;

  String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return email;
    final name = email.substring(0, at);
    final domain = email.substring(at);
    final visible = name.substring(0, 1);
    final hiddenCount = (name.length - 1).clamp(1, 6);
    return '$visible${'•' * hiddenCount}$domain';
  }

  // ---- Actions ------------------------------------------------------------

  Future<void> _sendCode() async {
    if (!_isEmailValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address')),
      );
      return;
    }
    final email = _emailController.text.trim();
    setState(() => _isSending = true);
    try {
      await SupabaseService.instance.sendPasswordResetOtp(email: email);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _codeVerified = false;
        _codeErrorMessage = null;
        _codeController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });
      final masked = _maskEmail(email);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification code sent to $masked')),
      );
    } catch (e) {
      _logger.e('Failed to send reset code: $e');
      final lower = e.toString().toLowerCase();
      final msg = lower.contains('rate') || lower.contains('security purposes')
          ? 'Too many attempts. Please wait a few minutes and try again.'
          : 'Failed to send verification code. Please try again.';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _verifyCode() async {
    if (!_isCodeValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code from your email')),
      );
      return;
    }
    setState(() => _isVerifying = true);
    try {
      await SupabaseService.instance.verifyPasswordResetCode(
        email: _emailController.text.trim(),
        otp: _codeController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _codeVerified = true;
        _codeErrorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code verified. Set your new password.')),
      );
    } catch (e) {
      _logger.e('Reset code verification failed: $e');
      final lower = e.toString().toLowerCase();
      final isExpiredOrInvalid =
          lower.contains('expired') ||
          lower.contains('invalid') ||
          lower.contains('token');
      final msg = isExpiredOrInvalid
          ? 'Invalid or expired code. Please request a new one.'
          : 'Verification failed. Please try again.';
      if (!mounted) return;
      setState(() {
        _codeErrorMessage = msg;
        if (isExpiredOrInvalid) {
          _codeController.clear();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _updatePassword() async {
    if (!_codeVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please verify the code first.')),
      );
      return;
    }
    if (_newPasswordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 8 characters')),
      );
      return;
    }
    if (!_passwordsMatch) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    // Capture the messenger so the success message survives after we pop.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isUpdating = true);
    try {
      await SupabaseService.instance.updatePassword(
        newPassword: _newPasswordController.text,
      );
      // Sign out so the user lands on a known signed-out state and confirms the
      // new password by signing in again.
      await SupabaseService.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Password updated. Please sign in with your new password.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _logger.e('Failed to update password: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update password. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(title: const Text('Reset Password')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _buildSendCodeCard(),
            const SizedBox(height: 12),
            _buildVerifyCodeCard(),
            const SizedBox(height: 12),
            _buildNewPasswordCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildSendCodeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 1: Send Verification Code',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              enabled: !_isSending,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton.icon(
                onPressed: (_isSending || !_isEmailValid) ? null : _sendCode,
                icon: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSending ? 'Sending...' : 'Send Code'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerifyCodeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 2: Verify Your Email',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              enabled: _codeSent && !_isVerifying && !_codeVerified,
              decoration: InputDecoration(
                labelText: 'Enter 6-digit code',
                border: const OutlineInputBorder(),
                counterText: '',
                errorText: _codeErrorMessage,
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => _codeErrorMessage = null),
            ),
            const SizedBox(height: 12),
            if (_codeErrorMessage != null && !_codeVerified) ...[
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendCode,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Resend Code'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              height: 45,
              child: OutlinedButton.icon(
                onPressed:
                    (!_codeSent ||
                        _isVerifying ||
                        _codeVerified ||
                        !_isCodeValid)
                    ? null
                    : _verifyCode,
                icon: _isVerifying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified),
                label: Text(_isVerifying ? 'Verifying...' : 'Verify Code'),
              ),
            ),
            if (_codeSent && !_codeVerified && _codeErrorMessage == null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _isSending ? null : _sendCode,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Resend Code'),
                ),
              ),
            if (_codeVerified)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Verified! Set a new password below.',
                      style: TextStyle(color: Colors.green),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewPasswordCard() {
    final hasMinimumPasswordLength = _newPasswordController.text.length >= 8;
    final showMatchHint = _confirmPasswordController.text.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 3: Set New Password',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _newPasswordController,
              enabled: _codeVerified && !_isUpdating,
              obscureText: _obscureNew,
              decoration: InputDecoration(
                labelText: 'New password (min 8 chars)',
                helperText:
                    '${_newPasswordController.text.length}/8 characters',
                helperStyle: TextStyle(
                  color: hasMinimumPasswordLength ? Colors.green : null,
                ),
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: hasMinimumPasswordLength ? Colors.green : Colors.grey,
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
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNew ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
              onChanged: (_) => setState(() {
                if (_newPasswordController.text.length < 8) {
                  _confirmPasswordController.clear();
                }
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              enabled: _codeVerified && hasMinimumPasswordLength && !_isUpdating,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Confirm new password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (showMatchHint)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    Icon(
                      _passwordsMatch ? Icons.check_circle : Icons.cancel,
                      color: _passwordsMatch ? Colors.green : Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _passwordsMatch
                          ? 'Passwords match'
                          : 'Passwords do not match',
                      style: TextStyle(
                        color: _passwordsMatch ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton.icon(
                onPressed: (_codeVerified && _isPasswordValid && !_isUpdating)
                    ? _updatePassword
                    : null,
                icon: _isUpdating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock),
                label: Text(_isUpdating ? 'Updating...' : 'Update Password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
