import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'face_net_service.dart';

/// A service to ensure that each registered face is unique within the system.
class FaceUniquenessService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  static final FaceNetService _faceNetService = FaceNetService();

  /// Checks if a given face embedding is already registered in the database.
  ///
  /// Returns `true` if a similar face is found, `false` otherwise.
  static Future<bool> isFaceAlreadyRegistered(List<double> newEmbedding, {String? currentUserIdToIgnore}) async {
    try {
      print('🛡️ Starting face uniqueness check...');
      if (currentUserIdToIgnore != null) {
        print('🛡️ Ignoring matches for user ID: $currentUserIdToIgnore');
      }

      if (newEmbedding.isEmpty) {
        print('⚠️ Uniqueness check skipped: New embedding is empty.');
        return false; // Cannot check an empty embedding
      }

      final storedFaces = await _getAllStoredFaceEmbeddings();

      if (storedFaces.isEmpty) {
        print('✅ No existing faces in the database. This face is unique.');
        return false; // No faces to compare against
      }

      print('📊 Comparing new face against ${storedFaces.length} existing faces.');

      // A very strict threshold to prevent duplicate registrations.
      const double uniquenessThreshold = 0.99;

      for (final storedFace in storedFaces) {
        final String storedUserId = storedFace['userId'] as String;

        // If a user has to restart registration, ignore their own previously stored temp embedding.
        if (storedUserId == currentUserIdToIgnore) {
          print('⚖️ Skipping comparison with self ($storedUserId)');
          continue;
        }
        
        final storedEmbeddingRaw = storedFace['embedding'] as List;
        final storedEmbeddingList = storedEmbeddingRaw.map((e) => (e as num).toDouble()).toList();

        // Normalize the stored embedding to ensure a fair comparison.
        final storedEmbedding = _faceNetService.normalize(storedEmbeddingList);

        final similarity = _faceNetService.cosineSimilarity(newEmbedding, storedEmbedding);

        print('⚖️ Similarity with user ${storedFace['userId']} is ${similarity.toStringAsFixed(4)}');

        if (similarity > uniquenessThreshold) {
          print('❌ UNIQUENESS CHECK FAILED: New face is too similar to existing user ${storedFace['userId']} (Similarity: $similarity)');
          return true; // Found a face that is too similar
        }
      }

      print('✅ UNIQUENESS CHECK PASSED: New face is unique.');
      return false; // No similar faces found
    } catch (e) {
      print('❌ Error during face uniqueness check: $e');
      // In case of error, default to allowing registration to not block the user,
      // but this should be monitored.
      return false;
    }
  }

  /// Helper to get all stored face embeddings.
  static Future<List<Map<String, dynamic>>> _getAllStoredFaceEmbeddings() async {
    try {
      final snapshot = await _firestore.collection('face_embeddings').get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('❌ Error getting stored face embeddings for uniqueness check: $e');
      return [];
    }
  }
}

