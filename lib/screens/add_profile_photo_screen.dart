import 'dart:io';

import 'package:capstone2/screens/under_verification_screen.dart';
import 'package:capstone2/services/image_metadata_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import '../services/production_face_recognition_service.dart';
import '../services/face_auth_backend_service.dart';

class AddProfilePhotoScreen extends StatefulWidget {
  const AddProfilePhotoScreen({super.key});

  @override
  State<AddProfilePhotoScreen> createState() => _AddProfilePhotoScreenState();
}

class _AddProfilePhotoScreenState extends State<AddProfilePhotoScreen> {
  final ImagePicker _picker = ImagePicker();
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.1,
    ),
  );
  XFile? _image;
  bool _isVerifying = false;
  
  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedImage = await _picker.pickImage(source: source);
    if (pickedImage != null) {
      setState(() {
        _image = pickedImage;
      });
    }
  }

  Future<void> _saveProfilePhoto() async {
    if (_image != null) {
      setState(() {
        _isVerifying = true;
      });

      try {
        // Get current user ID - use custom format: user_{timestamp}_{username}
        // This matches the format used in fill_information_screen
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('signup_user_id') ?? 
                      prefs.getString('current_user_id') ?? '';
        
        if (userId.isEmpty) {
          print('❌❌❌ CRITICAL: No user ID found!');
          print('❌ signup_user_id: ${prefs.getString('signup_user_id')}');
          print('❌ current_user_id: ${prefs.getString('current_user_id')}');
          _showErrorDialog('Error', 'No user logged in. Please sign in again.');
          return;
        }
        
        print('🔍 Using custom user ID format: $userId');
        
        print('🔍 Checking user document for userId: $userId');

        // Verify image originality using metadata service
        final imageVerification = await ImageMetadataService.verifyImageOriginality(File(_image!.path));
        
        if (!imageVerification.isValid) {
          _showErrorDialog(
            'Image Verification Failed',
            'Please upload an original photo taken with your camera.',
          );
          return;
        }

        // Extract face embedding from profile photo
        print('🔍 Extracting face embedding from profile photo...');
        final imageBytes = await File(_image!.path).readAsBytes();
        final inputImage = InputImage.fromFilePath(_image!.path);
        final faces = await _faceDetector.processImage(inputImage);
        
        if (faces.isEmpty) {
          _showErrorDialog(
            'No Face Detected',
            'Please upload a photo with a clear face visible.',
          );
          return;
        }
        
        if (faces.length > 1) {
          _showErrorDialog(
            'Multiple Faces Detected',
            'Please upload a photo with only one face.',
          );
          return;
        }
        
        final detectedFace = faces.first;
        
        // CRITICAL SECURITY: Verify the face matches the user's registered face BEFORE uploading
        // This ensures users can only upload their own face as profile photo
        print('🔐 Starting PERFECT face verification for profile photo...');
        
        // Get user's email/phone for verification
        final firestore = FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: 'marketsafe',
        );
        final userDoc = await firestore.collection('users').doc(userId).get();
        
        if (!userDoc.exists) {
          _showErrorDialog('Error', 'User account not found');
          return;
        }
        
        final userData = userDoc.data()!;
        final email = userData['email']?.toString() ?? '';
        final phone = userData['phoneNumber']?.toString() ?? '';
        
        print('🔍 User document data:');
        print('   - Email: $email');
        print('   - Phone: $phone');
        print('   - luxandUuid: ${userData['luxandUuid']}');
        print('   - luxand.uuid: ${userData['luxand']?['uuid']}');
        
        if (email.isEmpty && phone.isEmpty) {
          _showErrorDialog('Error', 'User account missing email/phone. Cannot verify face.');
          return;
        }
        
        // CRITICAL: User must have completed 3 facial verification steps first
        // The face should already be enrolled from those steps
        // We only verify the profile photo matches the enrolled face, we do NOT enroll a new face
        // Check both 'luxandUuid' and 'luxand.uuid' fields (in case it's stored in nested structure)
        String? luxandUuid = userData['luxandUuid']?.toString() ?? 
                             userData['luxand']?['uuid']?.toString();
        
        if (luxandUuid == null || luxandUuid.isEmpty) {
          print('❌❌❌ CRITICAL: User has no luxandUuid!');
          print('❌ User ID: $userId');
          print('❌ Email: $email');
          print('❌ Phone: $phone');
          print('❌ User document keys: ${userData.keys.toList()}');
          print('❌ This means enrollment did not complete successfully!');
          print('❌ User must complete the 3 facial verification steps again.');
          
          _showErrorDialog(
            'Face Verification Required',
            'Please complete the 3 facial verification steps (blink, move closer, head movement) before uploading your profile photo. Your face must be enrolled first.',
          );
          return;
        }
        
        print('✅ Face enrollment verified from 3 verification steps. luxandUuid: $luxandUuid');
        
        // Use PERFECT RECOGNITION to verify face matches user's registered face
        // NOTE: isProfilePhotoVerification=true for more lenient consistency checks
        final emailOrPhone = email.isNotEmpty ? email : phone;
        final verificationResult = await ProductionFaceRecognitionService.verifyUserFace(
          emailOrPhone: emailOrPhone,
          detectedFace: detectedFace,
          cameraImage: null,
          imageBytes: imageBytes,
          isProfilePhotoVerification: true, // More lenient for profile photos
        );
        
        if (verificationResult['success'] != true) {
          print('🚨 Profile photo face verification FAILED: ${verificationResult['error']}');
          _showErrorDialog(
            'Face Verification Failed',
            verificationResult['error'] ?? 'The uploaded photo does not match your registered face. Please upload a photo of yourself.',
          );
          return;
        }
        
        final similarity = verificationResult['similarity'] as double?;
        print('✅ Profile photo face verification PASSED! Similarity: ${similarity?.toStringAsFixed(4) ?? 'unknown'}');
        
        // CRITICAL: Verify similarity meets threshold (80%+ for profile photos, more lenient than login)
        // Profile photos can have very different lighting/angles/conditions, so we use 80%+ instead of 99%+
        // This accounts for natural variation between verification steps and profile photos
        if (similarity == null || similarity < 0.80) {
          print('🚨 PROFILE PHOTO REJECTION: Similarity ${similarity?.toStringAsFixed(4) ?? 'null'} < 0.80');
          _showErrorDialog(
            'Face Verification Failed',
            'The uploaded photo does not match your registered face with sufficient accuracy. Please upload a clear photo of yourself.',
          );
          return;
        }
        
        print('🎯 PERFECT RECOGNITION: Profile photo face matches registered face (similarity: ${similarity.toStringAsFixed(4)})');
        
        // CRITICAL SECURITY: Check if this face is 95%+ similar to ANY OTHER user's face
        // This prevents the same person from having multiple accounts
        print('🔍 [DUPLICATE CHECK] Checking if face is 95%+ similar to another user...');
        try {
          const backendUrl = String.fromEnvironment(
            'FACE_AUTH_BACKEND_URL',
            defaultValue: 'https://marketsafe-production.up.railway.app',
          );
          final backendService = FaceAuthBackendService(backendUrl: backendUrl);
          
          final duplicateCheckResult = await backendService.checkDuplicate(
            email: email.isNotEmpty ? email : phone,
            photoBytes: imageBytes,
            phone: phone.isNotEmpty ? phone : null,
          );
          
          if (duplicateCheckResult['isDuplicate'] == true) {
            final duplicateIdentifier = duplicateCheckResult['duplicateIdentifier']?.toString() ?? 'another account';
            final duplicateSimilarity = duplicateCheckResult['similarity'] as double?;
            final duplicateMessage = duplicateCheckResult['message']?.toString() ?? 
                'This face is already registered with a different account. You cannot use the same face for multiple accounts.';
            
            print('🚨🚨🚨 [DUPLICATE CHECK] DUPLICATE FACE DETECTED!');
            print('🚨 Similarity to other user: ${duplicateSimilarity?.toStringAsFixed(3) ?? 'N/A'}');
            print('🚨 Existing identifier: $duplicateIdentifier');
            
            _showErrorDialog(
              'Duplicate Face Detected',
              duplicateMessage,
            );
            return;
          } else {
            print('✅ [DUPLICATE CHECK] No duplicate faces found. Face is unique.');
          }
        } catch (duplicateCheckError) {
          print('⚠️ [DUPLICATE CHECK] Error during duplicate check: $duplicateCheckError');
          // On error, allow upload to proceed (prevent false positives from blocking legitimate users)
          // The duplicate check is a security measure, but we don't want to block users if the check fails
        }
        
        // Get email and phone for registration
        final signupEmail = prefs.getString('signup_email') ?? email;
        final signupPhone = prefs.getString('signup_phone') ?? phone;
        
        // Register face embedding from profile photo (now that we've verified it matches)
        final embeddingResult = await ProductionFaceRecognitionService.registerAdditionalEmbedding(
          userId: userId,
          detectedFace: detectedFace,
          cameraImage: null,
          imageBytes: imageBytes,
          source: 'profile_photo',
          email: signupEmail.isNotEmpty ? signupEmail : null,
          phoneNumber: signupPhone.isNotEmpty ? signupPhone : null,
        );
        
        if (embeddingResult['success'] != true) {
          print('⚠️ Failed to register profile photo embedding: ${embeddingResult['error']}');
          // Continue anyway - face is verified, just embedding registration failed
        } else {
          print('✅ Profile photo embedding registered successfully');
        }

        // Upload the profile photo (only after PERFECT face verification)
        final uploadResult = await _uploadProfilePhoto(_image!.path);
        
        if (uploadResult['success'] == true) {
          // Save the Firebase Storage URL to SharedPreferences for immediate access
          if (uploadResult['downloadUrl'] != null) {
            await prefs.setString('profile_photo_url', uploadResult['downloadUrl']);
            print('📸 Profile photo URL saved to SharedPreferences: ${uploadResult['downloadUrl']}');
          }
          
          // Photo verified successfully - proceed to under verification screen
          _showSuccessDialog(
            'Photo Verified',
            'Your profile photo has been verified and uploaded successfully!',
            () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const UnderVerificationScreen()),
              );
            },
          );
          
          print('📸 Profile photo verified and uploaded: ${uploadResult['downloadUrl']}');
        } else {
          // Photo verification failed
          _showErrorDialog(
            'Photo Verification Failed',
            uploadResult['message'] ?? 'The uploaded photo doesn\'t match to the face verification',
          );
        }
      } catch (e) {
        print('❌ Error saving profile photo: $e');
        _showErrorDialog(
          'Error',
          'Failed to verify profile photo: $e',
        );
      } finally {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  void _showSuccessDialog(String title, String message, VoidCallback onOk) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            title,
            style: const TextStyle(color: Colors.green),
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onOk();
              },
              child: const Text(
                'Continue',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
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
              onPressed: () => Navigator.of(context).pop(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity, // full screen
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.black, Color(0xFF2B0000)], // same gradient as OTP
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
            children: [

            const Text(
              "ADD PROFILE PHOTO",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            // Profile photo preview
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white,
              backgroundImage: _image != null ? FileImage(
                // ignore: unnecessary_cast
                  (File(_image!.path)) as File
              ) : null,
              child: _image == null
                  ? const Icon(Icons.person, size: 60, color: Colors.black)
                  : null,
            ),

            const SizedBox(height: 30),

            // Buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // New Picture button
                GestureDetector(
                  onTap: _isVerifying ? null : () => _pickImage(ImageSource.camera),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _isVerifying ? Colors.grey : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.camera_alt, size: 30),
                      ),
                      const SizedBox(height: 8),
                      const Text("NEW PICTURE", style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),

                const SizedBox(width: 40),

                // From Gallery button
                GestureDetector(
                  onTap: _isVerifying ? null : () => _pickImage(ImageSource.gallery),
                   child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _isVerifying ? Colors.grey : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.image, size: 30),
                      ),
                      const SizedBox(height: 8),
                      const Text("FROM GALLERY", style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Next button
            ElevatedButton(
              onPressed: _isVerifying ? null : () async {
                if (_image == null) {
                  _showErrorDialog('No Photo Selected', 'Please select a photo first.');
                  return;
                }
                
                await _saveProfilePhoto();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _isVerifying ? Colors.grey : Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: _isVerifying 
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text("VERIFYING...", style: TextStyle(color: Colors.white)),
                    ],
                  )
                : const Text("NEXT", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
        ),
    );
  }

  // Real profile photo upload method
  Future<Map<String, dynamic>> _uploadProfilePhoto(String imagePath) async {
    try {
      print('📸 Starting profile photo upload...');
      
      // Get current user ID
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('signup_user_id') ?? 
                    prefs.getString('current_user_id') ?? '';
      
      if (userId.isEmpty) {
        return {
          'success': false,
          'message': 'No user logged in'
        };
      }
      
      // Upload to Firebase Storage
      final file = File(imagePath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child('profile_photos/$userId/profile_$timestamp.jpg');
      
      print('📸 Uploading to Firebase Storage...');
      final uploadTask = await ref.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      
      print('✅ Profile photo uploaded: $downloadUrl');
      
      // Update user document in Firestore
      await FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      ).collection('users').doc(userId).update({
        'profilePictureUrl': downloadUrl,
        'profilePhotoUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ User document updated in Firestore');
      
      return {
        'success': true,
        'downloadUrl': downloadUrl,
        'message': 'Profile photo uploaded successfully'
      };
    } catch (e) {
      print('❌ Error uploading profile photo: $e');
      return {
        'success': false,
        'message': 'Failed to upload profile photo: $e'
      };
    }
  }
}