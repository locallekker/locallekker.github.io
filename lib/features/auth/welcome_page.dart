import 'package:flutter/material.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'dart:async';
import 'members_signup_page.dart';
import 'tp_interest_form_page.dart';
import 'forgot_password_page.dart';
import '../../services/supabase_service.dart';
import 'widgets/otp_verification_dialog.dart';
import '../../widgets/loading_screen.dart';
import 'set_initial_password_page.dart';
import 'set_password_page.dart';
import 'package:flutter/foundation.dart';

class WelcomePage extends StatefulWidget {
  final bool openSignInOnLoad;
  final String? prefillEmail;

  const WelcomePage({
    super.key,
    this.openSignInOnLoad = false,
    this.prefillEmail,
  });

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  @override
  void initState() {
    super.initState();
    if (widget.openSignInOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showSigninDialog(context, prefillEmail: widget.prefillEmail);
        }
      });
    }
  }

  void _showForgotPasswordFlow(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ForgotPasswordPage()));
  }

  // Show OTP verification dialog for admin-created user password setup
  void _showOtpVerificationForPasswordSetup(
    BuildContext context,
    String email,
    String newPassword,
  ) {
    final otpController = TextEditingController();
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Verify Your Email'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'We sent a 6-digit verification code to $email',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: otpController,
                  decoration: InputDecoration(
                    labelText: 'Enter 6-digit code',
                    hintText: '000000',
                    border: const OutlineInputBorder(),
                    errorText: errorMessage,
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await SupabaseService.instance.sendPasswordResetOtp(
                    email: email,
                  );
                  if (!context.mounted) return;
                  otpController.clear();
                  setState(() => errorMessage = null);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('A new verification code has been sent.'),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  setState(
                    () => errorMessage =
                        'Could not send a new code. Please try again shortly.',
                  );
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Resend Code'),
            ),
            ElevatedButton(
              onPressed: () async {
                final otp = otpController.text.trim();
                if (otp.length != 6) {
                  setState(
                    () => errorMessage = 'Please enter a valid 6-digit code',
                  );
                  return;
                }

                try {
                  if (kDebugMode) {
                    print(
                      '🔐 WelcomePage: Verifying OTP and setting password for: $email',
                    );
                  }

                  // Verify OTP and update password
                  await SupabaseService.instance.verifyPasswordResetOtp(
                    email: email,
                    otp: otp,
                    newPassword: newPassword,
                  );

                  // Update profile to mark password as set
                  final userId = SupabaseService.instance.getCurrentUser()?.id;
                  if (userId != null) {
                    await SupabaseService.instance.updateUserProfile(
                      userId: userId,
                      profileData: {'password_set': true},
                    );
                  }

                  Navigator.pop(dialogContext); // Close OTP dialog

                  if (!context.mounted) return;

                  // Sign in with new password
                  try {
                    final response = await SupabaseService.instance.signIn(
                      email: email,
                      password: newPassword,
                    );

                    if (response.user != null) {
                      await _startSmoothSignInTransition(
                        context,
                        dialogContext,
                        response.user!.id,
                      );
                    }
                  } catch (signInError) {
                    if (kDebugMode) {
                      print(
                        '🔐 WelcomePage: Sign in after password setup error: $signInError',
                      );
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Password set successfully! Please sign in.',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (kDebugMode) {
                    print('🔐 WelcomePage: OTP verification error: $e');
                  }
                  setState(
                    () => errorMessage = e.toString().replaceAll(
                      'Exception: ',
                      '',
                    ),
                  );
                }
              },
              child: const Text('Verify & Continue'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(title: const Text('Welcome to Local Lekker')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Don't have an account?",
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _showSignupDialog(context),
              child: const Text('Sign Up'),
            ),
            const SizedBox(height: 24),
            Text(
              'Already have an account?',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _showSigninDialog(context),
              child: const Text('Sign In'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _showOtpSigninDialog(context),
              child: const Text('Sign In with OTP'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _handleGoogleSignIn(context),
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 20),
            // Show sign out button if user is already signed in
            Builder(
              builder: (context) {
                final currentUser = SupabaseService.instance.getCurrentUser();
                if (currentUser != null) {
                  return Column(
                    children: [
                      Text(
                        'Signed in as: ${currentUser.email}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () async {
                          try {
                            await SupabaseService.instance.signOut();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Signed out successfully'),
                                ),
                              );
                              // Refresh the UI
                              setState(() {});
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Sign out failed: $e')),
                              );
                            }
                          }
                        },
                        child: const Text('Sign Out'),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// "Continue with Google" — additive alternative to email/password sign-in.
  /// Feeds into the exact same downstream flow (profile completion, member
  /// terms, subscription/payment gating) via _startSmoothSignInTransition, so
  /// nothing about the existing signup/payment pipeline changes.
  Future<void> _handleGoogleSignIn(BuildContext context) async {
    try {
      final response = await SupabaseService.instance.signInWithGoogle();
      final user = response.user;
      if (user == null) return;

      // Safe no-op upsert if a profile row already exists for this user.
      try {
        await SupabaseService.instance.createInitialUserProfile();
      } catch (e) {
        if (kDebugMode) {
          print('🔐 WelcomePage: createInitialUserProfile after Google sign-in failed: $e');
        }
      }

      if (!context.mounted) return;
      await _startSmoothSignInTransition(context, context, user.id);
    } catch (e) {
      if (!context.mounted) return;
      final message = e.toString().replaceAll('Exception: ', '');
      if (message.toLowerCase().contains('cancelled')) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign-in failed: $message')),
      );
    }
  }

  void _showSignupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Account Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Member'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MembersSignupPage(),
                  ),
                );
              },
            ),
            ListTile(
              title: const Text('Trusted Partner (Business)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TpInterestFormPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Start smooth sign-in transition: Show loading screen then let app handle navigation
  Future<void> _startSmoothSignInTransition(
    BuildContext parentContext,
    BuildContext dialogContext,
    String userId,
  ) async {
    if (kDebugMode) {
      print('🔐 WelcomePage: Starting sign-in transition for user $userId');
    }

    // Close dialog immediately (only if dialogContext is different from parentContext,
    // to avoid accidentally popping the WelcomePage itself)
    if (dialogContext != parentContext && Navigator.canPop(dialogContext)) {
      Navigator.pop(dialogContext);
    }

    // Check if user is admin-created and needs to set password
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user != null) {
        final adminStatus = await SupabaseService.instance
            .checkAdminCreatedStatus(user.email ?? '');

        final isAdminCreated = adminStatus['admin_created'] == true;
        final passwordSet = adminStatus['password_set'] == true;

        if (kDebugMode) {
          print(
            '🔐 WelcomePage: Admin status - admin_created: $isAdminCreated, password_set: $passwordSet',
          );
        }

        if (isAdminCreated && !passwordSet) {
          // Redirect to password setup page
          if (kDebugMode) {
            print('🔐 WelcomePage: Redirecting to initial password setup');
          }
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              parentContext,
              MaterialPageRoute(
                builder: (context) => const SetInitialPasswordPage(),
              ),
              (route) => false,
            );
          }
          return;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('🔐 WelcomePage: Error checking admin status: $e');
      }
      // Continue with normal flow if check fails
    }

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(
          content: Text('Sign in successful!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 40, left: 16, right: 16),
        ),
      );
    }

    // Show the Local Lekker loading screen with auto-transition enabled
    if (kDebugMode) {
      print(
        '🔐 WelcomePage: Showing Local Lekker loading screen with auto-transition',
      );
    }
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        parentContext,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const LoadingScreen(autoTransitionAfterAuth: true),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
          fullscreenDialog: false,
        ),
        (route) => false, // Remove all previous routes
      );
    }
  }

  void _showSigninDialog(BuildContext context, {String? prefillEmail}) {
    final emailController = TextEditingController(text: prefillEmail ?? '');
    final passwordController = TextEditingController();
    final passwordFocusNode = FocusNode();
    final parentContext = context;

    // Email validation state
    bool isEmailValid = prefillEmail != null && prefillEmail.isNotEmpty;
    bool isCheckingEmail = false;
    Timer? emailCheckTimer;
    bool emailIsDeactivated = false;

    if (isEmailValid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (passwordFocusNode.canRequestFocus) {
          passwordFocusNode.requestFocus();
        }
      });
    }

    // Admin-created user state
    bool isAdminCreated = false;
    bool needsPasswordSetup = false;
    final confirmPasswordController = TextEditingController();
    String? signInError;
    bool isPasswordIncorrect = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(needsPasswordSetup ? 'Set Your Password' : 'Sign In'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter your email address',
                    errorText:
                        emailController.text.isNotEmpty &&
                            !isCheckingEmail &&
                            (emailIsDeactivated || !isEmailValid)
                        ? emailIsDeactivated
                              ? 'Account is deactivated. Please reactivate to sign in.'
                              : 'Email not found'
                        : null,
                    suffixIcon: isCheckingEmail
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : emailController.text.isNotEmpty
                        ? Icon(
                            emailIsDeactivated
                                ? Icons.block
                                : isEmailValid
                                ? Icons.check_circle
                                : Icons.error,
                            color: emailIsDeactivated
                                ? Colors.red
                                : isEmailValid
                                ? Colors.green
                                : Colors.red,
                          )
                        : null,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !needsPasswordSetup, // Disable when setting password
                  onChanged: (value) {
                    // Cancel previous timer
                    emailCheckTimer?.cancel();

                    if (signInError != null) {
                      setState(() => signInError = null);
                    }

                    if (value.isEmpty) {
                      setState(() {
                        isEmailValid = false;
                        isCheckingEmail = false;
                        emailIsDeactivated = false;
                      });
                      return;
                    }

                    // Debounce email validation (short to feel instant while typing)
                    emailCheckTimer = Timer(
                      const Duration(milliseconds: 300),
                      () async {
                        final trimmed = value.trim();
                        setState(() => isCheckingEmail = true);

                        if (kDebugMode) {
                          print('🔐 WelcomePage: Validating email: "$trimmed"');
                        }
                        final exists = await SupabaseService.instance
                            .checkEmailExists(trimmed);
                        if (kDebugMode) {
                          print(
                            '🔐 WelcomePage: Email validation result: $exists',
                          );
                        }

                        // If user kept typing, abort: a newer timer will handle it
                        if (trimmed != emailController.text.trim()) return;

                        // Run admin-created lookup and deactivation check in parallel
                        // to minimise perceived delay.
                        Map<String, dynamic> adminStatus = const {};
                        bool isDeactivated = false;
                        if (exists) {
                          final results = await Future.wait([
                            SupabaseService.instance.checkAdminCreatedStatus(
                              trimmed,
                            ),
                            SupabaseService.instance.isEmailDeactivated(
                              trimmed,
                            ),
                          ]);
                          adminStatus = results[0] as Map<String, dynamic>;
                          isDeactivated = results[1] as bool;

                          if (kDebugMode) {
                            print('🔐 WelcomePage: Admin status: $adminStatus');
                          }

                          isAdminCreated = adminStatus['admin_created'] == true;
                          final emailVerified =
                              adminStatus['email_verified'] == true;
                          needsPasswordSetup =
                              isAdminCreated &&
                              adminStatus['password_set'] == false;

                          if (isAdminCreated && !emailVerified) {
                            if (mounted) {
                              setState(() {
                                isEmailValid = exists;
                                isCheckingEmail = false;
                              });
                            }

                            Navigator.pop(context);

                            _showOtpVerificationForTrustedPartner(
                              parentContext,
                              trimmed,
                            );
                            return;
                          }
                        }

                        if (mounted && isDeactivated) {
                          setState(() {
                            emailIsDeactivated = true;
                            isEmailValid = false;
                            isCheckingEmail = false;
                            signInError =
                                'This account is deactivated. Please reactivate to continue.';
                          });
                          return;
                        }

                        if (mounted) {
                          setState(() {
                            emailIsDeactivated = false;
                            isEmailValid = exists;
                            isCheckingEmail = false;
                          });
                          if (exists && !needsPasswordSetup) {
                            // Focus password field for regular users
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (passwordFocusNode.canRequestFocus) {
                                passwordFocusNode.requestFocus();
                              }
                            });
                          }
                        }
                      },
                    );
                  },
                ),
                if (needsPasswordSetup) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Your account was created by an administrator. Please set your password to continue.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    focusNode: passwordFocusNode,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      hintText: 'Create a strong password',
                      border: OutlineInputBorder(),
                      helperText: 'At least 6 characters',
                    ),
                    obscureText: true,
                    onChanged: (value) {
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      hintText: 'Re-enter your password',
                      border: const OutlineInputBorder(),
                      errorText:
                          confirmPasswordController.text.isNotEmpty &&
                              passwordController.text !=
                                  confirmPasswordController.text
                          ? 'Passwords do not match'
                          : null,
                    ),
                    obscureText: true,
                    onChanged: (value) {
                      setState(() {});
                    },
                  ),
                ] else if (isEmailValid) ...[
                  if (signInError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        border: Border.all(color: Colors.red.shade200),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              signInError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    focusNode: passwordFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter your password',
                      border: const OutlineInputBorder(),
                      errorText: isPasswordIncorrect
                          ? 'Incorrect password'
                          : null,
                      focusedBorder: isPasswordIncorrect
                          ? const OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.red,
                                width: 2,
                              ),
                            )
                          : null,
                      suffixIcon: isPasswordIncorrect
                          ? const Icon(Icons.error, color: Colors.red)
                          : null,
                    ),
                    obscureText: true,
                    onChanged: (value) {
                      // Clear stale error when user edits password
                      if (signInError != null || isPasswordIncorrect) {
                        setState(() {
                          signInError = null;
                          isPasswordIncorrect = false;
                        });
                      } else {
                        // Trigger rebuild to enable/disable Sign In button
                        setState(() {});
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if (!needsPasswordSetup)
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close sign in dialog
                  _showForgotPasswordFlow(context);
                },
                child: const Text('Forgot Password?'),
              ),
            ElevatedButton(
              onPressed:
                  isEmailValid &&
                      passwordController.text.isNotEmpty &&
                      (!needsPasswordSetup ||
                          (passwordController.text.length >= 6 &&
                              passwordController.text ==
                                  confirmPasswordController.text))
                  ? () async {
                      final email = emailController.text;
                      final password = passwordController.text;

                      if (needsPasswordSetup) {
                        // Handle admin-created user password setup
                        try {
                          if (kDebugMode) {
                            print(
                              '🔐 WelcomePage: Setting up password for admin-created user: $email',
                            );
                          }

                          // First sign in with temp password to get session
                          // We need to get the temp password from somewhere...
                          // Actually, we can't sign in without knowing the temp password
                          // So we need to use the password reset flow instead

                          // Send OTP for password reset
                          await SupabaseService.instance.client.auth
                              .resetPasswordForEmail(email);

                          if (!mounted) return;

                          Navigator.pop(
                            dialogContext,
                          ); // Close password setup dialog

                          // Show OTP dialog for verification
                          _showOtpVerificationForPasswordSetup(
                            parentContext,
                            email,
                            password,
                          );

                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please check your email for the verification code',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (kDebugMode) {
                            print('🔐 WelcomePage: Password setup error: $e');
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(content: Text('Error: ${e.toString()}')),
                            );
                          }
                        }
                        return;
                      }

                      // Regular sign-in flow
                      // Check if user is already signed in
                      final currentUser = SupabaseService.instance
                          .getCurrentUser();
                      if (currentUser != null && currentUser.email == email) {
                        if (kDebugMode) {
                          print(
                            '🔐 WelcomePage: User already signed in: ${currentUser.id}',
                          );
                        }
                        await _startSmoothSignInTransition(
                          parentContext,
                          dialogContext,
                          currentUser.id,
                        );
                        return;
                      }

                      try {
                        if (kDebugMode) {
                          print(
                            '🔐 WelcomePage: Attempting sign in for email: $email',
                          );
                        }

                        // Email existence + deactivation already verified
                        // while the user typed (button is disabled otherwise),
                        // so skip the redundant network round-trip here.
                        final response = await SupabaseService.instance.signIn(
                          email: email,
                          password: password,
                        );
                        if (kDebugMode) {
                          print(
                            '🔐 WelcomePage: Sign in response received, user: ${response.user?.id}',
                          );
                        }

                        if (response.user != null) {
                          // Start the smooth transition flow
                          await _startSmoothSignInTransition(
                            parentContext,
                            dialogContext,
                            response.user!.id,
                          );
                        } else {
                          if (kDebugMode) {
                            print(
                              '🔐 WelcomePage: Sign in response has no user',
                            );
                          }
                          try {
                            if (mounted) {
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Sign in failed - no user returned',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            // Context might be invalid
                          }
                        }
                      } catch (e) {
                        if (kDebugMode) {
                          print('🔐 WelcomePage: Sign in error: $e');
                        }
                        final errorString = e.toString();
                        String errorMessage = 'Sign in error: $errorString';
                        bool wrongPassword = false;
                        if (errorString.contains('Invalid login credentials')) {
                          errorMessage =
                              'Incorrect password. Please try again.';
                          wrongPassword = true;
                        } else if (errorString.contains(
                          'Email not confirmed',
                        )) {
                          errorMessage =
                              'Please check your email and confirm your account';
                        } else if (errorString.contains(
                          'over_email_send_rate_limit',
                        )) {
                          errorMessage =
                              'Too many attempts. Please wait before trying again';
                        }
                        if (mounted) {
                          setState(() {
                            signInError = errorMessage;
                            isPasswordIncorrect = wrongPassword;
                          });
                          if (wrongPassword) {
                            // Clear the password and drop focus so the
                            // keyboard collapses and the inline error banner
                            // is visible to the user.
                            passwordController.clear();
                            passwordFocusNode.unfocus();
                            FocusScope.of(parentContext).unfocus();
                          }
                          ScaffoldMessenger.of(parentContext)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(errorMessage),
                                backgroundColor: wrongPassword
                                    ? Colors.red
                                    : null,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                        }
                      }
                    }
                  : null,
              child: const Text('Sign In'),
            ),
          ],
        ),
      ),
    );
  }

  void _showOtpSigninDialog(BuildContext context) {
    final emailController = TextEditingController();
    final parentContext = context;

    // Email validation state
    bool isEmailValid = false;
    bool isCheckingEmail = false;
    Timer? emailCheckTimer;
    bool emailIsDeactivated = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Sign In with OTP'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter your email address',
                    errorText:
                        emailController.text.isNotEmpty &&
                            !isCheckingEmail &&
                            (emailIsDeactivated || !isEmailValid)
                        ? emailIsDeactivated
                              ? 'Account is deactivated. Please reactivate to sign in.'
                              : 'Email not found'
                        : null,
                    suffixIcon: isCheckingEmail
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : emailController.text.isNotEmpty
                        ? Icon(
                            emailIsDeactivated
                                ? Icons.block
                                : isEmailValid
                                ? Icons.check_circle
                                : Icons.error,
                            color: emailIsDeactivated
                                ? Colors.red
                                : isEmailValid
                                ? Colors.green
                                : Colors.red,
                          )
                        : null,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (value) {
                    // Cancel previous timer
                    emailCheckTimer?.cancel();

                    if (value.isEmpty) {
                      setState(() {
                        isEmailValid = false;
                        isCheckingEmail = false;
                        emailIsDeactivated = false;
                      });
                      return;
                    }

                    // Debounce email validation (short to feel instant while typing)
                    emailCheckTimer = Timer(
                      const Duration(milliseconds: 300),
                      () async {
                        final trimmed = value.trim();
                        setState(() => isCheckingEmail = true);

                        if (kDebugMode) {
                          print(
                            '🔐 WelcomePage: Validating email (otp signin): "$trimmed"',
                          );
                        }
                        final exists = await SupabaseService.instance
                            .checkEmailExists(trimmed);
                        if (kDebugMode) {
                          print(
                            '🔐 WelcomePage: Email validation result (otp signin): $exists',
                          );
                        }

                        // If user kept typing, abort: a newer timer will handle it
                        if (trimmed != emailController.text.trim()) return;

                        final isDeactivated = exists
                            ? await SupabaseService.instance.isEmailDeactivated(
                                trimmed,
                              )
                            : false;

                        if (mounted && isDeactivated) {
                          setState(() {
                            isEmailValid = false;
                            isCheckingEmail = false;
                            emailIsDeactivated = true;
                          });
                          return;
                        }

                        if (mounted) {
                          setState(() {
                            emailIsDeactivated = false;
                            isEmailValid = exists;
                            isCheckingEmail = false;
                          });
                        }
                      },
                    );
                  },
                ),
                const SizedBox(height: 10),
                const Text(
                  'We\'ll send a 6-digit code to your email for verification.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isEmailValid
                  ? () async {
                      final email = emailController.text.trim();

                      try {
                        final isDeactivated = await SupabaseService.instance
                            .isEmailDeactivated(email);
                        if (isDeactivated) {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'This account is deactivated. Please reactivate to sign in.',
                              ),
                            ),
                          );
                          return;
                        }

                        Navigator.pop(dialogContext); // Close email dialog

                        // Show OTP verification dialog with merchant check
                        if (mounted) {
                          showDialog(
                            context: parentContext,
                            barrierDismissible: false,
                            builder: (c) => OtpVerificationDialog(
                              email: email,
                              isForSignIn: true,
                              onVerificationSuccess: (String? userId) async {
                                // Start smooth sign-in transition (dialog will be closed by the method)
                                await _startSmoothSignInTransition(
                                  parentContext,
                                  parentContext, // Use parentContext as dialogContext since OTP dialog is modal
                                  userId!,
                                );
                              },
                            ),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(
                          parentContext,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  : null,
              child: const Text('Send OTP'),
            ),
          ],
        ),
      ),
    );
  }

  void _showOtpVerificationForTrustedPartner(
    BuildContext context,
    String email,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verify Your Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'An OTP has been sent to your email. Please enter it below to verify your account.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text('Email:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(email),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (c) => OtpVerificationDialog(
                  email: email,
                  isForSignIn: true,
                  onVerificationSuccess: (String? userId) async {
                    if (userId == null) return;

                    final profile = await SupabaseService.instance.client
                        .from('profiles')
                        .select('password_set')
                        .eq('id', userId)
                        .maybeSingle();

                    final passwordSet =
                        profile?['password_set'] as bool? ?? true;

                    if (!passwordSet) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) =>
                              SetPasswordPage(email: email, userId: userId),
                        ),
                      );
                    } else {
                      await _startSmoothSignInTransition(
                        context,
                        context,
                        userId,
                      );
                    }
                  },
                ),
              );
            },
            child: const Text('Enter OTP'),
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: const Text('Home'),
        actions: [
          const SizedBox(width: 8),
          // Logout button with confirmation to avoid accidental logouts.
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              final should = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Confirm logout'),
                  content: const Text(
                    'Are you sure you want to sign out from this device?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );

              if (should == true) {
                await SupabaseService.instance.signOut();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const WelcomePage()),
                  (route) => false, // Remove all previous routes
                );
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: const Center(child: Text('Welcome to Local Lekker!')),
    );
  }
}
