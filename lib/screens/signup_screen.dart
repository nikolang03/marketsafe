import 'package:capstone2/services/email_service.dart';
import 'package:capstone2/services/user_check_service.dart';
import 'package:capstone2/services/network_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'otp_screen.dart';
import '../widgets/terms_and_conditions_dialog.dart';

class SignUpScreen extends StatefulWidget {
  final bool? hasAgreedToTerms;
  
  const SignUpScreen({
    super.key,
    this.hasAgreedToTerms,
  });

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _inputController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _inputType; // 'phone' or 'email'
  late bool _hasAgreedToTerms;

  @override
  void initState() {
    super.initState();
    // If coming from welcome screen with agreement, set it to true
    _hasAgreedToTerms = widget.hasAgreedToTerms ?? false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set global context for network monitoring overlays
    NetworkService.setGlobalContext(context);
    // Start monitoring network connectivity
    NetworkService.startMonitoring();
  }

  @override
  void dispose() {
    // Stop network monitoring when leaving the screen
    NetworkService.stopMonitoring();
    _inputController.dispose();
    super.dispose();
  }

  void _detectInputType(String input) {
    // Check if it's a Philippine phone number (starts with 09, 10 digits total)
    if (RegExp(r'^09\d{9}$').hasMatch(input)) {
      _inputType = 'phone';
    } else if (input.contains('@')) {
      _inputType = 'email';
    } else {
      _inputType = null;
    }
  }

  String _formatPhoneNumber(String phone) {
    // Convert 09123456789 to +639123456789
    if (phone.startsWith('09')) {
      return '+63${phone.substring(1)}';
    }
    return phone;
  }

  Future<void> _sendOtp() async {
    // Check network connection first
    final isConnected = await NetworkService.checkConnectivity();
    if (!isConnected) {
      if (mounted) {
        NetworkService.showNetworkErrorDialog(
          context,
          'No internet connection. Please check your network and try again.',
          onRetry: () => _sendOtp(),
        );
      }
      return;
    }

    // Check if user has agreed to terms
    if (!_hasAgreedToTerms) {
      final agreed = await TermsAndConditionsDialog.show(context);
      if (agreed != true) {
        setState(() => _errorMessage = 'You must agree to the Terms and Conditions to continue');
        return;
      }
      setState(() => _hasAgreedToTerms = true);
    }

    final input = _inputController.text.trim();

    if (input.isEmpty) {
      setState(() => _errorMessage = 'Please enter your phone number or email');
      return;
    }

    // Detect input type
    _detectInputType(input);

    if (_inputType == null) {
      setState(() => _errorMessage =
          'Please enter a valid phone number (09123456789) or email address');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check if user already exists with network retry and loading
      print('🔍 Checking if user already exists...');
      final userCheck = await NetworkService.executeWithRetry(
        () => UserCheckService.checkUserExists(input),
        maxRetries: 3,
        retryDelay: const Duration(seconds: 2),
        loadingMessage: 'Checking if user exists...',
        context: context,
        showNetworkErrors: true,
      );
      
      if (userCheck['exists']) {
        setState(() {
          _isLoading = false;
          _errorMessage = userCheck['message'];
        });
        return;
      }

      print('✅ User does not exist - proceeding with OTP...');

      if (_inputType == 'phone') {
        // Phone verification - convert to international format
        String phoneNumber = _formatPhoneNumber(input);

        // Check network before starting phone verification
        final isConnected = await NetworkService.checkConnectivity();
        if (!isConnected) {
          if (mounted) {
            setState(() => _isLoading = false);
            NetworkService.showNetworkErrorDialog(
              context,
              'No internet connection',
              onRetry: () => _sendOtp(),
            );
          }
          return;
        }

        // Keep loading indicator showing while waiting for Chrome/reCAPTCHA
        // Note: verifyPhoneNumber uses callbacks, so we can't wrap it in executeWithRetry
        // Instead, we check network before calling it and show loading via _isLoading state
        try {
          await FirebaseAuth.instance.verifyPhoneNumber(
            phoneNumber: phoneNumber,
            timeout: const Duration(seconds: 60),
            verificationCompleted: (PhoneAuthCredential credential) async {
              // Auto sign-in
              if (mounted) {
                setState(() => _isLoading = false);
              }
            },
            verificationFailed: (FirebaseAuthException e) {
              if (mounted) {
                // Check if it's a network error
                final isNetworkError = e.code == 'network-request-failed' || 
                                      e.message?.toLowerCase().contains('network') == true ||
                                      e.message?.toLowerCase().contains('connection') == true;
                
                if (isNetworkError) {
                  NetworkService.showNetworkErrorDialog(
                    context,
                    e.message ?? 'Network error during phone verification',
                    onRetry: () => _sendOtp(),
                  );
                } else {
                  setState(() {
                    _isLoading = false;
                    _errorMessage = e.message;
                  });
                }
              }
            },
            codeSent: (String verificationId, int? resendToken) {
              // Hide loading when code is sent (user returned from Chrome)
              if (mounted) {
                setState(() => _isLoading = false);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OtpVerificationScreen(
                      verificationId: verificationId,
                      phoneNumber: input, // Keep original format for display
                      verificationType: 'phone',
                    ),
                  ),
                );
              }
            },
            codeAutoRetrievalTimeout: (_) {
              // Timeout - hide loading
              if (mounted) {
                setState(() => _isLoading = false);
              }
            },
          );
        } catch (e) {
          // Handle any synchronous errors
          if (mounted) {
            final errorStr = e.toString();
            final isNetworkError = errorStr.toLowerCase().contains('network') ||
                                  errorStr.toLowerCase().contains('connection');
            
            if (isNetworkError) {
              setState(() => _isLoading = false);
              NetworkService.showNetworkErrorDialog(
                context,
                'Network error: $errorStr',
                onRetry: () => _sendOtp(),
              );
            } else {
              setState(() {
                _isLoading = false;
                _errorMessage = errorStr;
              });
            }
          }
        }
        // Note: Don't set _isLoading = false here - wait for codeSent callback
        // This keeps the loading indicator showing while Chrome opens and user completes reCAPTCHA
      } else {
        // Email verification with network retry and loading
        await NetworkService.executeWithRetry(
          () => EmailService.sendOtp(input),
          maxRetries: 3,
          retryDelay: const Duration(seconds: 2),
          loadingMessage: 'Sending verification email...',
          context: context,
          showNetworkErrors: true,
        );

        setState(() => _isLoading = false);
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              verificationId: '', // Not needed for email
              phoneNumber: input, // Reusing phoneNumber field for email
              verificationType: 'email',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ensure global context is set for network monitoring
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NetworkService.setGlobalContext(context);
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black, Color(0xFF2B0000)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - 
                            MediaQuery.of(context).padding.top - 
                            MediaQuery.of(context).padding.bottom - 48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    Image.asset('assets/logo.png', height: 80),
                    const SizedBox(height: 30),
                    const Text(
                      "SIGN UP",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Terms and Conditions Agreement
                    if (!_hasAgreedToTerms)
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.5)),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.red, size: 24),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'You must agree to the Terms and Conditions to continue',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final agreed = await TermsAndConditionsDialog.show(context);
                                  if (agreed == true) {
                                    setState(() {
                                      _hasAgreedToTerms = true;
                                    });
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  'View Terms and Conditions',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Single input field for phone or email
                    TextField(
                      controller: _inputController,
                      enabled: _hasAgreedToTerms,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        labelText: "Phone Number or Email",
                        hintText: _hasAgreedToTerms 
                            ? "Enter 09123456789 or your@email.com"
                            : "Please agree to Terms and Conditions first",
                        prefixIcon: const Icon(Icons.person, color: Colors.white),
                        labelStyle: TextStyle(
                          color: _hasAgreedToTerms ? Colors.white : Colors.white54,
                        ),
                        hintStyle: TextStyle(
                          color: _hasAgreedToTerms ? Colors.grey : Colors.white38,
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: _hasAgreedToTerms ? Colors.white : Colors.white38,
                          ),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.red),
                        ),
                        disabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38),
                        ),
                      ),
                      style: TextStyle(
                        color: _hasAgreedToTerms ? Colors.white : Colors.white54,
                      ),
                      onTap: () {
                        if (!_hasAgreedToTerms) {
                          // Show terms dialog when user tries to interact with field
                          TermsAndConditionsDialog.show(context).then((agreed) {
                            if (agreed == true) {
                              setState(() {
                                _hasAgreedToTerms = true;
                              });
                            }
                          });
                        }
                      },
                      onChanged: (value) {
                        // Clear error message when user starts typing
                        if (_errorMessage != null) {
                          setState(() => _errorMessage = null);
                        }
                        // Detect input type as user types
                        _detectInputType(value);
                        setState(() {}); // Update UI to show detected type
                      },
                    ),

                    const SizedBox(height: 10),

                    // Show detected input type
                    if (_inputController.text.isNotEmpty)
                      Text(
                        _inputType == 'phone'
                            ? "📱 Phone verification will be used"
                            : _inputType == 'email'
                                ? "📧 Email verification will be used"
                                : "❌ Invalid format",
                        style: TextStyle(
                          color: _inputType != null ? Colors.green : Colors.red,
                          fontSize: 12,
                        ),
                      ),

                    const SizedBox(height: 20),

                    if (_errorMessage != null)
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),

                    const SizedBox(height: 30),

                    SizedBox(
                      width: 180,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _sendOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: _isLoading
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  if (_inputType == 'phone') ...[
                                    const SizedBox(width: 8),
                                    const Text(
                                      "Opening...",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : const Text(
                                "SEND OTP",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ),
                    
                    // Show helpful message when loading for phone verification
                    if (_isLoading && _inputType == 'phone')
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Text(
                          "Please complete the verification in Chrome...",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    const SizedBox(height: 20),

                    // Help text
                    const Text(
                      "Enter your phone number (09123456789) or email address",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
