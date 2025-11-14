import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  /// Create a notification for product status change
  static Future<void> createProductNotification({
    required String userId,
    required String productId,
    required String productTitle,
    required String status,
    String? rejectionReason,
    String? adminNote,
  }) async {
    try {
      print('🔔 Creating notification for product: $productTitle, status: $status');
      print('🔔 Product ID: $productId');
      print('🔔 User ID: $userId');
      
      // Skip product verification for new products - we know they exist since they were just created
      print('🔍 Skipping product verification for new product notification');
      
      final notificationId = 'notification_${DateTime.now().millisecondsSinceEpoch}';
      
      final notification = {
        'id': notificationId,
        'userId': userId,
        'productId': productId,
        'productTitle': productTitle,
        'type': 'product_status',
        'status': status,
        'rejectionReason': rejectionReason,
        'adminNote': adminNote,
        'isRead': false,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'title': _getNotificationTitle(status),
        'message': _getNotificationMessage(status, productTitle, rejectionReason, adminNote),
      };

      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .set(notification);
      
      print('✅ Notification created successfully: $notificationId');
    } catch (e) {
      print('❌ Error creating notification: $e');
    }
  }

  /// Get all notifications for a user
  static Future<List<Map<String, dynamic>>> getUserNotifications(String userId) async {
    try {
      print('🔔 Fetching notifications for user: $userId');
      print('🔔 Using database: marketsafe');
      
      final querySnapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .get();

      print('🔔 Query returned ${querySnapshot.docs.length} documents');
      
      // Debug: Print all document IDs and user IDs
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        print('🔔 Found notification: ${doc.id}');
        print('🔔   - User ID: ${data['userId']}');
        print('🔔   - Title: ${data['title']}');
        print('🔔   - Status: ${data['status']}');
        print('🔔   - Product ID: ${data['productId']}');
        print('🔔   - CreatedAt type: ${data['createdAt'].runtimeType}');
        print('🔔   - CreatedAt value: ${data['createdAt']}');
      }
      
      // Check if the specific notification from web admin exists
      final webAdminNotificationId = 'notification_1760552923796_product_1760550161560_user_1760401522367_cunanankonifers';
      final webAdminDoc = await _firestore.collection('notifications').doc(webAdminNotificationId).get();
      print('🔍 Web admin notification exists: ${webAdminDoc.exists}');
      if (webAdminDoc.exists) {
        final webAdminData = webAdminDoc.data()!;
        print('🔍 Web admin notification data: ${webAdminData['title']} - ${webAdminData['status']}');
      }
      
      final notifications = querySnapshot.docs
          .map((doc) {
            final data = doc.data();
            print('🔔 Notification data: ${doc.id} - ${data['title']} - ${data['status']}');
            return data;
          })
          .toList();
      
      // Sort in memory instead of using orderBy
      notifications.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime); // Descending order
      });
      
      print('✅ Found ${notifications.length} notifications for user $userId');
      return notifications;
    } catch (e) {
      print('❌ Error fetching notifications: $e');
      return [];
    }
  }

  /// Get unread notification count (excluding duplicates)
  static Future<int> getUnreadCount(String userId) async {
    try {
      print('🔔 Getting unread count for user: $userId');
      
      final querySnapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .get();

      // Group notifications by productId and status to avoid counting duplicates
      final Map<String, List<QueryDocumentSnapshot>> groupedNotifications = {};
      
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final productId = data['productId'] as String?;
        final status = data['status'] as String?;
        
        if (productId != null && status != null) {
          final key = '${productId}_$status';
          groupedNotifications.putIfAbsent(key, () => []).add(doc);
        }
      }
      
      // Count unique notifications (one per productId+status combination)
      int uniqueUnreadCount = 0;
      for (var entry in groupedNotifications.entries) {
        final notifications = entry.value;
        if (notifications.isNotEmpty) {
          // Check if any of the notifications for this product+status is unread
          final hasUnread = notifications.any((doc) => (doc.data() as Map<String, dynamic>?)?['isRead'] == false);
          if (hasUnread) {
            uniqueUnreadCount++;
          }
        }
      }
      
      print('📊 Unique unread notifications count: $uniqueUnreadCount (total docs: ${querySnapshot.docs.length})');
      return uniqueUnreadCount;
    } catch (e) {
      print('❌ Error getting unread count: $e');
      return 0;
    }
  }

  /// Mark notification as read
  static Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
      
      print('✅ Notification marked as read: $notificationId');
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }

  /// Mark all notifications as read
  static Future<void> markAllAsRead(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (var doc in querySnapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      
      await batch.commit();
      print('✅ All notifications marked as read for user: $userId');
    } catch (e) {
      print('❌ Error marking all notifications as read: $e');
    }
  }

  /// Delete a specific notification
  static Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .delete();
      
      print('✅ Notification deleted: $notificationId');
    } catch (e) {
      print('❌ Error deleting notification: $e');
    }
  }

  /// Delete all notifications for a user
  static Future<void> deleteAllNotifications(String userId) async {
    try {
      print('🗑️ Starting deletion of all notifications for user: $userId');
      
      final querySnapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .get();

      print('🗑️ Found ${querySnapshot.docs.length} notifications to delete');
      
      if (querySnapshot.docs.isEmpty) {
        print('🗑️ No notifications found to delete');
        return;
      }

      final batch = _firestore.batch();
      for (var doc in querySnapshot.docs) {
        print('🗑️ Deleting notification: ${doc.id}');
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print('✅ All ${querySnapshot.docs.length} notifications deleted for user: $userId');
      
      // Verify deletion by checking again
      final verifyQuery = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .get();
      
      print('🔍 Verification: ${verifyQuery.docs.length} notifications remaining after deletion');
      
    } catch (e) {
      print('❌ Error deleting all notifications: $e');
      rethrow; // Re-throw to show error in UI
    }
  }

  /// Completely disable notification creation for a user (temporary)
  static Future<void> disableNotificationCreation(String userId) async {
    try {
      print('🚫 Disabling notification creation for user: $userId');
      
      // Store a flag in user preferences to disable notifications
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_disabled_$userId', true);
      
      print('✅ Notification creation disabled for user: $userId');
    } catch (e) {
      print('❌ Error disabling notification creation: $e');
    }
  }

  /// Re-enable notification creation for a user
  static Future<void> enableNotificationCreation(String userId) async {
    try {
      print('✅ Enabling notification creation for user: $userId');
      
      // Remove the flag from user preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('notifications_disabled_$userId');
      
      print('✅ Notification creation enabled for user: $userId');
    } catch (e) {
      print('❌ Error enabling notification creation: $e');
    }
  }

  /// Check if notification creation is disabled for a user
  static Future<bool> isNotificationCreationDisabled(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('notifications_disabled_$userId') ?? false;
    } catch (e) {
      print('❌ Error checking notification creation status: $e');
      return false;
    }
  }

  /// Get current notification count for a user (for debugging)
  static Future<int> getCurrentNotificationCount(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .get();
      
      print('📊 Current notification count for user $userId: ${querySnapshot.docs.length}');
      
      // Debug: Print all notification details
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        print('📊 Notification: ${doc.id} - ${data['title']} - ${data['status']} - ${data['createdAt']}');
      }
      
      return querySnapshot.docs.length;
    } catch (e) {
      print('❌ Error getting current notification count: $e');
      return 0;
    }
  }

  /// Debug method to check all notifications in database
  static Future<void> debugAllNotifications() async {
    try {
      print('🔍 Debug: Checking all notifications in database...');
      
      final querySnapshot = await _firestore
          .collection('notifications')
          .get();
      
      print('🔍 Debug: Found ${querySnapshot.docs.length} total notifications');
      
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        print('🔍 Debug Notification: ${doc.id}');
        print('  - User ID: ${data['userId']}');
        print('  - Product ID: ${data['productId']}');
        print('  - Title: ${data['title']}');
        print('  - Status: ${data['status']}');
        print('  - Created: ${data['createdAt']}');
        print('  - Read: ${data['isRead']}');
        print('---');
      }
    } catch (e) {
      print('❌ Debug error: $e');
    }
  }

  /// Delete notifications by type for a user
  static Future<void> deleteNotificationsByType(String userId, String type) async {
    try {
      final querySnapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: type)
          .get();

      final batch = _firestore.batch();
      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print('✅ Notifications of type "$type" deleted for user: $userId');
    } catch (e) {
      print('❌ Error deleting notifications by type: $e');
    }
  }

  /// Create missing approval notification for a product
  static Future<void> createMissingApprovalNotification(String productId) async {
    try {
      print('🔧 Creating missing approval notification for product: $productId');
      
      // First, find the product to get the correct details
      final productDoc = await _firestore.collection('products').doc(productId).get();
      
      if (!productDoc.exists) {
        print('❌ Product not found: $productId');
        return;
      }
      
      final productData = productDoc.data()!;
      final sellerId = productData['sellerId'] ?? '';
      final productTitle = productData['title'] ?? '';
      
      if (sellerId.isEmpty) {
        print('❌ No seller ID found for product: $productId');
        return;
      }
      
      // Create the approval notification
      await createProductNotification(
        userId: sellerId,
        productId: productId,
        productTitle: productTitle,
        status: 'approved',
      );
      
      print('✅ Missing approval notification created for product: $productId');
    } catch (e) {
      print('❌ Error creating missing approval notification: $e');
    }
  }

  /// Create a notification for when a user follows another user
  static Future<void> createFollowNotification({
    required String targetUserId,
    required String followerId,
    String? followerUsername,
  }) async {
    try {
      print('🔔 Creating follow notification');
      print('🔔 Target User ID: $targetUserId');
      print('🔔 Follower ID: $followerId');
      
      // Get follower's username if not provided
      String username = followerUsername ?? 'Someone';
      if (followerUsername == null) {
        try {
          final followerDoc = await _firestore.collection('users').doc(followerId).get();
          if (followerDoc.exists) {
            final followerData = followerDoc.data()!;
            username = followerData['username'] ?? 'Someone';
          }
        } catch (e) {
          print('⚠️ Could not fetch follower username: $e');
        }
      }
      
      final notificationId = 'notification_${DateTime.now().millisecondsSinceEpoch}_follow_$followerId';
      
      final notification = {
        'id': notificationId,
        'userId': targetUserId,
        'type': 'follow',
        'followerId': followerId,
        'followerUsername': username,
        'isRead': false,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'title': 'New Follower 👤',
        'message': '$username started following you',
      };

      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .set(notification);
      
      print('✅ Follow notification created successfully: $notificationId');
    } catch (e) {
      print('❌ Error creating follow notification: $e');
    }
  }

  /// Get notification title based on status
  static String _getNotificationTitle(String status) {
    switch (status) {
      case 'pending':
        return 'Product Under Review ⏳';
      case 'approved':
        return 'Product Approved! 🎉';
      case 'rejected':
        return 'Product Rejected ❌';
      case 'deleted':
        return 'Product Deleted 🗑️';
      default:
        return 'Product Status Update';
    }
  }

  /// Get notification message based on status
  static String _getNotificationMessage(String status, String productTitle, String? rejectionReason, String? adminNote) {
    switch (status) {
      case 'pending':
        return 'Your product "$productTitle" is under review by our team.';
      case 'approved':
        return 'Great news! Your product "$productTitle" has been approved and is now live!';
      case 'rejected':
        final reason = rejectionReason != null ? '\n\nReason: $rejectionReason' : '';
        return 'Your product "$productTitle" has been rejected.$reason';
      case 'deleted':
        final note = adminNote != null ? '\n\nNote: $adminNote' : '';
        return 'Your product "$productTitle" has been deleted from our platform.$note';
      default:
        return 'Your product "$productTitle" status has been updated.';
    }
  }
}