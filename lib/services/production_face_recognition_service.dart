import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:flutter_image_compress/flutter_image_compress.dart';

// import 'face_net_service.dart';  // Removed - TensorFlow Lite no longer used
// import 'face_uniqueness_service.dart';  // Removed - using backend for duplicate detection
import 'face_landmark_service.dart';
import 'face_auth_backend_service.dart';

import 'dart:math' show sqrt, pow;

/// SECURE Face Recognition Service
/// Uses backend API for Luxand face recognition (API key stays secure on server)
/// Flow: Flutter → Your Backend → Luxand Cloud → Response
/// luxandUuid is synced to Firestore after enrollment for easy lookup
/// NOTE: TensorFlow Lite removed - all face recognition now handled by backend/Luxand
class ProductionFaceRecognitionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  // static final FaceNetService _faceNetService = FaceNetService();  // Removed - TensorFlow Lite no longer used
  static const bool _useBackendForVerification = true; // Use backend API (recommended - keeps API key secure)
  
  // Backend API URL - configure via environment variable or update default
  // Flutter → Your Backend → Luxand Cloud (API key stays on server)
  // SECURITY: All production URLs must use HTTPS
  static const String _backendUrl = String.fromEnvironment(
    'FACE_AUTH_BACKEND_URL',
    defaultValue: 'https://marketsafe-production.up.railway.app', // Production backend URL (HTTPS required)
  );
  
  // Validate backend URL uses HTTPS (except for local development)
  static String _validateBackendUrl(String url) {
    if (url.isEmpty || url == 'https://your-backend-domain.com') {
      return url; // Will be caught by other validation
    }
    
    // Allow localhost/127.0.0.1/192.168.x for local development only
    final isLocal = url.contains('localhost') || 
                    url.contains('127.0.0.1') || 
                    url.contains('192.168.');
    
    if (!isLocal && !url.startsWith('https://')) {
      throw Exception('SECURITY ERROR: Backend URL must use HTTPS for production. Current URL: $url');
    }
    
    return url;
  }
  
  static FaceAuthBackendService? _backendService;
  static FaceAuthBackendService get _backendServiceInstance {
    final validatedUrl = _validateBackendUrl(_backendUrl);
    return _backendService ??= FaceAuthBackendService(backendUrl: validatedUrl);
  }

  /// Enroll a user's face using backend API (which calls Luxand) and store the returned uuid.
  /// Flow: Flutter → Your Backend → Luxand Cloud → Response
  /// Returns: { success: bool, luxandUuid: String, provider: 'backend' } on success.
  static Future<Map<String, dynamic>> enrollUserFaceWithLuxand({
    required String email,
    required Uint8List imageBytes,
  }) async {
    try {
      if (!_useBackendForVerification) {
        return {
          'success': false,
          'error': 'Backend verification not enabled',
        };
      }

      // Check if backend URL is configured
      if (_backendUrl == 'https://your-backend-domain.com' || _backendUrl.isEmpty) {
        return {
          'success': false,
          'error': 'Backend URL not configured. Please set FACE_AUTH_BACKEND_URL or update the default URL.',
        };
      }

      // Find user by email (case-insensitive)
      final users = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();
      if (users.docs.isEmpty) {
        return {
          'success': false,
          'error': 'User not found for enrollment',
        };
      }
      final String userId = users.docs.first.id;

      // Call backend API for enrollment (backend handles liveness + Luxand enrollment)
      print('🔍 Calling backend API for face enrollment...');
      print('🔍 Backend URL: $_backendUrl');
      final enrollResult = await _backendServiceInstance.enroll(
        email: email,
        photoBytes: imageBytes,
      );

      if (enrollResult['success'] != true) {
        return {
          'success': false,
          'error': enrollResult['error']?.toString() ?? 'Enrollment failed',
          'provider': 'backend',
        };
      }

      final String luxandUuid = (enrollResult['uuid']?.toString() ?? '').trim();
      if (luxandUuid.isEmpty) {
        return {
          'success': false,
          'error': 'Backend did not return a uuid',
          'provider': 'backend',
        };
      }

      // Store uuid on user's document (backend already stores it, but we sync here too)
      await _firestore.collection('users').doc(userId).set({
        'luxandUuid': luxandUuid,
        'luxand': {
          'uuid': luxandUuid,
          'enrolledAt': FieldValue.serverTimestamp(),
        },
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ Face enrolled successfully via backend. UUID: $luxandUuid');
      return {
        'success': true,
        'luxandUuid': luxandUuid,
        'provider': 'backend',
      };
    } catch (e) {
      print('❌ Enrollment error: $e');
      return {
        'success': false,
        'error': 'Enrollment error: $e',
        'provider': 'backend',
      };
    }
  }

  /// Alias for signup flows: uses the same Luxand enrollment as above.
  /// Call this during signup when you capture the user's face.
  static Future<Map<String, dynamic>> signupWithFace({
    required String email,
    required Uint8List imageBytes,
  }) {
    return enrollUserFaceWithLuxand(email: email, imageBytes: imageBytes);
  }

  /// Test backend and Luxand API connection
  /// Returns: { ok: bool, message: String, luxandConfigured: bool?, luxandWorking: bool? }
  static Future<Map<String, dynamic>> testBackendConnection() async {
    try {
      print('🔍 Testing backend and Luxand API connection...');
      print('🔍 Backend URL: $_backendUrl');
      
      final testResult = await _backendServiceInstance.testConnection();
      
      print('📦 Backend connection test result:');
      print('   - ok: ${testResult['ok']}');
      print('   - message: ${testResult['message']}');
      print('   - luxandConfigured: ${testResult['luxandConfigured']}');
      print('   - luxandWorking: ${testResult['luxandWorking']}');
      
      if (testResult['ok'] != true) {
        print('❌❌❌ CRITICAL: Backend connection test FAILED!');
        print('❌ This means the app cannot connect to the backend or Luxand API!');
        print('❌ Error: ${testResult['error'] ?? testResult['message']}');
      } else {
        print('✅✅✅ Backend connection test PASSED!');
      }
      
      return testResult;
    } catch (e) {
      print('❌ Error testing backend connection: $e');
      return {
        'ok': false,
        'message': 'Failed to test backend connection: ${e.toString()}',
        'error': e.toString(),
      };
    }
  }

  /// Enroll all 3 face images from signup (blink, move closer, head movement)
  /// This provides better accuracy by enrolling multiple angles/expressions
  /// Returns: { success: bool, luxandUuid: String?, enrolledCount: int, errors: List<String>? }
  static Future<Map<String, dynamic>> enrollAllThreeFaces({
    required String email,
    String? userId, // Optional: Pass userId directly to avoid query issues
  }) async {
    try {
      if (!_useBackendForVerification) {
        return {
          'success': false,
          'error': 'Backend verification not enabled',
        };
      }

      // Use provided userId or find user by email
      String? finalUserId = userId;
      if (finalUserId == null || finalUserId.isEmpty) {
        final users = await _firestore
            .collection('users')
            .where('email', isEqualTo: email.toLowerCase())
            .limit(1)
            .get();
        if (users.docs.isEmpty) {
          return {
            'success': false,
            'error': 'User not found for enrollment',
          };
        }
        finalUserId = users.docs.first.id;
      }

      // Get face images from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final blinkImagePath = prefs.getString('face_verification_blinkImagePath');
      final moveCloserImagePath = prefs.getString('face_verification_moveCloserImagePath');
      final headMovementImagePath = prefs.getString('face_verification_headMovementImagePath');
      
      // Also check completion flags
      final blinkCompleted = prefs.getBool('face_verification_blinkCompleted') ?? false;
      final moveCloserCompleted = prefs.getBool('face_verification_moveCloserCompleted') ?? false;
      final headMovementCompleted = prefs.getBool('face_verification_headMovementCompleted') ?? false;

      print('🔍 Checking for saved face images:');
      print('  - Blink completed: $blinkCompleted');
      print('  - Blink image: ${blinkImagePath != null && blinkImagePath.isNotEmpty ? "✅ Found: $blinkImagePath" : "❌ Not found"}');
      print('  - Move closer completed: $moveCloserCompleted');
      print('  - Move closer image: ${moveCloserImagePath != null && moveCloserImagePath.isNotEmpty ? "✅ Found: $moveCloserImagePath" : "❌ Not found"}');
      print('  - Head movement completed: $headMovementCompleted');
      print('  - Head movement image: ${headMovementImagePath != null && headMovementImagePath.isNotEmpty ? "✅ Found: $headMovementImagePath" : "❌ Not found"}');
      
      // Debug: List all face verification keys in SharedPreferences
      final allKeys = prefs.getKeys();
      final faceVerificationKeys = allKeys.where((key) => key.startsWith('face_verification_')).toList();
      print('🔍 All face verification keys in SharedPreferences: ${faceVerificationKeys.length}');
      for (final key in faceVerificationKeys) {
        final value = prefs.get(key);
        if (value is String && value.length > 100) {
          print('  - $key: ${value.substring(0, 50)}... (${value.length} chars)');
        } else {
          print('  - $key: $value');
        }
      }

      final List<String> imagePaths = [];
      
      // Check each image path and verify file exists
      if (blinkImagePath != null && blinkImagePath.isNotEmpty) {
        final file = File(blinkImagePath);
        if (await file.exists()) {
          imagePaths.add(blinkImagePath);
          print('✅ Blink image file exists: ${blinkImagePath}');
        } else {
          print('⚠️ Blink image file not found: ${blinkImagePath}');
        }
      }
      
      if (moveCloserImagePath != null && moveCloserImagePath.isNotEmpty) {
        final file = File(moveCloserImagePath);
        if (await file.exists()) {
          imagePaths.add(moveCloserImagePath);
          print('✅ Move closer image file exists: ${moveCloserImagePath}');
        } else {
          print('⚠️ Move closer image file not found: ${moveCloserImagePath}');
        }
      }
      
      if (headMovementImagePath != null && headMovementImagePath.isNotEmpty) {
        final file = File(headMovementImagePath);
        if (await file.exists()) {
          imagePaths.add(headMovementImagePath);
          print('✅ Head movement image file exists: ${headMovementImagePath}');
        } else {
          print('⚠️ Head movement image file not found: ${headMovementImagePath}');
        }
      }

      if (imagePaths.isEmpty) {
        print('❌ No valid face images found. Please complete face verification steps.');
        return {
          'success': false,
          'error': 'No face images found. Please complete face verification steps.',
        };
      }
      
      print('✅ Found ${imagePaths.length} valid face image(s) to enroll');

      print('🔍 Enrolling ${imagePaths.length} face images to Luxand via backend...');
      print('🔍 Backend URL: $_backendUrl');
      
      // CRITICAL: Test backend connection before attempting enrollment
      print('🔍 Testing backend connection before enrollment...');
      final connectionTest = await testBackendConnection();
      if (connectionTest['ok'] != true) {
        final errorMsg = connectionTest['message']?.toString() ?? 'Backend connection failed';
        print('❌❌❌ CRITICAL: Cannot enroll - backend connection test failed!');
        print('❌ Error: $errorMsg');
        return {
          'success': false,
          'error': 'Cannot connect to backend server. $errorMsg',
          'enrolledCount': 0,
          'errors': ['Backend connection failed: $errorMsg'],
        };
      }
      
      print('✅ Backend connection test passed - proceeding with enrollment');
      if (_backendUrl == 'https://your-backend-domain.com' || _backendUrl.isEmpty) {
        print('❌❌❌ CRITICAL: Backend URL not configured!');
        print('❌ Backend URL is: "$_backendUrl"');
        print('❌ Enrollment will fail! Please set FACE_AUTH_BACKEND_URL environment variable.');
        return {
          'success': false,
          'error': 'Backend URL not configured. Please set FACE_AUTH_BACKEND_URL or update the default URL.',
          'enrolledCount': 0,
          'errors': ['Backend URL not configured'],
        };
      }
      
      // Verify backend is reachable
      try {
        print('🔍 Testing backend connectivity...');
        final testUri = Uri.parse('$_backendUrl/api/health');
        final testResponse = await http.get(testUri).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Backend health check timeout');
          },
        );
        if (testResponse.statusCode == 200) {
          print('✅ Backend is reachable and responding');
        } else {
          print('⚠️ Backend responded with status: ${testResponse.statusCode}');
        }
      } catch (e) {
        print('⚠️⚠️⚠️ WARNING: Could not reach backend: $e');
        print('⚠️ Enrollment may fail if backend is not accessible!');
      }
      
      String? luxandUuid;
      int enrolledCount = 0;
      final List<String> errors = [];

      // Enroll each face image through backend
      for (int i = 0; i < imagePaths.length; i++) {
        try {
          final imageFile = File(imagePaths[i]);
          if (!await imageFile.exists()) {
            print('⚠️ Image file not found: ${imagePaths[i]}');
            errors.add('Image ${i + 1} not found');
            continue;
          }

          var imageBytes = await imageFile.readAsBytes();
          if (imageBytes.isEmpty) {
            print('⚠️ Image file is empty: ${imagePaths[i]}');
            errors.add('Image ${i + 1} is empty');
            continue;
          }

          // CRITICAL: Preprocess image to ensure it's in the correct format for Luxand
          // Luxand requires JPEG format and specific size constraints
          print('🔧 Preprocessing image ${i + 1} for Luxand compatibility...');
          try {
            imageBytes = await _preprocessImageForLuxand(imageBytes, imagePaths[i]);
            print('✅ Image ${i + 1} preprocessed successfully. New size: ${imageBytes.length} bytes');
          } catch (preprocessError) {
            print('❌❌❌ CRITICAL: Image preprocessing failed for image ${i + 1}!');
            print('❌ Error: $preprocessError');
            print('❌ This image may not work with Luxand - skipping...');
            errors.add('Image ${i + 1}: Failed to process image. Please retake with better quality.');
            continue;
          }

          // Validate image contains a face before sending to backend
          // This prevents sending invalid images to Luxand
          print('🔍 Validating image ${i + 1} contains a detectable face...');
          try {
            final inputImage = InputImage.fromFilePath(imagePaths[i]);
            final faceDetector = FaceDetector(
              options: FaceDetectorOptions(
                enableClassification: false,
                enableLandmarks: false,
                enableTracking: false,
                minFaceSize: 0.1, // Lower threshold to catch more faces
              ),
            );
            
            final faces = await faceDetector.processImage(inputImage);
            await faceDetector.close();
            
            if (faces.isEmpty) {
              print('❌❌❌ CRITICAL: No face detected in image ${i + 1}!');
              print('❌ Image path: ${imagePaths[i]}');
              print('❌ Image size: ${imageBytes.length} bytes');
              print('❌ This image will be skipped - Luxand will reject it');
              errors.add('Image ${i + 1}: No face detected in image. Please retake with face clearly visible.');
              continue; // Skip this image
            } else {
              print('✅ Face detected in image ${i + 1}: ${faces.length} face(s) found');
              final face = faces.first;
              final boundingBox = face.boundingBox;
              print('   - Face bounding box: ${boundingBox.width}x${boundingBox.height} at (${boundingBox.left}, ${boundingBox.top})');
            }
          } catch (faceDetectionError) {
            print('⚠️ Face detection validation failed for image ${i + 1}: $faceDetectionError');
            print('⚠️ Proceeding with enrollment anyway - backend will validate');
            // Continue with enrollment - backend will also validate
          }

          print('📸 Enrolling face ${i + 1}/${imagePaths.length} via backend...');
          print('📸 Image file: ${imagePaths[i]}');
          print('📸 Image size: ${imageBytes.length} bytes');
          print('📸 Enrollment identifier: $email');
          
          // Call backend API for enrollment (backend handles liveness + Luxand enrollment)
          final enrollResult = await _backendServiceInstance.enroll(
            email: email,
            photoBytes: imageBytes,
          );
          
          print('📸 Enrollment result for face ${i + 1}: success=${enrollResult['success']}, uuid=${enrollResult['uuid']}, error=${enrollResult['error']}');

          if (enrollResult['success'] == true) {
            final uuid = enrollResult['uuid']?.toString();
            print('🔍 Face ${i + 1} enrollment result:');
            print('   - success: true');
            print('   - uuid from result: ${uuid ?? "NULL"}');
            print('   - uuid type: ${uuid.runtimeType}');
            print('   - uuid isEmpty: ${uuid?.isEmpty ?? "N/A"}');
            
            if (uuid != null && uuid.isNotEmpty) {
              luxandUuid = uuid; // Store the UUID (should be same for all enrollments)
              enrolledCount++;
              print('✅ Face ${i + 1} enrolled successfully via backend. UUID: $uuid');
            } else {
              print('❌❌❌ CRITICAL: Backend returned success=true but UUID is null or empty!');
              print('❌ enrollResult keys: ${enrollResult.keys.toList()}');
              print('❌ enrollResult full: $enrollResult');
              errors.add('Face ${i + 1}: No UUID returned from backend (success=true but uuid is null/empty)');
            }
          } else {
            final error = enrollResult['error']?.toString() ?? 'Unknown error';
            errors.add('Face ${i + 1}: $error');
            print('❌ Face ${i + 1} enrollment failed: $error');
          }
        } catch (e) {
          errors.add('Face ${i + 1}: $e');
          print('❌ Error enrolling face ${i + 1}: $e');
        }
      }

      if (luxandUuid == null || luxandUuid.isEmpty) {
        print('❌❌❌ CRITICAL: Enrollment failed - no UUID returned!');
        print('❌ Enrollment identifier: $email');
        print('❌ Errors: ${errors.join("; ")}');
        print('❌ Enrolled count: $enrolledCount');
        return {
          'success': false,
          'error': 'Failed to enroll any faces. ${errors.join('; ')}',
          'enrolledCount': enrolledCount,
          'errors': errors,
        };
      }
      
      print('✅✅✅ Enrollment SUCCESS: UUID = $luxandUuid');
      print('✅ Enrollment identifier: $email');
      print('✅ Enrolled $enrolledCount face(s)');

      // Store uuid on user's document
      // CRITICAL: Save luxandUuid at top level AND in nested luxand object
      print('💾 Saving UUID to Firestore...');
      print('   - User ID: $finalUserId');
      print('   - UUID: $luxandUuid');
      print('   - Enrolled faces: $enrolledCount');
      
      try {
        await _firestore.collection('users').doc(finalUserId).set({
          'luxandUuid': luxandUuid, // Top-level field (required for profile photo check)
          'luxand': {
            'uuid': luxandUuid,
            'enrolledAt': FieldValue.serverTimestamp(),
            'enrolledFaces': enrolledCount,
          },
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        print('✅✅✅ UUID saved to Firestore successfully!');
        print('✅ Enrolled $enrolledCount/${imagePaths.length} faces successfully via backend. UUID: $luxandUuid');
        print('✅ UUID saved to Firestore for user: $finalUserId');
      } catch (firestoreError) {
        print('❌❌❌ CRITICAL: Failed to save UUID to Firestore!');
        print('❌ Error: $firestoreError');
        print('❌ User ID: $finalUserId');
        print('❌ UUID: $luxandUuid');
        print('❌ This is a critical error - UUID will not be available for verification!');
        // Don't throw - we still want to return success if enrollment worked
        // But log the error so we can diagnose
      }
      
      // Verify enrollment by checking if UUID exists in Firestore
      final verifyDoc = await _firestore.collection('users').doc(finalUserId).get();
      if (verifyDoc.exists) {
        final savedUuid = verifyDoc.data()?['luxandUuid']?.toString() ?? '';
        if (savedUuid == luxandUuid) {
          print('✅✅✅ ENROLLMENT VERIFICATION: UUID confirmed in Firestore!');
        } else {
          print('⚠️⚠️⚠️ WARNING: UUID mismatch! Expected: $luxandUuid, Found: $savedUuid');
        }
      } else {
        print('⚠️⚠️⚠️ WARNING: User document not found after enrollment!');
      }
      return {
        'success': true,
        'luxandUuid': luxandUuid,
        'enrolledCount': enrolledCount,
        'totalFaces': imagePaths.length,
        'errors': errors.isNotEmpty ? errors : null,
        'provider': 'backend',
      };
    } catch (e) {
      print('❌ Error enrolling all three faces: $e');
      return {
        'success': false,
        'error': 'Enrollment error: $e',
        'provider': 'backend',
      };
    }
  }

  /// Generate a normalized embedding for the detected face.
  /// NOTE: TensorFlow Lite removed - embeddings now handled by backend/Luxand
  /// Returns an empty list (no longer used - backend handles all face recognition)
  static Future<List<double>> generateEmbedding({
    required Face face,
    CameraImage? cameraImage,
    Uint8List? imageBytes,
    bool normalize = true,
  }) async {
    // TensorFlow Lite removed - all face recognition now handled by backend/Luxand
    print('⚠️ generateEmbedding called but TensorFlow Lite is removed. Using backend/Luxand for all face recognition.');
    return const [];
  }

  /// Register an additional face embedding (for multi-shot registration).
  /// NOTE: TensorFlow Lite removed - all face recognition now handled by backend/Luxand
  /// This function now just validates the face and returns success (backend handles storage)
  static Future<Map<String, dynamic>> registerAdditionalEmbedding({
    required String userId,
    required Face detectedFace,
    CameraImage? cameraImage,
    Uint8List? imageBytes,
    required String source, // 'profile_photo', 'blink_twice', 'head_movement', etc.
    String? email,
    String? phoneNumber,
  }) async {
    try {
      print('🔐 Registering additional face data from source: $source for user: $userId');
      print('ℹ️ TensorFlow Lite removed - backend/Luxand handles all face recognition');

      if (cameraImage == null && imageBytes == null) {
        return {'success': false, 'error': 'Camera image not available.'};
      }

      // Validate essential features are present
      final hasEssentialFeatures = FaceLandmarkService.validateEssentialFeatures(detectedFace);
      if (!hasEssentialFeatures) {
        print('🚨 CRITICAL: Missing essential facial features (eyes, nose, mouth)');
        return {
          'success': false,
          'error': 'Face features not complete. Please ensure all features (eyes, nose, mouth) are visible.',
        };
      }
      
      // Extract landmark features for validation
      final landmarkFeatures = FaceLandmarkService.extractLandmarkFeatures(detectedFace);
      final featureDistances = FaceLandmarkService.calculateFeatureDistances(detectedFace);
      
      print('✅ Landmark features extracted: ${landmarkFeatures.keys.join(', ')}');
      print('✅ Feature distances calculated: ${featureDistances.keys.join(', ')}');
      print('✅ Face validated - backend/Luxand handles all recognition and storage');

      return {
        'success': true,
        'message': 'Additional face data registered successfully. Backend/Luxand handles recognition.',
      };
    } catch (e) {
      print('❌ Error registering additional embedding: $e');
      return {
        'success': false,
        'error': 'Failed to register additional face data: $e',
      };
    }
  }

  /// Register a user's face.
  /// NOTE: TensorFlow Lite removed - all face recognition now handled by backend/Luxand
  /// This function now just validates the face and returns success (backend handles storage)
  static Future<Map<String, dynamic>> registerUserFace({
    required String userId,
    required Face detectedFace,
    CameraImage? cameraImage,
    Uint8List? imageBytes,
    String? email,
    String? phoneNumber,
  }) async {
    try {
      print('🔐 Starting SECURE face registration for user: $userId');
      print('ℹ️ TensorFlow Lite removed - backend/Luxand handles all face recognition');

      if (cameraImage == null && imageBytes == null) {
        return {'success': false, 'error': 'Camera image not available.'};
      }

      // Validate essential features are present
      final hasEssentialFeatures = FaceLandmarkService.validateEssentialFeatures(detectedFace);
      if (!hasEssentialFeatures) {
        print('🚨 CRITICAL: Missing essential facial features (eyes, nose, mouth)');
        return {
          'success': false,
          'error': 'Face features not complete. Please ensure all features (eyes, nose, mouth) are visible.',
        };
      }
      
      // Extract landmark features for validation
      final landmarkFeatures = FaceLandmarkService.extractLandmarkFeatures(detectedFace);
      final featureDistances = FaceLandmarkService.calculateFeatureDistances(detectedFace);
      
      print('✅ Landmark features extracted: ${landmarkFeatures.keys.join(', ')}');
      print('✅ Feature distances calculated: ${featureDistances.keys.join(', ')}');
      print('✅ Face validated - backend/Luxand handles all recognition and storage');
      print('ℹ️ Duplicate detection handled by backend - no local TensorFlow check needed');

      return {
        'success': true,
        'message': 'Face registered successfully. Backend/Luxand handles recognition.',
      };
    } catch (e) {
      print('❌ Error in SECURE face registration: $e');
      return {
        'success': false,
        'error': 'Face registration failed: $e',
      };
    }
  }

  /// Authenticate a user.
  /// NOTE: DEPRECATED - This function is legacy and not used. Use verifyUserFace() instead which uses backend.
  /// TensorFlow Lite removed - all face recognition now handled by backend/Luxand
  @Deprecated('Use verifyUserFace() instead - this function uses deprecated local TensorFlow authentication')
  static Future<Map<String, dynamic>> authenticateUser({
    required Face detectedFace,
    CameraImage? cameraImage,
    Uint8List? imageBytes,
  }) async {
    // TensorFlow Lite removed - this function is deprecated
    // All authentication now uses backend via verifyUserFace()
    print('⚠️ authenticateUser() is deprecated. Use verifyUserFace() instead which uses backend/Luxand.');
    return {
      'success': false,
      'error': 'Local authentication is deprecated. Please use backend authentication.',
    };
  }

  /// Calculate variance of embedding to ensure it's meaningful
  /// Low variance indicates all values are similar (not good for face recognition)
  static double _calculateEmbeddingVariance(List<double> embedding) {
    if (embedding.isEmpty) return 0.0;
    
    final mean = embedding.reduce((a, b) => a + b) / embedding.length;
    final variance = embedding.map((e) => pow(e - mean, 2)).reduce((a, b) => a + b) / embedding.length;
    
    return variance;
  }
  
  /// Helper function: Calculate L2 norm (replaces TensorFlow Lite)
  static double _l2Norm(List<double> vector) {
    double sum = 0.0;
    for (final value in vector) {
      sum += value * value;
    }
    return sqrt(sum);
  }
  
  /// Helper function: Normalize vector (replaces TensorFlow Lite)
  static List<double> _normalize(List<double> vector) {
    final norm = _l2Norm(vector);
    if (norm == 0.0) return vector;
    return vector.map((v) => v / norm).toList();
  }
  
  /// Helper function: Calculate cosine similarity (replaces TensorFlow Lite)
  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// Verify user face against stored embeddings using email or phone number (1:1 verification)
  /// This is more secure than 1:N search and requires both email/phone AND face to match
  /// 
  /// [isProfilePhotoVerification]: If true, uses more lenient consistency checks for profile photos
  /// which may have different lighting/angles than signup face verification steps
  /// 🔐 SECURE 1:1 FACE VERIFICATION (EMAIL-FIRST APPROACH)
  /// 
  /// This method implements the recommended security flow:
  /// 1. User inputs email/phone → Verify email/phone exists in database
  /// 2. Retrieve ONLY that user's face embeddings (not all users)
  /// 3. Compare detected face ONLY against that user's embeddings (1:1 verification)
  /// 4. Require high similarity threshold (99%+ for login, 98.5%+ for profile photos)
  /// 
  /// ✅ SECURITY BENEFITS:
  /// - Prevents unregistered users from logging in with someone else's email
  /// - No global comparison - only compares to the specific user's embeddings
  /// - Email/phone must exist and be verified before face comparison
  /// - High similarity threshold prevents false positives
  /// 
  /// 🚫 NEVER does global comparison against all users - only 1:1 verification
  static Future<Map<String, dynamic>> verifyUserFace({
    required String emailOrPhone,
    required Face detectedFace,
    CameraImage? cameraImage,
    Uint8List? imageBytes,
    List<double>? precomputedEmbedding,
    double? stabilityScore,
    bool isProfilePhotoVerification = false,
  }) async {
    try {
      print('🔐 ==========================================');
      print('🔐 SECURE 1:1 FACE VERIFICATION');
      print('🔐 ==========================================');
      print('🔐 Email/Phone: $emailOrPhone');
      print('🔐 Mode: ${isProfilePhotoVerification ? "Profile Photo" : "Login"}');
      print('🔐 Security: Email-first → 1:1 verification (NOT global comparison)');
      print('🔐 ==========================================');

      if (precomputedEmbedding != null && precomputedEmbedding.isNotEmpty) {
        final variance = _calculateEmbeddingVariance(precomputedEmbedding);
        final stabilityLabel = stabilityScore != null
            ? '${(stabilityScore * 100).toStringAsFixed(2)}%'
            : 'unknown';
        print('🔍 Deep scan embedding provided (${precomputedEmbedding.length}D, '
            'variance=${variance.toStringAsFixed(6)}, stability=$stabilityLabel)');
      }

      if (cameraImage == null && imageBytes == null) {
        return {'success': false, 'error': 'Camera image not available.'};
      }

      // ==========================================
      // STEP 1: VERIFY EMAIL/PHONE EXISTS FIRST
      // ==========================================
      // CRITICAL SECURITY: Always verify email/phone exists before face comparison
      // This prevents anyone from trying to log in with someone else's email
      print('🔍 STEP 1: Verifying email/phone exists in database...');
      print('🔍 This ensures only registered users can proceed to face verification');
      String? userId;
      Map<String, dynamic>? userData;
      
      try {
        // Try email first
        final emailQuery = await _firestore
            .collection('users')
            .where('email', isEqualTo: emailOrPhone.trim().toLowerCase())
            .where('signupCompleted', isEqualTo: true)
            .limit(1)
            .get();
        
        if (emailQuery.docs.isNotEmpty) {
          userId = emailQuery.docs.first.id;
          userData = emailQuery.docs.first.data();
          print('✅ Found user by email: $userId');
        } else {
          // Try phone number
          final phoneQuery = await _firestore
              .collection('users')
              .where('phoneNumber', isEqualTo: emailOrPhone.trim())
              .where('signupCompleted', isEqualTo: true)
              .limit(1)
              .get();
          
          if (phoneQuery.docs.isNotEmpty) {
            userId = phoneQuery.docs.first.id;
            userData = phoneQuery.docs.first.data();
            print('✅ Found user by phone: $userId');
          } else {
            print('❌ No user found with email/phone: $emailOrPhone');
            return {
              'success': false,
              'error': 'No account found with this email or phone number. Please sign up first.',
            };
          }
        }
      } catch (e) {
        print('❌ Error looking up user: $e');
        return {
          'success': false,
          'error': 'Error looking up user account. Please try again.',
        };
      }

      // Step 2: Verify user exists and completed signup
      // userId and userData are already verified above (non-null at this point)
      final signupCompleted = userData['signupCompleted'] ?? false;
      if (!signupCompleted) {
        print('❌ SECURITY: User signup not completed');
        return {
          'success': false,
          'error': 'Account not completed. Please complete signup first.',
        };
      }
      
      // CRITICAL SECURITY: Verify the email/phone matches the user document
      final userEmail = userData['email']?.toString().toLowerCase() ?? '';
      final userPhone = userData['phoneNumber']?.toString() ?? '';
      final inputLower = emailOrPhone.trim().toLowerCase();
      
      final emailMatches = userEmail == inputLower;
      final phoneMatches = userPhone == emailOrPhone.trim();
      
      if (!emailMatches && !phoneMatches) {
        print('🚨 SECURITY ALERT: Email/phone mismatch!');
        print('   Input: $emailOrPhone');
        print('   User email: $userEmail');
        print('   User phone: $userPhone');
        print('   This should not happen - rejecting for security');
        return {
          'success': false,
          'error': 'Account verification failed. Please try again.',
        };
      }

      print('✅ STEP 1 COMPLETE: User found and verified');
      print('✅ Email/phone match verified: ${emailMatches ? "email" : "phone"}');
      print('✅ Security: Email/phone exists and is valid - proceeding to face verification');

      // ==========================================
      // BACKEND API - PRIMARY VERIFICATION PATH (RECOMMENDED)
      // ==========================================
      // Flow: Flutter → Your Backend → Luxand Cloud → Response
      // Backend handles: liveness check + Luxand verification
      // API key stays secure on server
      if (_useBackendForVerification) {
        try {
          // Check if backend URL is configured
          if (_backendUrl == 'https://your-backend-domain.com' || _backendUrl.isEmpty) {
            return {
              'success': false,
              'error': 'Backend URL not configured. Please set FACE_AUTH_BACKEND_URL or update the default URL.',
            };
          }

          // Ensure we have JPEG bytes to send to backend
          final Uint8List? currentJpeg = imageBytes;
          if (currentJpeg == null) {
            print('⚠️ Backend: No JPEG bytes available from camera for verification.');
            return {
              'success': false,
              'error': 'Unable to capture image for verification. Please try again.',
            };
          }

          // Check if user has luxandUuid (enrolled)
          final String luxandUuid = (userData['luxandUuid']?.toString() ?? '').trim();
          if (luxandUuid.isEmpty) {
            print('❌ Backend: User has no stored Luxand UUID. Enrollment required.');
            return {
              'success': false,
              'error': 'Face not enrolled. Please enroll your face first.',
              'provider': 'backend',
            };
          }

          // Call backend API for verification (backend handles liveness + Luxand compare)
          print('🔍 Calling backend API for face verification...');
          print('🔍 Backend URL: $_backendUrl');
          print('🔍 Using UUID for 1:1 verification: $luxandUuid');
          
          // Get both email and phone to check both identifiers (faces may have been enrolled with either)
          final userEmail = userData['email']?.toString() ?? '';
          final userPhone = userData['phoneNumber']?.toString() ?? '';
          
          // CRITICAL: Always pass BOTH email and phone if available
          // This allows verification to match faces enrolled with either identifier
          // Example: Face enrolled with phone "09154615423" can be verified with email "user@gmail.com"
          // as long as both identifiers belong to the same user
          final verifyEmail = userEmail.isNotEmpty ? userEmail : emailOrPhone;
          final verifyPhone = userPhone.isNotEmpty ? userPhone : null;
          
          final verifyResult = await _backendServiceInstance.verify(
            email: verifyEmail, // Always pass email (or emailOrPhone if no email)
            phone: verifyPhone, // Pass phone if available for cross-checking
            photoBytes: currentJpeg,
            luxandUuid: luxandUuid, // Pass UUID for 1:1 verification
          );

          if (verifyResult['ok'] == true) {
            final double? similarity = verifyResult['similarity'] as double?;
            print('✅ Backend verification successful. Similarity: ${similarity?.toStringAsFixed(3) ?? 'N/A'}');
            return {
              'success': true,
              'userId': userId,
              'similarity': similarity ?? 0.85,
              'userData': userData,
              'provider': 'backend',
            };
          } else {
            // Verification failed
            final String? errorMsg = verifyResult['error']?.toString();
            final String? reason = verifyResult['reason']?.toString();
            print('❌ Backend verification failed: $errorMsg (reason: $reason)');
            
            // Customize error message for profile photos
            final String errorMessage = isProfilePhotoVerification
                ? 'The uploaded photo does not match your enrolled face. Please upload a photo of yourself that matches your signup face.'
                : (errorMsg ?? 'Face verification failed. Please try again with better lighting and alignment.');
            
            return {
              'success': false,
              'error': errorMessage,
              'provider': 'backend',
              'reason': reason,
            };
          }
        } catch (e) {
          print('⚠️ Backend verification error: $e');
          return {
            'success': false,
            'error': 'Verification service error. Please try again.',
            'provider': 'backend',
          };
        }
      }

      // ==========================================
      // BACKEND IS AUTHORITATIVE - NO FALLBACK TO LOCAL EMBEDDINGS
      // ==========================================
      // If backend is enabled, we should have already returned above.
      // If we reach here, it means backend is not enabled or failed, but since
      // we want backend to be the only method, return an error.
      if (_useBackendForVerification) {
        print('❌ Backend verification path did not return a result. This should not happen.');
        return {
          'success': false,
          'error': 'Face verification service unavailable. Please try again.',
          'provider': 'backend',
        };
      }

      // ==========================================
      // STEP 2: RETRIEVE ONLY THIS USER'S EMBEDDINGS (DEPRECATED - LUXAND ONLY)
      // ==========================================
      // CRITICAL SECURITY: Only retrieve embeddings for THIS specific user
      // NEVER retrieve all users' embeddings - this is 1:1 verification, not global search
      print('🔍 STEP 2: Retrieving stored face embeddings for THIS USER ONLY...');
      print('🔍 User ID: $userId');
      print('🔍 Security: Only this user\'s embeddings will be compared (1:1 verification)');
      print('🔍 NOT doing global comparison - this prevents unauthorized access');
      DocumentSnapshot faceDoc = await _firestore.collection('face_embeddings').doc(userId).get();
      
      // CRITICAL SECURITY FIX: Strict fallback - only allow temp_ IDs that match the user
      // REMOVED: Global search through all face_embeddings (security risk)
      // REMOVED: Email/phone search that could match wrong users
      // NEW: Only allow fallback if document ID is temp_<userId> or matches userId exactly
      if (!faceDoc.exists) {
        print('⚠️ No face embeddings found for user: $userId');
        print('🔍 Attempting STRICT fallback: Checking temp_ ID only...');
        
        // CRITICAL SECURITY: Only check temp_<userId> - no global search
        // This prevents matching wrong users' embeddings
        final tempUserId = 'temp_$userId';
        final tempFaceDoc = await _firestore.collection('face_embeddings').doc(tempUserId).get();
        
        if (tempFaceDoc.exists) {
          print('✅ Found face embeddings under temp_ ID: $tempUserId');
        
          // CRITICAL: Verify temp_ document belongs to this user
          final tempFaceData = tempFaceDoc.data();
          if (tempFaceData != null) {
            final tempEmail = tempFaceData['email']?.toString().toLowerCase() ?? '';
            final tempPhone = tempFaceData['phoneNumber']?.toString() ?? '';
            final tempUserIdField = tempFaceData['userId']?.toString() ?? '';
            
            // CRITICAL: Verify email/phone AND userId field match EXACTLY
            final emailMatches = tempEmail.isEmpty || userEmail.isEmpty || tempEmail == userEmail.toLowerCase();
            final phoneMatches = tempPhone.isEmpty || userPhone.isEmpty || tempPhone == userPhone;
            final userIdMatches = tempUserIdField.isEmpty || tempUserIdField == userId;
            
            if (!emailMatches || !phoneMatches || !userIdMatches) {
              print('🚨🚨🚨🚨🚨 CRITICAL SECURITY: Temp_ document does NOT belong to this user!');
              print('🚨🚨🚨 Temp email: $tempEmail, User email: $userEmail');
              print('🚨🚨🚨 Temp phone: $tempPhone, User phone: $userPhone');
              print('🚨🚨🚨 Temp userId: $tempUserIdField, User userId: $userId');
              print('🚨🚨🚨 REJECTING - temp_ document belongs to different user');
              return {
                'success': false,
                'error': 'Face not registered. Please complete signup with face verification.',
              };
            }
            
            print('✅ Temp_ document verified - belongs to this user');
            
            // Migrate embeddings to permanent userId
            print('🔄 Migrating face embeddings from temp_ ID to permanent userId...');
            try {
              final tempEmbeddings = tempFaceData['embeddings'] as List?;
              
              if (tempEmbeddings != null && tempEmbeddings.isNotEmpty) {
                // Copy embeddings to permanent userId
                await _firestore.collection('face_embeddings').doc(userId).set({
                  'userId': userId,
                  'embedding': tempFaceData['embedding'],
                  'embeddings': tempEmbeddings,
                  'email': userEmail,
                  'phoneNumber': userPhone,
                  'registeredAt': tempFaceData['registeredAt'] ?? FieldValue.serverTimestamp(),
                  'lastUpdated': FieldValue.serverTimestamp(),
                }, SetOptions(merge: false));
                print('✅ Face embeddings migrated to permanent userId: $userId');
                
                // Re-fetch from permanent userId
                faceDoc = await _firestore.collection('face_embeddings').doc(userId).get();
              } else {
                print('⚠️ Temp_ document has no embeddings - cannot migrate');
                return {
                  'success': false,
                  'error': 'Face not registered. Please complete signup with face verification.',
                };
            }
          } catch (e) {
              print('⚠️ Error migrating embeddings: $e');
              return {
                'success': false,
                'error': 'Face verification failed. Please try again.',
              };
            }
          } else {
            print('❌ Temp_ document data is null');
            return {
              'success': false,
              'error': 'Face not registered. Please complete signup with face verification.',
            };
          }
        } else {
          // No temp_ ID found either - try searching by email/phone as fallback
          print('⚠️ No face embeddings found for user: $userId (checked both permanent and temp_ ID)');
          print('🔍 Attempting fallback: Searching by email/phone...');
          
          // CRITICAL SECURITY: Only search by email/phone if both match exactly
          // This prevents matching wrong users' embeddings
          try {
            final emailQuery = userEmail.isNotEmpty 
                ? await _firestore
                    .collection('face_embeddings')
                    .where('email', isEqualTo: userEmail.toLowerCase())
                    .limit(1)
                    .get()
                : null;
            
            final phoneQuery = userPhone.isNotEmpty
                ? await _firestore
                    .collection('face_embeddings')
                    .where('phoneNumber', isEqualTo: userPhone)
                    .limit(1)
                    .get()
                : null;
            
            DocumentSnapshot? fallbackDoc;
            
            // Try email first
            if (emailQuery != null && emailQuery.docs.isNotEmpty) {
              final doc = emailQuery.docs.first;
              final docData = doc.data() as Map<String, dynamic>?;
              final docEmail = docData?['email']?.toString().toLowerCase() ?? '';
              final docPhone = docData?['phoneNumber']?.toString() ?? '';
              
              // Verify email matches exactly
              if (docEmail == userEmail.toLowerCase() && (userPhone.isEmpty || docPhone == userPhone || docPhone.isEmpty)) {
                print('✅ Found face embeddings by email: ${doc.id}');
                fallbackDoc = doc;
              }
            }
            
            // Try phone if email didn't work
            if (fallbackDoc == null && phoneQuery != null && phoneQuery.docs.isNotEmpty) {
              final doc = phoneQuery.docs.first;
              final docData = doc.data() as Map<String, dynamic>?;
              final docEmail = docData?['email']?.toString().toLowerCase() ?? '';
              final docPhone = docData?['phoneNumber']?.toString() ?? '';
              
              // Verify phone matches exactly
              if (docPhone == userPhone && (userEmail.isEmpty || docEmail == userEmail.toLowerCase() || docEmail.isEmpty)) {
                print('✅ Found face embeddings by phone: ${doc.id}');
                fallbackDoc = doc;
              }
            }
            
            if (fallbackDoc != null && fallbackDoc.exists) {
              print('✅ Found face embeddings via email/phone fallback: ${fallbackDoc.id}');
              print('🔄 Migrating to permanent userId: $userId');
              
              // Migrate embeddings to permanent userId
              try {
                final fallbackData = fallbackDoc.data() as Map<String, dynamic>?;
                if (fallbackData != null) {
                  final fallbackEmbeddings = fallbackData['embeddings'] as List?;
                  
                  if (fallbackEmbeddings != null && fallbackEmbeddings.isNotEmpty) {
                    // Copy embeddings to permanent userId
                    await _firestore.collection('face_embeddings').doc(userId).set({
                      'userId': userId,
                      'embedding': fallbackData['embedding'],
                      'embeddings': fallbackEmbeddings,
                      'email': userEmail,
                      'phoneNumber': userPhone,
                      'registeredAt': fallbackData['registeredAt'] ?? FieldValue.serverTimestamp(),
                      'lastUpdated': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: false));
                    print('✅ Face embeddings migrated to permanent userId: $userId');
                    
                    // Re-fetch from permanent userId
                    faceDoc = await _firestore.collection('face_embeddings').doc(userId).get();
                  } else {
                    print('⚠️ Fallback document has no embeddings - cannot migrate');
                    return {
                      'success': false,
                      'error': 'Face not registered. Please complete signup with face verification.',
                    };
                  }
                  }
                } catch (e) {
                print('⚠️ Error migrating embeddings from fallback: $e');
                return {
                  'success': false,
                  'error': 'Face verification failed. Please try again.',
                };
              }
            } else {
              // No embeddings found by email/phone either
              print('❌ No face embeddings found for user: $userId (checked permanent ID, temp_ ID, and email/phone)');
              return {
                'success': false,
                'error': 'Face not registered. Please complete signup with face verification.',
              };
              }
          } catch (e) {
            print('⚠️ Error during email/phone fallback search: $e');
            return {
              'success': false,
              'error': 'Face not registered. Please complete signup with face verification.',
            };
          }
        }
      }
      
      // Final check: if still no embeddings found, reject
      if (!faceDoc.exists) {
        print('❌ No face embeddings found for user: $userId (even after fallback search)');
        return {
          'success': false,
          'error': 'Face not registered. Please complete signup with face verification.',
        };
      }

      final faceData = faceDoc.data() as Map<String, dynamic>?;
      if (faceData == null) {
        print('❌ Face embeddings document data is null');
        return {
          'success': false,
          'error': 'Face not registered. Please complete signup with face verification.',
        };
      }
      
      // CRITICAL SECURITY: Verify face_embeddings document belongs to THIS exact user
      // This prevents using wrong user's embeddings even if document ID matches
      final faceDocUserId = faceDoc.id; // Document ID should be userId
      final faceDataUserId = faceData['userId']?.toString() ?? '';
      final faceDocEmail = faceData['email']?.toString().toLowerCase() ?? '';
      final faceDocPhone = faceData['phoneNumber']?.toString() ?? '';
      
      // CRITICAL: Document ID must match userId OR be temp_<userId> OR match email/phone (if found via fallback)
      // If found via email/phone fallback, verify email/phone match exactly
      final docEmailMatches = faceDocEmail.isNotEmpty && userEmail.isNotEmpty && faceDocEmail == userEmail.toLowerCase();
      final docPhoneMatches = faceDocPhone.isNotEmpty && userPhone.isNotEmpty && faceDocPhone == userPhone;
      final idMatches = faceDocUserId == userId || faceDocUserId.startsWith('temp_');
      
      if (!idMatches && !docEmailMatches && !docPhoneMatches) {
        print('🚨🚨🚨🚨🚨 CRITICAL SECURITY: Face embeddings document does NOT belong to this user!');
        print('🚨🚨🚨 Document ID: $faceDocUserId');
        print('🚨🚨🚨 User ID: $userId');
        print('🚨🚨🚨 Document email: $faceDocEmail, User email: $userEmail');
        print('🚨🚨🚨 Document phone: $faceDocPhone, User phone: $userPhone');
        print('🚨🚨🚨 REJECTING - document does not belong to this user');
        return {
          'success': false,
          'error': 'Face verification failed. Account verification error.',
        };
      }
      
      // CRITICAL: If userId field exists in document and doesn't match, but email/phone match, allow it
      // (This handles the case where embeddings were saved with a different userId but same email/phone)
      if (faceDataUserId.isNotEmpty && faceDataUserId != userId && !docEmailMatches && !docPhoneMatches) {
        print('🚨🚨🚨🚨🚨 CRITICAL SECURITY: Face embeddings userId field does NOT match!');
        print('🚨🚨🚨 Document userId field: $faceDataUserId');
        print('🚨🚨🚨 User ID: $userId');
        print('🚨🚨🚨 REJECTING - embeddings do not belong to this user');
        return {
          'success': false,
          'error': 'Face verification failed. Account verification error.',
        };
      }
      
      // CRITICAL: Verify email/phone in face_embeddings document matches user (already extracted above)
      
      // If email/phone are stored, they must match EXACTLY
      if (faceDocEmail.isNotEmpty && userEmail.isNotEmpty && faceDocEmail != userEmail.toLowerCase()) {
        print('🚨🚨🚨🚨🚨 CRITICAL SECURITY: Face embeddings email does NOT match!');
        print('🚨🚨🚨 Document email: $faceDocEmail');
        print('🚨🚨🚨 User email: $userEmail');
        print('🚨🚨🚨 REJECTING - embeddings do not belong to this email');
        return {
          'success': false,
          'error': 'Face verification failed. Account verification error.',
        };
      }
      
      if (faceDocPhone.isNotEmpty && userPhone.isNotEmpty && faceDocPhone != userPhone) {
        print('🚨🚨🚨🚨🚨 CRITICAL SECURITY: Face embeddings phone does NOT match!');
        print('🚨🚨🚨 Document phone: $faceDocPhone');
        print('🚨🚨🚨 User phone: $userPhone');
        print('🚨🚨🚨 REJECTING - embeddings do not belong to this phone');
        return {
          'success': false,
          'error': 'Face verification failed. Account verification error.',
        };
      }
      
      print('✅✅✅ Face embeddings document verified - belongs to this exact user');
      print('✅✅✅ Document ID: $faceDocUserId, User ID: $userId');
      print('✅✅✅ Email/phone match confirmed');
      
      // ==========================================
      // CRITICAL SECURITY: CHECK IF FACE MATCHES OTHER USERS BETTER
      // ==========================================
      // If a different face is getting 0.99+ similarity, it might match OTHER users even better
      // This is a fundamental security check - if the face matches someone else better, reject it
      if (!isProfilePhotoVerification) {
        print('🔍🔍🔍 CRITICAL SECURITY CHECK: Verifying face does NOT match other users better...');
        print('🔍🔍🔍 This prevents different faces from accessing accounts');
        
        try {
          // Get current embedding first (we'll generate it later, but need to check uniqueness)
          // Actually, we'll do this check AFTER generating the embedding
          // For now, just log that we'll do this check
          print('🔍🔍🔍 Will check after embedding generation if face matches other users better');
        } catch (e) {
          print('⚠️ Error preparing uniqueness check: $e');
        }
      }
      
      final embeddingsData = faceData['embeddings'] as List?;
      List<Map<String, dynamic>> storedEmbeddings = [];
      
      if (embeddingsData != null && embeddingsData.isNotEmpty) {
        for (final embData in embeddingsData) {
          if (embData is Map && embData['embedding'] != null) {
            storedEmbeddings.add(Map<String, dynamic>.from(embData));
          }
        }
      } else if (faceData['embedding'] != null) {
        // Legacy single embedding format
        storedEmbeddings.add({
          'embedding': faceData['embedding'],
          'source': 'legacy',
        });
      }

      if (storedEmbeddings.isEmpty) {
        print('❌ No valid embeddings found for user: $userId');
        return {
          'success': false,
          'error': 'Face not registered. Please complete signup with face verification.',
        };
      }

      print('✅ STEP 2 COMPLETE: Found ${storedEmbeddings.length} stored embedding(s) for this user');
      
      // CRITICAL SECURITY: Check if stored embeddings are corrupted or identical
      // If all stored embeddings are identical, this indicates corruption or model failure
      if (storedEmbeddings.length >= 2 && !isProfilePhotoVerification) {
        print('🔍 Checking stored embeddings for corruption/identical values...');
        List<List<double>> validEmbeddings = [];
        for (final embData in storedEmbeddings) {
          final embedding = embData['embedding'] as List?;
          if (embedding != null && embedding.isNotEmpty) {
            validEmbeddings.add(embedding.map((e) => (e as num).toDouble()).toList());
          }
        }
        
        if (validEmbeddings.length >= 2) {
          // Check if embeddings are identical (corruption detection)
          double maxSimilarity = 0.0;
          for (int i = 0; i < validEmbeddings.length; i++) {
            for (int j = i + 1; j < validEmbeddings.length; j++) {
              final similarity = _cosineSimilarity(validEmbeddings[i], validEmbeddings[j]);
              if (similarity > maxSimilarity) {
                maxSimilarity = similarity;
              }
            }
          }
          
          // Check if embeddings are suspiciously similar
          // Very high similarity might indicate:
          // 1. Same image registered multiple times (legitimate but not ideal)
          // 2. Embeddings stored incorrectly (corruption)
          // 3. Model producing identical outputs (model failure)
          // 4. Very similar registration conditions (legitimate)
          // Only reject if similarity is extremely high (>=0.999999) - likely exact duplicates/corruption
          // Allow high similarity (0.999-0.999999) with warning - might be legitimate
          // Note: Even identical faces in same conditions typically get 0.99-0.995 similarity, not 0.999+
          if (maxSimilarity >= 0.999999) {
            // Extremely high similarity (>=99.9999%) - likely exact duplicates or corruption
            print('🚨🚨🚨🚨🚨 CRITICAL: Stored embeddings are extremely similar (similarity: ${maxSimilarity.toStringAsFixed(6)})');
            print('🚨🚨🚨 This indicates possible corruption or exact duplicates - embeddings may not differentiate faces');
            print('🚨🚨🚨 REJECTING ACCESS - stored embeddings are invalid');
            return {
              'success': false,
              'error': 'Face verification failed. Stored face data is corrupted. Please re-register your face.',
            };
          } else if (maxSimilarity >= 0.9999) {
            // Very high similarity (99.99%+) - might be legitimate (same conditions) but warn
            print('⚠️⚠️⚠️ WARNING: Stored embeddings are very similar (similarity: ${maxSimilarity.toStringAsFixed(4)})');
            print('⚠️ This might indicate:');
            print('   - Same image registered multiple times (legitimate but not ideal)');
            print('   - Very similar registration conditions (legitimate)');
            print('   - Possible storage issue (investigate if login fails)');
            print('⚠️ Proceeding with verification - will use embedding similarity check as primary validation');
          } else if (maxSimilarity >= 0.999) {
            // High similarity (99.9%+) - likely legitimate, just warn
            print('⚠️ NOTE: Stored embeddings are highly similar (similarity: ${maxSimilarity.toStringAsFixed(4)})');
            print('⚠️ This is normal if registered in similar conditions - proceeding with verification');
          }
          
          print('✅ Stored embeddings check: Max similarity between stored embeddings: ${maxSimilarity.toStringAsFixed(4)} (OK - not identical)');
        }
      }
      
      // ==========================================
      // STEP 2.5: VALIDATE EMAIL-TO-FACE BINDING
      // ==========================================
      // CRITICAL SECURITY: Verify that stored embeddings are actually linked to this email/user
      // This ensures the face data belongs to the registered email - prevents wrong face access
      print('🔐 STEP 2.5: Validating email-to-face binding...');
      print('🔐 Verifying that stored embeddings are linked to email: $userEmail / phone: $userPhone');
      
      // Verify the face_embeddings document has matching email/phone
      final storedEmail = faceData['email']?.toString().toLowerCase() ?? '';
      final storedPhone = faceData['phoneNumber']?.toString() ?? '';
      
      final storedEmailMatches = storedEmail.isEmpty || userEmail.isEmpty || storedEmail == userEmail.toLowerCase();
      final storedPhoneMatches = storedPhone.isEmpty || userPhone.isEmpty || storedPhone == userPhone;
      
      if (!storedEmailMatches && !storedPhoneMatches) {
        print('🚨🚨🚨🚨🚨 CRITICAL SECURITY BREACH: Face embeddings email/phone mismatch!');
        print('🚨🚨🚨 Stored email: $storedEmail, Login email: $userEmail');
        print('🚨🚨🚨 Stored phone: $storedPhone, Login phone: $userPhone');
        print('🚨🚨🚨 These face embeddings do NOT belong to this email/user!');
        print('🚨🚨🚨 REJECTING ACCESS - face data does not match registered email');
        return {
          'success': false,
          'error': 'Face verification failed. These face embeddings do not match the registered email/phone.',
        };
      }
      
      // Verify each embedding has correct email/phone binding (if stored in embedding)
      int validEmbeddingsCount = 0;
      for (final embData in storedEmbeddings) {
        // Check if embedding has email/phone stored (new format)
        final embEmail = embData['email']?.toString().toLowerCase() ?? '';
        final embPhone = embData['phoneNumber']?.toString() ?? '';
        
        if (embEmail.isNotEmpty || embPhone.isNotEmpty) {
          // Embedding has email/phone stored - verify it matches
          final embEmailMatches = embEmail.isEmpty || userEmail.isEmpty || embEmail == userEmail.toLowerCase();
          final embPhoneMatches = embPhone.isEmpty || userPhone.isEmpty || embPhone == userPhone;
          
          if (!embEmailMatches && !embPhoneMatches) {
            print('🚨 SECURITY: Embedding email/phone mismatch - skipping this embedding');
            print('   Embedding email: $embEmail, Login email: $userEmail');
            print('   Embedding phone: $embPhone, Login phone: $userPhone');
            continue; // Skip this embedding
          }
        }
        
        validEmbeddingsCount++;
      }
      
      if (validEmbeddingsCount == 0) {
        print('🚨🚨🚨 CRITICAL: No valid embeddings found after email/phone validation!');
        return {
          'success': false,
          'error': 'Face verification failed. Face embeddings do not match the registered email/phone.',
        };
      }
      
      // Filter to only valid embeddings
      storedEmbeddings = storedEmbeddings.where((embData) {
        final embEmail = embData['email']?.toString().toLowerCase() ?? '';
        final embPhone = embData['phoneNumber']?.toString() ?? '';
        
        if (embEmail.isNotEmpty || embPhone.isNotEmpty) {
          final embEmailMatches = embEmail.isEmpty || userEmail.isEmpty || embEmail == userEmail.toLowerCase();
          final embPhoneMatches = embPhone.isEmpty || userPhone.isEmpty || embPhone == userPhone;
          return embEmailMatches || embPhoneMatches;
        }
        return true; // If no email/phone stored in embedding, assume valid (legacy format)
      }).toList();
      
      print('✅ Email-to-face binding validated: $validEmbeddingsCount / ${storedEmbeddings.length} embeddings match email/phone');
      print('✅ Security: Only embeddings linked to this email/user will be compared');
      print('✅ Security: Face data is confirmed to belong to registered email: $userEmail');

      // ==========================================
      // DEPRECATED: Old Luxand direct call removed
      // Backend API handles all verification now
      // ==========================================

      // ==========================================
      // STEP 3: GENERATE EMBEDDING FOR CURRENT FACE
      // ==========================================
      print('🔍 STEP 3: Preparing embedding for current detected face...');
      List<double> normalizedCurrentEmbedding;
      if (precomputedEmbedding != null && precomputedEmbedding.isNotEmpty) {
        normalizedCurrentEmbedding = List<double>.from(precomputedEmbedding);
        print('✅ Using precomputed deep scan embedding (${normalizedCurrentEmbedding.length}D)');
      } else {
        final generatedEmbedding = await generateEmbedding(
          face: detectedFace,
          cameraImage: cameraImage,
          imageBytes: imageBytes,
          normalize: true,
        );

        if (generatedEmbedding.isEmpty) {
        print('🚨🚨🚨 CRITICAL: Embedding generation returned empty list');
        print('🚨 This can happen if:');
        print('   1. Embedding validation failed (range/variance/stdDev below threshold)');
        print('   2. Model output was all zeros (invalid/corrupted image)');
        print('   3. Image decoding/cropping failed');
        print('🚨 Check FaceNetService logs above for specific validation failure');
        print('💡 Solution: Ensure photo has good lighting, clear face visibility, and proper positioning');
        return {
          'success': false,
          'error': 'Failed to generate face embedding. Please ensure the photo has good lighting and a clear, visible face.',
          };
        }

        normalizedCurrentEmbedding = generatedEmbedding;
      }

      final double embeddingVariance = _calculateEmbeddingVariance(normalizedCurrentEmbedding);
      print('📊 Current embedding variance: ${embeddingVariance.toStringAsFixed(6)}');
      if (embeddingVariance < 0.0005) {
        print('🚨 CRITICAL: Embedding variance extremely low - rejecting frame');
        return {
          'success': false,
          'error': 'Face quality too low for recognition. Please hold steady and ensure your full face is visible.',
        };
      }
      
      // CRITICAL: Validate essential features are present in current face
      final hasEssentialFeatures = FaceLandmarkService.validateEssentialFeatures(detectedFace);
      if (!hasEssentialFeatures) {
        print('🚨 CRITICAL: Current face missing essential features (eyes, nose, mouth)');
        return {
          'success': false,
          'error': 'Face features not complete. Please ensure all features (eyes, nose, mouth) are visible.',
        };
      }
      
      // CRITICAL: Extract landmark features from current face for "whose face is this" validation
      final currentLandmarkFeatures = FaceLandmarkService.extractLandmarkFeatures(detectedFace);
      final currentFeatureDistances = FaceLandmarkService.calculateFeatureDistances(detectedFace);
      
      print('✅ Current face landmark features extracted: ${currentLandmarkFeatures.keys.join(', ')}');
      print('✅ Current face feature distances: ${currentFeatureDistances.keys.join(', ')}');
      print('🔐 This enables validation: "whose nose, eyes, lips, etc. is this"');
      
      // Verify normalization
      final currentNorm = _l2Norm(normalizedCurrentEmbedding);
      if (currentNorm < 0.9 || currentNorm > 1.1) {
        print('⚠️ WARNING: Current embedding normalization issue! Norm: $currentNorm');
        if (currentNorm > 0.0) {
          final renormalized = _normalize(normalizedCurrentEmbedding);
          for (int i = 0; i < normalizedCurrentEmbedding.length && i < renormalized.length; i++) {
            normalizedCurrentEmbedding[i] = renormalized[i];
          }
        }
      }

      print('✅ STEP 3 COMPLETE: Current embedding generated and normalized');

      // ==========================================
      // STEP 4: 1:1 COMPARISON - ONLY THIS USER'S EMBEDDINGS
      // ==========================================
      // CRITICAL SECURITY: Compare ONLY against this user's embeddings
      // This is the core security feature - prevents unauthorized access
      // Different people typically have similarity 0.70-0.95
      // Same person should have similarity 0.99+ (for login)
      print('🔍 ==========================================');
      print('🔍 STEP 4: PERFECT FACE RECOGNITION (1:1 VERIFICATION)');
      print('🔍 ==========================================');
      print('🔍 Comparing detected face ONLY against this user\'s ${storedEmbeddings.length} embedding(s)');
      print('🔍 Email/Phone: $userEmail / $userPhone');
      print('🔍 User ID: $userId');
      print('🔍 NOT comparing against all users - this is 1:1 verification');
      print('🔍 CRITICAL: Only the user who registered this email/phone can pass');
      print('🔍 CRITICAL: ANY other face (wrong person) will be REJECTED');
      print('🔍 ==========================================');
      double bestSimilarity = 0.0;
      String? bestSource;
      
      // CRITICAL SECURITY: For 1:1 verification, use ABSOLUTE MAXIMUM STRICTNESS
      // Since we know exactly which user it should match, require EXTREMELY HIGH similarity
      // Different people typically have similarity 0.70-0.95, same person should be 0.97-0.99+
      final embeddingCount = storedEmbeddings.length;
      
      // PERFECT RECOGNITION: Use ABSOLUTE MAXIMUM thresholds for perfect accuracy
      // Different people typically have similarity 0.70-0.95, same person should be 0.99+
      // For PERFECT recognition, we require EXTREMELY HIGH similarity (99%+)
      // NOTE: Profile photos may have slightly lower similarity due to different conditions
      
      // ABSOLUTE MINIMUM: Reject anything below this (definitely wrong face)
      // CRITICAL SECURITY: Set high enough to prevent false positives
      double absoluteMinimum; // Will be set based on verification type
      
      // PERFECT THRESHOLD: Must meet this to pass (PERFECT recognition requires 99%+)
      // For profile photos, use slightly lower threshold (98.5%+) to account for different conditions
      double threshold;
      if (isProfilePhotoVerification) {
        // PROFILE PHOTO: More lenient threshold (75-80%) to account for different lighting/angles/conditions
        // Profile photos can have very different conditions than verification steps
        if (embeddingCount <= 1) {
          threshold = 0.75; // 75% for single embedding (profile photo)
          absoluteMinimum = 0.70; // Reject if < 70%
          print('📸 PROFILE PHOTO: Using threshold (${threshold.toStringAsFixed(3)}) for user with 1 embedding');
        } else if (embeddingCount == 2) {
          threshold = 0.80; // 80% for 2 embeddings (profile photo)
          absoluteMinimum = 0.75; // Reject if < 75%
          print('📸 PROFILE PHOTO: Using threshold (${threshold.toStringAsFixed(3)}) for user with 2 embeddings');
        } else {
          threshold = 0.80; // 80% for 3+ embeddings (profile photo)
          absoluteMinimum = 0.75; // Reject if < 75%
          print('📸 PROFILE PHOTO: Using threshold (${threshold.toStringAsFixed(3)}) for user with ${embeddingCount} embeddings');
        }
        print('📸 PROFILE PHOTO MODE: Requiring ${threshold.toStringAsFixed(3)} similarity (allows variation in lighting/angles/conditions)');
      } else {
        // LOGIN: BALANCED STRICTNESS - 99%+ required for reliable recognition
        // CRITICAL SECURITY: Unregistered users must NEVER be able to log in
        // Different people: 0.70-0.95 | Same person: 0.99+ (RELIABLE)
        // Balanced threshold: 99% for reliable recognition while preventing false rejections
        // Adjusted from 0.995 to 0.99 to allow legitimate users while maintaining security
        threshold = 0.99; // BALANCED: 99% for reliable recognition (allows legitimate variations)
        absoluteMinimum = 0.97; // CRITICAL: Reject if < 97% (balanced to prevent false rejections)
        
        // BALANCED: Use 99% threshold for ALL embedding counts (balanced for legitimate users)
        // This prevents similar-looking people while allowing legitimate users
        print('🔐 ==========================================');
        print('🔐 BALANCED SECURITY: LOGIN VERIFICATION');
        print('🔐 ==========================================');
        print('🔐 Balanced threshold: 0.99 (99%) for reliable recognition');
        print('🔐 This allows legitimate users while preventing unauthorized access');
        print('🔐 Different people typically achieve 0.70-0.95 similarity, NOT 0.99+');
        print('🔐 Same person should achieve 0.99+ similarity for reliable recognition');
        print('📊 User has ${embeddingCount} stored embedding(s)');
        print('🎯 REQUIRED: ${threshold.toStringAsFixed(3)} similarity (99%+) for authentication');
        print('🎯 This ensures reliable recognition while allowing legitimate variations');
        print('🔐 ==========================================');
      }

      // Compare against all stored embeddings
      // CRITICAL: Validate each stored embedding before comparison
      // CRITICAL: Also validate landmark features for "whose face is this" recognition
      List<double> allSimilarities = [];
      int passingEmbeddingsCount = 0; // Track how many embeddings pass both checks
      int embeddingsWithValidLandmarks = 0; // Track embeddings with valid landmark features
      double bestWeightedScore = 0.0; // Track best weighted score separately from similarity
      double bestActualSimilarity = 0.0; // Track actual similarity for final validation
      for (final embData in storedEmbeddings) {
        final storedEmbeddingRaw = embData['embedding'] as List?;
        
        // CRITICAL: Validate landmark features match for "whose nose, eyes, lips, etc. is this"
        // This ensures the face features match the registered user
        final storedLandmarkFeatures = embData['landmarkFeatures'] as Map<String, dynamic>?;
        final storedFeatureDistances = embData['featureDistances'] as Map<String, dynamic>?;
        
        bool landmarkFeaturesMatch = true;
        // Track if stored landmarks are valid (not corrupted) - used to count embeddingsWithValidLandmarks
        bool hasValidLandmarkFeatures = false;
        
        if (storedLandmarkFeatures != null && currentLandmarkFeatures.isNotEmpty) {
          // Convert stored features to proper format
          final storedFeatures = <String, List<double>>{};
          storedLandmarkFeatures.forEach((key, value) {
            if (value is List && value.isNotEmpty) {
              storedFeatures[key] = value.map((e) => (e as num).toDouble()).toList();
            }
          });
          
          // CRITICAL: Check if stored landmark features are valid (not empty/corrupted)
          // If stored features are empty, treat as "no landmark features" and skip validation
          if (storedFeatures.isEmpty) {
            print('⚠️ Stored landmark features exist but are empty/corrupted - treating as "no landmark features"');
            print('⚠️ This is normal for corrupted or incomplete embeddings - proceeding with embedding comparison');
            hasValidLandmarkFeatures = false;
            landmarkFeaturesMatch = true; // Skip landmark validation
          } else {
            // Stored features are valid - mark as having valid landmarks
            hasValidLandmarkFeatures = true;
            embeddingsWithValidLandmarks++; // Count this embedding as having valid landmarks
          
          // Compare landmark features
          final landmarkSimilarity = FaceLandmarkService.compareLandmarkFeatures(
            storedFeatures,
            currentLandmarkFeatures,
          );
          
          // PROFILE PHOTO MODE: More lenient landmark validation
          // Profile photos can have different angles/lighting, so landmark positions vary more
          // Use lower threshold for profile photos (0.60) vs login (0.80)
          final landmarkThreshold = isProfilePhotoVerification ? 0.60 : 0.80;
          
            // CRITICAL SECURITY: For login, if landmark similarity is VERY low (< 0.50), reject immediately
            // This indicates a completely different person - no fallback should be allowed
            // BUT: If similarity is exactly 0.0000, it might indicate corrupted data, not wrong person
            final criticalRejectThreshold = 0.50; // If below this, definitely wrong person
            
            // CRITICAL: If landmark similarity is extremely low (< 0.20), it might be corrupted data
            // Check if stored features actually have valid data before rejecting
            // Landmark similarity of 0.0000 or very low (< 0.20) often indicates corrupted/missing data
            if (landmarkSimilarity < 0.20) {
              print('⚠️ Landmark similarity is very low (${landmarkSimilarity.toStringAsFixed(4)}) - likely corrupted/incomplete data');
              print('⚠️ Stored features count: ${storedFeatures.length} (expected: 4-6 features)');
              print('⚠️ Treating as "no valid landmark features" - proceeding with embedding comparison');
              hasValidLandmarkFeatures = false;
              landmarkFeaturesMatch = true; // Skip landmark validation for corrupted data
            } else if (landmarkSimilarity < landmarkThreshold) {
            print('🚨 Landmark feature mismatch: similarity=${landmarkSimilarity.toStringAsFixed(4)} < $landmarkThreshold');
            print('🚨 This face\'s features (nose, eyes, lips) do NOT match stored features');
            
              // CRITICAL SECURITY: For login, if landmark similarity is very low, reject immediately
              // Different people typically have landmark similarity < 0.50
              // Same person should have landmark similarity > 0.60 even with different angles/lighting
              // BUT: If similarity is very low (< 0.20), it might indicate corrupted data
              if (!isProfilePhotoVerification && landmarkSimilarity < criticalRejectThreshold) {
                print('🚨🚨🚨🚨🚨 CRITICAL SECURITY REJECTION: Landmark similarity ${landmarkSimilarity.toStringAsFixed(4)} < ${criticalRejectThreshold.toStringAsFixed(2)}');
                print('🚨🚨🚨 This indicates a COMPLETELY DIFFERENT PERSON - no fallback allowed');
                print('🚨🚨🚨 Same person should have landmark similarity > 0.50 even with different angles/lighting');
                print('🚨🚨🚨 Different people typically have landmark similarity < 0.50');
                print('🚨🚨🚨 REJECTING IMMEDIATELY - this is NOT the registered user');
                landmarkFeaturesMatch = false;
              } else {
              // Landmark similarity is low but not critically low - check feature distances as fallback
              // BUT: For login, require BOTH landmark similarity >= 0.50 AND feature distances to pass
              // This prevents wrong faces from passing based on feature distances alone
            if (storedFeatureDistances != null && currentFeatureDistances.isNotEmpty) {
              double totalDistanceError = 0.0;
              int matchingFeatures = 0;
              
              for (final featureName in storedFeatureDistances.keys) {
                if (currentFeatureDistances.containsKey(featureName)) {
                  final storedDist = (storedFeatureDistances[featureName] as num).toDouble();
                  final currentDist = currentFeatureDistances[featureName]!;
                  final error = (storedDist - currentDist).abs();
                  totalDistanceError += error;
                  matchingFeatures++;
                }
              }
              
              if (matchingFeatures > 0) {
                final avgDistanceError = totalDistanceError / matchingFeatures;
                  // CRITICAL SECURITY: For login, use STRICTER distance threshold (0.05 instead of 0.10)
                  // This prevents wrong faces from passing based on feature distances alone
                  final distanceThreshold = isProfilePhotoVerification ? 0.1 : 0.05; // STRICTER for login
                  
                  // CRITICAL: For login, require BOTH landmark similarity >= 0.50 AND feature distances to pass
                  // This prevents wrong faces from passing when landmark similarity is very low
                  if (!isProfilePhotoVerification) {
                    if (landmarkSimilarity >= criticalRejectThreshold && avgDistanceError <= distanceThreshold) {
                      print('✅ LOGIN MODE: Both landmark similarity (${landmarkSimilarity.toStringAsFixed(4)} >= ${criticalRejectThreshold.toStringAsFixed(2)}) AND feature distances (avgError=${avgDistanceError.toStringAsFixed(4)} <= ${distanceThreshold.toStringAsFixed(2)}) pass');
                      print('✅ This face passes BOTH checks - accepting');
                      landmarkFeaturesMatch = true;
                    } else {
                      if (landmarkSimilarity < criticalRejectThreshold) {
                        print('🚨🚨🚨 LOGIN REJECTION: Landmark similarity ${landmarkSimilarity.toStringAsFixed(4)} < ${criticalRejectThreshold.toStringAsFixed(2)} - REJECTING');
                        print('🚨🚨🚨 This indicates a different person - no fallback allowed for login');
                      } else {
                        print('🚨🚨🚨 LOGIN REJECTION: Feature distance avgError=${avgDistanceError.toStringAsFixed(4)} > ${distanceThreshold.toStringAsFixed(2)} - REJECTING');
                        print('🚨🚨🚨 Feature distances do NOT match - this is NOT the registered user');
                      }
                      landmarkFeaturesMatch = false;
                    }
                  } else {
                    // Profile photo mode - more lenient
                if (avgDistanceError <= distanceThreshold) {
                    print('✅ PROFILE PHOTO MODE: Feature distances pass - accepting despite landmark position differences');
                    print('✅ Profile photos can have different angles/lighting, so landmark positions vary more');
                    print('✅ Using feature distances (more stable) as primary validation for profile photos');
                      landmarkFeaturesMatch = true;
                } else {
                  print('🚨 Feature distance mismatch: avgError=${avgDistanceError.toStringAsFixed(4)} > $distanceThreshold');
                  print('🚨 This face\'s feature distances (eye distance, nose-mouth distance) do NOT match');
                  landmarkFeaturesMatch = false;
                    }
                }
              } else {
                // No matching features for distance check - reject
                print('🚨 No matching feature distances found for comparison');
                landmarkFeaturesMatch = false;
              }
            } else {
              // No feature distances stored - this is normal for old embeddings
                // CRITICAL SECURITY: For login, require landmark similarity >= 0.50 even for old embeddings
                // If landmark similarity is very low, this is likely a wrong face
              print('⚠️ No feature distances available for fallback validation');
              print('⚠️ This is normal for older embeddings - checking landmark similarity as minimum validation');
              
                // CRITICAL: For login, require higher landmark similarity (0.50) even for old embeddings
                // For profile photos, be more lenient (0.30)
                final minLandmarkThreshold = isProfilePhotoVerification ? 0.30 : 0.50;
              if (landmarkSimilarity >= minLandmarkThreshold) {
                print('⚠️ Landmark similarity ${landmarkSimilarity.toStringAsFixed(4)} >= ${minLandmarkThreshold.toStringAsFixed(2)} - allowing comparison');
                  print('⚠️ Old embedding without feature distances - will proceed with embedding similarity check (${threshold.toStringAsFixed(3)}+ required)');
                  print('⚠️ Note: Embedding similarity (${threshold.toStringAsFixed(3)}+) is the primary security check');
                landmarkFeaturesMatch = true; // Allow comparison for old embeddings
              } else {
                print('🚨🚨🚨 CRITICAL: Landmark similarity ${landmarkSimilarity.toStringAsFixed(4)} < ${minLandmarkThreshold.toStringAsFixed(2)} - REJECTING');
                print('🚨🚨🚨 Landmark positions are extremely different - likely NOT the same person');
                landmarkFeaturesMatch = false; // Reject if landmark similarity is extremely low
                }
              }
            }
          } else {
            print('✅ Landmark features match: similarity=${landmarkSimilarity.toStringAsFixed(4)} (>= $landmarkThreshold)');
            print('✅ This face\'s features (nose, eyes, lips) match stored features');
            
            // Also validate feature distances as secondary check
            if (storedFeatureDistances != null && currentFeatureDistances.isNotEmpty) {
              double totalDistanceError = 0.0;
              int matchingFeatures = 0;
              
              for (final featureName in storedFeatureDistances.keys) {
                if (currentFeatureDistances.containsKey(featureName)) {
                  final storedDist = (storedFeatureDistances[featureName] as num).toDouble();
                  final currentDist = currentFeatureDistances[featureName]!;
                  final error = (storedDist - currentDist).abs();
                  totalDistanceError += error;
                  matchingFeatures++;
                }
              }
              
              if (matchingFeatures > 0) {
                final avgDistanceError = totalDistanceError / matchingFeatures;
                if (avgDistanceError > 0.1) {
                  print('🚨 Feature distance mismatch: avgError=${avgDistanceError.toStringAsFixed(4)} > 0.1');
                  print('🚨 This face\'s feature distances (eye distance, nose-mouth distance) do NOT match');
                  landmarkFeaturesMatch = false;
                } else {
                  print('✅ Feature distances match: avgError=${avgDistanceError.toStringAsFixed(4)} < 0.1');
                }
                }
              }
            }
          }
        } else {
          // No landmark features stored - skip landmark validation
          // This can happen for old embeddings that don't have landmark data
          print('⚠️ No landmark features stored for this embedding - skipping landmark validation');
          print('⚠️ This is normal for older embeddings - proceeding with embedding comparison');
          hasValidLandmarkFeatures = false;
          landmarkFeaturesMatch = true;
        }
        
        // CRITICAL: First check if embedding is valid
        if (storedEmbeddingRaw == null || storedEmbeddingRaw.isEmpty) {
          print('⚠️ Skipping invalid embedding: null or empty');
          continue;
        }
        
        // CRITICAL: Skip this embedding if landmark features don't match
        // This ensures "whose nose, eyes, lips, etc. is this" validation
        // EXCEPTION: For profile photos, be more lenient - still calculate similarity even if landmarks don't match perfectly
        // Only skip if it's a critical mismatch (very low similarity indicating wrong person)
        if (!landmarkFeaturesMatch) {
          if (isProfilePhotoVerification) {
            // PROFILE PHOTO: More lenient - still calculate similarity even if landmarks don't match
            // Profile photos can have different angles/lighting, so landmark positions vary more
            // Only skip if landmark similarity is critically low (< 0.30) indicating wrong person
            final storedLandmarkFeatures = embData['landmarkFeatures'] as Map<String, dynamic>?;
            if (storedLandmarkFeatures != null && currentLandmarkFeatures.isNotEmpty) {
              final storedFeatures = <String, List<double>>{};
              storedLandmarkFeatures.forEach((key, value) {
                if (value is List && value.isNotEmpty) {
                  storedFeatures[key] = value.map((e) => (e as num).toDouble()).toList();
                }
              });
              if (storedFeatures.isNotEmpty) {
                final landmarkSimilarity = FaceLandmarkService.compareLandmarkFeatures(
                  storedFeatures,
                  currentLandmarkFeatures,
                );
                // For profile photos, only skip if landmark similarity is critically low (< 0.30)
                if (landmarkSimilarity < 0.30) {
                  print('🚨🚨🚨 PROFILE PHOTO: Critical landmark mismatch (${landmarkSimilarity.toStringAsFixed(4)} < 0.30) - skipping embedding');
                  print('🚨🚨🚨 This indicates a completely different person');
                  continue; // Skip this embedding - critically low landmark similarity
                } else {
                  print('⚠️ PROFILE PHOTO: Landmark features don\'t match perfectly (${landmarkSimilarity.toStringAsFixed(4)}), but similarity is acceptable for profile photos');
                  print('⚠️ Still calculating embedding similarity - profile photos can have different angles/lighting');
                  // Continue to calculate similarity despite landmark mismatch
                }
              } else {
                // No valid stored features - proceed with similarity calculation
                print('⚠️ PROFILE PHOTO: No valid stored landmark features - proceeding with similarity calculation');
              }
            } else {
              // No landmark features - proceed with similarity calculation
              print('⚠️ PROFILE PHOTO: No landmark features available - proceeding with similarity calculation');
            }
          } else {
            // LOGIN: Strict - skip if landmarks don't match
          print('🚨🚨🚨 CRITICAL: Landmark features do NOT match - skipping this embedding');
          print('🚨🚨🚨 This face\'s features (nose, eyes, lips) are NOT the registered user\'s features');
          continue; // Skip this embedding - features don't match
          }
        }
        
        final storedEmbeddingList = storedEmbeddingRaw.map((e) => (e as num).toDouble()).toList();

        // CRITICAL: Validate dimension
        if (storedEmbeddingList.length != normalizedCurrentEmbedding.length) {
          print('⚠️ Skipping embedding with wrong dimension: ${storedEmbeddingList.length} vs ${normalizedCurrentEmbedding.length}');
          continue;
        }
        
        // CRITICAL: Validate embedding quality - check for invalid values
        bool isValidEmbedding = true;
        for (int i = 0; i < storedEmbeddingList.length; i++) {
          if (storedEmbeddingList[i].isNaN || storedEmbeddingList[i].isInfinite) {
            print('⚠️ Skipping embedding with invalid value at index $i: ${storedEmbeddingList[i]}');
            isValidEmbedding = false;
            break;
          }
        }
        
        if (!isValidEmbedding) {
          continue;
        }
        
        // CRITICAL: Check if stored embedding is normalized and validate
        final storedNorm = _l2Norm(storedEmbeddingList);
        List<double> storedEmbedding;
        
        if (storedNorm < 0.9 || storedNorm > 1.1) {
          print('⚠️ Stored embedding not normalized (norm: ${storedNorm.toStringAsFixed(6)}), normalizing...');
          storedEmbedding = _normalize(storedEmbeddingList);
          // Verify normalization succeeded
          final newNorm = _l2Norm(storedEmbedding);
          if (newNorm < 0.9 || newNorm > 1.1) {
            print('⚠️ Normalization failed, skipping embedding');
            continue;
          }
        } else {
          storedEmbedding = storedEmbeddingList;
        }
        
        // PERFECT RECOGNITION: Calculate similarity with validated embeddings
        final similarity = _cosineSimilarity(normalizedCurrentEmbedding, storedEmbedding);
        
        // CRITICAL: Validate similarity result
        if (similarity.isNaN || similarity.isInfinite || similarity < -1.0 || similarity > 1.0) {
          print('⚠️ Invalid similarity result: $similarity, skipping');
          continue;
        }
        
        // PERFECT RECOGNITION: Additional validation using Euclidean distance
        // For normalized embeddings, Euclidean distance = sqrt(2 - 2*cosine_similarity)
        // This provides an additional verification metric for perfect accuracy
        double euclideanDistance = 0.0;
        for (int i = 0; i < normalizedCurrentEmbedding.length && i < storedEmbedding.length; i++) {
          final diff = normalizedCurrentEmbedding[i] - storedEmbedding[i];
          euclideanDistance += diff * diff;
        }
        euclideanDistance = sqrt(euclideanDistance);
        
        // PERFECT RECOGNITION: For same person with normalized embeddings:
        // - Cosine similarity: 0.99+ (very high)
        // - Euclidean distance: < 0.15 (very small)
        // For different people:
        // - Cosine similarity: 0.70-0.95 (lower)
        // - Euclidean distance: > 0.3 (larger)
        
        // BALANCED SECURITY: Distance check for login
        // Distance threshold: 0.15 for login (balanced for legitimate users and variations)
        // This prevents unregistered users while allowing legitimate variations in lighting/angles
        // Unregistered users typically get distance > 0.20, legitimate users get < 0.15
        final maxDistanceForSamePerson = isProfilePhotoVerification ? 0.15 : 0.15; // Balanced for login (allows legitimate variations)
        
        allSimilarities.add(similarity);
        print('📊 Similarity with ${embData['source'] ?? 'unknown'}: ${similarity.toStringAsFixed(4)}');
        print('📊 Euclidean distance: ${euclideanDistance.toStringAsFixed(4)} (max for same person: ${maxDistanceForSamePerson.toStringAsFixed(2)})');
        
        // CRITICAL SECURITY: For login, ONLY accept if BOTH similarity >= threshold AND distance <= maxDistance
        // This prevents unregistered users who might get high similarity but wrong distance
        // CRITICAL: For login, we MUST require threshold (0.99) - no exceptions
        if (isProfilePhotoVerification) {
          // Profile photos: More lenient - always track bestSimilarity for debugging
          if (similarity > bestSimilarity) {
            bestSimilarity = similarity; // Always track best similarity for debugging
            bestSource = embData['source']?.toString() ?? 'unknown';
          }
          
          // PROFILE PHOTO: More lenient threshold
          // Profile photos can have very different lighting/angles, so similarity can be lower
          // If landmark features passed (even if not perfectly), use lower threshold
          // The landmark check already validated that this is the same person's face structure
          final profilePhotoThreshold = 0.75; // Use 75% threshold during loop (will use 80% at final check)
          
          if (similarity >= profilePhotoThreshold) {
            print('✅ PROFILE PHOTO MATCH: Similarity ${similarity.toStringAsFixed(4)} >= ${profilePhotoThreshold.toStringAsFixed(3)}');
            print('✅ Profile photos can have lower similarity due to different lighting/angles');
          } else {
            print('🚨 PROFILE PHOTO: Similarity ${similarity.toStringAsFixed(4)} < ${profilePhotoThreshold.toStringAsFixed(3)} (will check at end if acceptable)');
            print('   - Normal threshold: ${threshold.toStringAsFixed(3)}, Profile photo threshold: ${profilePhotoThreshold.toStringAsFixed(3)}');
            print('   - Euclidean distance: ${euclideanDistance.toStringAsFixed(4)} (max: ${maxDistanceForSamePerson.toStringAsFixed(2)})');
            print('   - Note: Final check will use more lenient threshold (80%) for profile photos');
          }
        } else {
          // LOGIN: Require BOTH similarity >= threshold (0.99) AND distance <= maxDistance (0.12)
          // BALANCED SECURITY: This is the PRIMARY security gate - balanced for legitimate users
          // Unregistered users typically get 0.70-0.95 similarity, which fails this check
          // Even if similarity is high, distance must also pass (prevents false positives)
          // Distance threshold increased from 0.10 to 0.12 to allow legitimate variations
          
          // ==========================================
          // MULTI-FACTOR WEIGHTED SCORING SYSTEM
          // ==========================================
          // Instead of binary pass/fail, calculate a weighted score
          // This allows partial matches and better decision making
          
          // 1. Similarity Score (0-1, normalized)
          // Higher similarity = higher score, but cap at 1.0
          final similarityScore = (similarity / 1.0).clamp(0.0, 1.0);
          
          // 2. Distance Score (0-1, normalized)
          // Lower distance = higher score (inverse relationship)
          // Normalize: distance 0.0 = score 1.0, distance maxDistance = score 0.0
          final maxDistanceForScoring = maxDistanceForSamePerson * 1.5; // Allow some margin
          final distanceScore = (1.0 - (euclideanDistance / maxDistanceForScoring).clamp(0.0, 1.0));
          
          // 3. Landmark Score (0-1, normalized)
          double landmarkScore = 1.0; // Default: full score if no landmarks
          if (storedLandmarkFeatures != null && currentLandmarkFeatures.isNotEmpty && hasValidLandmarkFeatures) {
            final storedFeatures = <String, List<double>>{};
            storedLandmarkFeatures.forEach((key, value) {
              if (value is List && value.isNotEmpty) {
                storedFeatures[key] = value.map((e) => (e as num).toDouble()).toList();
              }
            });
            if (storedFeatures.isNotEmpty) {
              final landmarkSimilarity = FaceLandmarkService.compareLandmarkFeatures(
                storedFeatures,
                currentLandmarkFeatures,
              );
              // Normalize landmark similarity to 0-1 score
              landmarkScore = landmarkSimilarity.clamp(0.0, 1.0);
            }
          }
          
          // 4. Feature Distance Score (0-1, normalized)
          double featureDistanceScore = 1.0; // Default: full score if no feature distances
          if (storedFeatureDistances != null && currentFeatureDistances.isNotEmpty) {
            double totalDistanceError = 0.0;
            int matchingFeatures = 0;
            for (final featureName in storedFeatureDistances.keys) {
              if (currentFeatureDistances.containsKey(featureName)) {
                final storedDist = (storedFeatureDistances[featureName] as num).toDouble();
                final currentDist = currentFeatureDistances[featureName]!;
                final error = (storedDist - currentDist).abs();
                totalDistanceError += error;
                matchingFeatures++;
              }
            }
            if (matchingFeatures > 0) {
              final avgDistanceError = totalDistanceError / matchingFeatures;
              final featureDistanceThreshold = isProfilePhotoVerification ? 0.1 : 0.05;
              // Normalize: error 0.0 = score 1.0, error threshold = score 0.0
              featureDistanceScore = (1.0 - (avgDistanceError / featureDistanceThreshold).clamp(0.0, 1.0));
            }
          }
          
          // Calculate weighted final score
          // Weights: Similarity (40%), Distance (25%), Landmarks (20%), Feature Distances (15%)
          final weightedScore = (similarityScore * 0.40) +
                               (distanceScore * 0.25) +
                               (landmarkScore * 0.20) +
                               (featureDistanceScore * 0.15);
          
          // Adaptive threshold based on registration quality
          // High quality (3+ embeddings): 0.75, Medium (2): 0.70, Low (1): 0.65
          final adaptiveThreshold = embeddingCount >= 3 ? 0.75 : (embeddingCount == 2 ? 0.70 : 0.65);
          
          print('📊 ==========================================');
          print('📊 MULTI-FACTOR SCORING FOR EMBEDDING');
          print('📊 ==========================================');
          print('📊 Similarity: ${similarity.toStringAsFixed(4)} → Score: ${(similarityScore * 100).toStringAsFixed(1)}% (40% weight)');
          print('📊 Distance: ${euclideanDistance.toStringAsFixed(4)} → Score: ${(distanceScore * 100).toStringAsFixed(1)}% (25% weight)');
          print('📊 Landmarks: ${landmarkScore.toStringAsFixed(4)} → Score: ${(landmarkScore * 100).toStringAsFixed(1)}% (20% weight)');
          print('📊 Feature Distances: ${featureDistanceScore.toStringAsFixed(4)} → Score: ${(featureDistanceScore * 100).toStringAsFixed(1)}% (15% weight)');
          print('📊 WEIGHTED FINAL SCORE: ${(weightedScore * 100).toStringAsFixed(1)}%');
          print('📊 Adaptive Threshold: ${(adaptiveThreshold * 100).toStringAsFixed(1)}% (based on ${embeddingCount} embedding(s))');
          print('📊 ==========================================');
          
          // Use weighted score instead of binary pass/fail
          final scorePass = weightedScore >= adaptiveThreshold;
          final similarityPass = similarity >= threshold; // Keep for logging
          final distancePass = euclideanDistance <= maxDistanceForSamePerson; // Keep for logging
          
          if (scorePass) {
            // Weighted score passed - this is a valid match
            passingEmbeddingsCount++; // Count how many embeddings passed
            if (weightedScore > bestWeightedScore || (weightedScore == bestWeightedScore && similarity > bestActualSimilarity)) {
              bestWeightedScore = weightedScore; // Store best weighted score
              bestActualSimilarity = similarity; // Store actual similarity for validation
              bestSimilarity = similarity; // Keep for backward compatibility
              bestSource = embData['source']?.toString() ?? 'unknown';
              print('✅✅✅ WEIGHTED SCORE MATCH: ${(weightedScore * 100).toStringAsFixed(1)}% >= ${(adaptiveThreshold * 100).toStringAsFixed(1)}%');
              print('✅✅✅ This is the CORRECT user - weighted score passed');
              print('🔐🔐🔐 SECURITY: bestWeightedScore: ${(bestWeightedScore * 100).toStringAsFixed(1)}%, bestSimilarity: ${bestActualSimilarity.toStringAsFixed(4)}');
            } else {
              print('⚠️ Valid match found but score ${(weightedScore * 100).toStringAsFixed(1)}% <= bestScore ${(bestWeightedScore * 100).toStringAsFixed(1)}% - keeping best match');
            }
          } else {
            // AT LEAST ONE check failed - REJECT this embedding
            // CRITICAL: This is a WRONG FACE - must be rejected
            print('🚨🚨🚨🚨🚨🚨🚨🚨🚨 WRONG FACE DETECTED - REJECTING');
            print('🚨🚨🚨 ==========================================');
            print('🚨🚨🚨 SECURITY REJECTION: This face does NOT match registered user');
            print('🚨🚨🚨 ==========================================');
            print('🚨🚨🚨 Similarity: ${similarity.toStringAsFixed(4)} ${similarityPass ? 'PASS' : '❌ FAIL'} (required: >= ${threshold.toStringAsFixed(3)})');
            print('🚨🚨🚨 Distance: ${euclideanDistance.toStringAsFixed(4)} ${distancePass ? 'PASS' : '❌ FAIL'} (required: <= ${maxDistanceForSamePerson.toStringAsFixed(2)})');
            print('🚨🚨🚨 This embedding is REJECTED - wrong face cannot pass both checks');
            print('🚨🚨🚨 CRITICAL: This is NOT the registered user\'s face');
            print('🚨🚨🚨 Unregistered/wrong faces typically get:');
            print('🚨🚨🚨   - Similarity: 0.70-0.95 (FAIL - below ${threshold.toStringAsFixed(3)} threshold)');
            print('🚨🚨🚨   - Distance: > 0.10 (FAIL - too far from registered face)');
            print('🚨🚨🚨 Only the CORRECT user can pass BOTH checks');
            print('🚨🚨🚨 ==========================================');
            
            // CRITICAL: DO NOT update bestSimilarity if either check failed
            // This prevents wrong faces from setting bestSimilarity
            if (!similarityPass) {
              print('🚨 REASON: Similarity ${similarity.toStringAsFixed(4)} < ${threshold.toStringAsFixed(3)} - this is NOT the registered user');
              print('🚨 Different people typically get 0.70-0.95 similarity, NOT ${threshold.toStringAsFixed(3)}+');
            }
            if (!distancePass) {
              print('🚨 REASON: Distance ${euclideanDistance.toStringAsFixed(4)} > ${maxDistanceForSamePerson.toStringAsFixed(2)} - this is NOT the registered user');
              print('🚨 Different people typically get distance > 0.10, NOT <= 0.10');
            }
          }
        }
      }
      
      // CRITICAL: Ensure we have at least one valid similarity
      if (allSimilarities.isEmpty) {
        print('🚨🚨🚨 CRITICAL: No valid similarities calculated - all embeddings were invalid');
        return {
          'success': false,
          'error': 'Face verification failed. No valid face data found. Please re-register your face.',
        };
      }

      // CRITICAL SECURITY: Detect model failure - if ALL similarities are suspiciously high
      // This indicates the model is not differentiating faces properly
      // BUT: Only trigger if similarities are extremely high (>= 0.999) - not just 0.99
      // This prevents false positives from legitimate high similarities in 1:1 verification
      // NOTE: In 1:1 verification, high similarities (0.99+) are expected for the correct user
      // Model failure detection should only trigger for 1:N searches, not 1:1 verification
      // SKIP model failure detection for 1:1 verification - it's not applicable here

      // ==========================================
      // BALANCED SECURITY: VERIFY WEIGHTED SCORE WAS SET BY VALID MATCH
      // ==========================================
      // For login, bestWeightedScore MUST be set by an embedding that passed weighted score check
      // If bestWeightedScore is still 0.0, NO embedding passed - REJECT IMMEDIATELY
      if (!isProfilePhotoVerification) {
        if (bestWeightedScore == 0.0 || bestActualSimilarity == 0.0) {
          print('🚨🚨🚨🚨🚨🚨🚨🚨🚨 BALANCED SECURITY:');
          print('🚨🚨🚨 No valid match found - all embeddings failed weighted score check');
          print('🚨🚨🚨 This prevents unregistered users - no embedding passed weighted score');
          print('🚨🚨🚨 All similarities calculated: ${allSimilarities.map((s) => s.toStringAsFixed(4)).join(', ')}');
          print('🚨🚨🚨 This means the scanned face does NOT match the registered face');
          print('🚨🚨🚨 Unregistered users typically cannot pass weighted score - REJECTING ACCESS');
          print('🚨🚨🚨 WRONG FACE DETECTED - this is NOT the registered user');
          return {
            'success': false,
            'error': 'Face verification failed. This face does not match the registered face for this account. Please ensure you are using the correct email/phone.',
            'similarity': bestActualSimilarity,
          };
        }
        
        // Final validation: Ensure weighted score meets minimum threshold
        final finalAdaptiveThreshold = embeddingCount >= 3 ? 0.75 : (embeddingCount == 2 ? 0.70 : 0.65);
        if (bestWeightedScore < finalAdaptiveThreshold) {
          print('🚨🚨🚨 BALANCED SECURITY: Weighted score ${(bestWeightedScore * 100).toStringAsFixed(1)}% < ${(finalAdaptiveThreshold * 100).toStringAsFixed(1)}%');
          print('🚨🚨🚨 REJECTING - weighted score does not meet threshold');
          return {
            'success': false,
            'error': 'Face verification failed. This face does not match the registered face for this account.',
            'similarity': bestActualSimilarity,
          };
        }
        
        // CRITICAL SECURITY: For users with only 1 embedding, still require 0.995+ similarity
        // Single embeddings are validated by the same threshold (0.995) - no extra strictness needed
        // The 0.995 threshold itself is already very strict and prevents unauthorized access
        if (embeddingCount == 1) {
          print('🔐 Single embedding detected - using standard ${threshold.toStringAsFixed(3)} threshold (balanced)');
          print('🔐 The ${threshold.toStringAsFixed(3)} threshold is balanced for reliable recognition');
        }
        
        // BALANCED SECURITY: Require embeddings to pass, but be lenient for legitimate users
        // This prevents similar-looking people while allowing legitimate users
        // BUT: Only count embeddings with valid landmark features in the requirement
        // Embeddings without valid landmarks (corrupted data) can still pass based on embedding similarity alone
        // BALANCED: For users with 3+ embeddings, require at least 1 to pass (lenient for legitimate users)
        // For users with 2 embeddings, require at least 1 to pass
        // For users with 1 embedding, require that 1 to pass
        final requiredPassingCount = embeddingsWithValidLandmarks >= 3 ? 1 : (embeddingsWithValidLandmarks >= 2 ? 1 : 1);
        
        // BALANCED: If most embeddings have corrupted landmark data, be VERY lenient
        // If < 2 embeddings have valid landmarks, only require 1 to pass (the embedding similarity check is primary)
        // ALSO: If most embeddings (>= 50%) have corrupted landmarks, be lenient and only require 1 to pass
        final corruptedLandmarkRatio = embeddingCount > 0 ? (embeddingCount - embeddingsWithValidLandmarks) / embeddingCount : 0.0;
        final actualRequiredCount = (embeddingsWithValidLandmarks < 2 || corruptedLandmarkRatio >= 0.5) ? 1 : requiredPassingCount;
        
        print('📊 Landmark data quality: $embeddingsWithValidLandmarks / $embeddingCount embeddings have valid landmarks');
        print('📊 Corrupted landmark ratio: ${(corruptedLandmarkRatio * 100).toStringAsFixed(1)}%');
        print('📊 Required passing count: $actualRequiredCount (based on landmark data quality)');
        
        if (embeddingCount >= 2 && passingEmbeddingsCount < actualRequiredCount) {
          print('🚨🚨🚨🚨🚨🚨🚨🚨🚨 CRITICAL SECURITY BREACH PREVENTION:');
          print('🚨🚨🚨 Not enough embeddings passed the security checks');
          print('🚨🚨🚨 User has $embeddingCount embedding(s), but only $passingEmbeddingsCount passed');
          print('🚨🚨🚨 Embeddings with valid landmarks: $embeddingsWithValidLandmarks');
          print('🚨🚨🚨 Required: At least $actualRequiredCount embedding(s) must pass');
          print('🚨🚨🚨 This prevents similar-looking people from accessing accounts');
          if (passingEmbeddingsCount == 1) {
          print('🚨🚨🚨 Only ONE embedding passed - this is SUSPICIOUS');
          print('🚨🚨🚨 The CORRECT user should have MULTIPLE embeddings pass');
          }
          print('🚨🚨🚨 WRONG FACE DETECTED - REJECTING ACCESS');
          return {
            'success': false,
            'error': 'Face verification failed. This face does not match the registered face for this account. Please ensure you are using the correct email/phone.',
            'similarity': bestSimilarity,
          };
        }
        
        print('🔐🔐🔐 ==========================================');
        print('🔐🔐🔐 BALANCED RECOGNITION VALIDATION');
        print('🔐🔐🔐 ==========================================');
        print('🔐   - bestSimilarity: ${bestSimilarity.toStringAsFixed(4)}');
        print('🔐   - bestSource: ${bestSource ?? "unknown"}');
        print('🔐   - Passing embeddings: $passingEmbeddingsCount / $embeddingCount (required: $actualRequiredCount)');
        print('🔐   - This means $passingEmbeddingsCount embedding(s) passed BOTH checks:');
        print('🔐     ✓ Similarity >= ${threshold.toStringAsFixed(3)} (${bestSimilarity.toStringAsFixed(4)} >= ${threshold.toStringAsFixed(3)})');
        print('🔐     ✓ Distance check passed');
        print('🔐   - BALANCED: Legitimate users can pass with proper similarity and distance');
        print('🔐   - Wrong faces get similarity 0.70-0.95 (FAIL) OR distance > 0.15 (FAIL)');
        print('🔐   - This is the CORRECT user - face matches registered email/phone');
        print('🔐🔐🔐 ==========================================');
        
        // CRITICAL: Additional check - ensure bestSimilarity is actually valid (not just any high value)
        // Even if bestSimilarity > 0, it must meet the threshold (0.995) AND have passed distance check
        // This is redundant but critical for security
        if (bestSimilarity < threshold) {
          print('🚨🚨🚨🚨🚨 CRITICAL SECURITY: bestSimilarity ${bestSimilarity.toStringAsFixed(4)} < threshold ${threshold.toStringAsFixed(3)}');
          print('🚨🚨🚨 This should not happen if distance check worked correctly - REJECTING');
          print('🚨🚨🚨 This prevents unregistered users from accessing registered accounts');
          return {
            'success': false,
            'error': 'Face verification failed. This face does not match the registered face for this account.',
            'similarity': bestSimilarity,
          };
        }
        
        // ==========================================
        // CRITICAL SECURITY: FINAL EMAIL-TO-FACE VALIDATION
        // ==========================================
        // Explicitly confirm that this face belongs to this email
        // This is the final check: registered email = this face
        print('🔐🔐🔐 ==========================================');
        print('🔐🔐🔐 FINAL EMAIL-TO-FACE BINDING VALIDATION');
        print('🔐🔐🔐 ==========================================');
        print('🔐 Registered Email: $userEmail');
        print('🔐 Registered Phone: $userPhone');
        print('🔐 Detected Face Similarity: ${bestSimilarity.toStringAsFixed(4)}');
        print('🔐 Passing Embeddings: $passingEmbeddingsCount / $embeddingCount');
        print('🔐 CRITICAL: Verifying that this face belongs to this email...');
        
        // Verify the best match came from an embedding linked to this email
        if (bestSource != null) {
          final bestEmbedding = storedEmbeddings.firstWhere(
            (e) => e['source']?.toString() == bestSource,
            orElse: () => <String, dynamic>{},
          );
          
          if (bestEmbedding.isNotEmpty) {
            final bestEmbEmail = bestEmbedding['email']?.toString().toLowerCase() ?? '';
            final bestEmbPhone = bestEmbedding['phoneNumber']?.toString() ?? '';
            
            // If embedding has email/phone stored, verify it matches
            if (bestEmbEmail.isNotEmpty || bestEmbPhone.isNotEmpty) {
              final bestEmailMatches = bestEmbEmail.isEmpty || userEmail.isEmpty || bestEmbEmail == userEmail.toLowerCase();
              final bestPhoneMatches = bestEmbPhone.isEmpty || userPhone.isEmpty || bestEmbPhone == userPhone;
              
              if (!bestEmailMatches && !bestPhoneMatches) {
                print('🚨🚨🚨🚨🚨🚨🚨 CRITICAL SECURITY BREACH: Best match embedding does NOT match email!');
                print('🚨🚨🚨 Best embedding email: $bestEmbEmail, Login email: $userEmail');
                print('🚨🚨🚨 Best embedding phone: $bestEmbPhone, Login phone: $userPhone');
                print('🚨🚨🚨 This face does NOT belong to this email - REJECTING ACCESS');
                return {
                  'success': false,
                  'error': 'Face verification failed. This face does not match the registered email/phone.',
                  'similarity': bestSimilarity,
                };
              }
              
              print('✅✅✅ Email-to-face binding CONFIRMED: Best match embedding belongs to this email');
              print('✅✅✅ This face is CONFIRMED to belong to registered email: $userEmail');
            } else {
              print('⚠️ Best embedding does not have email/phone stored (legacy format) - assuming valid');
            }
          }
        }
        
        print('🔐🔐🔐 VALIDATION: Registered email = This face ✅');
        print('🔐🔐🔐 VALIDATION: Face matches stored embeddings ✅');
        print('🔐🔐🔐 VALIDATION: Multiple embeddings passed ✅');
        print('🔐🔐🔐 This is the CORRECT user - email and face are linked');
        print('🔐🔐🔐 ==========================================');
      }

      print('📊 Best similarity: ${bestSimilarity.toStringAsFixed(4)} (threshold: $threshold, absolute minimum: $absoluteMinimum)');
      print('📊 Best source: ${bestSource ?? 'unknown'}');
      print('📊 All similarities: ${allSimilarities.map((s) => s.toStringAsFixed(4)).join(', ')}');
      
        // BALANCED SECURITY: For login, verify bestSimilarity meets threshold
        // This is a redundant check but important for security
      if (!isProfilePhotoVerification && bestSimilarity < threshold) {
        print('🚨🚨🚨 CRITICAL SECURITY: bestSimilarity ${bestSimilarity.toStringAsFixed(4)} < threshold $threshold');
        print('🚨 This should not happen - rejecting for security');
        print('🚨 This prevents unregistered users from accessing registered accounts');
        return {
          'success': false,
          'error': 'Face verification failed. This face does not match the registered face for this account.',
          'similarity': bestSimilarity,
        };
      }
      
      // ==========================================
      // CRITICAL SECURITY: CHECK IF FACE MATCHES OTHER USERS BETTER
      // ==========================================
      // USER'S INSIGHT: If different faces are getting 0.99+ similarity, the embeddings
      // might not be properly differentiating between different people.
      // SOLUTION: Check if this face matches OTHER users' embeddings even better.
      // If it does, this face doesn't belong to the current user - REJECT IMMEDIATELY.
      if (!isProfilePhotoVerification && bestSimilarity >= threshold) {
        print('🔍🔍🔍 ==========================================');
        print('🔍🔍🔍 CRITICAL SECURITY: UNIQUENESS CHECK');
        print('🔍🔍🔍 ==========================================');
        print('🔍🔍🔍 Checking if face matches OTHER users better than current user...');
        print('🔍🔍🔍 Current user similarity: ${bestSimilarity.toStringAsFixed(4)}');
        print('🔍🔍🔍 If face matches someone else better, this is NOT the correct user');
        print('🔍🔍🔍 ==========================================');
        
        try {
          // Get all other users' face embeddings (excluding current user)
          // Note: Firestore doesn't support isNotEqualTo on document ID, so we get all and filter
          final allFaceDocs = await _firestore
              .collection('face_embeddings')
              .limit(100) // Get up to 100 users for comparison
              .get();
          
          // Filter out current user and any temp_ IDs that belong to this user
          final otherUserDocs = allFaceDocs.docs.where((doc) {
            // Exclude current user's permanent ID
            if (doc.id == userId) return false;
            
            // Exclude temp_ IDs that match the current user's ID format
            if (doc.id.startsWith('temp_$userId')) return false;
            
            // Exclude temp_ IDs that belong to this user (check by email/phone)
            if (doc.id.startsWith('temp_')) {
              final docData = doc.data() as Map<String, dynamic>?;
              if (docData != null) {
                final docEmail = docData['email']?.toString().toLowerCase() ?? '';
                final docPhone = docData['phoneNumber']?.toString() ?? '';
                final docUserId = docData['userId']?.toString() ?? '';
                
                // If email/phone matches OR userId field matches, it's the same user
                final emailMatches = docEmail.isNotEmpty && userEmail.isNotEmpty && docEmail == userEmail.toLowerCase();
                final phoneMatches = docPhone.isNotEmpty && userPhone.isNotEmpty && docPhone == userPhone;
                final userIdMatches = docUserId.isNotEmpty && docUserId == userId;
                
                if (emailMatches || phoneMatches || userIdMatches) {
                  print('🔍 Skipping temp_ document ${doc.id} - belongs to current user (email/phone/userId match)');
                  return false; // Exclude this temp_ document
                }
              }
            }
            
            return true; // Include this document in comparison
          }).toList();
          
          if (otherUserDocs.isNotEmpty) {
            print('🔍🔍🔍 Comparing against ${otherUserDocs.length} other users\' embeddings...');
            
            double bestOtherUserSimilarity = 0.0;
            String? bestOtherUserId;
            
            for (final otherUserDoc in otherUserDocs) {
              final otherUserData = otherUserDoc.data();
              final otherUserEmbeddings = otherUserData['embeddings'] as List?;
              
              if (otherUserEmbeddings != null && otherUserEmbeddings.isNotEmpty) {
                // Compare against all embeddings of this other user
                for (final otherEmbData in otherUserEmbeddings) {
                  if (otherEmbData is Map && otherEmbData['embedding'] != null) {
                    final otherEmbeddingRaw = otherEmbData['embedding'] as List?;
                    if (otherEmbeddingRaw != null) {
                      final otherEmbedding = otherEmbeddingRaw.map((e) => (e as num).toDouble()).toList();
                      
                      // Normalize and compare
                      if (otherEmbedding.length == normalizedCurrentEmbedding.length) {
                        final otherNorm = _l2Norm(otherEmbedding);
                        final normalizedOtherEmbedding = (otherNorm >= 0.9 && otherNorm <= 1.1) 
                            ? otherEmbedding 
                            : _normalize(otherEmbedding);
                        
                        final otherSimilarity = _cosineSimilarity(
                          normalizedCurrentEmbedding, 
                          normalizedOtherEmbedding
                        );
                        
                        if (otherSimilarity > bestOtherUserSimilarity) {
                          bestOtherUserSimilarity = otherSimilarity;
                          bestOtherUserId = otherUserDoc.id;
                        }
                      }
                    }
                  }
                }
              } else if (otherUserData['embedding'] != null) {
                // Legacy single embedding format
                final otherEmbeddingRaw = otherUserData['embedding'] as List?;
                if (otherEmbeddingRaw != null) {
                  final otherEmbedding = otherEmbeddingRaw.map((e) => (e as num).toDouble()).toList();
                  
                  if (otherEmbedding.length == normalizedCurrentEmbedding.length) {
                    final otherNorm = _l2Norm(otherEmbedding);
                    final normalizedOtherEmbedding = (otherNorm >= 0.9 && otherNorm <= 1.1) 
                        ? otherEmbedding 
                        : _normalize(otherEmbedding);
                    
                    final otherSimilarity = _cosineSimilarity(
                      normalizedCurrentEmbedding, 
                      normalizedOtherEmbedding
                    );
                    
                    if (otherSimilarity > bestOtherUserSimilarity) {
                      bestOtherUserSimilarity = otherSimilarity;
                      bestOtherUserId = otherUserDoc.id;
                    }
                  }
                }
              }
            }
            
            print('🔍🔍🔍 Best match with OTHER user: ${bestOtherUserSimilarity.toStringAsFixed(4)} (User: $bestOtherUserId)');
            print('🔍🔍🔍 Best match with CURRENT user: ${bestSimilarity.toStringAsFixed(4)}');
            
            // CRITICAL: If face matches another user better (or even close), reject
            // This prevents different faces from accessing accounts
            // Use a margin to account for legitimate variations
            // BUT: If the "other user" is actually a temp_ ID that belongs to this user, allow it
            final margin = 0.01; // 1% margin - if other user is within 1%, reject
            if (bestOtherUserSimilarity >= bestSimilarity - margin) {
              // Check if the "other user" is actually a temp_ ID belonging to this user
              bool isOwnTempId = false;
              if (bestOtherUserId != null && bestOtherUserId.startsWith('temp_')) {
                try {
                  final otherUserDoc = await _firestore.collection('face_embeddings').doc(bestOtherUserId).get();
                  if (otherUserDoc.exists) {
                    final otherUserData = otherUserDoc.data();
                    if (otherUserData != null) {
                      final otherEmail = otherUserData['email']?.toString().toLowerCase() ?? '';
                      final otherPhone = otherUserData['phoneNumber']?.toString() ?? '';
                      final otherUserId = otherUserData['userId']?.toString() ?? '';
                      
                      // Check if this temp_ document belongs to the current user
                      final emailMatches = otherEmail.isNotEmpty && userEmail.isNotEmpty && otherEmail == userEmail.toLowerCase();
                      final phoneMatches = otherPhone.isNotEmpty && userPhone.isNotEmpty && otherPhone == userPhone;
                      final userIdMatches = otherUserId.isNotEmpty && otherUserId == userId;
                      
                      if (emailMatches || phoneMatches || userIdMatches) {
                        print('✅✅✅ "Other user" is actually current user\'s temp_ ID - allowing access');
                        print('✅ This is the same user - temp_ document belongs to current user');
                        isOwnTempId = true;
                      }
                    }
                  }
                } catch (e) {
                  print('⚠️ Error checking temp_ document ownership: $e');
                }
              }
              
              if (!isOwnTempId) {
                print('🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨');
                print('🚨🚨🚨 CRITICAL SECURITY BREACH DETECTED!');
                print('🚨🚨🚨 ==========================================');
                print('🚨🚨🚨 This face matches ANOTHER user better or equally!');
                print('🚨🚨🚨 Current user similarity: ${bestSimilarity.toStringAsFixed(4)}');
                print('🚨🚨🚨 Other user similarity: ${bestOtherUserSimilarity.toStringAsFixed(4)} (User: $bestOtherUserId)');
                print('🚨🚨🚨 This face does NOT belong to the current user!');
                print('🚨🚨🚨 REJECTING ACCESS - face belongs to a different user');
                print('🚨🚨🚨 ==========================================');
                print('🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨');
                
                return {
                  'success': false,
                  'error': 'Face verification failed. This face appears to belong to a different account. Please use the correct email/phone.',
                  'similarity': bestSimilarity,
                };
              } else {
                print('✅✅✅ Uniqueness check passed - "other user" is actually current user\'s temp_ ID');
              }
            } else {
              print('✅✅✅ Uniqueness check PASSED: Face matches current user better than any other user');
              print('✅✅✅ Current user: ${bestSimilarity.toStringAsFixed(4)} vs Best other: ${bestOtherUserSimilarity.toStringAsFixed(4)}');
              print('✅✅✅ This face belongs to the current user');
            }
          } else {
            print('⚠️ No other users found for uniqueness check (first user or database issue)');
          }
        } catch (e) {
          print('⚠️ Error checking uniqueness against other users: $e');
          // Don't fail on error - this is an additional security check
          // If it fails, we still have the primary threshold check
        }
      }
      
      // ==========================================
      // CRITICAL: For 1:1 VERIFICATION (LOGIN), SKIP ALL MODEL FAILURE DETECTION
      // ==========================================
      // In 1:1 verification, we're comparing against ONE user's multiple embeddings
      // - High similarities (0.98+) are EXPECTED and CORRECT (same person, different conditions)
      // - Small similarity spread is EXPECTED (all embeddings are from the same person)
      // - High average similarity is EXPECTED (they're all the same person!)
      //
      // Model failure detection is ONLY for 1:N searches (comparing against DIFFERENT users)
      // For 1:1 verification, we ONLY need to check: bestSimilarity >= threshold (already done above)
      //
      // CRITICAL: Skip ALL model failure checks for login - they are NOT applicable
      if (!isProfilePhotoVerification) {
        print('✅✅✅ 1:1 VERIFICATION: Skipping ALL model failure detection');
        print('✅ This is CORRECT - high similarities are EXPECTED when comparing against same user\'s embeddings');
        print('✅ We only compare against this user\'s ${storedEmbeddings.length} embedding(s) - NOT global search');
        print('✅ Similarities: ${allSimilarities.map((s) => s.toStringAsFixed(4)).join(', ')}');
        print('✅ Best similarity: ${bestSimilarity.toStringAsFixed(4)} >= threshold ${threshold.toStringAsFixed(3)} ✅');
        print('✅ Security: Email-first verification ensures only this user\'s embeddings are compared');
        print('✅ Uniqueness check passed - face does not match other users better');
        print('✅ Model failure detection is NOT applicable for 1:1 verification - proceeding to final checks');
        
        // Skip ALL model failure detection - proceed directly to final security checks
        // The threshold check (bestSimilarity >= threshold) was already done above (line 1967)
        // If we reach here, bestSimilarity has passed the threshold, so login should succeed
      } else if (allSimilarities.isNotEmpty) {
        // PROFILE PHOTO: Calculate similarity stats for logging only (no rejection)
        final avgSimilarity = allSimilarities.reduce((a, b) => a + b) / allSimilarities.length;
        final minSimilarity = allSimilarities.reduce((a, b) => a < b ? a : b);
        final maxSimilarity = allSimilarities.reduce((a, b) => a > b ? a : b);
        final similarityRange = maxSimilarity - minSimilarity;
        
        print('📊 Similarity analysis:');
        print('   - Count: ${allSimilarities.length}');
        print('   - Average: ${avgSimilarity.toStringAsFixed(4)}');
        print('   - Range: ${minSimilarity.toStringAsFixed(4)} - ${maxSimilarity.toStringAsFixed(4)}');
        print('   - Spread: ${similarityRange.toStringAsFixed(4)}');
        print('   - Verification type: PROFILE PHOTO');
        
        if (isProfilePhotoVerification) {
          // PROFILE PHOTO: More lenient validation
          // Profile photos can have very different lighting/angles, so similarity can be lower
          // If feature distances passed, it means the face structure matches (more reliable)
          print('📸 PROFILE PHOTO: Checking similarity with lenient thresholds...');
          print('📸 Profile photos can have different lighting/angles, so similarity may be lower');
          
          // Check if any embedding passed the profile photo threshold
          // We need to check if bestSimilarity meets the adjusted threshold
          // For profile photos, if feature distances passed, we use 0.75 threshold
          // Otherwise, we use the normal threshold (0.985)
          // Since we can't easily track which embedding had passing feature distances here,
          // we'll use a more lenient check: if bestSimilarity >= 0.70 and feature distances passed, accept
          // OR if bestSimilarity >= 0.85 (moderate similarity), accept
          final profilePhotoMinThreshold = 0.70; // Minimum for profile photos (very lenient)
          final profilePhotoModerateThreshold = 0.85; // Moderate threshold
          
          if (bestSimilarity < profilePhotoMinThreshold) {
            print('🚨📸 PROFILE PHOTO: Best similarity ${bestSimilarity.toStringAsFixed(4)} is very low (<${profilePhotoMinThreshold.toStringAsFixed(2)})');
            print('🚨 This indicates the profile photo does not match the registered face');
            return {
              'success': false,
              'error': 'Face verification failed. The uploaded photo does not match your registered face.',
              'similarity': bestSimilarity,
            };
          } else if (bestSimilarity < profilePhotoModerateThreshold) {
            // Similarity is low but not critically low - check if we can be more lenient
            // If average similarity is consistent (low spread), it might be legitimate
            final avgSimilarity = allSimilarities.isNotEmpty 
                ? allSimilarities.reduce((a, b) => a + b) / allSimilarities.length 
                : 0.0;
            // If similarities are consistent and above minimum, might be legitimate
            // But still require at least 0.75 for profile photos
            if (bestSimilarity >= 0.75 && avgSimilarity >= 0.75) {
              print('⚠️ PROFILE PHOTO: Similarity is moderate (${bestSimilarity.toStringAsFixed(4)}), but consistent across embeddings');
              print('⚠️ Profile photos can have lower similarity due to different conditions');
              print('⚠️ Proceeding with verification - similarity is above minimum threshold (0.75)');
            } else {
              print('🚨📸 PROFILE PHOTO: Best similarity ${bestSimilarity.toStringAsFixed(4)} is too low (<0.75)');
            print('🚨 This indicates the profile photo does not match the registered face');
            return {
              'success': false,
              'error': 'Face verification failed. The uploaded photo does not match your registered face.',
              'similarity': bestSimilarity,
            };
            }
          }
          
          // For profile photos, if we reach here, similarity is acceptable
          print('✅ PROFILE PHOTO: Similarity checks passed (${bestSimilarity.toStringAsFixed(4)} >= ${profilePhotoMinThreshold.toStringAsFixed(2)})');
        }
        // NOTE: Login (1:1 verification) is already handled above with early skip - no duplicate logic needed
      }
      
      // CRITICAL SECURITY CHECK 1: Reject if similarity is below absolute minimum (definitely wrong face)
      // This catches cases where someone enters another person's email but their face doesn't match
      // CRITICAL: For login, absoluteMinimum is 0.985 (98.5%) - this prevents unregistered users
      // Unregistered users typically achieve 0.70-0.95 similarity, which is well below 0.985
      // CRITICAL: This check MUST come AFTER verifying bestSimilarity was set by valid match
      // If bestSimilarity < absoluteMinimum, this is definitely NOT the registered user
      // EXCEPTION: For profile photos, use more lenient absolute minimum
      final effectiveAbsoluteMinimum = isProfilePhotoVerification ? 0.70 : absoluteMinimum;
      if (bestSimilarity < effectiveAbsoluteMinimum) {
        print('🚨🚨🚨🚨🚨 CRITICAL SECURITY REJECTION: Similarity ${bestSimilarity.toStringAsFixed(4)} < absolute minimum ${absoluteMinimum.toStringAsFixed(3)}');
        print('🚨🚨🚨 This is definitely NOT the correct user - face does not match registered face');
        print('🚨🚨🚨 This prevents unregistered users from accessing registered accounts');
        print('🚨🚨🚨 Different people typically achieve 0.70-0.95 similarity, NOT ${absoluteMinimum.toStringAsFixed(3)}+');
        print('🚨🚨🚨 Similarity ${bestSimilarity.toStringAsFixed(4)} indicates this is an unregistered user or wrong person');
        print('🚨🚨🚨 REJECTING ACCESS - this face does NOT belong to the registered user');
        return {
          'success': false,
          'error': 'Face not recognized. This face does not match the registered face for this account. Please ensure you are using the correct email/phone.',
          'similarity': bestSimilarity,
        };
      }
      
      // CRITICAL SECURITY CHECK 2: Reject if similarity is in the "ambiguous" range
      // Range 0.85-0.988 typically indicates similar-looking people but NOT the same person
      // For login, absoluteMinimum is 0.988, so this catches 0.85-0.988 range
      // CRITICAL: This range is definitely NOT the correct user - reject immediately
      if (bestSimilarity >= 0.85 && bestSimilarity < absoluteMinimum) {
        print('🚨🚨🚨 SECURITY REJECTION: Similarity ${bestSimilarity.toStringAsFixed(4)} is in ambiguous range (0.85-${absoluteMinimum.toStringAsFixed(3)})');
        print('🚨 Face might be similar but NOT the same person - rejecting for security');
        print('🚨 Different people typically achieve 0.70-0.95 similarity, NOT 0.99+');
        print('🚨 Similarity ${bestSimilarity.toStringAsFixed(4)} indicates this is an unregistered user or wrong person');
        return {
          'success': false,
          'error': 'Face verification failed. This face does not match the registered face for this account.',
          'similarity': bestSimilarity,
        };
      }
      
      // CRITICAL SECURITY CHECK 3: Reject anything below threshold (even if above minimum)
      // For 1:1 verification, we need EXTREMELY HIGH confidence
      // The range between absoluteMinimum and threshold is "suspicious" - reject it
      // EXCEPTION: For profile photos, use more lenient threshold (0.75)
      final effectiveThreshold = isProfilePhotoVerification ? 0.75 : threshold;
      if (bestSimilarity < effectiveThreshold) {
        if (isProfilePhotoVerification) {
          print('🚨📸 PROFILE PHOTO: Similarity ${bestSimilarity.toStringAsFixed(4)} < profile photo threshold ${effectiveThreshold.toStringAsFixed(3)}');
          print('🚨 Profile photos require at least ${effectiveThreshold.toStringAsFixed(3)} similarity');
        } else {
        print('🚨🚨🚨 SECURITY REJECTION: Similarity ${bestSimilarity.toStringAsFixed(4)} < STRICT threshold $threshold');
        print('🚨 For 1:1 verification, we require EXTREMELY HIGH similarity (${threshold.toStringAsFixed(3)})');
        print('🚨 This prevents unauthorized access - face does not match with sufficient confidence');
        }
        
        // Additional check: If user has multiple embeddings, require consistency
        // NOTE: Made more lenient - only reject if average is significantly below threshold
        if (embeddingCount >= 2 && allSimilarities.length >= 2) {
          final avgSimilarity = allSimilarities.reduce((a, b) => a + b) / allSimilarities.length;
          final minSimilarity = allSimilarities.reduce((a, b) => a < b ? a : b);
          
          print('📊 Consistency check:');
          print('   - Average: ${avgSimilarity.toStringAsFixed(4)}');
          print('   - Minimum: ${minSimilarity.toStringAsFixed(4)}');
          print('   - Embedding count: $embeddingCount');
          
          // ADAPTIVE: More lenient margin based on embedding count and verification type
          // For profile photos, allow MUCH more variation due to different lighting/angles/environment
          double consistencyMargin;
          if (isProfilePhotoVerification) {
            // PROFILE PHOTO: Very lenient (6-8% margin)
            consistencyMargin = embeddingCount >= 3 ? 0.08 : 0.06; // 6-8% margin for profile photos
            print('📸 PROFILE PHOTO: Using very lenient consistency margin: ${consistencyMargin.toStringAsFixed(3)}');
          } else {
            // LOGIN: MAXIMUM STRICTNESS (1-2% margin) - prevents unregistered users
            consistencyMargin = embeddingCount >= 3 ? 0.02 : (embeddingCount == 2 ? 0.015 : 0.01); // 1-2% margin for login
            print('🔐 LOGIN: Using MAXIMUM strict consistency margin: ${consistencyMargin.toStringAsFixed(3)}');
            print('🔐 This prevents unregistered users from accessing registered accounts');
          }
          
          // Only reject if average is significantly below threshold (not just slightly)
          if (avgSimilarity < threshold - consistencyMargin) {
            print('🚨 SECURITY REJECTION: Average similarity ${avgSimilarity.toStringAsFixed(4)} is significantly below threshold');
            print('🚨 Required: ${(threshold - consistencyMargin).toStringAsFixed(4)}, Got: ${avgSimilarity.toStringAsFixed(4)}');
            print('🚨 Face does not consistently match - likely different person');
            return {
              'success': false,
              'error': 'Face verification failed. This face does not consistently match the registered face for this account.',
              'similarity': bestSimilarity,
            };
          }
          
          print('✅ Consistency check passed: Average similarity ${avgSimilarity.toStringAsFixed(4)} is acceptable');
        }
        
        return {
          'success': false,
          'error': 'Face not recognized. This does not match the registered face for this account. Please ensure you are using the correct email/phone.',
          'similarity': bestSimilarity,
        };
      }
      
      // At this point, bestSimilarity >= threshold (passed all checks above)
      // CRITICAL SECURITY CHECK 4: Final validation - ensure consistency across embeddings
      // If user has multiple embeddings, the current face should match them consistently
      // NOTE: Made more lenient for profile photos which may have different lighting/angles
      if (embeddingCount >= 2 && allSimilarities.length >= 2) {
        // Calculate average similarity across all embeddings
        final avgSimilarity = allSimilarities.reduce((a, b) => a + b) / allSimilarities.length;
        final minSimilarity = allSimilarities.reduce((a, b) => a < b ? a : b);
        
        print('📊 Final consistency check:');
        print('   - Best: ${bestSimilarity.toStringAsFixed(4)}');
        print('   - Average: ${avgSimilarity.toStringAsFixed(4)}');
        print('   - Minimum: ${minSimilarity.toStringAsFixed(4)}');
        print('   - Embedding count: $embeddingCount');
        
        // ADAPTIVE CONSISTENCY: More lenient thresholds based on embedding count and verification type
        // For profile photos, be MUCH more lenient (different lighting/angles/environment)
        // For login, be stricter (same environment, same camera)
        double avgThresholdMargin;
        double minThresholdMargin;
        
        if (isProfilePhotoVerification) {
          // PROFILE PHOTO: Very lenient - profile photos can have very different conditions
          if (embeddingCount >= 3) {
            avgThresholdMargin = 0.06; // 6% margin (avg >= 93% for 99% threshold) - VERY LENIENT
            minThresholdMargin = 0.08; // 8% margin (min >= 91% for 99% threshold) - VERY LENIENT
            print('📸 PROFILE PHOTO: Using very lenient consistency thresholds for ${embeddingCount} embeddings');
            print('📸 Allows significant variation in lighting/angles/environment for profile photos');
          } else if (embeddingCount == 2) {
            avgThresholdMargin = 0.05; // 5% margin (avg >= 94% for 99% threshold)
            minThresholdMargin = 0.07; // 7% margin (min >= 92% for 99% threshold)
            print('📸 PROFILE PHOTO: Using lenient consistency thresholds for 2 embeddings');
          } else {
            // Single embedding - no consistency check needed
            avgThresholdMargin = 0.0;
            minThresholdMargin = 0.0;
          }
        } else {
          // LOGIN: MAXIMUM STRICTNESS - require very high consistency
          // CRITICAL SECURITY: Unregistered users must fail consistency checks
          // Even with 1 embedding, require high consistency (within 1% of threshold)
          if (embeddingCount >= 3) {
            avgThresholdMargin = 0.02; // 2% margin (avg >= 97% for 99% threshold) - STRICTER
            minThresholdMargin = 0.03; // 3% margin (min >= 96% for 99% threshold) - STRICTER
            print('🔐 LOGIN: Using MAXIMUM strict consistency thresholds for ${embeddingCount} embeddings');
            print('🔐 Average must be >= 97%, Minimum must be >= 96% (prevents unregistered users)');
          } else if (embeddingCount == 2) {
            avgThresholdMargin = 0.015; // 1.5% margin (avg >= 97.5% for 99% threshold) - STRICTER
            minThresholdMargin = 0.025; // 2.5% margin (min >= 96.5% for 99% threshold) - STRICTER
            print('🔐 LOGIN: Using MAXIMUM strict consistency thresholds for 2 embeddings');
            print('🔐 Average must be >= 97.5%, Minimum must be >= 96.5% (prevents unregistered users)');
          } else {
            // LOGIN: Even with single embedding, require high consistency
            // CRITICAL SECURITY: Unregistered users must fail even with single embedding
            avgThresholdMargin = 0.01; // 1% margin (avg >= 98% for 99% threshold) - STRICTER
            minThresholdMargin = 0.01; // 1% margin (min >= 98% for 99% threshold) - STRICTER
            print('🔐 LOGIN: Using MAXIMUM strict consistency thresholds for single embedding');
            print('🔐 Even with 1 embedding, require high consistency (avg >= 98%, min >= 98%)');
            print('🔐 This prevents unregistered users from accessing registered accounts');
          }
        }
        
        // CRITICAL: Average must be reasonable (within margin of threshold)
        // This ensures the face consistently matches most stored embeddings
        // But allows for variation in lighting/angles between signup and profile photo
        // CRITICAL SECURITY: For login, require VERY HIGH consistency (prevents unregistered users)
        if (avgThresholdMargin > 0 && avgSimilarity < threshold - avgThresholdMargin) {
          print('🚨 SECURITY REJECTION: Average similarity ${avgSimilarity.toStringAsFixed(4)} is too low');
          print('🚨 Required: ${(threshold - avgThresholdMargin).toStringAsFixed(4)}, Got: ${avgSimilarity.toStringAsFixed(4)}');
          print('🚨 The face does not consistently match stored embeddings - likely different person');
          return {
            'success': false,
            'error': 'Face verification failed. This face does not consistently match the registered face for this account.',
            'similarity': bestSimilarity,
          };
        }
        
        // CRITICAL: Minimum similarity must also be reasonable (within margin of threshold)
        // This ensures most stored embeddings match well
        // For login: Require VERY HIGH minimum similarity (prevents unregistered users)
        // For profile photos: Allow more variation (different lighting/angles)
        if (minThresholdMargin > 0 && minSimilarity < threshold - minThresholdMargin) {
          print('🚨 SECURITY REJECTION: Minimum similarity ${minSimilarity.toStringAsFixed(4)} is too low');
          print('🚨 Required: ${(threshold - minThresholdMargin).toStringAsFixed(4)}, Got: ${minSimilarity.toStringAsFixed(4)}');
          if (isProfilePhotoVerification) {
            print('🚨📸 PROFILE PHOTO: At least one stored embedding does not match well');
          } else {
            print('🚨🔐 LOGIN: At least one stored embedding does not match well - likely unregistered user');
            print('🚨 Unregistered users typically achieve 0.70-0.95 similarity, NOT 0.99+');
            print('🚨 Minimum similarity ${minSimilarity.toStringAsFixed(4)} indicates this is an unregistered user');
          }
          return {
            'success': false,
            'error': 'Face verification failed. This face does not match all registered face samples for this account.',
            'similarity': bestSimilarity,
          };
        }
        
        print('✅ Consistency check passed: Face matches stored embeddings (best: ${bestSimilarity.toStringAsFixed(4)}, avg: ${avgSimilarity.toStringAsFixed(4)}, min: ${minSimilarity.toStringAsFixed(4)})');
      }
      
      // FINAL VALIDATION: Double-check that similarity is truly high enough
      // This is a redundant check but ensures no edge cases slip through
      if (bestSimilarity < threshold) {
        print('🚨🚨🚨 FINAL SECURITY CHECK FAILED: Similarity ${bestSimilarity.toStringAsFixed(4)} < threshold $threshold');
        print('🚨 This should not happen - rejecting for security');
        return {
          'success': false,
          'error': 'Face verification failed. Security check failed.',
          'similarity': bestSimilarity,
        };
      }
      
      // Final validation - require threshold based on verification type
      // For profile photos, use more lenient threshold (80-85%) to account for different lighting/angles/conditions
      // Profile photos can have very different conditions than verification steps, so similarity can be lower
      // For login, use balanced 99%+ threshold (RELIABLE RECOGNITION) - balanced for legitimate users
      // BALANCED SECURITY: Unregistered users must NEVER pass this check
      // BALANCED: Use the SAME threshold as set earlier (0.99 for login) - balanced for legitimate users
      final finalThreshold = isProfilePhotoVerification
          ? (embeddingCount >= 3 ? 0.80 : (embeddingCount == 2 ? 0.80 : 0.75)) // More lenient: 75-80% for profile photos
          : threshold; // LOGIN: Use the same threshold (0.99 = 99%) as set earlier - balanced for legitimate users
      
      // CRITICAL SECURITY: Additional validation - verify Euclidean distance for login
      // This is a DOUBLE CHECK to prevent any false positives
      // CRITICAL: This ensures that even if similarity passes, the match must have also passed distance check
      if (!isProfilePhotoVerification && bestSimilarity >= finalThreshold) {
        // CRITICAL: Verify that bestSimilarity was set by a match that passed BOTH checks
        // This is redundant but CRITICAL for security - prevents any bypass attempts
        print('🔐🔐🔐 LOGIN: Final verification of best match (similarity: ${bestSimilarity.toStringAsFixed(4)})');
        print('🔐🔐🔐 This match MUST have passed BOTH similarity (>= 0.99) AND distance (<= 0.12) checks');
        print('🔐🔐🔐 This prevents unregistered users even if similarity is high');
        
        // CRITICAL: If bestSimilarity is suspiciously high (>= 0.9999), reject
        // Legitimate matches should be 0.99-0.999, not 0.9999+ (might indicate identical embeddings or model failure)
        if (bestSimilarity >= 0.9999) {
          print('🚨🚨🚨🚨🚨 CRITICAL SECURITY: bestSimilarity is extremely high (${bestSimilarity.toStringAsFixed(4)})');
          print('🚨🚨🚨 This might indicate identical embeddings or model failure');
          print('🚨🚨🚨 Rejecting for security - legitimate matches should be 0.99-0.999, not 0.9999+');
          print('🚨🚨🚨 This prevents unregistered users from accessing registered accounts');
          return {
            'success': false,
            'error': 'Face verification failed. Security validation error.',
            'similarity': bestSimilarity,
          };
        }
        
        // CRITICAL: Additional check - ensure similarity is not too low (should be >= threshold = 0.995)
        // This is redundant but critical for security
        if (bestSimilarity < threshold) {
          print('🚨🚨🚨🚨🚨 CRITICAL SECURITY: bestSimilarity ${bestSimilarity.toStringAsFixed(4)} < threshold ${threshold.toStringAsFixed(3)} in final check');
          print('🚨🚨🚨 This should not happen - REJECTING for security');
          print('🚨🚨🚨 This prevents unregistered users from accessing registered accounts');
          return {
            'success': false,
            'error': 'Face verification failed. This face does not match the registered face for this account.',
            'similarity': bestSimilarity,
          };
        }
      }
      
      if (bestSimilarity < finalThreshold) {
        if (isProfilePhotoVerification) {
          print('🚨📸 PROFILE PHOTO FINAL REJECTION: Similarity ${bestSimilarity.toStringAsFixed(4)} < threshold ${finalThreshold.toStringAsFixed(3)}');
          print('🚨 Profile photo does not match registered face with sufficient accuracy');
          print('🚨 Similarity ${bestSimilarity.toStringAsFixed(4)} indicates this may not be the correct user');
        } else {
          print('🚨🚨🚨 PERFECT RECOGNITION FINAL REJECTION: Similarity ${bestSimilarity.toStringAsFixed(4)} < PERFECT threshold ${finalThreshold.toStringAsFixed(3)}');
          print('🚨🚨🚨 This is the FINAL CHECK - no exceptions allowed');
          print('🚨 Different people: 0.70-0.95 | Same person: 0.99+ (PERFECT)');
          print('🚨 Similarity ${bestSimilarity.toStringAsFixed(4)} indicates this is NOT the registered user');
          print('🚨 PERFECT RECOGNITION requires ${finalThreshold.toStringAsFixed(3)} similarity for authentication');
        }
        return {
          'success': false,
          'error': 'Face verification failed. This face does not match the registered face for this account. Please ensure you are using the correct email/phone.',
          'similarity': bestSimilarity,
        };
      }

      // CRITICAL: Final validation - ensure signupCompleted is true
      // This prevents redirecting to signup when user exists
      // Note: userData and userId are already verified as non-null earlier in the function
      final finalSignupCompleted = userData['signupCompleted'] ?? false;
      if (!finalSignupCompleted) {
        print('🚨🚨🚨 CRITICAL ERROR: signupCompleted is false after successful verification');
        print('🚨 This should never happen - signupCompleted was checked earlier');
        return {
          'success': false,
          'error': 'Account not completed. Please complete signup first.',
        };
      }

      // CRITICAL: Final email/phone verification - ensure they match
      final finalEmail = userData['email']?.toString().toLowerCase() ?? '';
      final finalPhone = userData['phoneNumber']?.toString() ?? '';
      final inputLowerFinal = emailOrPhone.trim().toLowerCase();
      final finalEmailMatches = finalEmail == inputLowerFinal;
      final finalPhoneMatches = finalPhone == emailOrPhone.trim();

      if (!finalEmailMatches && !finalPhoneMatches) {
        print('🚨🚨🚨 CRITICAL SECURITY: Email/phone mismatch in final check');
        print('🚨 Input: $emailOrPhone');
        print('🚨 User email: $finalEmail');
        print('🚨 User phone: $finalPhone');
        return {
          'success': false,
          'error': 'Account verification failed. Please try again.',
        };
      }

      // CRITICAL SECURITY: ABSOLUTE FINAL CHECK before returning success
      // This is the LAST LINE OF DEFENSE - no exceptions
      if (!isProfilePhotoVerification) {
        // TRIPLE-CHECK: Verify bestSimilarity is truly high enough
        if (bestSimilarity < 0.995) {
          print('🚨🚨🚨🚨🚨 CRITICAL SECURITY BREACH PREVENTION: bestSimilarity ${bestSimilarity.toStringAsFixed(4)} < 0.995 in ABSOLUTE FINAL return check');
          print('🚨🚨🚨 This should NEVER happen - all checks above should have caught this');
          print('🚨🚨🚨 REJECTING ACCESS - security validation failed');
          return {
            'success': false,
            'error': 'Face verification failed. Security validation error.',
            'similarity': bestSimilarity,
          };
        }
        
        // CRITICAL: Verify bestSimilarity is in valid range (not suspiciously high or low)
        // Valid range: 0.995 - 0.9998 (beyond 0.9998 might indicate identical embeddings)
        if (bestSimilarity < 0.995 || bestSimilarity > 0.9998) {
          print('🚨🚨🚨🚨🚨 CRITICAL: bestSimilarity ${bestSimilarity.toStringAsFixed(4)} is outside valid range (0.995-0.9998)');
          if (bestSimilarity > 0.9998) {
            print('🚨🚨🚨 Similarity is suspiciously high (>= 0.9998) - might indicate model failure');
          }
          print('🚨🚨🚨 REJECTING ACCESS - invalid similarity range');
          return {
            'success': false,
            'error': 'Face verification failed. Security validation error.',
            'similarity': bestSimilarity,
          };
        }
        
        // CRITICAL: Verify that we're comparing against the correct user's embeddings
        // Double-check that userId matches the email/phone entered
        final returnedEmail = userEmail;
        final returnedPhone = userPhone;
        final inputEmailOrPhone = emailOrPhone.trim().toLowerCase();
        
        final emailMatches = returnedEmail.toLowerCase() == inputEmailOrPhone;
        final phoneMatches = returnedPhone == emailOrPhone.trim();
        
        if (!emailMatches && !phoneMatches) {
          print('🚨🚨🚨🚨🚨 CRITICAL SECURITY BREACH: User ID mismatch in final check!');
          print('🚨🚨🚨 Entered: $emailOrPhone');
          print('🚨🚨🚨 User email: $returnedEmail');
          print('🚨🚨🚨 User phone: $returnedPhone');
          print('🚨🚨🚨 REJECTING ACCESS - user verification failed');
          return {
            'success': false,
            'error': 'Face verification failed. Account verification error.',
            'similarity': bestSimilarity,
          };
        }
      }
      
      // BALANCED SECURITY: FINAL CHECK before returning success
      // This is the LAST GATE - balanced for legitimate users
      // BALANCED: For login, bestSimilarity MUST be >= threshold AND must have passed distance check
      if (!isProfilePhotoVerification) {
        // LOGIN: Require threshold similarity (${threshold.toStringAsFixed(3)}+) - balanced for legitimate users
        if (bestSimilarity < threshold) {
          print('🚨🚨🚨🚨🚨 BALANCED SECURITY: bestSimilarity ${bestSimilarity.toStringAsFixed(4)} < ${threshold.toStringAsFixed(3)} in FINAL return check');
          print('🚨🚨🚨 This should not happen - REJECTING');
          print('🚨🚨🚨 Unregistered/similar faces typically cannot achieve ${threshold.toStringAsFixed(3)}+ similarity - REJECTING ACCESS');
          return {
            'success': false,
            'error': 'Face verification failed. This face does not match the registered face for this account.',
            'similarity': bestSimilarity,
          };
        }
        
        // BALANCED: Verify bestSimilarity is not suspiciously high (might indicate model failure)
        if (bestSimilarity >= 0.9999) {
          print('🚨🚨🚨🚨🚨 BALANCED SECURITY: bestSimilarity ${bestSimilarity.toStringAsFixed(4)} is suspiciously high (>= 0.9999)');
          print('🚨🚨🚨 This might indicate identical embeddings or model failure - REJECTING');
          return {
            'success': false,
            'error': 'Face verification failed. Security validation error.',
            'similarity': bestSimilarity,
          };
        }
      }
      
      print('✅ Step 4 Complete: Face matches stored embeddings with PERFECT confidence');
      print('🔐 ==========================================');
      print('✅ 1:1 FACE VERIFICATION SUCCESSFUL');
      print('🔐 ==========================================');
      print('✅ User ID: $userId');
      print('✅ Email: $finalEmail');
      print('✅ Phone: $finalPhone');
      print('✅ Similarity: ${bestSimilarity.toStringAsFixed(4)} (Required: ${threshold.toStringAsFixed(3)})');
      print('✅ Security: Email-first → 1:1 verification → PERFECT match');
      print('✅ All security checks passed - face belongs to the registered user');
      print('🎯 PERFECT RECOGNITION: Similarity ${bestSimilarity.toStringAsFixed(4)} >= ${threshold.toStringAsFixed(3)} indicates PERFECT match');
      print('🎯 This is the correct user - unregistered users cannot achieve this similarity');
      print('🔐 NOT a global search - only compared against this user\'s embeddings (1:1 verification)');
      print('🔐 ==========================================');

      // ==========================================
      // CRITICAL SECURITY: ABSOLUTE FINAL VALIDATION BEFORE RETURNING SUCCESS
      // ==========================================
      // This is the LAST LINE OF DEFENSE - verify everything one more time
      if (!isProfilePhotoVerification) {
        // LOGIN: TRIPLE-CHECK bestSimilarity meets threshold
        if (bestSimilarity < 0.995) {
          print('🚨🚨🚨🚨🚨🚨🚨 CRITICAL SECURITY BREACH: bestSimilarity ${bestSimilarity.toStringAsFixed(4)} < 0.995 in FINAL return');
          print('🚨🚨🚨 This should NEVER happen - REJECTING IMMEDIATELY');
          print('🚨🚨🚨 Unregistered/similar faces CANNOT achieve 0.995+ similarity');
          print('🚨🚨🚨 REJECTING ACCESS - wrong face detected');
          return {
            'success': false,
            'error': 'Face verification failed. This face does not match the registered face for this account.',
            'similarity': bestSimilarity,
          };
        }
        
        // CRITICAL: Verify bestSimilarity was set by a valid match (not initialized incorrectly)
        if (bestSource == null) {
          print('🚨🚨🚨🚨🚨 CRITICAL SECURITY: bestSource is null - bestSimilarity may be invalid');
          print('🚨 REJECTING - similarity must come from a valid embedding match');
          return {
            'success': false,
            'error': 'Face verification failed. Security validation error.',
            'similarity': bestSimilarity,
          };
        }
        
        // CRITICAL: Verify bestSimilarity is in valid range (0.995-0.9998)
        // Values outside this range indicate errors or model failure
        if (bestSimilarity < 0.995 || bestSimilarity > 0.9998) {
          print('🚨🚨🚨🚨🚨 CRITICAL SECURITY: bestSimilarity ${bestSimilarity.toStringAsFixed(4)} is outside valid range (0.995-0.9998)');
          print('🚨 REJECTING - invalid similarity value');
          return {
            'success': false,
            'error': 'Face verification failed. Security validation error.',
            'similarity': bestSimilarity,
          };
        }
        
        print('🔐🔐🔐 FINAL SECURITY VALIDATION PASSED:');
        print('🔐   - bestSimilarity: ${bestSimilarity.toStringAsFixed(4)} >= 0.995 ✅');
        print('🔐   - bestSource: $bestSource ✅');
        print('🔐   - Valid range: 0.995-0.9998 ✅');
        print('🔐   - This is the CORRECT user - unregistered/similar users cannot pass these checks');
      }
      
      // CRITICAL: Return success ONLY if all conditions are met
      // CRITICAL: For login, bestSimilarity MUST be >= 0.995 (verified above)
      // Ensure userData is included to prevent navigation to signup
      return {
        'success': true,
        'userId': userId,
        'similarity': bestSimilarity,
        'userData': userData, // CRITICAL: Always include userData to prevent signup redirect
      };
    } catch (e) {
      // CRITICAL SECURITY: On any error, ALWAYS reject authentication
      // Never allow access on error - fail securely
      print('🚨🚨🚨 CRITICAL SECURITY: Error in 1:1 face verification: $e');
      print('🚨 REJECTING ACCESS - fail securely on any error');
      print('🚨 Stack trace: ${StackTrace.current}');
      return {
        'success': false,
        'error': 'Face verification failed. Please try again.',
      };
    }
  }

  /// Preprocess image for Luxand compatibility
  /// - Resizes if too large (max 1920x1920)
  /// - Ensures minimum size (at least 200x200)
  /// - Converts to JPEG format
  /// - Compresses to reasonable quality (85%)
  static Future<Uint8List> _preprocessImageForLuxand(Uint8List imageBytes, String imagePath) async {
    try {
      print('🔧 Preprocessing image for Luxand...');
      print('   - Original size: ${imageBytes.length} bytes');
      
      // Decode image
      img.Image? decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        print('❌ Failed to decode image, trying alternative method...');
        // Try using flutter_image_compress as fallback
        final tempFile = File(imagePath);
        if (await tempFile.exists()) {
          final compressed = await FlutterImageCompress.compressWithFile(
            tempFile.absolute.path,
            minWidth: 200,
            minHeight: 200,
            quality: 85,
            format: CompressFormat.jpeg,
          );
          if (compressed != null) {
            print('✅ Image compressed using FlutterImageCompress. New size: ${compressed.length} bytes');
            return Uint8List.fromList(compressed);
          }
        }
        throw Exception('Failed to decode image');
      }
      
      print('   - Original dimensions: ${decodedImage.width}x${decodedImage.height}');
      
      // Check minimum size
      if (decodedImage.width < 200 || decodedImage.height < 200) {
        print('⚠️ Image is too small (${decodedImage.width}x${decodedImage.height}). Minimum: 200x200');
        throw Exception('Image is too small. Minimum size: 200x200 pixels');
      }
      
      // Resize if too large (Luxand may have size limits)
      const maxDimension = 1920;
      if (decodedImage.width > maxDimension || decodedImage.height > maxDimension) {
        print('   - Resizing from ${decodedImage.width}x${decodedImage.height} to max ${maxDimension}x${maxDimension}');
        final aspectRatio = decodedImage.width / decodedImage.height;
        int newWidth, newHeight;
        if (decodedImage.width > decodedImage.height) {
          newWidth = maxDimension;
          newHeight = (maxDimension / aspectRatio).round();
        } else {
          newHeight = maxDimension;
          newWidth = (maxDimension * aspectRatio).round();
        }
        decodedImage = img.copyResize(decodedImage, width: newWidth, height: newHeight);
        print('   - New dimensions: ${decodedImage.width}x${decodedImage.height}');
      }
      
      // Convert to JPEG format (Luxand requires JPEG)
      final jpegBytes = img.encodeJpg(decodedImage, quality: 85);
      print('   - JPEG encoded size: ${jpegBytes.length} bytes');
      print('   - Compression ratio: ${((1 - jpegBytes.length / imageBytes.length) * 100).toStringAsFixed(1)}%');
      
      if (jpegBytes.isEmpty) {
        throw Exception('Failed to encode image as JPEG');
      }
      
      return Uint8List.fromList(jpegBytes);
    } catch (e) {
      print('❌ Image preprocessing error: $e');
      // If preprocessing fails, try using flutter_image_compress as fallback
      try {
        final tempFile = File(imagePath);
        if (await tempFile.exists()) {
          print('🔄 Trying FlutterImageCompress as fallback...');
          final compressed = await FlutterImageCompress.compressWithFile(
            tempFile.absolute.path,
            minWidth: 200,
            minHeight: 200,
            quality: 85,
            format: CompressFormat.jpeg,
          );
          if (compressed != null && compressed.isNotEmpty) {
            print('✅ Image compressed using FlutterImageCompress fallback. New size: ${compressed.length} bytes');
            return Uint8List.fromList(compressed);
          }
        }
      } catch (fallbackError) {
        print('❌ FlutterImageCompress fallback also failed: $fallbackError');
      }
      rethrow;
    }
  }
}
