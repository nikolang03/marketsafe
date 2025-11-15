import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
// import 'production_face_service.dart';  // Removed - TensorFlow Lite no longer used

/// @deprecated Face Recognition Service for Login
/// 
/// ⚠️ DEPRECATED: This service uses OLD biometricFeatures format (64D simulated)
/// ⚠️ NEW SYSTEM: Use ProductionFaceRecognitionService instead (512D real embeddings)
/// 
/// Old implementation with:
/// - 0.85 similarity threshold (too low)
/// - Reads from biometricFeatures.biometricSignature (deprecated)
/// - 64D simulated embeddings (not real)
/// 
/// Implements the face recognition process as described:
/// 1. Open camera and detect current face
/// 2. Generate embedding using TFLite model
/// 3. Compare with stored embeddings in Firebase
/// 4. Return user ID if match found (distance < threshold)
@Deprecated('Use ProductionFaceRecognitionService instead - this uses old biometricFeatures format')
class FaceRecognitionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  // Enhanced security thresholds for mathematical face recognition
  static const double _similarityThreshold = 0.85; // 85% similarity required for security

  /// Recognize a user by their face during login
  /// Returns user ID if match found, null otherwise
  static Future<String?> recognizeUser({
    required String email,
    required Face detectedFace,
    CameraImage? cameraImage,
  }) async {
    try {
      print('🔍 Starting face recognition (legacy service) for login...');
      print('🔐 Email (1:1 target): $email');
      
      // Step 1: Generate 128D face embedding for the detected face
      print('📊 Generating face embedding for recognition...');
      final detectedEmbedding = await _generateFaceEmbedding(detectedFace, cameraImage);
      
      if (detectedEmbedding.isEmpty || detectedEmbedding.every((x) => x == 0.0)) {
        print('❌ Failed to generate face embedding');
        return null;
      }
      
      print('✅ Generated ${detectedEmbedding.length}D face embedding');
      print('📊 Sample embedding values: ${detectedEmbedding.take(5).toList()}');
      
      // Step 2: Get embedding for the specific email (1:1)
      print('🔍 Retrieving stored face embedding for $email ...');
      final storedEmbedding = await _getEmbeddingByEmail(email);
      
      if (storedEmbedding == null) {
        print('❌ No face embedding found for email: $email');
        await _logRecognitionEvent(null, 0.0, false, 'NO_EMBEDDING_FOR_EMAIL');
        return null;
      }
      
      final storedVector = storedEmbedding['faceEmbedding'] as List<double>;
      final storedUserId = storedEmbedding['userId'] as String? ?? '';

      print('📊 Retrieved stored embedding (${storedVector.length}D) for user: $storedUserId');

      // Step 3: Compare embeddings using Euclidean distance
      print('🔍 Performing 1:1 distance comparison...');
      final distance = _calculateEuclideanDistance(storedVector, detectedEmbedding);
      final similarity = 1.0 - distance; // simple similarity approximation
        
      print('📊 Distance: ${distance.toStringAsFixed(4)} (threshold: $_similarityThreshold)');
      print('📊 Similarity approximation: ${similarity.toStringAsFixed(4)}');

      if (similarity >= _similarityThreshold) {
        print('✅ Face verified successfully for $email (user: $storedUserId)');
        await _logRecognitionEvent(storedUserId.isNotEmpty ? storedUserId : email, similarity, true, '1:1_MATCH');
        return storedUserId.isNotEmpty ? storedUserId : email;
      } else {
        print('❌ Face did not match the registered embedding for $email');
        await _logRecognitionEvent(storedUserId.isNotEmpty ? storedUserId : null, similarity, false, 'MISMATCH');
        return null;
      }
      
    } catch (e) {
      print('❌ Face recognition failed: $e');
      return null;
    }
  }

  /// Generate face embedding using TFLite model ONLY
  /// NOTE: DEPRECATED - TensorFlow Lite removed, this function is no longer functional
  @Deprecated('TensorFlow Lite removed - use ProductionFaceRecognitionService with backend/Luxand instead')
  static Future<List<double>> _generateFaceEmbedding(Face face, [CameraImage? cameraImage]) async {
    // TensorFlow Lite removed - this function is deprecated
    print('⚠️ _generateFaceEmbedding is deprecated - TensorFlow Lite removed');
    print('⚠️ Use ProductionFaceRecognitionService with backend/Luxand instead');
    throw Exception('TensorFlow Lite removed - use backend/Luxand for face recognition');
  }
  


  /// Get a stored face embedding by email
  static Future<Map<String, dynamic>?> _getEmbeddingByEmail(String email) async {
    try {
      print('🔍 Looking for face embedding for email: $email');

      final usersSnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();

      if (usersSnapshot.docs.isEmpty) {
        print('❌ No user document found for email: $email');
        return null;
      }

      final userDoc = usersSnapshot.docs.first;
      final userId = userDoc.id;
      final userData = userDoc.data();

      if (userData.containsKey('biometricFeatures')) {
        final biometricFeatures = userData['biometricFeatures'] as Map<String, dynamic>?;
        if (biometricFeatures != null && biometricFeatures.containsKey('biometricSignature')) {
          final biometricSignature = biometricFeatures['biometricSignature'] as List<dynamic>?;
          if (biometricSignature != null && biometricSignature.isNotEmpty) {
            final faceEmbedding = biometricSignature.map((e) => (e as num).toDouble()).toList();
            return {
              'userId': userId,
              'faceEmbedding': faceEmbedding,
            };
          }
        }
      }

      print('⚠️ No biometricSignature found for user: $userId');
      return null;
    } catch (e) {
      print('❌ Error retrieving embedding by email: $e');
      return null;
    }
  }

  /// Calculate Euclidean distance between two embeddings
  static double _calculateEuclideanDistance(List<double> a, List<double> b) {
    if (a.length != b.length) {
      print('⚠️ Embedding length mismatch: ${a.length} vs ${b.length}');
      return double.infinity;
    }

    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  /// Log recognition events for monitoring
  static Future<void> _logRecognitionEvent(String? userId, double similarity, bool success, [String? reason]) async {
    try {
      await _firestore.collection('face_recognition_logs').add({
        'userId': userId,
        'similarity': similarity,
        'success': success,
        'reason': reason,
        'threshold': _similarityThreshold,
        'timestamp': FieldValue.serverTimestamp(),
        'eventType': success ? 'RECOGNITION_SUCCESS' : 'RECOGNITION_FAILED',
      });
      
      print('📝 Recognition event logged: ${success ? 'SUCCESS' : 'FAILED'}');
    } catch (e) {
      print('❌ Error logging recognition event: $e');
    }
  }

  /// Get recognition statistics
  static Future<Map<String, dynamic>> getRecognitionStats() async {
    try {
      final snapshot = await _firestore
          .collection('face_recognition_logs')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();
      
      int successCount = 0;
      int failureCount = 0;
      double totalSimilarity = 0.0;
      int totalAttempts = 0;
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['success'] == true) {
          successCount++;
        } else {
          failureCount++;
        }
        totalSimilarity += data['similarity'] ?? 0.0;
        totalAttempts++;
      }
      
      return {
        'totalAttempts': totalAttempts,
        'successCount': successCount,
        'failureCount': failureCount,
        'successRate': totalAttempts > 0 ? successCount / totalAttempts : 0.0,
        'averageSimilarity': totalAttempts > 0 ? totalSimilarity / totalAttempts : 0.0,
      };
    } catch (e) {
      print('❌ Error getting recognition stats: $e');
      return {};
    }
  }
}
