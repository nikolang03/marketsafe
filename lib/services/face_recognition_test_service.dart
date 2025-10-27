import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Service to test and debug face recognition issues
class FaceRecognitionTestService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  /// Test if face embeddings exist in the database
  static Future<Map<String, dynamic>> testFaceEmbeddings() async {
    try {
      print('🧪 Testing face embeddings in database...');
      
      // Check face_embeddings collection
      final faceEmbeddingsSnapshot = await _firestore
          .collection('face_embeddings')
          .get();
      
      print('📊 Face embeddings collection: ${faceEmbeddingsSnapshot.docs.length} documents');
      
      final faceEmbeddings = <Map<String, dynamic>>[];
      for (final doc in faceEmbeddingsSnapshot.docs) {
        final data = doc.data();
        if (data['faceEmbedding'] != null) {
          final embedding = List<double>.from(data['faceEmbedding']);
          faceEmbeddings.add({
            'userId': doc.id,
            'embeddingSize': embedding.length,
            'isActive': data['isActive'] ?? false,
            'email': data['email'] ?? '',
            'phoneNumber': data['phoneNumber'] ?? '',
          });
        }
      }
      
      // Check users collection for completed signups
      final usersSnapshot = await _firestore
          .collection('users')
          .where('signupCompleted', isEqualTo: true)
          .get();
      
      print('📊 Users with completed signup: ${usersSnapshot.docs.length} documents');
      
      final completedUsers = <Map<String, dynamic>>[];
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        completedUsers.add({
          'userId': doc.id,
          'email': data['email'] ?? '',
          'phoneNumber': data['phoneNumber'] ?? '',
          'verificationStatus': data['verificationStatus'] ?? 'unknown',
          'signupCompleted': data['signupCompleted'] ?? false,
        });
      }
      
      // Check for biometric features in users
      final biometricUsers = <Map<String, dynamic>>[];
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        if (data['biometricFeatures'] != null) {
          final biometricFeatures = data['biometricFeatures'] as Map<String, dynamic>?;
          if (biometricFeatures != null && biometricFeatures['biometricSignature'] != null) {
            final signature = List<double>.from(biometricFeatures['biometricSignature']);
            biometricUsers.add({
              'userId': doc.id,
              'biometricSignatureSize': signature.length,
              'biometricType': biometricFeatures['biometricType'] ?? 'unknown',
            });
          }
        }
      }
      
      return {
        'faceEmbeddingsCount': faceEmbeddings.length,
        'faceEmbeddings': faceEmbeddings,
        'completedUsersCount': completedUsers.length,
        'completedUsers': completedUsers,
        'biometricUsersCount': biometricUsers.length,
        'biometricUsers': biometricUsers,
        'totalDocuments': faceEmbeddingsSnapshot.docs.length + usersSnapshot.docs.length,
      };
      
    } catch (e) {
      print('❌ Error testing face embeddings: $e');
      return {'error': e.toString()};
    }
  }

  /// Test similarity calculation between two embeddings
  static double testSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      print('⚠️ Dimension mismatch: ${embedding1.length}D vs ${embedding2.length}D');
      return 0.0;
    }
    
    // Calculate cosine similarity
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;
    
    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      norm1 += embedding1[i] * embedding1[i];
      norm2 += embedding2[i] * embedding2[i];
    }
    
    if (norm1 == 0.0 || norm2 == 0.0) {
      return 0.0;
    }
    
    final similarity = dotProduct / (sqrt(norm1) * sqrt(norm2));
    return similarity.clamp(0.0, 1.0);
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
