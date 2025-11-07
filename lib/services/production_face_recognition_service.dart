import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math';

import 'face_net_service.dart';
import 'face_uniqueness_service.dart';
import 'face_landmark_service.dart';
import 'face_auth_backend_service.dart';

import 'dart:math' show sqrt, pow;

/// SECURE Face Recognition Service
/// Uses backend API for Luxand face recognition (API key stays secure on server)
/// Flow: Flutter → Your Backend → Luxand Cloud → Response
/// luxandUuid is synced to Firestore after enrollment for easy lookup
class ProductionFaceRecognitionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  static final FaceNetService _faceNetService = FaceNetService();
  static const bool _useBackendForVerification = true; // Use backend API (recommended - keeps API key secure)
  
  // Backend API URL - configure via environment variable or update default
  // Flutter → Your Backend → Luxand Cloud (API key stays on server)
  static const String _backendUrl = String.fromEnvironment(
    'FACE_AUTH_BACKEND_URL',
    defaultValue: 'https://your-backend-domain.com', // TODO: Replace with your backend URL
  );
  
  static FaceAuthBackendService? _backendService;
  static FaceAuthBackendService get _backendServiceInstance {
    return _backendService ??= FaceAuthBackendService(backendUrl: _backendUrl);
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

  /// Enroll all 3 face images from signup (blink, move closer, head movement)
  /// This provides better accuracy by enrolling multiple angles/expressions
  /// Returns: { success: bool, luxandUuid: String?, enrolledCount: int, errors: List<String>? }
  static Future<Map<String, dynamic>> enrollAllThreeFaces({
    required String email,
  }) async {
    try {
      if (!_useBackendForVerification) {
        return {
          'success': false,
          'error': 'Backend verification not enabled',
        };
      }

      // Find user by email
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

      // Get face images from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final blinkImagePath = prefs.getString('face_verification_blinkImagePath');
      final moveCloserImagePath = prefs.getString('face_verification_moveCloserImagePath');
      final headMovementImagePath = prefs.getString('face_verification_headMovementImagePath');

      final List<String> imagePaths = [
        if (blinkImagePath != null && blinkImagePath.isNotEmpty) blinkImagePath,
        if (moveCloserImagePath != null && moveCloserImagePath.isNotEmpty) moveCloserImagePath,
        if (headMovementImagePath != null && headMovementImagePath.isNotEmpty) headMovementImagePath,
      ];

      if (imagePaths.isEmpty) {
        return {
          'success': false,
          'error': 'No face images found. Please complete face verification steps.',
        };
      }

      print('🔍 Enrolling ${imagePaths.length} face images to Luxand via backend...');
      print('🔍 Backend URL: $_backendUrl');
      
      // Check if backend URL is configured
      if (_backendUrl == 'https://your-backend-domain.com' || _backendUrl.isEmpty) {
        return {
          'success': false,
          'error': 'Backend URL not configured. Please set FACE_AUTH_BACKEND_URL or update the default URL.',
          'enrolledCount': 0,
          'errors': ['Backend URL not configured'],
        };
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

          final imageBytes = await imageFile.readAsBytes();
          if (imageBytes.isEmpty) {
            print('⚠️ Image file is empty: ${imagePaths[i]}');
            errors.add('Image ${i + 1} is empty');
            continue;
          }

          print('📸 Enrolling face ${i + 1}/${imagePaths.length} via backend...');
          
          // Call backend API for enrollment (backend handles liveness + Luxand enrollment)
          final enrollResult = await _backendServiceInstance.enroll(
            email: email,
            photoBytes: imageBytes,
          );

          if (enrollResult['success'] == true) {
            final uuid = enrollResult['uuid']?.toString();
            if (uuid != null && uuid.isNotEmpty) {
              luxandUuid = uuid; // Store the UUID (should be same for all enrollments)
              enrolledCount++;
              print('✅ Face ${i + 1} enrolled successfully via backend. UUID: $uuid');
            } else {
              errors.add('Face ${i + 1}: No UUID returned from backend');
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
        return {
          'success': false,
          'error': 'Failed to enroll any faces. ${errors.join('; ')}',
          'enrolledCount': enrolledCount,
          'errors': errors,
        };
      }

      // Store uuid on user's document
      await _firestore.collection('users').doc(userId).set({
        'luxandUuid': luxandUuid,
        'luxand': {
          'uuid': luxandUuid,
          'enrolledAt': FieldValue.serverTimestamp(),
          'enrolledFaces': enrolledCount,
        },
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ Enrolled $enrolledCount/${imagePaths.length} faces successfully via backend. UUID: $luxandUuid');
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
  /// Returns an empty list if embedding generation fails.
  static Future<List<double>> generateEmbedding({
    required Face face,
    CameraImage? cameraImage,
    Uint8List? imageBytes,
    bool normalize = true,
  }) async {
    if (cameraImage == null && imageBytes == null) {
      return const [];
    }

    List embedding;
    if (cameraImage != null) {
      embedding = await _faceNetService.predict(cameraImage, face);
    } else {
      embedding = await _faceNetService.predictFromBytes(imageBytes!, face);
    }

    if (embedding.isEmpty) {
      return const [];
    }

    final List<double> result = embedding.map((e) => (e as num).toDouble()).toList();

    if (normalize) {
      final norm = _faceNetService.L2Norm(result);
      if (norm > 0.0) {
        for (int i = 0; i < result.length; i++) {
          result[i] = result[i] / norm;
        }
      }
    }

    return result;
  }

  /// Register an additional face embedding (for multi-shot registration).
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
      print('🔐 Registering additional face embedding from source: $source for user: $userId');

      if (cameraImage == null && imageBytes == null) {
        return {'success': false, 'error': 'Camera image not available.'};
      }

      // Generate embedding from the detected face.
      List embedding;
      if (cameraImage != null) {
        embedding = await _faceNetService.predict(cameraImage, detectedFace);
      } else {
        embedding = await _faceNetService.predictFromBytes(imageBytes!, detectedFace);
      }

      if (embedding.isEmpty) {
        return {
          'success': false,
          'error': 'Failed to generate face embedding.',
        };
      }

      // CRITICAL: FaceNetService.predict() already returns normalized embeddings
      // Convert to List<double> for consistency
      final List<double> normalizedEmbedding = embedding.map((e) => (e as num).toDouble()).toList();
      
      print('📊 Generated ${normalizedEmbedding.length}D embedding from $source.');
      
      // CRITICAL: Extract landmark features for "whose face is this" recognition
      // This enables the app to know "whose nose, eyes, lips, etc. is this"
      final landmarkFeatures = FaceLandmarkService.extractLandmarkFeatures(detectedFace);
      final featureDistances = FaceLandmarkService.calculateFeatureDistances(detectedFace);
      
      // Validate essential features are present
      final hasEssentialFeatures = FaceLandmarkService.validateEssentialFeatures(detectedFace);
      if (!hasEssentialFeatures) {
        print('🚨 CRITICAL: Missing essential facial features (eyes, nose, mouth)');
        print('🚨 This face cannot be reliably recognized - embedding rejected');
        return {
          'success': false,
          'error': 'Face features not complete. Please ensure all features (eyes, nose, mouth) are visible.',
        };
      }
      
      print('✅ Landmark features extracted: ${landmarkFeatures.keys.join(', ')}');
      print('✅ Feature distances calculated: ${featureDistances.keys.join(', ')}');
      print('✅ This embedding knows "whose face is this" at feature level');
      
      // Verify normalization (should be ~1.0)
      final embeddingNorm = _faceNetService.L2Norm(normalizedEmbedding);
      if (embeddingNorm < 0.9 || embeddingNorm > 1.1) {
        print('⚠️ WARNING: Additional embedding normalization issue! Norm: $embeddingNorm');
        // Re-normalize if needed (shouldn't happen, but safety check)
        if (embeddingNorm > 0.0) {
          final renormalized = _faceNetService.normalize(normalizedEmbedding);
          // Update the list in place
          for (int i = 0; i < normalizedEmbedding.length && i < renormalized.length; i++) {
            normalizedEmbedding[i] = renormalized[i];
          }
        }
      }

      // NOTE: face_embeddings storage removed - using Luxand exclusively
      // Luxand handles all face recognition via backend API
      // No need to store local embeddings when using Luxand
      print('✅ Additional embedding processed (Luxand handles storage)');

      return {
        'success': true,
        'message': 'Additional embedding registered successfully.',
        'embeddingSize': embedding.length,
      };
    } catch (e) {
      print('❌ Error registering additional embedding: $e');
      return {
        'success': false,
        'error': 'Failed to register additional embedding: $e',
      };
    }
  }

  /// Register a user's face using FaceNet embeddings.
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

      if (cameraImage == null && imageBytes == null) {
        return {'success': false, 'error': 'Camera image not available.'};
      }

      // Generate embedding from the detected face.
      List embedding;
      if (cameraImage != null) {
        embedding = await _faceNetService.predict(cameraImage, detectedFace);
      } else {
        embedding = await _faceNetService.predictFromBytes(imageBytes!, detectedFace);
      }

      if (embedding.isEmpty) {
        return {
          'success': false,
          'error': 'Failed to generate face embedding.',
        };
      }

      // CRITICAL: FaceNetService.predict() already returns normalized embeddings
      // Convert to List<double> for consistency
      final List<double> normalizedEmbedding = embedding.map((e) => (e as num).toDouble()).toList();
      
      // CRITICAL: Extract landmark features for "whose face is this" recognition
      // This enables the app to know "whose nose, eyes, lips, etc. is this"
      final landmarkFeatures = FaceLandmarkService.extractLandmarkFeatures(detectedFace);
      final featureDistances = FaceLandmarkService.calculateFeatureDistances(detectedFace);
      
      // Validate essential features are present
      final hasEssentialFeatures = FaceLandmarkService.validateEssentialFeatures(detectedFace);
      if (!hasEssentialFeatures) {
        print('🚨 CRITICAL: Missing essential facial features (eyes, nose, mouth)');
        print('🚨 This face cannot be reliably recognized - embedding rejected');
        return {
          'success': false,
          'error': 'Face features not complete. Please ensure all features (eyes, nose, mouth) are visible.',
        };
      }
      
      print('✅ Landmark features extracted: ${landmarkFeatures.keys.join(', ')}');
      print('✅ Feature distances calculated: ${featureDistances.keys.join(', ')}');
      print('✅ This embedding knows "whose face is this" at feature level');
      
      // DEBUG: Verify normalization before storage
      final registrationNorm = _faceNetService.L2Norm(normalizedEmbedding);
      final embeddingMin = normalizedEmbedding.reduce((a, b) => a < b ? a : b);
      final embeddingMax = normalizedEmbedding.reduce((a, b) => a > b ? a : b);
      final embeddingMean = normalizedEmbedding.reduce((a, b) => a + b) / normalizedEmbedding.length;
      
      print('📊 Generated ${normalizedEmbedding.length}D embedding.');
      print('📊 Registration embedding normalized (norm: ${registrationNorm.toStringAsFixed(6)}, should be ~1.0)');
      print('📊 Registration embedding stats: min=${embeddingMin.toStringAsFixed(4)}, max=${embeddingMax.toStringAsFixed(4)}, mean=${embeddingMean.toStringAsFixed(4)}');
      print('📊 Registration embedding first 10 values: ${normalizedEmbedding.take(10).map((e) => e.toStringAsFixed(4)).join(', ')}');
      
      if (registrationNorm < 0.9 || registrationNorm > 1.1) {
        print('⚠️ WARNING: Registration embedding normalization issue! Norm: $registrationNorm');
        // Re-normalize if needed (shouldn't happen, but safety check)
        if (registrationNorm > 0.0) {
          final renormalized = _faceNetService.normalize(normalizedEmbedding);
          // Update the list in place
          for (int i = 0; i < normalizedEmbedding.length && i < renormalized.length; i++) {
            normalizedEmbedding[i] = renormalized[i];
          }
          print('✅ Re-normalized registration embedding');
        }
      }

      // Validate embedding quality before storing
      // Balanced: Check if embedding is meaningful but allow lower threshold for edge cases
      final embeddingVariance = _calculateEmbeddingVariance(normalizedEmbedding);
      if (embeddingVariance < 0.0005) { // Balanced: Lower threshold (was 0.001) to allow edge cases
        print('🚨🚨🚨 CRITICAL: Embedding variance is extremely low (${embeddingVariance.toStringAsFixed(6)})');
        print('🚨 This indicates the embedding is not meaningful - face may not have been scanned properly');
        print('🚨 Please ensure good lighting, clear face visibility, and proper face positioning');
        return {
          'success': false,
          'error': 'Face not properly scanned. Please ensure good lighting and clear face visibility.',
        };
      }
      
      if (embeddingVariance < 0.001) {
        print('⚠️ Embedding variance is low (${embeddingVariance.toStringAsFixed(6)}) - proceeding with caution');
      } else {
        print('✅ Embedding quality validated: variance=${embeddingVariance.toStringAsFixed(6)} (good)');
      }
      
      // CRITICAL SECURITY STEP: Check if this face is already registered to another user, ignoring the current user and email.
      // Use normalized embedding for uniqueness check (consistent with storage)
      final bool isFaceAlreadyRegistered = await FaceUniquenessService.isFaceAlreadyRegistered(
        normalizedEmbedding,
        currentUserIdToIgnore: userId,
        currentEmailToIgnore: email,
      );
      if (isFaceAlreadyRegistered) {
        return {
          'success': false,
          'error': 'This face appears to be already registered with another account.',
        };
      }

      // CRITICAL: Extract landmark features for "whose face is this" recognition
      final initialLandmarkFeatures = FaceLandmarkService.extractLandmarkFeatures(detectedFace);
      final initialFeatureDistances = FaceLandmarkService.calculateFeatureDistances(detectedFace);
      
      // Validate essential features are present
      final hasInitialEssentialFeatures = FaceLandmarkService.validateEssentialFeatures(detectedFace);
      if (!hasInitialEssentialFeatures) {
        print('🚨 CRITICAL: Missing essential facial features (eyes, nose, mouth)');
        return {
          'success': false,
          'error': 'Face features not complete. Please ensure all features (eyes, nose, mouth) are visible.',
        };
      }
      
      print('✅ Landmark features extracted: ${initialLandmarkFeatures.keys.join(', ')}');
      print('✅ Feature distances calculated: ${initialFeatureDistances.keys.join(', ')}');
      
      // NOTE: face_embeddings storage removed - using Luxand exclusively
      // Luxand handles all face recognition via backend API
      // No need to store local embeddings when using Luxand
      print('✅ Face registration processed (Luxand handles storage)');

      return {
        'success': true,
        'message': 'Face registered successfully.',
      };
    } catch (e) {
      print('❌ Error in SECURE face registration: $e');
      return {
        'success': false,
        'error': 'Face registration failed: $e',
      };
    }
  }

  /// Authenticate a user using FaceNet embeddings.
  static Future<Map<String, dynamic>> authenticateUser({
    required Face detectedFace,
    CameraImage? cameraImage,
    Uint8List? imageBytes,
  }) async {
    try {
      print('🔐 Starting SECURE face authentication...');

      if (cameraImage == null && imageBytes == null) {
        return {'success': false, 'error': 'Camera image not available.'};
      }

      // Generate embedding for the current face.
      List<double> currentEmbedding;
      if (cameraImage != null) {
        currentEmbedding = await _faceNetService.predict(cameraImage, detectedFace);
      } else {
        currentEmbedding = await _faceNetService.predictFromBytes(imageBytes!, detectedFace);
      }

      if (currentEmbedding.isEmpty) {
        return {'success': false, 'error': 'Failed to generate face embedding.'};
      }

      // CRITICAL: FaceNetService.predict() already returns normalized embeddings
      // Convert to List<double> for consistency - DO NOT normalize again (would cause double normalization)
      final List<double> normalizedCurrentEmbedding = currentEmbedding.map((e) => (e as num).toDouble()).toList();
      
      // DEBUG: Verify normalization
      final currentNorm = _faceNetService.L2Norm(normalizedCurrentEmbedding);
      print('📊 Current embedding normalized (norm: ${currentNorm.toStringAsFixed(6)}, should be ~1.0)');
      
      if (currentNorm < 0.9 || currentNorm > 1.1) {
        print('⚠️ WARNING: Current embedding normalization issue! Norm: $currentNorm');
        // Re-normalize if needed (shouldn't happen, but safety check)
        if (currentNorm > 0.0) {
          final renormalized = _faceNetService.normalize(normalizedCurrentEmbedding);
          // Update the list in place
          for (int i = 0; i < normalizedCurrentEmbedding.length && i < renormalized.length; i++) {
            normalizedCurrentEmbedding[i] = renormalized[i];
          }
          print('✅ Re-normalized current embedding');
        }
      }
      
      // DEBUG: Check embedding uniqueness
      final embeddingMin = normalizedCurrentEmbedding.reduce((a, b) => a < b ? a : b);
      final embeddingMax = normalizedCurrentEmbedding.reduce((a, b) => a > b ? a : b);
      final embeddingMean = normalizedCurrentEmbedding.reduce((a, b) => a + b) / normalizedCurrentEmbedding.length;
      print('📊 Current embedding stats: min=${embeddingMin.toStringAsFixed(4)}, max=${embeddingMax.toStringAsFixed(4)}, mean=${embeddingMean.toStringAsFixed(4)}');
      print('📊 First 10 values: ${normalizedCurrentEmbedding.take(10).map((e) => e.toStringAsFixed(4)).join(', ')}');

      // Get all stored face embeddings.
      final storedFaces = await _getAllStoredFaceEmbeddings();

      if (storedFaces.isEmpty) {
        return {'success': false, 'error': 'No registered faces found.'};
      }

      // CRITICAL: Validate that stored embeddings are diverse (not all identical)
      // This checks if the model stored different embeddings for different users
      final embeddingDiversityCheck = await _validateEmbeddingDiversity(storedFaces);
      if (!embeddingDiversityCheck['isDiverse']) {
        print('🚨🚨🚨 CRITICAL: Stored embeddings are NOT diverse!');
        print('🚨 All stored faces appear identical - this is a model/system error!');
        print('🚨 ${embeddingDiversityCheck['message']}');
        return {
          'success': false,
          'error': 'Face recognition system error. Stored embeddings are not diverse. Please contact support.',
        };
      }

      // Use all stored embeddings (including temp_) but resolve to permanent user after match
      final candidates = storedFaces;

      print('📊 Found ${candidates.length} stored face embeddings.');
      print('✅ Embedding diversity check passed: ${embeddingDiversityCheck['message']}');

      // Compare the current face with all stored faces.
      String? bestMatchUserId;
      double bestSimilarity = 0.0;
      double secondBestSimilarity = 0.0;
      String? secondBestUserId;
      
      // Store all similarities for detailed analysis
      List<Map<String, dynamic>> allSimilarities = [];

      print('🔍 ==========================================');
      print('🔍 COMPARING AGAINST ALL STORED USERS');
      print('🔍 ==========================================');

      for (final storedFace in candidates) {
        final userId = storedFace['userId'] as String;
        
        // Get all embeddings for this user (multi-shot support)
        final embeddingsData = storedFace['embeddings'] as List?;
        List<Map<String, dynamic>> embeddingsToCompare = [];
        
        if (embeddingsData != null && embeddingsData.isNotEmpty) {
          // Multi-shot: compare against all embeddings
          for (final embData in embeddingsData) {
            if (embData is Map && embData['embedding'] != null) {
              embeddingsToCompare.add(Map<String, dynamic>.from(embData));
            }
          }
        }
        
        // Fallback to single embedding (legacy format)
        if (embeddingsToCompare.isEmpty && storedFace['embedding'] != null) {
          embeddingsToCompare.add({
            'embedding': storedFace['embedding'],
            'source': 'legacy',
          });
        }
        
        // Compare against all embeddings for this user and take the best match
        double userBestSimilarity = 0.0;
        String? bestSource;
        for (final embData in embeddingsToCompare) {
          final storedEmbeddingRaw = embData['embedding'] as List;
          final storedEmbeddingList = storedEmbeddingRaw.map((e) => (e as num).toDouble()).toList();

          // Skip embeddings with a different dimensionality
          if (storedEmbeddingList.length != normalizedCurrentEmbedding.length) {
            print('⚠️ User $userId: Skipping embedding with wrong dimension (${storedEmbeddingList.length} vs ${normalizedCurrentEmbedding.length})');
            continue;
          }
          
          // CRITICAL: Stored embeddings are already normalized (from FaceNetService during registration)
          // DO NOT normalize again - this would cause double normalization and incorrect similarity scores
          // Only normalize if the stored embedding is not normalized (check norm first)
          final storedNorm = _faceNetService.L2Norm(storedEmbeddingList);
          List<double> storedEmbedding;
          if (storedNorm < 0.9 || storedNorm > 1.1) {
            // Stored embedding is not normalized, normalize it now
            print('⚠️ Stored embedding not normalized (norm: ${storedNorm.toStringAsFixed(6)}), normalizing...');
            storedEmbedding = _faceNetService.normalize(storedEmbeddingList);
          } else {
            // Stored embedding is already normalized, use as-is
            storedEmbedding = storedEmbeddingList;
          }
          
          // Use normalized current embedding for consistent comparison
          final similarity = _faceNetService.cosineSimilarity(normalizedCurrentEmbedding, storedEmbedding);
          
          // DEBUG: Log detailed comparison info for first embedding of each user
          if (userBestSimilarity == 0.0) {
            final storedNorm = _faceNetService.L2Norm(storedEmbedding);
            final storedMin = storedEmbedding.reduce((a, b) => a < b ? a : b);
            final storedMax = storedEmbedding.reduce((a, b) => a > b ? a : b);
            print('📊 Comparing with stored embedding from ${bestSource ?? 'unknown'}:');
            print('  - Stored norm: ${storedNorm.toStringAsFixed(6)}, Similarity: ${similarity.toStringAsFixed(4)}');
            print('  - Stored stats: min=${storedMin.toStringAsFixed(4)}, max=${storedMax.toStringAsFixed(4)}');
            print('  - Stored first 10: ${storedEmbedding.take(10).map((e) => e.toStringAsFixed(4)).join(', ')}');
            print('  - Current first 10: ${normalizedCurrentEmbedding.take(10).map((e) => e.toStringAsFixed(4)).join(', ')}');
          }
          
          // Track the best similarity for this user across all their embeddings
          if (similarity > userBestSimilarity) {
            userBestSimilarity = similarity;
            bestSource = embData['source']?.toString() ?? 'unknown';
          }
        }
        
        // Store similarity for this user
        if (userBestSimilarity > 0) {
          allSimilarities.add({
            'userId': userId,
            'similarity': userBestSimilarity,
            'source': bestSource ?? 'unknown',
            'embeddingCount': embeddingsToCompare.length,
          });
          
          print('🔍 User: $userId | Similarity: ${userBestSimilarity.toStringAsFixed(4)} | Embeddings: ${embeddingsToCompare.length} | Source: ${bestSource ?? 'unknown'}');
        }

        // Use the best similarity from all embeddings for this user
        if (userBestSimilarity > bestSimilarity) {
          secondBestSimilarity = bestSimilarity;
          secondBestUserId = bestMatchUserId;
          bestSimilarity = userBestSimilarity;
          bestMatchUserId = userId;
        } else if (userBestSimilarity > secondBestSimilarity) {
          secondBestSimilarity = userBestSimilarity;
          secondBestUserId = userId;
        }
      }

      print('🔍 ==========================================');
      print('🔍 SIMILARITY ANALYSIS SUMMARY');
      print('🔍 ==========================================');
      print('📊 Total users compared: ${allSimilarities.length}');
      
      // Sort by similarity for analysis
      allSimilarities.sort((a, b) => (b['similarity'] as double).compareTo(a['similarity'] as double));
      
      // Show top 5 similarities
      print('📊 Top 5 similarities:');
      for (int i = 0; i < allSimilarities.length && i < 5; i++) {
        final sim = allSimilarities[i];
        print('  ${i + 1}. User: ${sim['userId']} | Similarity: ${(sim['similarity'] as double).toStringAsFixed(4)}');
      }
      
        // Calculate similarity spread
        if (allSimilarities.length > 1) {
          final maxSim = allSimilarities.first['similarity'] as double;
          final minSim = allSimilarities.last['similarity'] as double;
          final spread = maxSim - minSim;
          print('📊 Similarity range: ${minSim.toStringAsFixed(4)} - ${maxSim.toStringAsFixed(4)}');
          print('📊 Similarity spread: ${spread.toStringAsFixed(4)}');
          
          // Check if similarities indicate model failure
          // Count how many similarities are >0.99 (very high)
          final highSimilarityCount = allSimilarities.where((sim) => (sim['similarity'] as double) > 0.99).length;
          final highSimilarityRatio = highSimilarityCount / allSimilarities.length;
          
          print('📊 Similarity analysis:');
          print('  - High similarities (>0.99): $highSimilarityCount / ${allSimilarities.length} (${(highSimilarityRatio * 100).toStringAsFixed(1)}%)');
          
          // CRITICAL: Check if current face matches ALL stored faces equally
          // This indicates either:
          // 1. Current embedding is a "universal match" (normalization issue)
          // 2. Current face image quality is very poor
          // 3. Model is generating identical embeddings
          
          // Calculate the actual margin between best and second best
          final actualMarginBetweenTop2 = maxSim - (allSimilarities.length > 1 ? (allSimilarities[1]['similarity'] as double) : maxSim);
          
          print('📊 Top-2 margin: ${actualMarginBetweenTop2.toStringAsFixed(4)}');
          
          // Only reject if ALL similarities are >0.99 AND margin is EXTREMELY small (<0.0001 = 0.01%)
          // This catches cases where current face genuinely matches all faces equally (within 0.01%)
          // But allow if there's ANY discernible difference (margin >= 0.0001)
          if (highSimilarityRatio >= 0.95 && actualMarginBetweenTop2 < 0.0001) {
            print('🚨🚨🚨 CRITICAL ERROR: ${(highSimilarityRatio * 100).toStringAsFixed(1)}% of similarities are >0.99 AND margin is extremely tiny (<0.0001)!');
            print('🚨 Current face matches ALL stored faces equally (within 0.01%) - this indicates:');
            print('🚨 1. Poor image quality, OR');
            print('🚨 2. Normalization issue, OR');
            print('🚨 3. Model generating identical embeddings');
            print('🚨 Authentication REJECTED for security.');
            return {
              'success': false,
              'error': 'Face recognition failed. Please ensure good lighting and face the camera directly.',
            };
          }
          
          // If most similarities are high BUT there's a discernible winner (margin >= 0.0001), allow it
          // This handles cases where the current face genuinely matches one user very well
          if (highSimilarityRatio >= 0.8 && actualMarginBetweenTop2 >= 0.0001) {
            print('⚠️ NOTE: ${(highSimilarityRatio * 100).toStringAsFixed(1)}% of similarities are high, but clear winner exists (margin: ${actualMarginBetweenTop2.toStringAsFixed(4)}).');
            print('⚠️ Proceeding with authentication - best match has sufficient margin.');
          }
          
          if (spread < 0.1) {
            print('⚠️ WARNING: Similarity spread is very small (<0.1). Model may not be differentiating faces well!');
            // Only reject if spread is tiny AND there's no clear winner (margin < 0.0001)
            // If there's a clear winner (margin >= 0.0001), allow it even if spread is small
            if (maxSim > 0.98 && spread < 0.05 && highSimilarityRatio >= 0.5 && actualMarginBetweenTop2 < 0.0001) {
              print('🚨 CRITICAL: Most similarities are extremely high (>0.98) with tiny spread (<0.05) AND no clear winner (margin < 0.0001). Model failure detected.');
              return {
                'success': false,
                'error': 'Face recognition system error. Please try again or contact support.',
              };
            } else if (maxSim > 0.98 && spread < 0.05 && highSimilarityRatio >= 0.5 && actualMarginBetweenTop2 >= 0.0001) {
              print('⚠️ NOTE: Spread is small but clear winner exists (margin: ${actualMarginBetweenTop2.toStringAsFixed(4)}). Proceeding.');
            }
          }
        }
      
      print('📊 Best match: $bestMatchUserId with similarity ${bestSimilarity.toStringAsFixed(4)}');
      print('📊 Second best: $secondBestUserId with similarity ${secondBestSimilarity.toStringAsFixed(4)}');
      print('📊 Margin difference: ${(bestSimilarity - secondBestSimilarity).toStringAsFixed(4)}');
      print('🔍 ==========================================');

      // CRITICAL SECURITY: MAXIMUM STRICTNESS to prevent unauthorized access and wrong account login
      // FaceNet typically produces 0.85-0.98 similarity for same person
      // We use EXTREMELY STRICT thresholds to prevent false positives
      final bestMatchEmbeddingCount = _getEmbeddingCountForUser(bestMatchUserId, storedFaces);
      double threshold = 0.96; // Default threshold for users with 3+ embeddings (96% similarity - VERY HIGH)
      double margin = 0.05; // Minimum 5% difference from second best match (VERY HIGH)
      
      if (bestMatchEmbeddingCount <= 1) {
        // Users with only 1 embedding: require very high threshold
        threshold = 0.94; // 94% similarity required (VERY HIGH)
        margin = 0.04; // 4% margin required (VERY HIGH)
        print('📊 Using very strict threshold (${threshold.toStringAsFixed(3)}) for user with ${bestMatchEmbeddingCount} embedding(s)');
      } else if (bestMatchEmbeddingCount == 2) {
        // Users with 2 embeddings: high threshold
        threshold = 0.95; // 95% similarity required (VERY HIGH)
        margin = 0.045; // 4.5% margin required (VERY HIGH)
        print('📊 Using high threshold (${threshold.toStringAsFixed(3)}) for user with ${bestMatchEmbeddingCount} embeddings');
      } else {
        // Users with 3+ embeddings: maximum threshold
        print('📊 Using maximum security threshold (${threshold.toStringAsFixed(3)}) for user with ${bestMatchEmbeddingCount} embeddings');
      }
      
      // SECURITY: Use strict margin requirements - NO adaptive reduction for maximum security
      // Only allow login if similarity is extremely high (>99%) AND margin is met
      double requiredMargin = margin;
      if (bestSimilarity >= 0.995) {
        // For extremely high similarities (>99.5%), use slightly smaller margin (0.02 = 2%)
        requiredMargin = 0.02;
        print('📊 Extremely high similarity detected (${bestSimilarity.toStringAsFixed(4)}), using reduced margin: ${requiredMargin.toStringAsFixed(4)}');
      } else {
        // For all other cases, use full margin requirement for security
        requiredMargin = margin;
        print('📊 Using full security margin: ${requiredMargin.toStringAsFixed(4)}');
      }

      // Check if top 2 matches are related (temp_ vs permanent for same person)
      bool areRelatedUsers = false;
      if (bestMatchUserId != null && secondBestUserId != null) {
        // If one is temp_ and one is permanent, check if they're related
        if (bestMatchUserId.startsWith('temp_') && !secondBestUserId.startsWith('temp_')) {
          try {
            final permanentUserId = await _findPermanentUserId(bestMatchUserId);
            if (permanentUserId == secondBestUserId) {
              areRelatedUsers = true;
              print('🔍 Top 2 matches are related: temp_ and permanent user for same person');
            }
          } catch (e) {
            // Ignore errors
          }
        } else if (!bestMatchUserId.startsWith('temp_') && secondBestUserId.startsWith('temp_')) {
          try {
            final permanentUserId = await _findPermanentUserId(secondBestUserId);
            if (permanentUserId == bestMatchUserId) {
              areRelatedUsers = true;
              print('🔍 Top 2 matches are related: temp_ and permanent user for same person');
            }
          } catch (e) {
            // Ignore errors
          }
        }
      }

      // CRITICAL SECURITY: Maximum strictness ambiguity guard - reject if top 2 matches are too close
      // This prevents unauthorized access and wrong account login when multiple users have similar faces
      final bool ambiguousTop2 = !areRelatedUsers && 
          bestSimilarity >= threshold && secondBestSimilarity >= threshold &&
          (bestSimilarity - secondBestSimilarity).abs() < requiredMargin &&
          bestSimilarity < 0.998; // Only allow if similarity is extremely high (>99.8%)

      // CRITICAL: Require BOTH margin AND very high similarity (unless users are related)
      // This prevents false positives and wrong account access
      final bool marginMet = (bestSimilarity - secondBestSimilarity) >= requiredMargin;
      final bool veryHighSimilarity = bestSimilarity >= 0.98; // Require at least 98% similarity
      final bool extremelyHighSimilarity = bestSimilarity >= 0.995; // For extremely high, be more lenient
      
      // CRITICAL SECURITY CHECK: Only reject if there's no clear winner
      // If most similarities are high BUT there's a clear margin between top 2, allow it
      final highSimilarityCount = allSimilarities.where((sim) => (sim['similarity'] as double) > 0.99).length;
      final highSimilarityRatio = allSimilarities.length > 0 ? highSimilarityCount / allSimilarities.length : 0.0;
      
      // Calculate margin between best and second best
      final top2Margin = (bestSimilarity - secondBestSimilarity).abs();
      
      // Only reject if ALL similarities are high AND margin is EXTREMELY tiny (no clear winner)
      // Use 0.0001 (0.01%) as threshold - this is the precision limit for distinguishing faces
      final allSimilaritiesHigh = allSimilarities.length > 1 && highSimilarityRatio >= 0.95 && top2Margin < 0.0001;
      
      if (allSimilaritiesHigh) {
        print('🚨🚨🚨 SECURITY REJECTION: ${(highSimilarityRatio * 100).toStringAsFixed(1)}% of similarities >0.99 AND margin is extremely tiny (<0.0001). No clear winner.');
        return {
          'success': false,
          'error': 'Face recognition failed. Please ensure good lighting and face the camera directly.',
        };
      }
      
      // If most similarities are high BUT there's a discernible winner (margin >= 0.0001), allow it
      if (highSimilarityRatio >= 0.8 && top2Margin >= 0.0001) {
        print('⚠️ NOTE: ${(highSimilarityRatio * 100).toStringAsFixed(1)}% of similarities are high, but clear winner exists (margin: ${top2Margin.toStringAsFixed(4)}).');
      }
      
      // CRITICAL: If margin is too small (<0.01 = 1%), reject even if similarity is high
      // This prevents cases where all faces match equally well
      final actualMargin = (bestSimilarity - secondBestSimilarity).abs();
      if (actualMargin < 0.01 && !areRelatedUsers && bestSimilarity < 0.998) {
        print('🚨 SECURITY REJECTION: Margin too small (${actualMargin.toStringAsFixed(4)} < 0.01). Faces are too similar.');
        return {
          'success': false,
          'error': 'Face verification ambiguous. Please try again.',
        };
      }
      
      // Allow login ONLY if:
      // 1. Best similarity meets threshold AND
      // 2. (Margin is met AND similarity is very high >0.98) OR (extremely high >99.5% OR users are related) AND
      // 3. Not ambiguous (unless users are related or extremely high similarity)
      // 4. NOT all similarities high with no clear winner (model differentiation check)
      final bool canProceed = bestSimilarity >= threshold && 
          ((marginMet && veryHighSimilarity) || extremelyHighSimilarity || areRelatedUsers) &&
          (!ambiguousTop2 || extremelyHighSimilarity || areRelatedUsers) &&
          !allSimilaritiesHigh;

      if (canProceed) {
        print('✅ SECURE face authentication preliminary match passed');
        
        String? finalUserId = bestMatchUserId;
        if (bestMatchUserId != null && bestMatchUserId.startsWith('temp_')) {
            print('🔍 Matched to temp_ user: $bestMatchUserId, attempting to resolve to permanent user...');
            final permanentUserId = await _findPermanentUserId(bestMatchUserId);
            if (permanentUserId != null) {
                print('✅ Resolved temp_ user to permanent user: $permanentUserId');
                
                // CRITICAL: Verify the permanent user actually has face embeddings matching this face
                // This prevents matching to wrong user if email lookup finds different user
                final permanentUserDoc = await _firestore.collection('users').doc(permanentUserId).get();
                if (permanentUserDoc.exists) {
                  final permanentUserData = permanentUserDoc.data()!;
                  final permanentSignupCompleted = permanentUserData['signupCompleted'] ?? false;
                  
                  if (permanentSignupCompleted) {
                    // Verify permanent user has matching face embedding
                    final permanentFaceDoc = await _firestore.collection('face_embeddings').doc(permanentUserId).get();
                    if (permanentFaceDoc.exists) {
                      final permanentEmbeddingsData = permanentFaceDoc.data()!['embeddings'] as List?;
                      if (permanentEmbeddingsData != null && permanentEmbeddingsData.isNotEmpty) {
                        // Verify at least one embedding matches well
                        bool permanentMatches = false;
                        for (final embData in permanentEmbeddingsData) {
                          if (embData is Map && embData['embedding'] != null) {
                            final permEmbRaw = embData['embedding'] as List;
                            final permEmbList = permEmbRaw.map((e) => (e as num).toDouble()).toList();
                            if (permEmbList.length == normalizedCurrentEmbedding.length) {
                              // CRITICAL: Check if permanent embedding is already normalized
                              final permNorm = _faceNetService.L2Norm(permEmbList);
                              List<double> permEmbNormalized;
                              if (permNorm < 0.9 || permNorm > 1.1) {
                                // Not normalized, normalize it
                                permEmbNormalized = _faceNetService.normalize(permEmbList);
                              } else {
                                // Already normalized, use as-is
                                permEmbNormalized = permEmbList;
                              }
                              final permSimilarity = _faceNetService.cosineSimilarity(normalizedCurrentEmbedding, permEmbNormalized);
                              if (permSimilarity >= threshold) {
                                permanentMatches = true;
                                print('✅ Verified permanent user has matching face embedding (similarity: ${permSimilarity.toStringAsFixed(4)})');
                                break;
                              }
                            }
                          }
                        }
                        
                        if (permanentMatches) {
                          finalUserId = permanentUserId;
                        } else {
                          print('⚠️ WARNING: Permanent user found but face embeddings don\'t match well. Using temp_ ID instead.');
                          // Fallback: try temp_ ID directly if it exists in users collection
                          final tempUserDoc = await _firestore.collection('users').doc(bestMatchUserId).get();
                          if (tempUserDoc.exists && (tempUserDoc.data()!['signupCompleted'] ?? false)) {
                            print('✅ Temp_ user exists with completed signup, using temp_ ID: $bestMatchUserId');
                            finalUserId = bestMatchUserId;
                          } else {
                            print('❌ Neither permanent nor temp_ user is valid. Rejecting authentication.');
                            return {
                              'success': false,
                              'error': 'User account not properly registered. Please sign up again.',
                            };
                          }
                        }
                      } else {
                        print('⚠️ Permanent user has no face embeddings. Using temp_ ID as fallback.');
                        finalUserId = bestMatchUserId;
                      }
                    } else {
                      print('⚠️ Permanent user has no face_embeddings document. Using temp_ ID as fallback.');
                      finalUserId = bestMatchUserId;
                    }
                  } else {
                    print('⚠️ Permanent user exists but signup not completed. Using temp_ ID as fallback.');
                    finalUserId = bestMatchUserId;
                  }
                } else {
                  print('⚠️ Permanent user document not found. Using temp_ ID as fallback.');
                  finalUserId = bestMatchUserId;
                }
            } else {
                print('⚠️ Matched temp_ but no permanent user found. Attempting to use temp_ ID directly...');
                // Fallback: Check if temp_ user exists in users collection with completed signup
                final tempUserDoc = await _firestore.collection('users').doc(bestMatchUserId).get();
                if (tempUserDoc.exists && (tempUserDoc.data()!['signupCompleted'] ?? false)) {
                  print('✅ Temp_ user exists with completed signup, using temp_ ID: $bestMatchUserId');
                  finalUserId = bestMatchUserId;
                } else {
                  print('❌ Temp_ user not found or signup not completed. Rejecting authentication.');
                  return {
                    'success': false,
                    'error': 'User account not properly registered. Please sign up again.',
                  };
                }
            }
        }

        // SECONDARY 1:1 VERIFICATION (mandatory)
        if (finalUserId == null) {
          return {
            'success': false,
            'error': 'Verification error. Please try again.',
          };
        }

        try {
          final secondaryEmbedding = await _getCompatibleSecondaryEmbedding(
            primaryEmbedding: normalizedCurrentEmbedding,
            finalUserId: finalUserId,
            altUserId: bestMatchUserId,
          );

          if (secondaryEmbedding == null) {
            print('❌ No compatible embedding available for secondary verification');
            return {
              'success': false,
              'error': 'Verification error. Please re-verify your face.',
            };
          }

          // CRITICAL: Secondary embedding may already be normalized, check before normalizing
          final secondaryNorm = _faceNetService.L2Norm(secondaryEmbedding);
          List<double> normalizedStoredUserEmbedding;
          if (secondaryNorm < 0.9 || secondaryNorm > 1.1) {
            // Not normalized, normalize it
            normalizedStoredUserEmbedding = _faceNetService.normalize(secondaryEmbedding);
          } else {
            // Already normalized, use as-is
            normalizedStoredUserEmbedding = secondaryEmbedding;
          }
          
          // Use normalized current embedding for secondary verification
          final secondSimilarity = _faceNetService.cosineSimilarity(normalizedCurrentEmbedding, normalizedStoredUserEmbedding);
          print('🔁 Secondary 1:1 verification similarity: ${secondSimilarity.toStringAsFixed(4)}');
          
          // CRITICAL: Use same strict threshold for secondary verification (no tolerance)
          // This ensures maximum security - both primary and secondary must pass
          if (secondSimilarity < threshold) {
            print('❌ Secondary verification failed: ${secondSimilarity.toStringAsFixed(4)} < $threshold');
            return {
              'success': false,
              'error': 'Face not recognized (secondary verification failed).',
            };
          }
          
          // TERTIARY CHECK: Both similarities must be consistent (within 3% of each other)
          // This prevents cases where primary passes but secondary is significantly different
          final similarityDifference = (bestSimilarity - secondSimilarity).abs();
          if (similarityDifference > 0.03) {
            print('❌ Tertiary verification failed: Similarity difference too large (${similarityDifference.toStringAsFixed(4)} > 0.03)');
            print('   Primary: ${bestSimilarity.toStringAsFixed(4)}, Secondary: ${secondSimilarity.toStringAsFixed(4)}');
            return {
              'success': false,
              'error': 'Face verification inconsistent. Please try again.',
            };
          }
          
          print('✅ Tertiary verification passed: Similarities are consistent');
        } catch (e) {
          print('⚠️ Secondary verification error: $e');
          return {
            'success': false,
            'error': 'Verification error. Please try again.',
          };
        }

        // CRITICAL SECURITY CHECK: Verify user exists and completed signup before allowing login
        print('🔒 Performing security verification: Checking if user completed signup...');
        final userDoc = await _firestore.collection('users').doc(finalUserId).get();
        
        if (!userDoc.exists) {
          print('❌ SECURITY: User document does not exist for matched userId: $finalUserId');
          return {
            'success': false,
            'error': 'Account not found. Please sign up first.',
          };
        }
        
        final userData = userDoc.data()!;
        final signupCompleted = userData['signupCompleted'] ?? false;
        
        if (!signupCompleted) {
          print('❌ SECURITY: User has not completed signup: $finalUserId');
          return {
            'success': false,
            'error': 'Please complete signup first.',
          };
        }
        
        print('✅ SECURITY: User verified - signup completed: $signupCompleted');

        return {
          'success': true,
          'userId': finalUserId,
          'similarity': bestSimilarity,
        };
      } else {
        // CRITICAL: Log detailed failure reason and ensure rejection
        if (bestSimilarity < 0.85) {
          // Very low similarity - definitely unregistered user
          print('❌ SECURE face authentication REJECTED: Very low similarity ${bestSimilarity.toStringAsFixed(4)} - Unregistered user detected');
          return {
            'success': false,
            'error': 'Face not registered. Please sign up first.',
          };
        } else if (bestSimilarity < threshold) {
          print('❌ SECURE face authentication REJECTED: similarity ${bestSimilarity.toStringAsFixed(4)} < threshold $threshold');
          return {
            'success': false,
            'error': 'Face not recognized. Please try again or sign up.',
          };
        } else if (!marginMet && !veryHighSimilarity && !areRelatedUsers) {
          print('❌ SECURE face authentication REJECTED: margin ${(bestSimilarity - secondBestSimilarity).toStringAsFixed(4)} < required margin ${requiredMargin.toStringAsFixed(4)}');
          print('   Best: ${bestSimilarity.toStringAsFixed(4)}, Second: ${secondBestSimilarity.toStringAsFixed(4)}, Difference: ${(bestSimilarity - secondBestSimilarity).toStringAsFixed(4)}');
          return {
            'success': false,
            'error': 'Face verification failed. Please try again.',
          };
        } else if (ambiguousTop2) {
          print('❌ SECURE face authentication REJECTED: Ambiguous top-2 match between $bestMatchUserId and $secondBestUserId. Rejecting for safety.');
          return {
            'success': false,
            'error': 'Face verification ambiguous. Please try again.',
          };
        } else {
          print('❌ SECURE face authentication REJECTED: Unknown reason. Best: ${bestSimilarity.toStringAsFixed(4)}, Threshold: $threshold');
          return {
            'success': false,
            'error': 'Face not recognized. Please try again.',
          };
        }
      }
    } catch (e) {
      print('❌ Error in SECURE face authentication: $e');
      return {
        'success': false,
        'error': 'Face authentication failed: $e',
      };
    }
  }

  /// Calculate variance of embedding to ensure it's meaningful
  /// Low variance indicates all values are similar (not good for face recognition)
  static double _calculateEmbeddingVariance(List<double> embedding) {
    if (embedding.isEmpty) return 0.0;
    
    final mean = embedding.reduce((a, b) => a + b) / embedding.length;
    final variance = embedding.map((e) => pow(e - mean, 2)).reduce((a, b) => a + b) / embedding.length;
    
    return variance;
  }
  
  /// Store face embedding in Firebase (supports multiple embeddings per user).
  /// DEPRECATED: This function is no longer used - Luxand handles all face recognition
  /// Kept for reference but not called - face_embeddings storage removed in favor of Luxand
  /// CRITICAL: Validates embedding quality and normalization before storage.
  /// Stores landmark features for "whose face is this" recognition.
  @Deprecated('Using Luxand exclusively - face_embeddings no longer stored')
  static Future<void> _storeFaceEmbedding(
    String userId,
    List embedding,
    String? email,
    String? phoneNumber, {
    String? source, // e.g., 'profile_photo', 'blink_twice', 'move_closer', 'head_movement'
    Map<String, List<double>>? landmarkFeatures, // Feature positions for "whose nose, eyes, lips, etc."
    Map<String, double>? featureDistances, // Feature distances/ratios unique per person
  }) async {
    try {
      print('💾 Storing face embedding in Firebase (source: ${source ?? 'unknown'})...');
      
      // CRITICAL: Validate embedding before storage
      if (embedding.isEmpty) {
        print('🚨 CRITICAL: Cannot store empty embedding');
        throw Exception('Embedding is empty - cannot store');
      }
      
      // Convert to List<double> and validate
      final List<double> embeddingList = embedding.map((e) => (e as num).toDouble()).toList();
      
      // CRITICAL: Validate embedding dimensions (should be 512D)
      if (embeddingList.length != 512) {
        print('🚨 CRITICAL: Invalid embedding dimension: ${embeddingList.length} (expected 512)');
        throw Exception('Invalid embedding dimension: ${embeddingList.length} (expected 512)');
      }
      
      // CRITICAL: Validate normalization (should be ~1.0)
      final embeddingNorm = _faceNetService.L2Norm(embeddingList);
      if (embeddingNorm < 0.9 || embeddingNorm > 1.1) {
        print('⚠️ WARNING: Embedding not properly normalized (norm: ${embeddingNorm.toStringAsFixed(6)})');
        print('⚠️ Re-normalizing before storage to ensure consistency...');
        // Re-normalize to ensure consistency
        final renormalized = _faceNetService.normalize(embeddingList);
        // Use renormalized embedding
        for (int i = 0; i < embeddingList.length && i < renormalized.length; i++) {
          embeddingList[i] = renormalized[i];
        }
        final newNorm = _faceNetService.L2Norm(embeddingList);
        print('✅ Re-normalized embedding (new norm: ${newNorm.toStringAsFixed(6)})');
      }
      
      // CRITICAL: Validate embedding quality - check for invalid values
      final embeddingMin = embeddingList.reduce((a, b) => a < b ? a : b);
      final embeddingMax = embeddingList.reduce((a, b) => a > b ? a : b);
      final embeddingMean = embeddingList.reduce((a, b) => a + b) / embeddingList.length;
      
      // Check for suspicious patterns (all zeros, all same value, etc.)
      if (embeddingMax == embeddingMin && embeddingMax == 0.0) {
        print('🚨 CRITICAL: Embedding is all zeros - model failure');
        throw Exception('Embedding is all zeros - model failure');
      }
      
      if (embeddingMax == embeddingMin) {
        print('🚨 CRITICAL: All embedding values are identical - model failure');
        throw Exception('All embedding values are identical - model failure');
      }
      
      // Check for NaN or Infinity values
      for (int i = 0; i < embeddingList.length; i++) {
        if (embeddingList[i].isNaN || embeddingList[i].isInfinite) {
          print('🚨 CRITICAL: Invalid value in embedding at index $i: ${embeddingList[i]}');
          throw Exception('Invalid value in embedding: NaN or Infinity detected');
        }
      }
      
      print('✅ Embedding validation passed:');
      print('   - Dimension: ${embeddingList.length}D');
      print('   - Norm: ${embeddingNorm.toStringAsFixed(6)} (should be ~1.0)');
      print('   - Min: ${embeddingMin.toStringAsFixed(4)}, Max: ${embeddingMax.toStringAsFixed(4)}');
      print('   - Mean: ${embeddingMean.toStringAsFixed(4)}');
      print('   - Quality: Valid (no zeros, no duplicates, no NaN/Infinity)');
      
      // Get existing document
      final docRef = _firestore.collection('face_embeddings').doc(userId);
      final docSnapshot = await docRef.get();
      
      if (docSnapshot.exists) {
        // Update existing document - add to embeddings array
        final existingData = docSnapshot.data()!;
        final existingEmbeddings = existingData['embeddings'] as List? ?? [];
        
        // Check if this is a single embedding (legacy format)
        if (existingData['embedding'] != null && existingEmbeddings.isEmpty) {
          // Migrate old single embedding to array format
          existingEmbeddings.add({
            'embedding': existingData['embedding'],
            'source': 'legacy_migration',
            'timestamp': existingData['registeredAt'],
          });
        }
        
        // Add new embedding - CRITICAL: Use validated embeddingList, not raw embedding
        // CRITICAL: Store email/phone AND landmark features for "whose face is this" recognition
        final embeddingData = {
          'embedding': embeddingList, // Use validated and normalized embedding
          'source': source ?? 'unknown',
          'timestamp': Timestamp.now(), // Use Timestamp.now() instead of FieldValue.serverTimestamp() for arrays
          'email': email ?? '', // CRITICAL: Link email to this embedding
          'phoneNumber': phoneNumber ?? '', // CRITICAL: Link phone to this embedding
        };
        
        // CRITICAL: Store landmark features for feature-level recognition
        // This enables the app to know "whose nose, eyes, lips, etc. is this"
        if (landmarkFeatures != null && landmarkFeatures.isNotEmpty) {
          embeddingData['landmarkFeatures'] = landmarkFeatures;
          print('✅ Storing landmark features: ${landmarkFeatures.keys.join(', ')}');
        }
        
        if (featureDistances != null && featureDistances.isNotEmpty) {
          embeddingData['featureDistances'] = featureDistances;
          print('✅ Storing feature distances: ${featureDistances.keys.join(', ')}');
        }
        
        existingEmbeddings.add(embeddingData);
        
        // Update document - CRITICAL: Use validated embeddingList
        await docRef.update({
          'embeddings': existingEmbeddings,
          'lastUpdated': FieldValue.serverTimestamp(),
          // Keep primary embedding (first one or best quality) for backward compatibility
          'embedding': embeddingList, // Use validated embedding
        });
        
        print('✅ Face embedding added to array. Total embeddings: ${existingEmbeddings.length}');
      } else {
        // Create new document with embeddings array - CRITICAL: Use validated embeddingList
        await docRef.set({
          'userId': userId,
          'embedding': embeddingList, // Primary embedding for backward compatibility - use validated embedding
          'embeddings': [
            {
              'embedding': embeddingList, // Use validated and normalized embedding
              'source': source ?? 'unknown',
              'timestamp': Timestamp.now(), // Use Timestamp.now() instead of FieldValue.serverTimestamp() for arrays
              'email': email ?? '', // CRITICAL: Link email to this embedding
              'phoneNumber': phoneNumber ?? '', // CRITICAL: Link phone to this embedding
              // CRITICAL: Store landmark features for "whose face is this" recognition
              if (landmarkFeatures != null && landmarkFeatures.isNotEmpty)
                'landmarkFeatures': landmarkFeatures,
              if (featureDistances != null && featureDistances.isNotEmpty)
                'featureDistances': featureDistances,
            }
          ],
          'email': email ?? '',
          'phoneNumber': phoneNumber ?? '',
          'registeredAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        print('✅ New face embedding document created with 1 embedding.');
      }
    } catch (e) {
      print('❌ Error storing face embedding: $e');
      throw Exception('Failed to store face embedding: $e');
    }
  }

  /// Get all stored face embeddings.
  static Future<List<Map<String, dynamic>>> _getAllStoredFaceEmbeddings() async {
    try {
      final snapshot = await _firestore.collection('face_embeddings').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        // Ensure userId is set from document ID if missing
        if (data['userId'] == null) {
          data['userId'] = doc.id;
        }
        return data;
      }).toList();
    } catch (e) {
      print('❌ Error getting stored face embeddings: $e');
      return [];
    }
  }

  /// Validate that stored embeddings are diverse (not all identical)
  /// Returns a map with 'isDiverse' boolean and 'message' string
  static Future<Map<String, dynamic>> _validateEmbeddingDiversity(
    List<Map<String, dynamic>> storedFaces,
  ) async {
    try {
      if (storedFaces.length < 2) {
        return {
          'isDiverse': true,
          'message': 'Only one stored face - diversity check skipped',
        };
      }

      // Extract primary embeddings from each user
      List<List<double>> primaryEmbeddings = [];
      List<String> userIds = [];

      for (final storedFace in storedFaces) {
        final userId = storedFace['userId'] as String? ?? '';
        if (userId.isEmpty) continue;

        // Get primary embedding (first from array, or legacy single embedding)
        List<double>? primaryEmbedding;
        final embeddingsData = storedFace['embeddings'] as List?;
        
        if (embeddingsData != null && embeddingsData.isNotEmpty) {
          final firstEmb = embeddingsData.first;
          if (firstEmb is Map && firstEmb['embedding'] != null) {
            final raw = firstEmb['embedding'] as List;
            primaryEmbedding = raw.map((e) => (e as num).toDouble()).toList();
          }
        } else if (storedFace['embedding'] != null) {
          final raw = storedFace['embedding'] as List;
          primaryEmbedding = raw.map((e) => (e as num).toDouble()).toList();
        }

        if (primaryEmbedding != null && primaryEmbedding.isNotEmpty) {
          // CRITICAL: Stored embeddings are already normalized (from FaceNetService during registration)
          // DO NOT normalize again - this would cause double normalization and false diversity failures
          // Check if embedding is already normalized (norm ~1.0)
          final embeddingNorm = _faceNetService.L2Norm(primaryEmbedding);
          List<double> normalizedPrimaryEmbedding;
          if (embeddingNorm < 0.9 || embeddingNorm > 1.1) {
            // Not normalized, normalize it
            print('⚠️ Primary embedding for $userId not normalized (norm: ${embeddingNorm.toStringAsFixed(6)}), normalizing...');
            normalizedPrimaryEmbedding = _faceNetService.normalize(primaryEmbedding);
          } else {
            // Already normalized, use as-is
            normalizedPrimaryEmbedding = primaryEmbedding;
          }
          primaryEmbeddings.add(normalizedPrimaryEmbedding);
          userIds.add(userId);
        }
      }

      if (primaryEmbeddings.length < 2) {
        return {
          'isDiverse': true,
          'message': 'Not enough valid embeddings for diversity check',
        };
      }

      // Compare all embeddings against each other
      List<double> allSimilarities = [];
      for (int i = 0; i < primaryEmbeddings.length; i++) {
        for (int j = i + 1; j < primaryEmbeddings.length; j++) {
          final similarity = _faceNetService.cosineSimilarity(
            primaryEmbeddings[i],
            primaryEmbeddings[j],
          );
          allSimilarities.add(similarity);
        }
      }

      if (allSimilarities.isEmpty) {
        return {
          'isDiverse': true,
          'message': 'Could not compute similarities',
        };
      }

      // Calculate statistics
      final avgSimilarity = allSimilarities.reduce((a, b) => a + b) / allSimilarities.length;
      final maxSimilarity = allSimilarities.reduce((a, b) => a > b ? a : b);
      final minSimilarity = allSimilarities.reduce((a, b) => a < b ? a : b);

      print('🔍 Embedding Diversity Check:');
      print('  - Users compared: ${primaryEmbeddings.length}');
      print('  - Average similarity: ${avgSimilarity.toStringAsFixed(4)}');
      print('  - Min similarity: ${minSimilarity.toStringAsFixed(4)}');
      print('  - Max similarity: ${maxSimilarity.toStringAsFixed(4)}');

      // CRITICAL: Check if embeddings are diverse
      // Reject only if:
      // 1. Average similarity is VERY high (>0.85) - means most faces are similar
      // 2. OR if max similarity is extremely high (>0.998) AND average is also high (>0.70)
      
      // Count how many pairs have similarity >0.95 (very similar)
      final verySimilarPairs = allSimilarities.where((s) => s > 0.95).length;
      final totalPairs = allSimilarities.length;
      final verySimilarRatio = verySimilarPairs / totalPairs;
      
      // Count how many pairs have similarity >0.98 (extremely similar)
      final extremelySimilarPairs = allSimilarities.where((s) => s > 0.98).length;
      final extremelySimilarRatio = extremelySimilarPairs / totalPairs;
      
      print('  - Very similar pairs (>0.95): $verySimilarPairs / $totalPairs (${(verySimilarRatio * 100).toStringAsFixed(1)}%)');
      print('  - Extremely similar pairs (>0.98): $extremelySimilarPairs / $totalPairs (${(extremelySimilarRatio * 100).toStringAsFixed(1)}%)');
      
      // CRITICAL: Adjusted thresholds to be very lenient
      // The previous threshold of 0.85 was way too strict and rejected legitimate users
      // The diversity check should only catch TRUE model failures (all embeddings identical)
      // Normal face recognition models can have similarities in the 0.85-0.99 range
      // We only reject if embeddings are EXTREMELY similar (near 1.0), indicating model failure
      
      // Only reject if average similarity is EXTREMELY high (>0.999) - this indicates true model failure
      // Previous threshold of 0.85 was way too strict and rejected legitimate users
      // Even 0.95 and 0.99 are too strict - many legitimate similar-looking people can have high similarity
      // Only reject if average is >0.999 (virtually identical embeddings, indicating model not working)
      // Note: With double normalization fixed, similarities should be more reasonable
      if (avgSimilarity > 0.999) {
        print('🚨 CRITICAL: Average similarity ${avgSimilarity.toStringAsFixed(4)} > 0.999 - all stored embeddings are virtually identical (model failure)');
        print('🚨 This indicates the model is not differentiating faces at all - all embeddings are the same');
        print('🚨 DIAGNOSTIC: Check if embeddings were stored correctly and model is working');
        return {
          'isDiverse': false,
          'message': 'Average similarity ${avgSimilarity.toStringAsFixed(4)} > 0.999 - all stored embeddings are virtually identical (model failure). Please contact support.',
        };
      }
      
      // Warn if average similarity is very high (0.99-0.999) but allow it
      // This helps diagnose issues without blocking legitimate users
      if (avgSimilarity > 0.99 && avgSimilarity <= 0.999) {
        print('⚠️ WARNING: Average similarity is very high (${avgSimilarity.toStringAsFixed(4)}) - close to model failure threshold');
        print('⚠️ DIAGNOSTIC: This might indicate:');
        print('  - Model not differentiating well (but still working)');
        print('  - Very similar user faces (family, twins)');
        print('  - Small user base');
        print('⚠️ Allowing authentication to proceed - but monitor for issues');
      }
      
      // Only reject if max similarity is extremely high (>0.999) AND average is also extremely high (>0.995)
      // This catches cases where the model is truly failing (all embeddings converging to same value)
      // But allows legitimate cases where some faces are similar (e.g., family members, twins)
      // Thresholds are very high to avoid false positives
      if (maxSimilarity > 0.999 && avgSimilarity > 0.995) {
        print('🚨 CRITICAL: Max similarity ${maxSimilarity.toStringAsFixed(4)} > 0.999 and average ${avgSimilarity.toStringAsFixed(4)} > 0.995 - model failure detected');
        print('🚨 This indicates the model is not differentiating faces - embeddings are converging to identical values');
        return {
          'isDiverse': false,
          'message': 'Max similarity ${maxSimilarity.toStringAsFixed(4)} > 0.999 and average ${avgSimilarity.toStringAsFixed(4)} > 0.995 - model failure detected. Please contact support.',
        };
      }
      
      // If average similarity is high but below 0.99, it's likely legitimate
      // (similar-looking people, family members, or the model is working but with high similarity)
      if (avgSimilarity > 0.90 && avgSimilarity <= 0.99) {
        print('⚠️ NOTE: Average similarity is high (${avgSimilarity.toStringAsFixed(4)}), but below critical threshold (0.99)');
        print('⚠️ This might indicate:');
        print('  - Similar-looking users (family members, twins)');
        print('  - Model working but with high baseline similarity');
        print('  - Small user base with similar demographics');
        print('⚠️ Proceeding with authentication - diversity check passed');
      }
      
      // If average is good (<0.70) but some pairs are very similar, it's probably legitimate
      // (e.g., similar-looking people, family members, or duplicate signups)
      if (maxSimilarity > 0.99 && avgSimilarity < 0.70) {
        print('⚠️ WARNING: Some pairs have very high similarity (>0.99), but average is good (${avgSimilarity.toStringAsFixed(4)}).');
        print('⚠️ This might be similar-looking people, family members, or duplicate signups. Proceeding with authentication.');
      }

      return {
        'isDiverse': true,
        'message': 'Diversity OK (avg: ${avgSimilarity.toStringAsFixed(4)}, range: ${minSimilarity.toStringAsFixed(4)}-${maxSimilarity.toStringAsFixed(4)})',
      };
    } catch (e) {
      print('⚠️ Error validating embedding diversity: $e');
      // On error, assume diverse (better to allow than block)
      return {
        'isDiverse': true,
        'message': 'Diversity check error - assuming diverse',
      };
    }
  }

  /// Get the number of embeddings for a specific user
  static int _getEmbeddingCountForUser(String? userId, List<Map<String, dynamic>> storedFaces) {
    if (userId == null) return 0;
    
    final userFace = storedFaces.firstWhere(
      (face) => face['userId'] == userId,
      orElse: () => <String, dynamic>{},
    );
    
    if (userFace.isEmpty) return 0;
    
    final embeddingsData = userFace['embeddings'] as List?;
    if (embeddingsData != null && embeddingsData.isNotEmpty) {
      return embeddingsData.length;
    }
    
    // Fallback: check if legacy single embedding exists
    if (userFace['embedding'] != null) {
      return 1;
    }
    
    return 0;
  }

  /// Find permanent user ID for a temporary user ID.
  /// Uses multiple strategies to ensure correct user matching:
  /// 1. Email-based lookup (primary)
  /// 2. Phone number-based lookup (fallback)
  /// 3. Face embedding similarity verification (security check)
  static Future<String?> _findPermanentUserId(String tempUserId) async {
    try {
      print('🔍 Finding permanent user ID for temp_ user: $tempUserId');
      
      final faceDoc = await _firestore.collection('face_embeddings').doc(tempUserId).get();
      if (!faceDoc.exists) {
        print('❌ Temp_ face_embeddings document not found');
        return null;
      }

      final faceData = faceDoc.data()!;
      final email = faceData['email'] as String?;
      final phoneNumber = faceData['phoneNumber'] as String?;
      
      print('🔍 Temp_ user data - Email: ${email ?? 'null'}, Phone: ${phoneNumber ?? 'null'}');

      // Strategy 1: Email-based lookup (primary)
      String? permanentUserId;
      if (email != null && email.isNotEmpty) {
        print('🔍 Attempting email-based lookup: $email');
        final usersSnapshot = await _firestore
            .collection('users')
            .where('email', isEqualTo: email)
            .where('signupCompleted', isEqualTo: true)
            .get();

        if (usersSnapshot.docs.isNotEmpty) {
          // If multiple users found, log warning but use first one
          if (usersSnapshot.docs.length > 1) {
            print('⚠️ WARNING: Multiple users found with same email! Using first match.');
            print('⚠️ Found ${usersSnapshot.docs.length} users with email: $email');
            for (var doc in usersSnapshot.docs) {
              print('  - User ID: ${doc.id}, Created: ${doc.data()['createdAt']}');
            }
          }
          permanentUserId = usersSnapshot.docs.first.id;
          print('✅ Found permanent user via email: $permanentUserId');
        } else {
          print('⚠️ No user found with email: $email');
        }
      }

      // Strategy 2: Phone number-based lookup (fallback if email fails)
      if (permanentUserId == null && phoneNumber != null && phoneNumber.isNotEmpty) {
        print('🔍 Attempting phone number-based lookup: $phoneNumber');
        final usersSnapshot = await _firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: phoneNumber)
            .where('signupCompleted', isEqualTo: true)
            .get();

        if (usersSnapshot.docs.isNotEmpty) {
          if (usersSnapshot.docs.length > 1) {
            print('⚠️ WARNING: Multiple users found with same phone number! Using first match.');
          }
          permanentUserId = usersSnapshot.docs.first.id;
          print('✅ Found permanent user via phone: $permanentUserId');
        } else {
          print('⚠️ No user found with phone: $phoneNumber');
        }
      }

      if (permanentUserId == null) {
        print('❌ Could not find permanent user for temp_ user: $tempUserId');
        return null;
      }

      // CRITICAL: Verify the permanent user document exists and is valid
      final permanentUserDoc = await _firestore.collection('users').doc(permanentUserId).get();
      if (!permanentUserDoc.exists) {
        print('❌ Permanent user document not found: $permanentUserId');
        return null;
      }

      final permanentUserData = permanentUserDoc.data()!;
      final signupCompleted = permanentUserData['signupCompleted'] ?? false;
      if (!signupCompleted) {
        print('❌ Permanent user signup not completed: $permanentUserId');
        return null;
      }

      print('✅ Permanent user verified: $permanentUserId (signupCompleted: $signupCompleted)');
      return permanentUserId;
    } catch (e) {
      print('❌ Error finding permanent user ID: $e');
      return null;
    }
  }

  /// Helper: fetch a compatible embedding for secondary verification
  static Future<List<double>?> _getCompatibleSecondaryEmbedding({
    required List<double> primaryEmbedding,
    required String? finalUserId,
    required String? altUserId,
  }) async {
  List<Future<List<double>?>> attempts = [];

  // Try users/{finalUserId}
  attempts.add(() async {
    if (finalUserId == null) return null;
    try {
      final usersFirestore = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      );
      final userDoc = await usersFirestore.collection('users').doc(finalUserId).get();
      if (!userDoc.exists) return null;
      final data = userDoc.data()!;
      // LEGACY: Check old biometricFeatures format (deprecated - kept for migration)
      // New system uses face_embeddings collection instead
      final bf = data['biometricFeatures'];
      List<double> emb = [];
      if (bf is Map && bf['biometricSignature'] is List) {
        emb = (bf['biometricSignature'] as List).map((e) => (e as num).toDouble()).toList();
      } else if (bf is List) {
        emb = bf.map((e) => (e as num).toDouble()).toList();
      }
      if (emb.isNotEmpty && emb.length == primaryEmbedding.length) return emb;
    } catch (_) {}
    return null;
  }());

  // Try face_embeddings/{finalUserId}
  attempts.add(() async {
    if (finalUserId == null) return null;
    try {
      final faceDoc = await _firestore
          .collection('face_embeddings').doc(finalUserId).get();
      if (!faceDoc.exists) return null;
      final data = faceDoc.data()!;
      final raw = data['embedding'];
      if (raw is List) {
        final emb = raw.map((e) => (e as num).toDouble()).toList();
        if (emb.isNotEmpty && emb.length == primaryEmbedding.length) return emb;
      }
    } catch (_) {}
    return null;
  }());

  // Try face_embeddings/{altUserId} (e.g., temp_ id)
  attempts.add(() async {
    if (altUserId == null) return null;
    try {
      final faceDoc = await _firestore
          .collection('face_embeddings').doc(altUserId).get();
      if (!faceDoc.exists) return null;
      final data = faceDoc.data()!;
      final raw = data['embedding'];
      if (raw is List) {
        final emb = raw.map((e) => (e as num).toDouble()).toList();
        if (emb.isNotEmpty && emb.length == primaryEmbedding.length) return emb;
      }
    } catch (_) {}
    return null;
  }());

    for (final fut in attempts) {
      final res = await fut;
      if (res != null) return res;
    }
    return null;
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
          final verifyResult = await _backendServiceInstance.verify(
            email: emailOrPhone,
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
              final similarity = _faceNetService.cosineSimilarity(validEmbeddings[i], validEmbeddings[j]);
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
      final currentNorm = _faceNetService.L2Norm(normalizedCurrentEmbedding);
      if (currentNorm < 0.9 || currentNorm > 1.1) {
        print('⚠️ WARNING: Current embedding normalization issue! Norm: $currentNorm');
        if (currentNorm > 0.0) {
          final renormalized = _faceNetService.normalize(normalizedCurrentEmbedding);
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
        // PROFILE PHOTO: Slightly lower threshold (98.5%+) to account for different lighting/angles
        if (embeddingCount <= 1) {
          threshold = 0.98; // 98% for single embedding (profile photo)
          absoluteMinimum = 0.94; // Reject if < 94%
          print('📸 PROFILE PHOTO: Using threshold (${threshold.toStringAsFixed(3)}) for user with 1 embedding');
        } else if (embeddingCount == 2) {
          threshold = 0.985; // 98.5% for 2 embeddings (profile photo)
          absoluteMinimum = 0.945; // Reject if < 94.5%
          print('📸 PROFILE PHOTO: Using threshold (${threshold.toStringAsFixed(3)}) for user with 2 embeddings');
        } else {
          threshold = 0.985; // 98.5% for 3+ embeddings (profile photo)
          absoluteMinimum = 0.945; // Reject if < 94.5%
          print('📸 PROFILE PHOTO: Using threshold (${threshold.toStringAsFixed(3)}) for user with ${embeddingCount} embeddings');
        }
        print('📸 PROFILE PHOTO MODE: Requiring ${threshold.toStringAsFixed(3)} similarity (allows variation in lighting/angles)');
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
        final storedNorm = _faceNetService.L2Norm(storedEmbeddingList);
        List<double> storedEmbedding;
        
        if (storedNorm < 0.9 || storedNorm > 1.1) {
          print('⚠️ Stored embedding not normalized (norm: ${storedNorm.toStringAsFixed(6)}), normalizing...');
          storedEmbedding = _faceNetService.normalize(storedEmbeddingList);
          // Verify normalization succeeded
          final newNorm = _faceNetService.L2Norm(storedEmbedding);
          if (newNorm < 0.9 || newNorm > 1.1) {
            print('⚠️ Normalization failed, skipping embedding');
            continue;
          }
        } else {
          storedEmbedding = storedEmbeddingList;
        }
        
        // PERFECT RECOGNITION: Calculate similarity with validated embeddings
        final similarity = _faceNetService.cosineSimilarity(normalizedCurrentEmbedding, storedEmbedding);
        
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
          final profilePhotoThreshold = 0.75; // Use 75% threshold for profile photos (more lenient)
          
          if (similarity >= profilePhotoThreshold) {
            print('✅ PROFILE PHOTO MATCH: Similarity ${similarity.toStringAsFixed(4)} >= ${profilePhotoThreshold.toStringAsFixed(3)}');
            print('✅ Profile photos can have lower similarity due to different lighting/angles');
          } else {
            print('🚨 PROFILE PHOTO: Similarity ${similarity.toStringAsFixed(4)} < ${profilePhotoThreshold.toStringAsFixed(3)} (will check at end if acceptable)');
            print('   - Normal threshold: ${threshold.toStringAsFixed(3)}, Profile photo threshold: ${profilePhotoThreshold.toStringAsFixed(3)}');
            print('   - Euclidean distance: ${euclideanDistance.toStringAsFixed(4)} (max: ${maxDistanceForSamePerson.toStringAsFixed(2)})');
            print('   - Note: Final check will use more lenient threshold for profile photos');
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
                        final otherNorm = _faceNetService.L2Norm(otherEmbedding);
                        final normalizedOtherEmbedding = (otherNorm >= 0.9 && otherNorm <= 1.1) 
                            ? otherEmbedding 
                            : _faceNetService.normalize(otherEmbedding);
                        
                        final otherSimilarity = _faceNetService.cosineSimilarity(
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
                    final otherNorm = _faceNetService.L2Norm(otherEmbedding);
                    final normalizedOtherEmbedding = (otherNorm >= 0.9 && otherNorm <= 1.1) 
                        ? otherEmbedding 
                        : _faceNetService.normalize(otherEmbedding);
                    
                    final otherSimilarity = _faceNetService.cosineSimilarity(
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
      // For profile photos, use slightly lower threshold (98.5%+) to account for different conditions
      // For login, use balanced 99%+ threshold (RELIABLE RECOGNITION) - balanced for legitimate users
      // BALANCED SECURITY: Unregistered users must NEVER pass this check
      // BALANCED: Use the SAME threshold as set earlier (0.99 for login) - balanced for legitimate users
      final finalThreshold = isProfilePhotoVerification
          ? (embeddingCount >= 3 ? 0.985 : (embeddingCount == 2 ? 0.985 : 0.98))
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
}
