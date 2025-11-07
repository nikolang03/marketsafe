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
  static Future<bool> isFaceAlreadyRegistered(
    List<double> newEmbedding, {
    String? currentUserIdToIgnore,
    String? currentEmailToIgnore,
  }) async {
    try {
      print('🛡️ Starting face uniqueness check...');
      if (currentUserIdToIgnore != null) {
        print('🛡️ Ignoring matches for user ID: $currentUserIdToIgnore');
      }
      if (currentEmailToIgnore != null && currentEmailToIgnore.isNotEmpty) {
        print('🛡️ Also ignoring matches for email: $currentEmailToIgnore');
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
      // Raised slightly to reduce false positives across different users.
      const double uniquenessThreshold = 0.995;
      const double margin = 0.02; // require separation from second best

      double best = 0.0;
      String? bestUser;
      double second = 0.0;

      for (final storedFace in storedFaces) {
        final String storedUserId = storedFace['userId'] as String;
        final String storedEmail = (storedFace['email'] ?? '').toString();

        // If a user has to restart registration, ignore their own previously stored temp embedding.
        if (storedUserId == currentUserIdToIgnore) {
          print('⚖️ Skipping comparison with self ($storedUserId)');
          continue;
        }
        // Ignore temp_ only if it's clearly our own in-progress signup (same email or same userId)
        if (storedUserId.startsWith('temp_')) {
          final bool sameEmail = currentEmailToIgnore != null && currentEmailToIgnore.isNotEmpty &&
              storedEmail.isNotEmpty && storedEmail.toLowerCase() == currentEmailToIgnore.toLowerCase();
          final bool sameUser = currentUserIdToIgnore != null && storedUserId == currentUserIdToIgnore;
          if (sameEmail || sameUser) {
            print('ℹ️ Skipping own temp signup embedding ($storedUserId)');
            continue;
          }
        }
        if (currentEmailToIgnore != null && currentEmailToIgnore.isNotEmpty &&
            storedEmail.isNotEmpty && storedEmail.toLowerCase() == currentEmailToIgnore.toLowerCase()) {
          print('⚖️ Skipping comparison with same email ($storedEmail)');
          continue;
        }
        
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
        for (final embData in embeddingsToCompare) {
          final storedEmbeddingRaw = embData['embedding'] as List;
          final storedEmbeddingList = storedEmbeddingRaw.map((e) => (e as num).toDouble()).toList();

          // Skip embedding length mismatch
          if (storedEmbeddingList.length != newEmbedding.length) {
            continue;
          }

          // Normalize the stored embedding to ensure a fair comparison
          final storedEmbedding = _faceNetService.normalize(storedEmbeddingList);
          final similarity = _faceNetService.cosineSimilarity(newEmbedding, storedEmbedding);
          
          // Track the best similarity for this user
          if (similarity > userBestSimilarity) {
            userBestSimilarity = similarity;
          }
        }
        
        if (userBestSimilarity > 0) {
          print('⚖️ Best similarity with user $storedUserId (across all embeddings): ${userBestSimilarity.toStringAsFixed(4)}');
        }

        // Track top-2 to enforce a safety margin
        if (userBestSimilarity > best) {
          second = best;
          best = userBestSimilarity;
          bestUser = storedUserId;
        } else if (userBestSimilarity > second) {
          second = userBestSimilarity;
        }
      }

      // Decide using threshold and margin to reduce false positives
      if (best >= uniquenessThreshold && (best - second) >= margin) {
        print('❌ UNIQUENESS CHECK FAILED: Best=${best.toStringAsFixed(4)}, Second=${second.toStringAsFixed(4)} (User=$bestUser)');
        return true;
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
      return snapshot.docs.map((doc) {
        final data = doc.data();
        // Ensure userId is set from document ID if missing
        if (data['userId'] == null) {
          data['userId'] = doc.id;
        }
        return data;
      }).toList();
    } catch (e) {
      print('❌ Error getting stored face embeddings for uniqueness check: $e');
      return [];
    }
  }
}