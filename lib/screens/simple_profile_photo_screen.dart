import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/real_face_recognition_service.dart';
import '../services/product_service.dart';

class SimpleProfilePhotoScreen extends StatefulWidget {
  const SimpleProfilePhotoScreen({super.key});

  @override
  State<SimpleProfilePhotoScreen> createState() => _SimpleProfilePhotoScreenState();
}

class _SimpleProfilePhotoScreenState extends State<SimpleProfilePhotoScreen> {
  final ImagePicker _picker = ImagePicker();
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: false,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.1,
    ),
  );
  XFile? _image;
  bool _isUploading = false;
  bool _isVerifying = false;

  Future<void> _pickImage(ImageSource source) async {
    final pickedImage = await _picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (pickedImage != null) {
      setState(() {
        _image = pickedImage;
      });
    }
  }

  Future<void> _uploadProfilePhoto() async {
    if (_image == null) return;

    setState(() {
      _isVerifying = true;
    });

    try {
      // Get current user ID
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id') ?? prefs.getString('signup_user_id');
      
      if (userId == null) {
        _showErrorDialog('Error', 'No user logged in');
        return;
      }

      // Step 1: Face Detection and Verification
      print('🔍 Starting face verification...');
      
      // Load and process the image
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

      // Step 2: Verify face matches user's registered face
      print('🔍 Verifying face match...');
      Map<String, dynamic> verificationResult;
      try {
        verificationResult = await _verifyFaceMatch(userId, detectedFace);
      } catch (e) {
        print('❌ Error in face verification: $e');
        _showErrorDialog(
          'Verification Error',
          'Failed to verify face. Please try again.',
        );
        return;
      }
      
      if (!verificationResult['success']) {
        _showErrorDialog(
          'Face Verification Failed',
          verificationResult['error'] ?? 'The uploaded photo doesn\'t match your registered face.',
        );
        return;
      }

      print('✅ Face verification passed! Similarity: ${verificationResult['similarity']}');

      // Step 3: Upload to Firebase Storage
      setState(() {
        _isVerifying = false;
        _isUploading = true;
      });

      String downloadUrl;
      try {
        final file = File(_image!.path);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final ref = FirebaseStorage.instance.ref().child('profile_photos/$userId/profile_$timestamp.jpg');
        
        final uploadTask = await ref.putFile(file);
        downloadUrl = await uploadTask.ref.getDownloadURL();
        print('✅ Profile photo uploaded to Firebase Storage');
      } catch (e) {
        print('❌ Error uploading to Firebase Storage: $e');
        _showErrorDialog(
          'Upload Error',
          'Failed to upload photo. Please check your internet connection and try again.',
        );
        return;
      }
      
      // Step 4: Update user document in Firestore
      try {
        await FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: 'marketsafe',
        ).collection('users').doc(userId).update({
          'profilePictureUrl': downloadUrl,
          'profilePhotoUpdatedAt': FieldValue.serverTimestamp(),
        });
        print('✅ User document updated in Firestore');
      } catch (e) {
        print('❌ Error updating Firestore: $e');
        _showErrorDialog(
          'Database Error',
          'Failed to save profile photo. Please try again.',
        );
        return;
      }
      
      // Step 5: Save to SharedPreferences
      await prefs.setString('profile_photo_url', downloadUrl);
      
      // Step 6: Sync profile picture to all user interactions
      try {
        print('🔄 Syncing profile picture to all user interactions...');
        await ProductService.syncCurrentUserProfilePicture();
        print('✅ Profile picture synced to all interactions');
      } catch (e) {
        print('⚠️ Warning: Could not sync profile picture to all interactions: $e');
      }
      
      // Show success and navigate back
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo verified and uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Navigate back to profile screen
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Verification Failed', 'Failed to verify profile photo: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _isUploading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _verifyFaceMatch(String userId, Face detectedFace) async {
    try {
      // Get user's stored face features
      final userDoc = await FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      ).collection('users').doc(userId).get();
      
      if (!userDoc.exists) {
        return {
          'success': false,
          'error': 'User data not found',
          'similarity': 0.0,
        };
      }

      final userData = userDoc.data()!;
      final storedBiometricFeatures = userData['biometricFeatures'];

      if (storedBiometricFeatures == null) {
        return {
          'success': false,
          'error': 'No face data found for this user. Please complete face verification first.',
          'similarity': 0.0,
        };
      }

      // Extract features from the uploaded photo
      List<double> detectedFeatures;
      try {
        detectedFeatures = await RealFaceRecognitionService.extractBiometricFeatures(detectedFace);
        print('✅ Face features extracted successfully: ${detectedFeatures.length}D');
      } catch (e) {
        print('❌ Error extracting face features: $e');
        return {
          'success': false,
          'error': 'Failed to process face features. Please try again.',
          'similarity': 0.0,
        };
      }
      
      // Safety check for detected features
      if (detectedFeatures.isEmpty || detectedFeatures.any((x) => x.isNaN || x.isInfinite)) {
        return {
          'success': false,
          'error': 'Failed to extract valid face features from uploaded photo',
          'similarity': 0.0,
        };
      }
      
      // Handle biometric features format
      List<double> storedFeatures = [];
      
      if (storedBiometricFeatures is Map && storedBiometricFeatures.containsKey('biometricSignature')) {
        // New format: {biometricSignature: [...], featureCount: 64, ...}
        final biometricSignature = storedBiometricFeatures['biometricSignature'];
        if (biometricSignature is List) {
          storedFeatures = biometricSignature.cast<double>();
        }
      } else if (storedBiometricFeatures is List) {
        // Old format: direct list of features
        storedFeatures = storedBiometricFeatures.cast<double>();
      }

      if (storedFeatures.isEmpty) {
        return {
          'success': false,
          'error': 'Invalid face data format',
          'similarity': 0.0,
        };
      }

      // Calculate real biometric similarity using lenient profile photo method
      final similarity = RealFaceRecognitionService.calculateProfilePhotoSimilarity(
        detectedFeatures, 
        storedFeatures,
      );

      print('📊 Face similarity calculation:');
      print('   - Detected features: ${detectedFeatures.length}');
      print('   - Stored features: ${storedFeatures.length}');
      print('   - Similarity score: $similarity');

      // Use a more lenient threshold for profile photo verification
      const double similarityThreshold = 0.4; // 40% similarity threshold for profile photos
      
      if (similarity >= similarityThreshold) {
        return {
          'success': true,
          'similarity': similarity,
        };
      } else {
        return {
          'success': false,
          'error': 'Face verification failed. The uploaded photo doesn\'t match your registered face. (Similarity: ${(similarity * 100).toStringAsFixed(1)}% - Required: 60%)',
          'similarity': similarity,
        };
      }
    } catch (e) {
      print('❌ Error in face verification: $e');
      return {
        'success': false,
        'error': 'Face verification failed: $e',
        'similarity': 0.0,
      };
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF5C0000),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
          ),
        ),
        title: const Text(
          'Add Profile Photo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
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
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "ADD PROFILE PHOTO",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Choose a clear photo of yourself\nYour face will be verified before upload",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Profile photo preview
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 80,
                  backgroundColor: Colors.grey[800],
                  backgroundImage: _image != null ? FileImage(File(_image!.path)) : null,
                  child: _image == null
                      ? const Icon(
                          Icons.person,
                          size: 80,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),

              const SizedBox(height: 40),

              // Buttons row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Camera button
                  _buildActionButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () => _pickImage(ImageSource.camera),
                  ),
                  
                  // Gallery button
                  _buildActionButton(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () => _pickImage(ImageSource.gallery),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // Upload button
              if (_image != null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_isUploading || _isVerifying) ? null : _uploadProfilePhoto,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5C0000),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: _isVerifying
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Verifying Face...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          )
                        : _isUploading
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Uploading...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'Verify & Upload',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
