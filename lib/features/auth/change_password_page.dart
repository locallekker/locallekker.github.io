import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/supabase_service.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final Logger _logger = Logger();

  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _codeSent = false;
  bool _otpVerified = false;
  bool _isSending = false;
  bool _isUpdating = false;

  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool get _passwordsMatch =>
      _newPasswordController.text.isNotEmpty &&
      _newPasswordController.text == _confirmPasswordController.text;

  bool get _isPasswordValid =>
      _newPasswordController.text.length >= 8 && _passwordsMatch;

  String? _email;

  @override
  void initState() {
    super.initState();
    _email = SupabaseService.instance.getCurrentUser()?.email;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final user = SupabaseService.instance.getCurrentUser();
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to change your password'),
        ),
      );
      return;
    }
    setState(() => _isSending = true);
    try {
      // Reauthentication emails a 6-digit verification code (not a magic link)
      // to the signed-in user. The code is later supplied as the nonce when the
      // password is updated.
      await SupabaseService.instance.client.auth.reauthenticate();
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _otpVerified = false;
        _codeController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification code sent to ${_email ?? 'your email'}'),
        ),
      );
    } catch (e) {
      _logger.e('Failed to send verification code: $e');
      final lower = e.toString().toLowerCase();
      final msg = (lower.contains('rate_limit') || lower.contains('rate limit'))
          ? 'Too many attempts. Please wait a few minutes and try again.'
          : 'Failed to send verification code. Please try again.';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _verifyOtp() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the code sent to your email')),
      );
      return;
    }
    if (code.length != 6 || int.tryParse(code) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code from your email')),
      );
      return;
    }
    // The reauthentication code is validated by Supabase when the password is
    // updated (it is supplied as the nonce). Here we accept a well-formed code
    // and unlock the new-password step.
    setState(() => _otpVerified = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code accepted. Set your new password below.'),
      ),
    );
  }

  Future<void> _updatePassword() async {
    if (!_otpVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the verification code first.'),
        ),
      );
      return;
    }

    final code = _codeController.text.trim();
    final newPwd = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    if (newPwd.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter and confirm your new password'),
        ),
      );
      return;
    }
    if (newPwd != confirm) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }
    if (newPwd.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 8 characters')),
      );
      return;
    }

    setState(() => _isUpdating = true);
    try {
      // Supplying the reauthentication code as the nonce both verifies the code
      // and updates the password in Supabase (auth.users).
      await SupabaseService.instance.client.auth.updateUser(
        UserAttributes(password: newPwd, nonce: code),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully')),
      );
      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      _logger.e('Failed to update password: ${e.message}');
      final lower = e.message.toLowerCase();
      final invalidCode =
          lower.contains('nonce') ||
          lower.contains('reauthentication') ||
          lower.contains('invalid') ||
          lower.contains('expired') ||
          lower.contains('token');
      final msg = invalidCode
          ? 'Invalid or expired code. Please request a new code and try again.'
          : 'Failed to update password. Please try again.';
      if (mounted) {
        setState(() => _otpVerified = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(title: const Text('Change Password')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // Step 1: Send Code
            Card(
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
                    Text(
                      _email == null
                          ? 'No email available'
                          : 'We\'ll send a code to: $_email',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton.icon(
                        onPressed: _isSending ? null : _sendOtp,
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
                        label: Text(
                          _isSending
                              ? 'Sending...'
                              : (_codeSent ? 'Resend Code' : 'Send Code'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Step 2: Verify Code
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Step 2: Verify Code',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Enter 6-digit code',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: OutlinedButton.icon(
                        onPressed: !_codeSent ? null : _verifyOtp,
                        icon: const Icon(Icons.verified),
                        label: const Text('Verify Code'),
                      ),
                    ),
                    if (_otpVerified)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Verified! You can now set a new password.',
                          style: TextStyle(color: Colors.green),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Step 3: Set New Password
            Card(
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
                      obscureText: _obscureNew,
                      decoration: InputDecoration(
                        labelText: 'New password (min 8 chars)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNew
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_newPasswordController.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            Icon(
                              _newPasswordController.text.length >= 8
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: _newPasswordController.text.length >= 8
                                  ? Colors.green
                                  : Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _newPasswordController.text.length >= 8
                                  ? 'At least 8 characters'
                                  : 'Must be at least 8 characters',
                              style: TextStyle(
                                color: _newPasswordController.text.length >= 8
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirm new password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_confirmPasswordController.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            Icon(
                              _passwordsMatch
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: _passwordsMatch
                                  ? Colors.green
                                  : Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _passwordsMatch
                                  ? 'Passwords match'
                                  : 'Passwords do not match',
                              style: TextStyle(
                                color: _passwordsMatch
                                    ? Colors.green
                                    : Colors.red,
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
                        onPressed:
                            _otpVerified && _isPasswordValid && !_isUpdating
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
                        label: Text(
                          _isUpdating ? 'Updating...' : 'Update Password',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
