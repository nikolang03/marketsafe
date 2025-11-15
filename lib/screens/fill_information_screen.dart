import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_check_service.dart';
import '../services/production_face_recognition_service.dart';
import '../services/face_auth_backend_service.dart';
import '../services/network_service.dart';
import 'add_profile_photo_screen.dart';

class FillInformationScreen extends StatefulWidget {
  const FillInformationScreen({super.key});

  @override
  State<FillInformationScreen> createState() => _FillInformationScreenState();
}

class _FillInformationScreenState extends State<FillInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _selectedDate;
  bool _isLoading = false;

  // Controllers for fields
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController ageController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController birthdayController = TextEditingController();

  String? gender; // Male or Female
  
  // Test enrollment cleanup tracking
  String _pendingTestUuidCleanup = '';
  String _pendingTestEmail = '';

  /// Get face verification data from SharedPreferences
  Future<Map<String, dynamic>> _getFaceVerificationDataWithoutUpload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get completion status
      final blinkCompleted = prefs.getBool('face_verification_blinkCompleted') ?? false;
      final moveCloserCompleted = prefs.getBool('face_verification_moveCloserCompleted') ?? false;
      final headMovementCompleted = prefs.getBool('face_verification_headMovementCompleted') ?? false;
      
      // Get completion timestamps
      final blinkCompletedAt = prefs.getString('face_verification_blinkCompletedAt') ?? '';
      final moveCloserCompletedAt = prefs.getString('face_verification_moveCloserCompletedAt') ?? '';
      final headMovementCompletedAt = prefs.getString('face_verification_headMovementCompletedAt') ?? '';
      
      // Get image paths (only if they exist and are not empty)
      final blinkImagePath = prefs.getString('face_verification_blinkImagePath');
      final moveCloserImagePath = prefs.getString('face_verification_moveCloserImagePath');
      final headMovementImagePath = prefs.getString('face_verification_headMovementImagePath');
      
      // Get metrics (only if they exist and are not empty)
      final blinkMetrics = prefs.getString('face_verification_blinkMetrics');
      final moveCloserMetrics = prefs.getString('face_verification_moveCloserMetrics');
      final headMovementMetrics = prefs.getString('face_verification_headMovementMetrics');
      
      // Get face features (only if they exist and are not empty)
      final blinkFeatures = prefs.getString('face_verification_blinkFeatures');
      final moveCloserFeatures = prefs.getString('face_verification_moveCloserFeatures');
      final headMovementFeatures = prefs.getString('face_verification_headMovementFeatures');
      
      print('📊 Retrieved face verification data:');
      print('  - Blink completed: $blinkCompleted');
      print('  - Move closer completed: $moveCloserCompleted');
      print('  - Head movement completed: $headMovementCompleted');
      if (blinkImagePath != null && blinkImagePath.isNotEmpty) {
        print('  - Blink image path: $blinkImagePath');
      }
      if (moveCloserImagePath != null && moveCloserImagePath.isNotEmpty) {
        print('  - Move closer image path: $moveCloserImagePath');
      }
      if (headMovementImagePath != null && headMovementImagePath.isNotEmpty) {
        print('  - Head movement image path: $headMovementImagePath');
      }
      
      // Build return map - only include fields that have actual values
      final Map<String, dynamic> faceData = {
        'blinkCompleted': blinkCompleted,
        'moveCloserCompleted': moveCloserCompleted,
        'headMovementCompleted': headMovementCompleted,
        'verificationTimestamp': DateTime.now().toIso8601String(),
      };
      
      // Only add completion timestamps if they exist
      if (blinkCompletedAt.isNotEmpty) {
        faceData['blinkCompletedAt'] = blinkCompletedAt;
      }
      if (moveCloserCompletedAt.isNotEmpty) {
        faceData['moveCloserCompletedAt'] = moveCloserCompletedAt;
      }
      if (headMovementCompletedAt.isNotEmpty) {
        faceData['headMovementCompletedAt'] = headMovementCompletedAt;
      }
      
      // Only add image paths if they exist and are not empty
      if (blinkImagePath != null && blinkImagePath.isNotEmpty) {
        faceData['blinkImagePath'] = blinkImagePath;
      }
      if (moveCloserImagePath != null && moveCloserImagePath.isNotEmpty) {
        faceData['moveCloserImagePath'] = moveCloserImagePath;
      }
      if (headMovementImagePath != null && headMovementImagePath.isNotEmpty) {
        faceData['headMovementImagePath'] = headMovementImagePath;
      }
      
      // Only add metrics if they exist and are not empty (and not just '{}')
      if (blinkMetrics != null && blinkMetrics.isNotEmpty && blinkMetrics != '{}') {
        faceData['blinkMetrics'] = blinkMetrics;
      }
      if (moveCloserMetrics != null && moveCloserMetrics.isNotEmpty && moveCloserMetrics != '{}') {
        faceData['moveCloserMetrics'] = moveCloserMetrics;
      }
      if (headMovementMetrics != null && headMovementMetrics.isNotEmpty && headMovementMetrics != '{}') {
        faceData['headMovementMetrics'] = headMovementMetrics;
      }
      
      // Only add face features if they exist and are not empty
      if (blinkFeatures != null && blinkFeatures.isNotEmpty) {
        faceData['blinkFeatures'] = blinkFeatures;
      }
      if (moveCloserFeatures != null && moveCloserFeatures.isNotEmpty) {
        faceData['moveCloserFeatures'] = moveCloserFeatures;
      }
      if (headMovementFeatures != null && headMovementFeatures.isNotEmpty) {
        faceData['headMovementFeatures'] = headMovementFeatures;
      }
      
      return faceData;
    } catch (e) {
      print('❌ Error retrieving face verification data: $e');
      // Return basic completion status if data retrieval fails
      return {
        'blinkCompleted': true,
        'moveCloserCompleted': true,
        'headMovementCompleted': true,
        'verificationTimestamp': DateTime.now().toIso8601String(),
        'error': 'Failed to retrieve detailed face verification data',
      };
    }
  }

  Future<void> _submitForm() async {
    if (!mounted) return;
    
    if (_formKey.currentState!.validate() &&
        gender != null &&
        _selectedDate != null) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Get signup data from OTP verification (stored in SharedPreferences)
        final prefs = await SharedPreferences.getInstance();
        final userEmail = prefs.getString('signup_email') ?? '';
        final userPhone = prefs.getString('signup_phone') ?? '';
        
        if (userEmail.isEmpty && userPhone.isEmpty) {
          throw Exception('No signup data found. Please restart the signup process.');
        }
        
        print('✅ Submitting signup form for: ${userEmail.isNotEmpty ? userEmail : userPhone}');
        
        // Final duplicate check before saving with network retry and loading
        print('🔍 Final duplicate check before saving user data...');
        
        if (userEmail.isNotEmpty) {
          final emailCheck = await NetworkService.executeWithRetry(
            () => UserCheckService.checkUserExists(userEmail),
            maxRetries: 3,
            retryDelay: const Duration(seconds: 2),
            loadingMessage: 'Checking email availability...',
            context: context,
            showNetworkErrors: true,
          );
          if (emailCheck['exists']) {
            throw Exception('This email is already registered. Please use a different email or try logging in.');
          }
        }
        
        if (userPhone.isNotEmpty) {
          final phoneCheck = await NetworkService.executeWithRetry(
            () => UserCheckService.checkUserExists(userPhone),
            maxRetries: 3,
            retryDelay: const Duration(seconds: 2),
            loadingMessage: 'Checking phone availability...',
            context: context,
            showNetworkErrors: true,
          );
          if (phoneCheck['exists']) {
            throw Exception('This phone number is already registered. Please use a different phone number or try logging in.');
          }
        }
        
        print('✅ Final duplicate check passed - proceeding with user registration');
        
        // Check username uniqueness with network retry and loading
        final username = usernameController.text.trim();
        if (username.isEmpty) {
          throw Exception('Username is required');
        }
        
        final usernameTaken = await NetworkService.executeWithRetry(
          () => UserCheckService.isUsernameTaken(username),
          maxRetries: 3,
          retryDelay: const Duration(seconds: 2),
          loadingMessage: 'Checking username availability...',
          context: context,
          showNetworkErrors: true,
        );
        if (usernameTaken) {
          throw Exception('This username is already taken. Please choose a different username.');
        }
        
        print('✅ Username check passed - username is available');
        
        // Parse age safely with validation
        final age = int.tryParse(ageController.text);
        if (age == null) {
          throw Exception('Invalid age format');
        }
        if (age < 13) {
          throw Exception('You must be at least 13 years old to use this app');
        }
        if (age > 150) {
          throw Exception('Please enter a valid age');
        }
        
        // Validate email format if email signup
        if (userEmail.isNotEmpty) {
          final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
          if (!emailRegex.hasMatch(userEmail)) {
            throw Exception('Please enter a valid email address');
          }
        }
        
        // Validate phone format if phone signup
        if (userPhone.isNotEmpty) {
          // Remove spaces and special characters for validation
          final cleanPhone = userPhone.replaceAll(RegExp(r'[^\d+]'), '');
          if (cleanPhone.length < 10 || cleanPhone.length > 15) {
            throw Exception('Please enter a valid phone number');
          }
        }

        print('🔄 Starting to save user data to Firestore...');
        print('👤 Username: ${usernameController.text.trim()}');
        print('🏠 Address: ${addressController.text.trim()}');

        // CRITICAL: Check for duplicate face BEFORE creating user account
        // This prevents creating accounts when face is already registered
        print('🔍 [PRE-CHECK] Checking for duplicate face before creating account...');
        try {
          final identifier = userEmail.isNotEmpty ? userEmail : userPhone;
          if (identifier.isNotEmpty) {
            // Get one face image to check for duplicates
            final moveCloserImagePath = prefs.getString('face_verification_moveCloserImagePath');
            
            if (moveCloserImagePath != null && moveCloserImagePath.isNotEmpty) {
              final imageFile = File(moveCloserImagePath);
              if (await imageFile.exists()) {
                final imageBytes = await imageFile.readAsBytes();
                
                // Try to enroll one face to check for duplicates
                // This will fail if duplicate is detected, and we can block account creation
                print('🔍 [PRE-CHECK] Testing enrollment with one face image to check for duplicates...');
                // Call backend directly to check for duplicates (doesn't require user to exist)
                // Use the same backend URL as ProductionFaceRecognitionService
                const backendUrl = String.fromEnvironment(
                  'FACE_AUTH_BACKEND_URL',
                  defaultValue: 'https://marketsafe-production.up.railway.app',
                );
                final backendService = FaceAuthBackendService(backendUrl: backendUrl);
                final testEnrollResult = await NetworkService.executeWithRetry(
                  () => backendService.enroll(
                    email: identifier,
                    photoBytes: imageBytes,
                  ),
                  maxRetries: 3,
                  retryDelay: const Duration(seconds: 2),
                  loadingMessage: 'Checking for duplicate face...',
                  context: context,
                  showNetworkErrors: true,
                );
                
                if (testEnrollResult['success'] != true) {
                  final errorMessage = testEnrollResult['error']?.toString() ?? 'Unknown error';
                  final reason = testEnrollResult['reason']?.toString() ?? '';
                  
                  // Check if this is a duplicate face error
                  final isDuplicateFace = reason == 'duplicate_face' ||
                                          errorMessage.toLowerCase().contains('already registered') ||
                                          errorMessage.toLowerCase().contains('duplicate') ||
                                          errorMessage.toLowerCase().contains('different account');
                  
                  if (isDuplicateFace && mounted) {
                    print('🚨 [PRE-CHECK] Duplicate face detected! Blocking account creation.');
                    _showErrorDialog(
                      'Account Already Exists',
                      errorMessage.isNotEmpty 
                        ? errorMessage
                        : 'This face is already registered with a different account. You cannot create multiple accounts with the same face. Please use your existing account or contact support if you believe this is an error.',
                      navigateToWelcome: true, // Navigate to welcome screen on OK
                    );
                    setState(() {
                      _isLoading = false;
                    });
                    return; // BLOCK account creation
                  }
                } else {
                  // If test enrollment succeeded, store UUID for cleanup later
                  final testUuid = testEnrollResult['uuid']?.toString() ?? '';
                  if (testUuid.isNotEmpty) {
                    print('🔍 [PRE-CHECK] Test enrollment succeeded. UUID: $testUuid');
                    // Store test UUID for cleanup later
                    _pendingTestUuidCleanup = testUuid;
                    _pendingTestEmail = identifier;
                  }
                }
              }
            }
          }
        } catch (preCheckError) {
          print('⚠️ [PRE-CHECK] Error during duplicate check: $preCheckError');
          // If pre-check fails, we should still block to be safe
          if (mounted) {
            _showErrorDialog(
              'Verification Error',
              'Unable to verify face uniqueness. Please try again or contact support.',
            );
            setState(() {
              _isLoading = false;
            });
            return;
          }
        }
        
        print('✅ [PRE-CHECK] Duplicate check passed. Proceeding with account creation...');

        // Always use custom format: user_{timestamp}_{username}
        // Sanitize username: lowercase, remove spaces and special characters (keep alphanumeric and underscore)
        // Note: username is already declared above, so we reuse it here
        if (username.isEmpty) {
          throw Exception('Username is required for user ID generation');
        }
        
        // Sanitize username: lowercase, replace spaces with nothing, keep only alphanumeric and underscore
        final sanitizedUsername = username
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9_]'), '') // Remove special characters except underscore
            .replaceAll(' ', ''); // Remove spaces
        
        if (sanitizedUsername.isEmpty) {
          throw Exception('Username must contain at least one alphanumeric character');
        }
        
        // Generate user ID in format: user_{timestamp}_{sanitizedUsername}
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final userId = 'user_${timestamp}_$sanitizedUsername';
        
        print('🆔 Generated user ID: $userId (format: user_{timestamp}_{username})');
        print('   - Timestamp: $timestamp');
        print('   - Original username: $username');
        print('   - Sanitized username: $sanitizedUsername');
        
        // Check if user document already exists (from AdminSyncService.initializeUser) with network retry
        final existingDoc = await NetworkService.executeWithRetry(
          () => FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'marketsafe',
          ).collection('users').doc(userId).get(),
          maxRetries: 3,
          retryDelay: const Duration(seconds: 2),
          loadingMessage: 'Checking user data...',
          context: context,
          showNetworkErrors: true,
        );
        
        if (existingDoc.exists) {
          print('⚠️ User document already exists - will update instead of creating new');
        }
        
        // Store the user ID and username in SharedPreferences for later verification checks
        await prefs.setString('signup_user_id', userId);
        await prefs.setString('signup_user_name', usernameController.text.trim());
        print('🆔 Stored signup user ID: $userId');
        print('👤 Stored signup username: ${usernameController.text.trim()}');
        
        // Get face verification data
        final faceData = await _getFaceVerificationDataWithoutUpload();
        
        // NOTE: biometricFeatures is DEPRECATED - new system uses face_embeddings collection
        // Face embeddings are stored separately in face_embeddings/{userId} collection
        // This is handled by ProductionFaceRecognitionService during registration
        
        // Get profile picture URL from SharedPreferences if available
        final profilePhotoUrl = prefs.getString('profile_photo_url') ?? '';
        
        // Get Firebase Auth UID for security rules
        final firebaseUser = FirebaseAuth.instance.currentUser;
        final firebaseAuthUid = firebaseUser?.uid ?? '';
        
        final userData = {
          'uid': userId,
          'firebaseAuthUid': firebaseAuthUid, // ADDED: For Firestore security rules
          'phoneNumber': userPhone,
          'email': userEmail,
          'username': username.trim().toLowerCase(), // Store username in lowercase for consistency
          'firstName': firstNameController.text.trim(),
          'lastName': lastNameController.text.trim(),
          'age': age,
          'address': addressController.text.trim(),
          'birthday': _selectedDate!,
          'gender': gender!,
          'profilePictureUrl': profilePhotoUrl,
          'verificationStatus': 'pending',
          'signupCompleted': true, // Mark signup as completed
          'createdAt': FieldValue.serverTimestamp(),
          'faceData': faceData,
          // REMOVED: 'biometricFeatures' - DEPRECATED (old 64D format)
          // New system uses face_embeddings collection with 512D real embeddings
          // Stored by ProductionFaceRecognitionService during registration
          'isSignupUser': true, // Mark as signup user (not authenticated yet)
          // Don't include isTemporaryUser field - it will be removed when we overwrite the document
        };
        
        print('🔍 User data being saved to Firestore:');
        print('  - User ID: $userId');
        print('  - Email: $userEmail');
        print('  - Phone: $userPhone');
        print('  - Username: ${usernameController.text.trim()}');
        print('  - First Name: ${firstNameController.text.trim()}');
        print('  - Last Name: ${lastNameController.text.trim()}');
        print('  - Age: $age');
        print('  - Address: ${addressController.text.trim()}');
        print('  - Birthday: $_selectedDate');
        print('  - Gender: $gender');
        print('  - Face data keys: ${faceData.keys.toList()}');
        print('  - Face embeddings: Stored in face_embeddings collection (new system)');
        print('  - NOTE: biometricFeatures removed (deprecated - old 64D format)');
        
        // Save the complete user data (this will overwrite the document and remove isTemporaryUser)
        // Use set() with merge: true to update existing document if it exists (from AdminSyncService)
        // Wrap with network retry and loading
        await NetworkService.executeWithRetry(
          () => FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'marketsafe',
          )
              .collection('users')
              .doc(userId)
              .set(userData, SetOptions(merge: true)),
          maxRetries: 3,
          retryDelay: const Duration(seconds: 2),
          loadingMessage: 'Saving your information...',
          context: context,
          showNetworkErrors: true,
        );

        print('✅ User data saved successfully to Firestore with signup ID: $userId');

        // CRITICAL: Enroll the 3 facial verification images to Luxand
        // This must happen after the form is submitted and user document is created
        // The profile photo upload will then verify against this enrolled face
        print('🔄 Enrolling 3 facial verification images to Luxand...');
        try {
          final identifier = userEmail.isNotEmpty ? userEmail : userPhone;
          if (identifier.isNotEmpty) {
            // Pass userId directly to ensure we update the correct document
            // Wrap with network retry and loading
            final enrollResult = await NetworkService.executeWithRetry(
              () => ProductionFaceRecognitionService.enrollAllThreeFaces(
                email: identifier,
                userId: userId, // Pass userId directly to avoid query issues
              ),
              maxRetries: 3,
              retryDelay: const Duration(seconds: 3),
              loadingMessage: 'Enrolling face verification...',
              context: context,
              showNetworkErrors: true,
            );
            
            if (enrollResult['success'] == true) {
              final luxandUuid = enrollResult['luxandUuid']?.toString();
              final enrolledCount = enrollResult['enrolledCount'] as int? ?? 0;
              print('✅ Enrolled $enrolledCount face(s) from 3 verification steps. UUID: $luxandUuid');
              
              // Clean up test enrollment if it exists
              if (_pendingTestUuidCleanup.isNotEmpty) {
                await _cleanupTestEnrollment(_pendingTestUuidCleanup, _pendingTestEmail);
                _pendingTestUuidCleanup = '';
                _pendingTestEmail = '';
              }
              
              // Verify the UUID was saved to Firestore with network retry
              await Future.delayed(const Duration(milliseconds: 500));
              final verifyDoc = await NetworkService.executeWithRetry(
                () => FirebaseFirestore.instanceFor(
                  app: Firebase.app(),
                  databaseId: 'marketsafe',
                ).collection('users').doc(userId).get(),
                maxRetries: 2,
                retryDelay: const Duration(seconds: 1),
                loadingMessage: 'Verifying enrollment...',
                context: context,
                showNetworkErrors: false, // Don't show errors for verification
              );
              
              if (verifyDoc.exists) {
                final savedUuid = verifyDoc.data()?['luxandUuid']?.toString() ?? '';
                if (savedUuid.isNotEmpty) {
                  print('✅ Verified UUID saved to Firestore: $savedUuid');
                } else {
                  print('⚠️ WARNING: UUID not found in Firestore after enrollment');
                }
              }
            } else {
              final errorMessage = enrollResult['error']?.toString() ?? 'Unknown error';
              final reason = enrollResult['reason']?.toString() ?? '';
              print('⚠️ Failed to enroll faces from 3 verification steps: $errorMessage');
              
              // Even if enrollment fails, clean up test enrollment
              if (_pendingTestUuidCleanup.isNotEmpty) {
                await _cleanupTestEnrollment(_pendingTestUuidCleanup, _pendingTestEmail);
                _pendingTestUuidCleanup = '';
                _pendingTestEmail = '';
              }
              
              // Check if this is a duplicate face error (by reason or message content)
              final isDuplicateFace = reason == 'duplicate_face' ||
                                      errorMessage.toLowerCase().contains('already registered') ||
                                      errorMessage.toLowerCase().contains('duplicate') ||
                                      errorMessage.toLowerCase().contains('different account');
              
              if (isDuplicateFace && mounted) {
                // Show error dialog for duplicate face
                _showErrorDialog(
                  'Account Already Exists',
                  errorMessage.isNotEmpty 
                    ? errorMessage
                    : 'This face is already registered with a different account. You cannot create multiple accounts with the same face. Please use your existing account or contact support if you believe this is an error.',
                  navigateToWelcome: true, // Navigate to welcome screen on OK
                );
              } else {
                // For other errors, just log (don't block - enrollment can be retried later)
                print('⚠️ Enrollment error (non-blocking): $errorMessage');
              }
            }
          } else {
            print('⚠️ Cannot enroll faces: No email or phone number');
          }
        } catch (e) {
          print('❌ Error enrolling faces from 3 verification steps: $e');
          // Don't block form submission - enrollment can be retried later
        }

        // Overwrite the temporary ID with the final ID
        await prefs.setString('signup_user_id', userId);

        // Final verification check for debugging with network retry
        final userDoc = await NetworkService.executeWithRetry(
          () => FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'marketsafe',
          )
              .collection('users')
              .doc(userId)
              .get(),
          maxRetries: 2,
          retryDelay: const Duration(seconds: 1),
          loadingMessage: null, // Don't show loading for final check
          context: context,
          showNetworkErrors: false, // Don't show errors for final check
        );
        print('✅ Final user document after update:');
        print('  - UID: ${userDoc.data()!['uid']}');
        print('  - IsTemporaryUser: ${userDoc.data()!['isTemporaryUser']}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Form Submitted Successfully!"),
              backgroundColor: Colors.green,
            ),
          );

          // Navigate after a short delay to ensure the snackbar is shown
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const AddProfilePhotoScreen()),
              );
            }
          });
        }
      } catch (e) {
        print('Error submitting form: $e');
        
        // Clean up test enrollment on error
        if (_pendingTestUuidCleanup.isNotEmpty) {
          await _cleanupTestEnrollment(_pendingTestUuidCleanup, _pendingTestEmail);
          _pendingTestUuidCleanup = '';
          _pendingTestEmail = '';
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error: ${e.toString()}"),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please fill in all required fields"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black, Color(0xFF2B0000)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 17),
                  const Text(
                    "FILL OUT THE FOLLOWING",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Form Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _buildTextField("Username", usernameController),
                        _buildTextField("First Name", firstNameController),
                        _buildTextField("Last Name", lastNameController),
                        _buildTextField(
                          "Age",
                          ageController,
                          keyboardType: TextInputType.number,
                        ),
                        _buildTextField("Address", addressController),
                        const SizedBox(height: 16),

                        // Birthday Picker
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Birthday",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime(2000),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );

                                if (picked != null) {
                                  setState(() {
                                    _selectedDate = picked;
                                  });
                                }
                              },
                              child: Container(
                                width: double.infinity, // ✅ full width
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.white,
                                ),
                                child: Text(
                                  _selectedDate == null
                                      ? "Select your birthday"
                                      : "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _selectedDate == null
                                        ? Colors.grey
                                        : Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),
                        const Text(
                          "Gender",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Radio<String>(
                              value: "Male",
                              groupValue: gender,
                              onChanged: (value) {
                                setState(() {
                                  gender = value;
                                });
                              },
                            ),
                            const Text("Male"),
                            const SizedBox(width: 20),
                            Radio<String>(
                              value: "Female",
                              groupValue: gender,
                              onChanged: (value) {
                                setState(() {
                                  gender = value;
                                });
                              },
                            ),
                            const Text("Female"),
                          ],
                        ),

                        const SizedBox(height: 20),

                        ElevatedButton(
                          onPressed: _isLoading ? null : _submitForm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 50,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  "SIGN UP",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ✅ Updated with Username validation
  Widget _buildTextField(String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return "$label is required";
          }

          if (label == "Username") {
            if (value.length < 8) {
              return "Username must be at least 8 characters long";
            }
            if (value.length > 30) {
              return "Username must be 30 characters or less";
            }
            // Check for valid characters (alphanumeric and underscore only)
            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
              return "Username can only contain letters, numbers, and underscores";
            }
          }

          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }

  /// Clean up test enrollment from Luxand
  Future<void> _cleanupTestEnrollment(String testUuid, String email) async {
    if (testUuid.isEmpty) return;
    
    try {
      print('🧹 [CLEANUP] Deleting test enrollment UUID: $testUuid');
      
      // Call backend to delete the test enrollment
      const backendUrl = String.fromEnvironment(
        'FACE_AUTH_BACKEND_URL',
        defaultValue: 'https://marketsafe-production.up.railway.app',
      );
      final backendService = FaceAuthBackendService(backendUrl: backendUrl);
      
      final deleteResult = await NetworkService.executeWithRetry(
        () => backendService.deletePerson(email: email, uuid: testUuid),
        maxRetries: 2,
        retryDelay: const Duration(seconds: 1),
        loadingMessage: null, // Don't show loading for cleanup
        context: context,
        showNetworkErrors: false, // Don't show errors for cleanup
      );
      
      if (deleteResult['success'] == true || deleteResult['ok'] == true) {
        print('✅ [CLEANUP] Test enrollment deleted successfully: $testUuid');
      } else {
        print('⚠️ [CLEANUP] Failed to delete test enrollment: ${deleteResult['error']}');
      }
    } catch (e) {
      print('⚠️ [CLEANUP] Error cleaning up test enrollment: $e');
      // Don't throw - cleanup failure shouldn't block signup
    }
  }

  void _showErrorDialog(String title, String message, {bool navigateToWelcome = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            title,
            style: const TextStyle(color: Colors.red),
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (navigateToWelcome) {
                  // Navigate to welcome screen after closing dialog
                  Navigator.of(context).pushReplacementNamed('/welcome');
                }
              },
              child: const Text(
                'OK',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  // REMOVED: _extractRealBiometricFeatures method
  // This method was creating old biometricFeatures format (64D simulated)
  // New system uses face_embeddings collection with 512D real embeddings
  // Handled by ProductionFaceRecognitionService during registration
  // No longer needed - embeddings are stored separately in face_embeddings/{userId}
}

