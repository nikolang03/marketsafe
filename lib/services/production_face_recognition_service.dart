import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';

import 'face_net_service.dart';
import 'face_uniqueness_service.dart';

/// SECURE Face Recognition Service
/// Uses a proper FaceNet model to generate unique embeddings.
class ProductionFaceRecognitionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  static final FaceNetService _faceNetService = FaceNetService();

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

      print('📊 Generated ${embedding.length}D embedding.');

      // CRITICAL SECURITY STEP: Check if this face is already registered to another user.
      final bool isFaceAlreadyRegistered = await FaceUniquenessService.isFaceAlreadyRegistered(embedding as List<double>);
      if (isFaceAlreadyRegistered) {
        return {
          'success': false,
          'error': 'This face appears to be already registered with another account.',
        };
      }

      // Store the embedding in Firebase.
      await _storeFaceEmbedding(userId, embedding, email, phoneNumber);

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

      // Get all stored face embeddings.
      final storedFaces = await _getAllStoredFaceEmbeddings();

      if (storedFaces.isEmpty) {
        return {'success': false, 'error': 'No registered faces found.'};
      }

      print('📊 Found ${storedFaces.length} stored face embeddings.');

      // Compare the current face with all stored faces.
      String? bestMatchUserId;
      double bestSimilarity = 0.0;

      for (final storedFace in storedFaces) {
        final storedEmbeddingRaw = storedFace['embedding'] as List;
        final storedEmbeddingList = storedEmbeddingRaw.map((e) => (e as num).toDouble()).toList();
        
        // CRITICAL FIX: Normalize the stored embedding before comparison to ensure a fair comparison.
        final storedEmbedding = _faceNetService.normalize(storedEmbeddingList);

        final similarity = _faceNetService.cosineSimilarity(currentEmbedding, storedEmbedding);

        print('🔍 Comparing with user ${storedFace['userId']}: similarity = ${similarity.toStringAsFixed(4)}');
        
        // AGGRESSIVE DEBUGGING (Temporary)
        if (similarity > 0.95) { // Log if similarity is suspiciously high
            print('🚨 HIGH SIMILARITY DETECTED 🚨');
            print('CURRENT EMBEDDING (sample): ${currentEmbedding.take(10).toList()}...');
            print('STORED EMBEDDING (sample): ${storedEmbedding.take(10).toList()}...');
        }

        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
          bestMatchUserId = storedFace['userId'];
        }
      }

      print('📊 Best match: $bestMatchUserId with similarity ${bestSimilarity.toStringAsFixed(4)}');

      // A threshold of 0.8 is generally good for FaceNet.
      // We are using a much higher threshold to prevent false positives.
      const double threshold = 0.99;
      if (bestSimilarity >= threshold) {
        print('✅ SECURE face authentication successful');
        
        String? finalUserId = bestMatchUserId;
        // If we found a match with a temporary ID, find the permanent user ID.
        if (bestMatchUserId != null && bestMatchUserId.startsWith('temp_')) {
            final permanentUserId = await _findPermanentUserId(bestMatchUserId);
            if (permanentUserId != null) {
                finalUserId = permanentUserId;
            }
        }

        return {
          'success': true,
          'userId': finalUserId,
          'similarity': bestSimilarity,
        };
      } else {
        print('❌ SECURE face authentication failed: similarity ${bestSimilarity.toStringAsFixed(4)} < $threshold');
        return {
          'success': false,
          'error': 'Face not recognized.',
        };
      }
    } catch (e) {
      print('❌ Error in SECURE face authentication: $e');
      return {
        'success': false,
        'error': 'Face authentication failed: $e',
      };
    }
  }

  /// Store face embedding in Firebase.
  static Future<void> _storeFaceEmbedding(
    String userId,
    List embedding,
    String? email,
    String? phoneNumber,
  ) async {
    try {
      print('💾 Storing face embedding in Firebase...');
      await _firestore.collection('face_embeddings').doc(userId).set({
        'userId': userId,
        'embedding': embedding,
        'email': email ?? '',
        'phoneNumber': phoneNumber ?? '',
        'registeredAt': FieldValue.serverTimestamp(),
      });
      print('✅ Face embedding stored successfully.');
    } catch (e) {
      print('❌ Error storing face embedding: $e');
      throw Exception('Failed to store face embedding: $e');
    }
  }

  /// Get all stored face embeddings.
  static Future<List<Map<String, dynamic>>> _getAllStoredFaceEmbeddings() async {
    try {
      final snapshot = await _firestore.collection('face_embeddings').get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('❌ Error getting stored face embeddings: $e');
      return [];
    }
  }

  /// Find permanent user ID for a temporary user ID.
  static Future<String?> _findPermanentUserId(String tempUserId) async {
    try {
      final faceDoc = await _firestore.collection('face_embeddings').doc(tempUserId).get();
      if (!faceDoc.exists) return null;

      final email = faceDoc.data()!['email'] as String?;
      if (email == null || email.isEmpty) return null;

      final usersSnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .where('signupCompleted', isEqualTo: true)
          .get();

      if (usersSnapshot.docs.isNotEmpty) {
        return usersSnapshot.docs.first.id;
      }
      return null;
    } catch (e) {
      print('❌ Error finding permanent user ID: $e');
      return null;
    }
  }
}
