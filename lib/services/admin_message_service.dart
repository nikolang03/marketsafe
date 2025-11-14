import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class AdminMessageService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  /// Send a message to all users (admin only)
  static Future<bool> sendMessageToAllUsers({
    required String message,
    required String adminId,
    String? adminName,
    String messageType = 'warning', // warning, announcement, info
  }) async {
    try {
      // Get all users
      final usersSnapshot = await _firestore.collection('users').get();
      
      if (usersSnapshot.docs.isEmpty) {
        print('⚠️ No users found');
        return false;
      }

      int successCount = 0;
      int failCount = 0;

      // Create a batch for better performance
      final batch = _firestore.batch();
      int batchCount = 0;
      const maxBatchSize = 500; // Firestore batch limit

      for (var userDoc in usersSnapshot.docs) {
        final userId = userDoc.id;
        
        // Create notification document
        final notificationRef = _firestore.collection('notifications').doc();
        batch.set(notificationRef, {
          'userId': userId,
          'type': 'admin_message',
          'title': messageType == 'warning' 
              ? '⚠️ Warning from Admin'
              : messageType == 'announcement'
                  ? '📢 Announcement'
                  : 'ℹ️ Important Notice',
          'message': message,
          'messageType': messageType,
          'adminId': adminId,
          'adminName': adminName ?? 'Admin',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        batchCount++;
        
        // Commit batch if it reaches the limit
        if (batchCount >= maxBatchSize) {
          try {
            await batch.commit();
            successCount += batchCount;
            batchCount = 0;
          } catch (e) {
            print('❌ Error committing batch: $e');
            failCount += batchCount;
            batchCount = 0;
          }
        }
      }

      // Commit remaining notifications
      if (batchCount > 0) {
        try {
          await batch.commit();
          successCount += batchCount;
        } catch (e) {
          print('❌ Error committing final batch: $e');
          failCount += batchCount;
        }
      }

      print('✅ Admin message sent: $successCount successful, $failCount failed');
      return successCount > 0;
    } catch (e) {
      print('❌ Error sending admin message to all users: $e');
      return false;
    }
  }

  /// Get total user count
  static Future<int> getTotalUserCount() async {
    try {
      final snapshot = await _firestore.collection('users').get();
      return snapshot.docs.length;
    } catch (e) {
      print('❌ Error getting user count: $e');
      return 0;
    }
  }
}


