import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Service to track user online/offline status
class PresenceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  /// Set user as online
  static Future<void> setOnline(String userId) async {
    try {
      if (userId.isEmpty) return;
      
      await _firestore.collection('users').doc(userId).update({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });
      print('✅ User $userId set as online');
    } catch (e) {
      print('❌ Error setting user online: $e');
    }
  }

  /// Set user as offline
  static Future<void> setOffline(String userId) async {
    try {
      if (userId.isEmpty) return;
      
      await _firestore.collection('users').doc(userId).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
      print('✅ User $userId set as offline');
    } catch (e) {
      print('❌ Error setting user offline: $e');
    }
  }

  /// Listen to user's online status
  static Stream<Map<String, dynamic>> listenToUserStatus(String userId) {
    if (userId.isEmpty) {
      return Stream.value({'isOnline': false, 'lastSeen': null});
    }
    
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        return {'isOnline': false, 'lastSeen': null};
      }
      
      final data = snapshot.data()!;
      return {
        'isOnline': data['isOnline'] ?? false,
        'lastSeen': data['lastSeen'],
      };
    });
  }

  /// Get user's online status (one-time)
  static Future<Map<String, dynamic>> getUserStatus(String userId) async {
    try {
      if (userId.isEmpty) {
        return {'isOnline': false, 'lastSeen': null};
      }
      
      final doc = await _firestore.collection('users').doc(userId).get();
      
      if (!doc.exists) {
        return {'isOnline': false, 'lastSeen': null};
      }
      
      final data = doc.data()!;
      return {
        'isOnline': data['isOnline'] ?? false,
        'lastSeen': data['lastSeen'],
      };
    } catch (e) {
      print('❌ Error getting user status: $e');
      return {'isOnline': false, 'lastSeen': null};
    }
  }

  /// Format last seen timestamp
  static String formatLastSeen(dynamic lastSeen) {
    if (lastSeen == null) return 'Offline';
    
    try {
      DateTime dateTime;
      if (lastSeen is Timestamp) {
        dateTime = lastSeen.toDate();
      } else if (lastSeen is DateTime) {
        dateTime = lastSeen;
      } else {
        return 'Offline';
      }

      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 5) {
        return 'Online';
      } else if (difference.inMinutes < 60) {
        return 'Active ${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return 'Active ${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return 'Active ${difference.inDays}d ago';
      } else {
        return 'Offline';
      }
    } catch (e) {
      return 'Offline';
    }
  }
}

