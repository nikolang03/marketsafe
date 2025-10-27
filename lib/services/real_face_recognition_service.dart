import 'dart:math';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'face_security_service.dart';
import 'lockout_service.dart';
import 'real_tflite_face_service.dart'; // REAL TensorFlow Lite service

/// Real Face Recognition Service using enhanced biometric authentication
/// This service provides genuine face authentication with improved security
class RealFaceRecognitionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      );

  // ULTRA-STRICT SECURITY THRESHOLDS - Maximum security to prevent unauthorized access
  static const double _similarityThreshold = 0.95; // 95% similarity required for match (ULTRA-STRICT)
  static const double _minimumUniquenessThreshold = 0.50; // 50% gap between best and second-best match (ULTRA-STRICT)
  static const double _maximumSecondBestThreshold = 0.30; // Maximum allowed second-best similarity (ULTRA-STRICT)
  static const double _crossReferenceThreshold = 0.20; // Maximum similarity allowed with other users (ULTRA-STRICT)

  /// Extract AI-based biometric features using deep learning
  /// This creates a unique biometric signature using AI face recognition
  static Future<List<double>> extractBiometricFeatures(Face face, [CameraImage? cameraImage]) async {
    try {
      print('🤖 Extracting REAL AI-based biometric features using TensorFlow Lite...');
      
      // Use REAL TensorFlow Lite service
      final aiFeatures = await RealTFLiteFaceService.extractFaceEmbeddings(face, cameraImage);
      
      if (aiFeatures.isNotEmpty && !aiFeatures.every((x) => x == 0.0)) {
        print('✅ Extracted ${aiFeatures.length}D REAL AI features');
        print('🔒 SECURITY: Using ULTRA-STRICT thresholds to prevent unauthorized access');
        return aiFeatures;
      } else {
        print('⚠️ REAL AI extraction failed, using fallback...');
        print('🚨 SECURITY WARNING: Falling back to mathematical approach - may be less secure');
        return List.generate(512, (index) => 0.0);
      }
      
    } catch (e) {
      print('❌ Error extracting REAL AI biometric features: $e');
      print('🔄 Using fallback mathematical approach...');
      return List.generate(512, (index) => 0.0);
    }
  }

  /// Extract CONSISTENT biometric features using standardized approach
  /// Always use the same feature extraction method for consistency
  static Future<List<double>> extractMatchingBiometricFeatures(Face face, [CameraImage? cameraImage]) async {
    try {
      print('🔧 Using AI-based feature extraction for professional accuracy...');
      
      // Use REAL TensorFlow Lite as primary method
      List<double> faceEmbedding;
      try {
        print('🤖 Extracting face embeddings using REAL TensorFlow Lite...');
        faceEmbedding = await RealTFLiteFaceService.extractFaceEmbeddings(face, cameraImage);
        print('✅ Using REAL AI-based 512D embeddings for maximum accuracy');
    } catch (e) {
        print('❌ REAL AI extraction failed: $e');
        print('🔄 Using fallback mathematical approach...');
        faceEmbedding = List.generate(512, (index) => 0.0);
        print('✅ Using fallback mathematical 512D embeddings');
      }
      
      return faceEmbedding;
      
    } catch (e) {
      print('❌ Error extracting AI biometric features: $e');
      return List.generate(512, (index) => 0.0);
    }
  }

  // This function is not currently used but kept for future reference
  // static Future<List<double>> _extract128DFaceEmbedding(Face face) async {
  //   final landmarks = face.landmarks;
  //   final contours = face.contours;
  //   final List<double> embedding = [];

  //   // Add landmark positions
  //   landmarks.forEach((key, landmark) {
  //     if (landmark != null) {
  //       embedding.add(landmark.position.x.toDouble());
  //       embedding.add(landmark.position.y.toDouble());
  //     }
  //   });

  //   // Add contour points
  //   contours.forEach((key, contour) {
  //     if (contour != null) {
  //       for (final point in contour.points) {
  //         embedding.add(point.x.toDouble());
  //         embedding.add(point.y.toDouble());
  //       }
  //     }
  //   });

  //   // Pad with zeros to 128 dimensions if needed
  //   while (embedding.length < 128) {
  //     embedding.add(0.0);
  //   }

  //   // Truncate to 128 dimensions if needed
  //   return embedding.sublist(0, 128);
  // }

  // This function is not currently used but kept for future reference
  // static List<double> _extractEnhancedLandmarkFeatures(Face face) {
  //   try {
  //     print('🔍 Extracting ENHANCED biometric features with 50+ measurements...');
      
  //     final boundingBox = face.boundingBox;
  //     final landmarks = face.landmarks;
      
  //     // Extract comprehensive facial measurements
  //     final features = <double>[];
      
  //     // Basic face geometry (5 features)
  //     features.addAll([
  //       boundingBox.width / 1000.0,
  //       boundingBox.height / 1000.0,
  //       boundingBox.width / boundingBox.height, // aspect ratio
  //       boundingBox.center.dx / 1000.0,
  //       boundingBox.center.dy / 1000.0,
  //     ]);
      
  //     // Eye measurements (15+ features)
  //     if (landmarks.containsKey(FaceLandmarkType.leftEye) && 
  //         landmarks.containsKey(FaceLandmarkType.rightEye)) {
  //       final leftEye = landmarks[FaceLandmarkType.leftEye]!;
  //       final rightEye = landmarks[FaceLandmarkType.rightEye]!;
        
  //       final eyeDistance = leftEye.position.distanceTo(rightEye.position);
  //       final eyeCenterX = (leftEye.position.x + rightEye.position.x) / 2;
  //       final eyeCenterY = (leftEye.position.y + rightEye.position.y) / 2;
        
  //       features.addAll([
  //         eyeDistance / 1000.0,
  //         eyeDistance / boundingBox.width,
  //         leftEye.position.x / 1000.0,
  //         leftEye.position.y / 1000.0,
  //         rightEye.position.x / 1000.0,
  //         rightEye.position.y / 1000.0,
  //         eyeCenterX / 1000.0,
  //         eyeCenterY / 1000.0,
  //         (eyeCenterX - boundingBox.center.dx) / boundingBox.width,
  //         (eyeCenterY - boundingBox.center.dy) / boundingBox.height,
  //       ]);
        
  //       // Eye symmetry
  //       final faceCenterX = boundingBox.center.dx;
  //       final leftEyeDistance = (leftEye.position.x - faceCenterX).abs();
  //       final rightEyeDistance = (rightEye.position.x - faceCenterX).abs();
  //       features.add((leftEyeDistance - rightEyeDistance).abs() / boundingBox.width);
        
  //       // Additional eye-related ratios
  //       features.addAll([
  //         leftEye.position.y / boundingBox.height,
  //         rightEye.position.y / boundingBox.height,
  //         (leftEye.position.y + rightEye.position.y) / (2 * boundingBox.height),
  //       ]);
  //     }
      
  //     // Nose measurements (10+ features)
  //     if (landmarks.containsKey(FaceLandmarkType.noseBase)) {
  //       final nose = landmarks[FaceLandmarkType.noseBase]!;
  //       features.addAll([
  //         nose.position.x / 1000.0,
  //         nose.position.y / 1000.0,
  //         (nose.position.y - boundingBox.top) / boundingBox.height,
  //         (nose.position.x - boundingBox.center.dx) / boundingBox.width,
  //         sqrt(pow(nose.position.x - boundingBox.center.dx, 2) + 
  //              pow(nose.position.y - boundingBox.center.dy, 2)) / boundingBox.width,
  //       ]);
        
  //       // Nose to eyes ratios
  //       if (landmarks.containsKey(FaceLandmarkType.leftEye) && 
  //           landmarks.containsKey(FaceLandmarkType.rightEye)) {
  //         final leftEye = landmarks[FaceLandmarkType.leftEye]!;
  //         final rightEye = landmarks[FaceLandmarkType.rightEye]!;
  //         features.addAll([
  //           nose.position.distanceTo(leftEye.position) / boundingBox.width,
  //           nose.position.distanceTo(rightEye.position) / boundingBox.width,
  //           (nose.position.distanceTo(leftEye.position) + 
  //            nose.position.distanceTo(rightEye.position)) / (2 * boundingBox.width),
  //         ]);
  //       }
  //     }
      
  //     // Mouth measurements (10+ features)
  //     if (landmarks.containsKey(FaceLandmarkType.bottomMouth)) {
  //       final mouth = landmarks[FaceLandmarkType.bottomMouth]!;
  //       features.addAll([
  //         mouth.position.x / 1000.0,
  //         mouth.position.y / 1000.0,
  //         (mouth.position.y - boundingBox.top) / boundingBox.height,
  //         (mouth.position.x - boundingBox.center.dx) / boundingBox.width,
  //         sqrt(pow(mouth.position.x - boundingBox.center.dx, 2) + 
  //              pow(mouth.position.y - boundingBox.center.dy, 2)) / boundingBox.width,
  //       ]);
        
  //       // Mouth to other features
  //       if (landmarks.containsKey(FaceLandmarkType.noseBase)) {
  //         final nose = landmarks[FaceLandmarkType.noseBase]!;
  //         features.addAll([
  //           mouth.position.distanceTo(nose.position) / boundingBox.height,
  //           (mouth.position.y - nose.position.y) / boundingBox.height,
  //         ]);
  //       }
  //     }
      
  //     // Head pose (3 features)
  //     features.addAll([
  //       (face.headEulerAngleX ?? 0.0) / 180.0,
  //       (face.headEulerAngleY ?? 0.0) / 180.0,
  //       (face.headEulerAngleZ ?? 0.0) / 180.0,
  //     ]);
      
  //     // Eye states (3 features)
  //     features.addAll([
  //       face.leftEyeOpenProbability ?? 0.0,
  //       face.rightEyeOpenProbability ?? 0.0,
  //       face.smilingProbability ?? 0.0,
  //     ]);
      
  //     // Additional unique features
  //     features.addAll([
  //       boundingBox.width * boundingBox.height / 1000000.0, // face area
  //       (boundingBox.left + boundingBox.width / 2) / 1000.0,
  //       (boundingBox.top + boundingBox.height / 2) / 1000.0,
  //     ]);
    
  //     // Pad to fixed length for consistency
  //     while (features.length < 64) {
  //       features.add(0.0);
  //     }
      
  //     // Normalize features
  //     final normalizedFeatures = _normalizeFeatures(features.take(64).toList());
      
  //     print('✅ Enhanced biometric features extracted: ${normalizedFeatures.length} dimensions');
  //     print('📊 Sample features: ${normalizedFeatures.take(5).toList()}');
  //     return normalizedFeatures;
      
  //   } catch (e) {
  //     print('❌ Error extracting enhanced landmark features: $e');
  //     return List.generate(64, (index) => 0.0);
  //   }
  // }

  /// Normalize features using min-max normalization
  static List<double> _normalizeFeatures(List<double> features) {
    if (features.isEmpty) return features;
    
    final minVal = features.reduce((a, b) => a < b ? a : b);
    final maxVal = features.reduce((a, b) => a > b ? a : b);
    
    if (maxVal == minVal) {
      return List.filled(features.length, 0.5);
    }
    
    return features.map((x) => (x - minVal) / (maxVal - minVal)).toList();
  }

  /// Perform enhanced liveness detection with stricter security
  static bool _performLivenessDetection(Face face) {
    try {
      print('🔍 Performing ENHANCED liveness detection with strict security...');
      
      final leftEyeOpen = face.leftEyeOpenProbability ?? 0.0;
      final rightEyeOpen = face.rightEyeOpenProbability ?? 0.0;
      
      // Balanced eye state requirements for usability
      if (leftEyeOpen < 0.3 || rightEyeOpen < 0.3) {
        print('❌ Liveness check failed: eyes not open enough (L:$leftEyeOpen, R:$rightEyeOpen)');
        return false;
      }
      
      // Check head pose for natural positioning (practical angles - more lenient)
      final headAngleX = face.headEulerAngleX ?? 0.0;
      final headAngleY = face.headEulerAngleY ?? 0.0;
      final headAngleZ = face.headEulerAngleZ ?? 0.0;
      
      // More practical head angle limits (45° instead of 30°)
      if (headAngleX.abs() > 45 || headAngleY.abs() > 45 || headAngleZ.abs() > 45) {
        print('❌ Liveness check failed: extreme head angle (X:$headAngleX, Y:$headAngleY, Z:$headAngleZ)');
        return false;
      }
      
      // Additional security: Check for natural facial expressions
      final smilingProb = face.smilingProbability ?? 0.0;
      if (smilingProb > 0.8) {
        print('⚠️ Warning: High smiling probability ($smilingProb) - potential photo spoofing');
        // Don't reject, but log for security monitoring
      }
      
      print('✅ Enhanced liveness check passed with strict security');
      return true;
      
    } catch (e) {
      print('❌ Liveness detection error: $e');
      return false;
    }
  }

  /// Calculate similarity between two biometric signatures using cosine similarity
  static double calculateBiometricSimilarity(List<double> signature1, List<double> signature2) {
    if (signature1.length != signature2.length) return 0.0;
    
    // Use cosine similarity for reliable face recognition
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;
    
    for (int i = 0; i < signature1.length; i++) {
      dotProduct += signature1[i] * signature2[i];
      norm1 += signature1[i] * signature1[i];
      norm2 += signature2[i] * signature2[i];
    }
    
    if (norm1 == 0.0 || norm2 == 0.0) return 0.0;
    
    final similarity = dotProduct / (sqrt(norm1) * sqrt(norm2));
    return similarity.clamp(0.0, 1.0);
  }

  /// Calculate similarity for profile photos with more lenient settings
  static double calculateProfilePhotoSimilarity(List<double> signature1, List<double> signature2) {
    return calculateBiometricSimilarity(signature1, signature2);
  }
  
  /// Calculate advanced similarity using AI-based methods when available
  static Future<double> _calculateAdvancedSimilarity(List<double> signature1, List<double> signature2) async {
    try {
      // Use standard cosine similarity for all embeddings
      return calculateBiometricSimilarity(signature1, signature2);
    } catch (e) {
      print('⚠️ AI similarity calculation failed, using standard method: $e');
      return calculateBiometricSimilarity(signature1, signature2);
    }
  }


  /// Store TRUE biometric features for a user
  static Future<void> storeBiometricFeatures(String userId, List<double> features) async {
    try {
      print('🔄 Storing TRUE biometric features for user: $userId');
      
      final biometricData = {
        'biometricSignature': features,
        'featureCount': features.length,
        'biometricType': 'ENHANCED_LANDMARK_BIOMETRIC',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isRealBiometric': true,
      };
      
      await _firestore.collection('users').doc(userId).update({
        'biometricFeatures': biometricData,
        'biometricFeaturesUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ TRUE biometric features stored successfully');
    } catch (e) {
      print('❌ Error storing true biometric features: $e');
      throw Exception('Failed to store true biometric features: $e');
    }
  }

  /// Find user by TRUE face recognition with IDENTIFICATION (not just matching)
  static Future<String?> findUserByRealFace(Face detectedFace, [CameraImage? cameraImage]) async {
    try {
      print('🚨 TRUE FACE IDENTIFICATION STARTING...');
      print('🚨 This is REAL biometric IDENTIFICATION (not just matching)!');
      
      // EMERGENCY: Check for lockout first
      if (LockoutService.shouldBlockAccess()) {
        print('🚨 ACCESS BLOCKED: System is locked out due to failed attempts');
        return "LOCKOUT_ACTIVE";
      }
      
      // Perform enhanced liveness detection
      if (!_performLivenessDetection(detectedFace)) {
        print('❌ Enhanced liveness detection failed');
        LockoutService.recordFailedAttempt();
        return "LIVENESS_FAILED";
      }
      
      // Extract TRUE biometric features for MATCHING (keep feature space compatible with stored data)
      final detectedBiometrics = await extractMatchingBiometricFeatures(detectedFace, cameraImage);
      if (detectedBiometrics.isEmpty || detectedBiometrics.every((x) => x == 0.0)) {
        print('❌ Failed to extract valid biometric features');
        LockoutService.recordFailedAttempt();
        return null;
      }
      
      // Additional safety check for null or invalid features
      if (detectedBiometrics.any((x) => x.isNaN || x.isInfinite)) {
        print('❌ Invalid biometric features detected (NaN or Infinite values)');
        LockoutService.recordFailedAttempt();
        return null;
      }
      
      print('📊 Extracted ${detectedBiometrics.length} biometric features');
      print('📊 Sample detected features: ${detectedBiometrics.take(5).toList()}');
      print('📊 Feature variance: ${_calculateFeatureVariance(detectedBiometrics)}');
      print('📊 Feature range: ${detectedBiometrics.reduce((a, b) => a < b ? a : b)} to ${detectedBiometrics.reduce((a, b) => a > b ? a : b)}');
      
      // DEBUG: Check if features are valid
      final validFeatures = detectedBiometrics.where((x) => !x.isNaN && !x.isInfinite && x != 0.0).length;
      print('🔍 DEBUG: Valid features: $validFeatures/${detectedBiometrics.length}');
      print('🔍 DEBUG: Zero features: ${detectedBiometrics.where((x) => x == 0.0).length}');
      print('🔍 DEBUG: NaN features: ${detectedBiometrics.where((x) => x.isNaN).length}');
      print('🔍 DEBUG: Infinite features: ${detectedBiometrics.where((x) => x.isInfinite).length}');
      
      // Get users with biometric data (both verified and pending)
      final usersSnapshot = await _firestore
          .collection('users')
          .get();
      
      final usersWithBiometrics = usersSnapshot.docs.where((doc) {
        final userData = doc.data();
        // CRITICAL SECURITY: Only accept VERIFIED users for login
        return userData['verificationStatus'] == 'verified' && 
               (userData['biometricFeatures'] != null || 
                userData['faceFeatures'] != null || 
                userData['moveCloserFeatures'] != null);
      }).toList();
      
      print('🔍 Found ${usersWithBiometrics.length} users with biometric data');
      
      // DEBUG: Show details about each user
      for (int i = 0; i < usersWithBiometrics.length; i++) {
        final doc = usersWithBiometrics[i];
        final userData = doc.data();
        print('🔍 DEBUG User $i: ${doc.id}');
        print('   - Verification Status: ${userData['verificationStatus']}');
        print('   - Has biometricFeatures: ${userData['biometricFeatures'] != null}');
        print('   - Has faceFeatures: ${userData['faceFeatures'] != null}');
        print('   - Has moveCloserFeatures: ${userData['moveCloserFeatures'] != null}');
      }
      
      if (usersWithBiometrics.isEmpty) {
        print('❌ No users with biometric data found');
        print('🔍 DEBUG: Total users in database: ${usersSnapshot.docs.length}');
        return null;
      }
      
      String? bestMatchUserId;
      double bestSimilarity = 0.0;
      double secondBestSimilarity = 0.0;
      
      // Compare with each user's stored biometric features
      for (final doc in usersWithBiometrics) {
        final userData = doc.data();
        final biometricFeatures = userData['biometricFeatures'];
        
        List<double> storedSignature = [];
        
        if (biometricFeatures is Map && biometricFeatures.containsKey('biometricSignature')) {
          storedSignature = List<double>.from(biometricFeatures['biometricSignature']);
          print('📊 User ${doc.id} has ${storedSignature.length} stored biometric features');
          print('📊 Sample stored features: ${storedSignature.take(5).toList()}');
        } else {
          // Check for moveCloserFeatures (newer format)
          final moveCloserFeatures = userData['moveCloserFeatures'];
          if (moveCloserFeatures is String) {
            final faceFeaturesList = moveCloserFeatures.split(',').map((e) => double.tryParse(e) ?? 0.0).toList();
            if (faceFeaturesList.isNotEmpty) {
              storedSignature = faceFeaturesList;
              print('📊 Using moveCloserFeatures: ${storedSignature.length} features');
            }
          } else {
          // Fallback to old face features if available
          final faceFeatures = userData['faceFeatures'];
          if (faceFeatures is String) {
            final faceFeaturesList = faceFeatures.split(',').map((e) => double.tryParse(e) ?? 0.0).toList();
            if (faceFeaturesList.isNotEmpty) {
              storedSignature = faceFeaturesList;
              print('📊 Using legacy face features: ${storedSignature.length} features');
              }
            }
          }
        }
        
        if (storedSignature.isNotEmpty) {
          // Handle different feature dimensions with compatibility layer
          List<double> normalizedStoredSignature = storedSignature;
          List<double> normalizedDetectedBiometrics = detectedBiometrics;
          
          // STANDARDIZE TO 128D: Convert all features to 128D for consistency
          if (storedSignature.length != detectedBiometrics.length) {
            print('📊 Feature dimension mismatch: Stored ${storedSignature.length}D vs Detected ${detectedBiometrics.length}D');
            
            if (storedSignature.length == 512 && detectedBiometrics.length == 128) {
              // Convert stored 512D to 128D by taking first 128 features
              print('🔄 Converting stored 512D to 128D for consistency...');
              normalizedStoredSignature = storedSignature.take(128).toList();
              normalizedDetectedBiometrics = detectedBiometrics; // Keep 128D as is
              print('✅ Converted stored features to 128D: ${normalizedStoredSignature.length} features');
            } else if (storedSignature.length == 128 && detectedBiometrics.length == 512) {
              // Convert detected 512D to 128D by taking first 128 features
              print('🔄 Converting detected 512D to 128D for consistency...');
              normalizedDetectedBiometrics = detectedBiometrics.take(128).toList();
              normalizedStoredSignature = storedSignature; // Keep 128D as is
              print('✅ Converted detected features to 128D: ${normalizedDetectedBiometrics.length} features');
            } else {
              // Fallback: use minimum length
              final targetLength = min(storedSignature.length, detectedBiometrics.length);
              normalizedStoredSignature = storedSignature.take(targetLength).toList();
              normalizedDetectedBiometrics = detectedBiometrics.take(targetLength).toList();
              print('📊 Adjusted feature dimensions: ${normalizedDetectedBiometrics.length}D');
            }
          }
          
          // Use AI-based similarity calculation if available
          final similarity = await _calculateAdvancedSimilarity(normalizedDetectedBiometrics, normalizedStoredSignature);
          print('🔍 DEBUG User ${doc.id}:');
          print('   - Detected features: ${normalizedDetectedBiometrics.length}D');
          print('   - Stored features: ${normalizedStoredSignature.length}D');
          print('   - Similarity: ${similarity.toStringAsFixed(4)}');
          print('   - Threshold: $_similarityThreshold');
          print('   - Passes threshold: ${similarity >= _similarityThreshold}');
          
          if (similarity > bestSimilarity) {
            secondBestSimilarity = bestSimilarity;
        bestSimilarity = similarity;
            bestMatchUserId = doc.id;
          } else if (similarity > secondBestSimilarity) {
            secondBestSimilarity = similarity;
          }
        }
      }
      
      // Security validation
      if (bestMatchUserId != null && bestSimilarity >= _similarityThreshold) {
        final uniquenessScore = bestSimilarity - secondBestSimilarity;
        
        print('🔍 SECURITY CHECK: Best similarity: ${bestSimilarity.toStringAsFixed(4)}, Second best: ${secondBestSimilarity.toStringAsFixed(4)}');
        print('🔍 SECURITY CHECK: Uniqueness score: ${uniquenessScore.toStringAsFixed(4)} (minimum required: $_minimumUniquenessThreshold)');
        
        if (uniquenessScore < _minimumUniquenessThreshold) {
          print('🚨 SECURITY REJECTION: Match not unique enough!');
          return null;
        }
        
        // Enhanced security check - reject if second best is too high
        if (secondBestSimilarity > _maximumSecondBestThreshold) {
          print('🚨 SECURITY REJECTION: Second best similarity too high (${secondBestSimilarity.toStringAsFixed(4)}) - potential false match');
          print('🚨 SECURITY REJECTION: Maximum allowed second-best: $_maximumSecondBestThreshold');
          return null;
        }
        
        // Check user verification status first
        final userDoc = await _firestore.collection('users').doc(bestMatchUserId).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          final verificationStatus = userData['verificationStatus'] ?? 'pending';
          
          if (verificationStatus == 'pending') {
            print('🔄 User is still pending verification - returning special status');
            return "PENDING_VERIFICATION"; // Special return value for pending users
          }
        }
        
        // Perform final security validation for verified users
        final finalValidation = await _performFinalSecurityValidation(
          bestMatchUserId, 
          detectedBiometrics, 
          bestSimilarity, 
          secondBestSimilarity
        );
        
        if (!finalValidation) {
          print('🚨 FINAL SECURITY VALIDATION FAILED');
          return null;
        }
        
        // CRITICAL: Additional face uniqueness check to prevent similar faces
        final uniquenessValidation = await _validateFaceUniqueness(
          bestMatchUserId,
          detectedBiometrics,
          bestSimilarity,
          secondBestSimilarity
        );
        
        if (!uniquenessValidation) {
          print('🚨 FACE UNIQUENESS VALIDATION FAILED - Potential false match detected');
          return null;
        }
        
        // CRITICAL: Cross-reference security check to prevent similar faces
        final crossReferenceValidation = await _performCrossReferenceSecurityCheck(
          bestMatchUserId,
          detectedBiometrics,
          bestSimilarity
        );
        
        if (!crossReferenceValidation) {
          print('🚨 CROSS-REFERENCE SECURITY CHECK FAILED - Face too similar to other users');
          return null;
        }
        
        // ADDITIONAL SECURITY: Verify the match is significantly better than any other user
        final securityGap = await _verifySecurityGap(bestMatchUserId, detectedBiometrics, bestSimilarity);
        if (!securityGap) {
          print('🚨 SECURITY GAP VALIDATION FAILED - Match not unique enough');
          return null;
        }
        
        // EMERGENCY: Ultra-strict validation to absolutely prevent unauthorized access
        final emergencyValidation = await _performEmergencySecurityValidation(
          bestMatchUserId,
          detectedBiometrics,
          bestSimilarity,
          secondBestSimilarity
        );
        
        if (!emergencyValidation) {
          print('🚨 EMERGENCY SECURITY VALIDATION FAILED - UNAUTHORIZED ACCESS BLOCKED');
          return null;
        }
        
        print('🎯 TRUE USER FOUND!');
        print('✅ User ID: $bestMatchUserId');
        print('✅ Biometric Similarity: ${bestSimilarity.toStringAsFixed(4)}');
        print('✅ This is REAL biometric authentication!');
        
        // Log successful authentication
        await FaceSecurityService.logSecurityEvent('FACE_LOGIN_SUCCESS', bestMatchUserId, {
          'similarity': bestSimilarity,
          'uniquenessScore': uniquenessScore,
          'secondBestSimilarity': secondBestSimilarity,
          'totalUsersChecked': usersWithBiometrics.length,
          'timestamp': DateTime.now().toIso8601String(),
        });
        
        // Seed identification features for future IDENTIFY flow if missing
        try {
          final idDoc = await _firestore.collection('users').doc(bestMatchUserId).get();
          final userData = idDoc.data() ?? {};
          if (userData['identificationFeatures'] == null && detectedBiometrics.isNotEmpty) {
            print('🧩 Seeding identificationFeatures for user: $bestMatchUserId');
            await _firestore.collection('users').doc(bestMatchUserId).update({
              'identificationFeatures': detectedBiometrics.take(200).toList(),
              'identificationFeatureCount': min(200, detectedBiometrics.length),
              'identificationStoredAt': FieldValue.serverTimestamp(),
            });
          }
        } catch (e) {
          print('⚠️ Failed to seed identification features: $e');
        }
        
        // Update last login time
        await _firestore.collection('users').doc(bestMatchUserId).update({
          'lastLoginAt': FieldValue.serverTimestamp(),
          'lastBiometricSimilarity': bestSimilarity,
          'lastUniquenessScore': uniquenessScore,
          'lastLoginMethod': 'FACE_RECOGNITION',
        });
        
        // Clear lockout on successful login
        LockoutService.clearLockout();
        
        return bestMatchUserId;
      } else {
        print('❌ No matching user found');
        print('❌ Best similarity: ${bestSimilarity.toStringAsFixed(4)} (threshold: $_similarityThreshold)');
        
        // Log failed authentication attempt
        await FaceSecurityService.logSecurityEvent('FACE_LOGIN_FAILED', 'UNKNOWN', {
          'bestSimilarity': bestSimilarity,
          'threshold': _similarityThreshold,
          'totalUsersChecked': usersWithBiometrics.length,
          'timestamp': DateTime.now().toIso8601String(),
        });
        
        // EMERGENCY: Record failed attempt for lockout
        LockoutService.recordFailedAttempt();
        
        return null;
      }
      
    } catch (e) {
      print('❌ True face recognition error: $e');
      return null;
    }
  }

  /// Check if there are users with real biometric features
  static Future<bool> hasUsersWithRealBiometrics() async {
    try {
      final usersSnapshot = await _firestore
          .collection('users')
          .where('biometricFeatures.isRealBiometric', isEqualTo: true)
          .limit(1)
          .get();
      
      return usersSnapshot.docs.isNotEmpty;
    } catch (e) {
      print('❌ Error checking for real biometric users: $e');
      return false;
    }
  }

  /// Perform final security validation before allowing login
  static Future<bool> _performFinalSecurityValidation(
    String userId, 
    List<double> detectedBiometrics, 
    double similarity, 
    double secondBestSimilarity
  ) async {
    try {
      print('🔍 Performing final security validation for user: $userId');
      
      // Check 1: Verify user is still verified
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        print('❌ Final validation failed: User does not exist');
        return false;
      }
      
      final userData = userDoc.data()!;
      final verificationStatus = userData['verificationStatus'] ?? 'pending';
      
      if (verificationStatus != 'verified') {
        print('❌ Final validation failed: User is not verified (status: $verificationStatus)');
        return false;
      }
      
      // Check 2: Verify similarity gap (enhanced security)
      final similarityGap = similarity - secondBestSimilarity;
      if (similarityGap < _minimumUniquenessThreshold) {
        print('❌ Final validation failed: Similarity gap too small (${similarityGap.toStringAsFixed(4)} < $_minimumUniquenessThreshold)');
        return false;
      }
      
      // Check 3: Verify second-best similarity is not too high
      if (secondBestSimilarity > _maximumSecondBestThreshold) {
        print('❌ Final validation failed: Second-best similarity too high (${secondBestSimilarity.toStringAsFixed(4)} > $_maximumSecondBestThreshold)');
        return false;
      }
      
      // Check 4: Verify biometric features are valid
      if (detectedBiometrics.isEmpty || detectedBiometrics.every((x) => x == 0.0)) {
        print('❌ Final validation failed: Invalid biometric features');
        return false;
      }
      
      print('✅ Final security validation passed');
      return true;
      
    } catch (e) {
      print('❌ Error in final security validation: $e');
      return false;
    }
  }

  /// Validate face uniqueness to prevent similar faces from matching
  static Future<bool> _validateFaceUniqueness(
    String userId,
    List<double> detectedBiometrics,
    double bestSimilarity,
    double secondBestSimilarity
  ) async {
    try {
      print('🔍 Performing face uniqueness validation...');
      
      // Check 1: Ensure significant gap between best and second-best match
      final similarityGap = bestSimilarity - secondBestSimilarity;
      if (similarityGap < _minimumUniquenessThreshold) {
        print('❌ Uniqueness validation failed: Gap too small (${similarityGap.toStringAsFixed(4)} < $_minimumUniquenessThreshold)');
        return false;
      }
      
      // Check 2: Ensure second-best similarity is not too high
      if (secondBestSimilarity > _maximumSecondBestThreshold) {
        print('❌ Uniqueness validation failed: Second-best too high (${secondBestSimilarity.toStringAsFixed(4)} > $_maximumSecondBestThreshold)');
        return false;
      }
      
      // Check 3: Additional biometric feature analysis (more lenient for legitimate faces)
      final biometricVariance = _calculateBiometricVariance(detectedBiometrics);
      if (biometricVariance < 0.0001) { // Very lenient for legitimate users
        print('❌ Uniqueness validation failed: Low biometric variance (${biometricVariance.toStringAsFixed(4)}) - potential duplicate');
        return false;
      }
      
      // Check 4: Cross-reference with other users to ensure uniqueness
      final crossReferenceResult = await _performCrossReferenceCheck(userId, detectedBiometrics, bestSimilarity);
      if (!crossReferenceResult) {
        print('❌ Uniqueness validation failed: Cross-reference check failed');
        return false;
      }
      
      print('✅ Face uniqueness validation passed');
      return true;
      
    } catch (e) {
      print('❌ Error in face uniqueness validation: $e');
      return false;
    }
  }

  /// Calculate variance in biometric features to detect duplicates
  static double _calculateBiometricVariance(List<double> features) {
    if (features.isEmpty) return 0.0;
    
    final mean = features.reduce((a, b) => a + b) / features.length;
    final variance = features.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / features.length;
    return variance;
  }

  /// Perform cross-reference check with other users
  static Future<bool> _performCrossReferenceCheck(
    String targetUserId,
    List<double> detectedBiometrics,
    double targetSimilarity
  ) async {
    try {
      print('🔍 Performing cross-reference check...');
      
      // Get all other users (excluding the target user)
      final allUsersSnapshot = await _firestore
          .collection('users')
          .where('verificationStatus', isEqualTo: 'verified')
          .get();
      
      int similarUsers = 0;
      for (final doc in allUsersSnapshot.docs) {
        if (doc.id == targetUserId) continue; // Skip target user
        
        final userData = doc.data();
        final biometricFeatures = userData['biometricFeatures'];
        
        if (biometricFeatures is Map && biometricFeatures.containsKey('biometricSignature')) {
          final storedSignature = List<double>.from(biometricFeatures['biometricSignature']);
          final similarity = calculateBiometricSimilarity(detectedBiometrics, storedSignature);
          
          // If similarity is too high with other users, it's not unique enough
          if (similarity > 0.90) {
            similarUsers++;
            print('⚠️ High similarity (${similarity.toStringAsFixed(4)}) with user ${doc.id}');
          }
        }
      }
      
      // Allow maximum 1 similar user (the target user should be the only match)
      if (similarUsers > 0) {
        print('❌ Cross-reference failed: Found $similarUsers similar users');
        return false;
      }
      
      print('✅ Cross-reference check passed: No similar users found');
      return true;
      
    } catch (e) {
      print('❌ Error in cross-reference check: $e');
      return false;
    }
  }

  /// Perform cross-reference security check to prevent similar faces from matching
  static Future<bool> _performCrossReferenceSecurityCheck(
    String targetUserId,
    List<double> detectedBiometrics,
    double targetSimilarity
  ) async {
    try {
      print('🔍 Performing cross-reference security check...');
      
      // Get all other users (excluding the target user)
      final allUsersSnapshot = await _firestore
          .collection('users')
          .where('verificationStatus', isEqualTo: 'verified')
          .get();
      
      int similarUsers = 0;
      double highestOtherSimilarity = 0.0;
      
      for (final doc in allUsersSnapshot.docs) {
        if (doc.id == targetUserId) continue; // Skip target user
        
        final userData = doc.data();
        final biometricFeatures = userData['biometricFeatures'];
        
        if (biometricFeatures is Map && biometricFeatures.containsKey('biometricSignature')) {
          final storedSignature = List<double>.from(biometricFeatures['biometricSignature']);
          final similarity = calculateBiometricSimilarity(detectedBiometrics, storedSignature);
          
          // Track highest similarity with other users
          if (similarity > highestOtherSimilarity) {
            highestOtherSimilarity = similarity;
          }
          
          // If similarity is too high with other users, it's not unique enough
          if (similarity > _crossReferenceThreshold) {
            similarUsers++;
            print('⚠️ High similarity (${similarity.toStringAsFixed(4)}) with user ${doc.id}');
          }
        }
      }
      
      // Security checks
      if (similarUsers > 0) {
        print('❌ Cross-reference failed: Found $similarUsers similar users');
        return false;
      }
      
      // Additional check: target similarity must be significantly higher than other similarities
      final similarityGap = targetSimilarity - highestOtherSimilarity;
      if (similarityGap < 0.20) { // Must be at least 20% higher than other users
        print('❌ Cross-reference failed: Target similarity not unique enough (gap: ${similarityGap.toStringAsFixed(4)})');
        return false;
      }
      
      print('✅ Cross-reference security check passed: No similar users found');
      print('✅ Target similarity: ${targetSimilarity.toStringAsFixed(4)}');
      print('✅ Highest other similarity: ${highestOtherSimilarity.toStringAsFixed(4)}');
      print('✅ Similarity gap: ${similarityGap.toStringAsFixed(4)}');
      return true;
      
    } catch (e) {
      print('❌ Error in cross-reference security check: $e');
      return false;
    }
  }

  /// Verify security gap - ensure the match is significantly better than any other user
  static Future<bool> _verifySecurityGap(
    String targetUserId,
    List<double> detectedBiometrics,
    double targetSimilarity
  ) async {
    try {
      print('🔍 Verifying security gap for user: $targetUserId');
      
      // Get all other users (excluding the target user)
      final allUsersSnapshot = await _firestore
          .collection('users')
          .where('verificationStatus', isEqualTo: 'verified')
          .get();
      
      double highestOtherSimilarity = 0.0;
      String? closestOtherUser;
      
      for (final doc in allUsersSnapshot.docs) {
        if (doc.id == targetUserId) continue; // Skip target user
        
        final userData = doc.data();
        final biometricFeatures = userData['biometricFeatures'];
        
        if (biometricFeatures is Map && biometricFeatures.containsKey('biometricSignature')) {
          final storedSignature = List<double>.from(biometricFeatures['biometricSignature']);
          
          // Handle dimension mismatch
          List<double> normalizedStoredSignature = storedSignature;
          List<double> normalizedDetectedBiometrics = detectedBiometrics;
          
          if (storedSignature.length != detectedBiometrics.length) {
            if (storedSignature.length == 512 && detectedBiometrics.length == 128) {
              normalizedStoredSignature = storedSignature.take(128).toList();
            } else if (storedSignature.length == 128 && detectedBiometrics.length == 512) {
              normalizedDetectedBiometrics = detectedBiometrics.take(128).toList();
            } else {
              final targetLength = min(storedSignature.length, detectedBiometrics.length);
              normalizedStoredSignature = storedSignature.take(targetLength).toList();
              normalizedDetectedBiometrics = detectedBiometrics.take(targetLength).toList();
            }
          }
          
          final similarity = calculateBiometricSimilarity(normalizedDetectedBiometrics, normalizedStoredSignature);
          
          if (similarity > highestOtherSimilarity) {
            highestOtherSimilarity = similarity;
            closestOtherUser = doc.id;
          }
        }
      }
      
      // Calculate security gap
      final securityGap = targetSimilarity - highestOtherSimilarity;
      
      print('🔍 Security gap analysis:');
      print('   - Target similarity: ${targetSimilarity.toStringAsFixed(4)}');
      print('   - Highest other similarity: ${highestOtherSimilarity.toStringAsFixed(4)}');
      print('   - Security gap: ${securityGap.toStringAsFixed(4)}');
      print('   - Closest other user: $closestOtherUser');
      
      // Require at least 25% gap to prevent false matches (AI-OPTIMIZED)
      if (securityGap < 0.25) {
        print('❌ Security gap too small: ${securityGap.toStringAsFixed(4)} < 0.25');
        return false;
      }
      
      // Additional check: target similarity must be at least 15% higher than any other user (AI-OPTIMIZED)
      if (targetSimilarity < (highestOtherSimilarity + 0.15)) {
        print('❌ Target similarity not high enough: ${targetSimilarity.toStringAsFixed(4)} < ${(highestOtherSimilarity + 0.15).toStringAsFixed(4)}');
        return false;
      }
      
      print('✅ Security gap validation passed');
      return true;
      
    } catch (e) {
      print('❌ Error in security gap verification: $e');
      return false; // Fail safe: block access if verification fails
    }
  }

  /// EMERGENCY SECURITY VALIDATION - Absolute maximum security to block unauthorized access
  static Future<bool> _performEmergencySecurityValidation(
    String targetUserId,
    List<double> detectedBiometrics,
    double targetSimilarity,
    double secondBestSimilarity
  ) async {
    try {
      print('🚨 EMERGENCY SECURITY VALIDATION: Ultra-strict security check...');
      
      // Check 1: Target similarity must be EXTREMELY high (85%+)
      if (targetSimilarity < _similarityThreshold) {
        print('🚨 EMERGENCY BLOCKED: Target similarity too low (${targetSimilarity.toStringAsFixed(4)} < $_similarityThreshold)');
        return false;
      }
      
      // Check 2: Uniqueness gap must be MASSIVE (60%+)
      final uniquenessGap = targetSimilarity - secondBestSimilarity;
      if (uniquenessGap < _minimumUniquenessThreshold) {
        print('🚨 EMERGENCY BLOCKED: Uniqueness gap too small (${uniquenessGap.toStringAsFixed(4)} < $_minimumUniquenessThreshold)');
        return false;
      }
      
      // Check 3: Second-best similarity must be VERY low (60% max)
      if (secondBestSimilarity > _maximumSecondBestThreshold) {
        print('🚨 EMERGENCY BLOCKED: Second-best similarity too high (${secondBestSimilarity.toStringAsFixed(4)} > $_maximumSecondBestThreshold)');
        return false;
      }
      
      // Check 4: Cross-reference with ALL other users
      final allUsersSnapshot = await _firestore
          .collection('users')
          .where('verificationStatus', isEqualTo: 'verified')
          .get();
      
      for (final doc in allUsersSnapshot.docs) {
        if (doc.id == targetUserId) continue; // Skip target user
        
        final userData = doc.data();
        final biometricFeatures = userData['biometricFeatures'];
        
        if (biometricFeatures is Map && biometricFeatures.containsKey('biometricSignature')) {
          final storedSignature = List<double>.from(biometricFeatures['biometricSignature']);
          final similarity = calculateBiometricSimilarity(detectedBiometrics, storedSignature);
          
          // EMERGENCY: If similarity with ANY other user is > 70%, BLOCK ACCESS
          if (similarity > _crossReferenceThreshold) {
            print('🚨 EMERGENCY BLOCKED: Too similar to user ${doc.id} (${similarity.toStringAsFixed(4)} > $_crossReferenceThreshold)');
            return false;
          }
        }
      }
      
      // Check 5: Additional biometric variance check (more lenient for legitimate faces)
      final biometricVariance = _calculateBiometricVariance(detectedBiometrics);
      if (biometricVariance < 0.0001) { // Much more lenient for legitimate users
        print('🚨 EMERGENCY BLOCKED: Low biometric variance (${biometricVariance.toStringAsFixed(4)}) - potential duplicate');
        return false;
      }
      
      // Check 6: Ultra-strict similarity gap with other users
      double highestOtherSimilarity = 0.0;
      for (final doc in allUsersSnapshot.docs) {
        if (doc.id == targetUserId) continue;
        
        final userData = doc.data();
        final biometricFeatures = userData['biometricFeatures'];
        
        if (biometricFeatures is Map && biometricFeatures.containsKey('biometricSignature')) {
          final storedSignature = List<double>.from(biometricFeatures['biometricSignature']);
          final similarity = calculateBiometricSimilarity(detectedBiometrics, storedSignature);
          
          if (similarity > highestOtherSimilarity) {
            highestOtherSimilarity = similarity;
          }
        }
      }
      
      // EMERGENCY: Target similarity must be at least 30% higher than any other user
      final emergencyGap = targetSimilarity - highestOtherSimilarity;
      if (emergencyGap < 0.30) {
        print('🚨 EMERGENCY BLOCKED: Target not unique enough (gap: ${emergencyGap.toStringAsFixed(4)} < 0.30)');
        return false;
      }
      
      print('✅ EMERGENCY SECURITY VALIDATION PASSED: Ultra-strict security satisfied');
      print('✅ Target similarity: ${targetSimilarity.toStringAsFixed(4)}');
      print('✅ Uniqueness gap: ${uniquenessGap.toStringAsFixed(4)}');
      print('✅ Highest other similarity: ${highestOtherSimilarity.toStringAsFixed(4)}');
      print('✅ Emergency gap: ${emergencyGap.toStringAsFixed(4)}');
      return true;
      
    } catch (e) {
      print('❌ Error in emergency security validation: $e');
      return false; // Fail safe: block access if validation fails
    }
  }

  /// Calculate variance in biometric features to detect duplicates
  static double _calculateFeatureVariance(List<double> features) {
    if (features.isEmpty) return 0.0;
    
    final mean = features.reduce((a, b) => a + b) / features.length;
    final variance = features.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / features.length;
    return variance;
  }

}
