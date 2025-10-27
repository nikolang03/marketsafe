import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import 'production_face_service.dart';

/// Face Recognition Service for Login
/// Implements the face recognition process as described:
/// 1. Open camera and detect current face
/// 2. Generate embedding using TFLite model
/// 3. Compare with stored embeddings in Firebase
/// 4. Return user ID if match found (distance < threshold)
class FaceRecognitionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  // Enhanced security thresholds for mathematical face recognition
  static const double _similarityThreshold = 0.85; // 85% similarity required for security
  static const double _uniquenessThreshold = 0.30; // 30% difference between best and second-best
  static const double _maxSecondBestSimilarity = 0.50; // Second-best must be below 50%

  /// Recognize a user by their face during login
  /// Returns user ID if match found, null otherwise
  static Future<String?> recognizeUser({
    required Face detectedFace,
    CameraImage? cameraImage,
  }) async {
    try {
      print('🔍 Starting face recognition for login...');
      
      // Step 1: Generate 128D face embedding for the detected face
      print('📊 Generating face embedding for recognition...');
      final detectedEmbedding = await _generateFaceEmbedding(detectedFace, cameraImage);
      
      if (detectedEmbedding.isEmpty || detectedEmbedding.every((x) => x == 0.0)) {
        print('❌ Failed to generate face embedding');
        return null;
      }
      
      print('✅ Generated ${detectedEmbedding.length}D face embedding');
      print('📊 Sample embedding values: ${detectedEmbedding.take(5).toList()}');
      
      // Step 2: Get all stored face embeddings from Firebase
      print('🔍 Retrieving stored face embeddings from Firebase...');
      final storedEmbeddings = await _getAllStoredEmbeddings();
      
      if (storedEmbeddings.isEmpty) {
        print('❌ No face embeddings found in database');
        print('🔍 This could mean:');
        print('  1. No users have completed signup yet');
        print('  2. Face embeddings were not stored properly');
        print('  3. Database query is not finding the right documents');
        return null;
      }
      
      print('📊 Found ${storedEmbeddings.length} stored face embeddings');
      
      // Step 3: Use production face service for comparison
      print('🔍 Comparing with stored embeddings using production service...');
      final matchResult = await ProductionFaceService.findBestMatch(detectedEmbedding, storedEmbeddings);
      
      if (matchResult != null) {
        final bestMatchUserId = matchResult['userId'] as String;
        final bestSimilarity = matchResult['similarity'] as double;
        final uniquenessScore = matchResult['uniquenessScore'] as double;
        
        print('📊 Best match: user $bestMatchUserId with similarity ${bestSimilarity.toStringAsFixed(4)}');
        print('📊 Uniqueness score: ${uniquenessScore.toStringAsFixed(4)}');
        print('📊 Threshold: $_similarityThreshold');
        print('📊 Uniqueness threshold: $_uniquenessThreshold');
        
        // Enhanced security checks
        final secondBestSimilarity = bestSimilarity - uniquenessScore;
        final isHighSimilarity = bestSimilarity >= _similarityThreshold;
        final isUniqueMatch = uniquenessScore >= _uniquenessThreshold;
        final isSecondBestLow = secondBestSimilarity <= _maxSecondBestSimilarity;
        
        print('🔒 Security Analysis:');
        print('  - Best similarity: ${bestSimilarity.toStringAsFixed(4)} (required: $_similarityThreshold)');
        print('  - Second-best similarity: ${secondBestSimilarity.toStringAsFixed(4)} (max: $_maxSecondBestSimilarity)');
        print('  - Uniqueness score: ${uniquenessScore.toStringAsFixed(4)} (required: $_uniquenessThreshold)');
        print('  - High similarity: $isHighSimilarity');
        print('  - Unique match: $isUniqueMatch');
        print('  - Second-best low: $isSecondBestLow');
        
        if (isHighSimilarity && isUniqueMatch && isSecondBestLow) {
          print('✅ Face recognized with SECURE unique match! User: $bestMatchUserId');
          
          // Log successful recognition
          await _logRecognitionEvent(bestMatchUserId, bestSimilarity, true, 'SECURE_MATCH');
          
          return bestMatchUserId;
        } else {
          String reason = '';
          if (!isHighSimilarity) reason += 'Low similarity; ';
          if (!isUniqueMatch) reason += 'Not unique; ';
          if (!isSecondBestLow) reason += 'Second-best too high; ';
          
          print('❌ Face not recognized. $reason');
          
          // Log failed recognition
          await _logRecognitionEvent(null, bestSimilarity, false, reason.trim());
          
          return null;
        }
      } else {
        print('❌ No suitable match found');
        
        // Log failed recognition
        await _logRecognitionEvent(null, 0.0, false);
        
        return null;
      }
      
    } catch (e) {
      print('❌ Face recognition failed: $e');
      return null;
    }
  }

  /// Generate face embedding using TFLite model ONLY
  static Future<List<double>> _generateFaceEmbedding(Face face, [CameraImage? cameraImage]) async {
    print('🤖 Generating face embedding using TFLite model...');
    
    await ProductionFaceService.initialize();
    final embedding = await ProductionFaceService.extractFaceEmbeddings(face, cameraImage);
    
    if (embedding.isNotEmpty && !embedding.every((x) => x == 0.0)) {
      print('✅ Generated ${embedding.length}D face embedding using TFLite');
      return embedding;
    } else {
      throw Exception('TFLite model failed - no fallback available');
    }
  }
  


  /// Get all stored face embeddings from Firebase
  static Future<List<Map<String, dynamic>>> _getAllStoredEmbeddings() async {
    try {
      print('🔍 Looking for face embeddings in users collection...');
      
      // Get all users who have completed signup
      final usersSnapshot = await _firestore
          .collection('users')
          .where('signupCompleted', isEqualTo: true)
          .get();
      
      print('📊 Found ${usersSnapshot.docs.length} users who completed signup');
      
      final embeddings = <Map<String, dynamic>>[];
      
      // For each user, check if they have face embeddings
      for (final userDoc in usersSnapshot.docs) {
        final userData = userDoc.data();
        final String userId = userDoc.id;
        
        print('🔍 Checking user: $userId');
        print('🔍 User data keys: ${userData.keys.toList()}');
        
        // Check if user has biometricFeatures with biometricSignature
        if (userData.containsKey('biometricFeatures')) {
          final biometricFeatures = userData['biometricFeatures'] as Map<String, dynamic>?;
          
          if (biometricFeatures != null && biometricFeatures.containsKey('biometricSignature')) {
            final biometricSignature = biometricFeatures['biometricSignature'] as List<dynamic>?;
            
            if (biometricSignature != null && biometricSignature.isNotEmpty) {
              final faceEmbedding = biometricSignature.cast<double>();
              
              print('📊 Face embedding size: ${faceEmbedding.length}D');
              print('📊 Sample values: ${faceEmbedding.take(5).toList()}');
              
              embeddings.add({
                'userId': userId,
                'faceEmbedding': faceEmbedding,
                'email': userData['email'] ?? '',
                'phoneNumber': userData['phoneNumber'] ?? '',
              });
              print('✅ Added face embedding for user: $userId');
            } else {
              print('⚠️ No biometricSignature found for user: $userId');
            }
          } else {
            print('⚠️ No biometricSignature found in biometricFeatures for user: $userId');
          }
        } else {
          print('⚠️ No biometricFeatures field found for user: $userId');
        }
      }
      
      print('📊 Total embeddings found: ${embeddings.length}');
      return embeddings;
    } catch (e) {
      print('❌ Error getting stored embeddings: $e');
      return [];
    }
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
