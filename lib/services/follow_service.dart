import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class FollowService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  /// Follow a user
  static Future<bool> followUser(String targetUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('current_user_id') ?? 
                           prefs.getString('signup_user_id') ?? '';
      
      if (currentUserId.isEmpty) {
        print('❌ No current user ID found');
        return false;
      }

      if (currentUserId == targetUserId) {
        print('❌ Cannot follow yourself');
        return false;
      }

      // Check if already following
      final alreadyFollowing = await isFollowing(targetUserId);
      if (alreadyFollowing) {
        print('⚠️ Already following user: $targetUserId');
        return true; // Return true since the desired state is already achieved
      }

      // Add to current user's following list
      // FieldValue.arrayUnion and FieldValue.increment work even if fields don't exist
      await _firestore.collection('users').doc(currentUserId).update({
        'following': FieldValue.arrayUnion([targetUserId]),
        'followingCount': FieldValue.increment(1),
        'lastFollowedAt': FieldValue.serverTimestamp(),
      });

      // Add to target user's followers list
      // FieldValue.arrayUnion and FieldValue.increment work even if fields don't exist
      await _firestore.collection('users').doc(targetUserId).update({
        'followers': FieldValue.arrayUnion([currentUserId]),
        'followersCount': FieldValue.increment(1),
        'lastFollowedAt': FieldValue.serverTimestamp(),
      });

      // Create follow relationship document
      await _firestore.collection('follows').add({
        'followerId': currentUserId,
        'followingId': targetUserId,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
      });

      // Get current user's username for notification
      String? followerUsername;
      try {
        final currentUserDoc = await _firestore.collection('users').doc(currentUserId).get();
        if (currentUserDoc.exists) {
          final currentUserData = currentUserDoc.data()!;
          followerUsername = currentUserData['username'] as String?;
        }
      } catch (e) {
        print('⚠️ Could not fetch follower username for notification: $e');
      }

      // Create notification for the followed user
      await NotificationService.createFollowNotification(
        targetUserId: targetUserId,
        followerId: currentUserId,
        followerUsername: followerUsername,
      );

      print('✅ Successfully followed user: $targetUserId');
      print('📊 Updated followers count for user: $targetUserId');
      return true;
    } catch (e) {
      print('❌ Error following user: $e');
      return false;
    }
  }

  /// Unfollow a user
  static Future<bool> unfollowUser(String targetUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('current_user_id') ?? 
                           prefs.getString('signup_user_id') ?? '';
      
      if (currentUserId.isEmpty) {
        print('❌ No current user ID found');
        return false;
      }

      // Check if actually following
      final isCurrentlyFollowing = await isFollowing(targetUserId);
      if (!isCurrentlyFollowing) {
        print('⚠️ Not following user: $targetUserId');
        return true; // Return true since the desired state is already achieved
      }

      // Remove from current user's following list
      await _firestore.collection('users').doc(currentUserId).update({
        'following': FieldValue.arrayRemove([targetUserId]),
        'followingCount': FieldValue.increment(-1),
      });

      // Remove from target user's followers list
      await _firestore.collection('users').doc(targetUserId).update({
        'followers': FieldValue.arrayRemove([currentUserId]),
        'followersCount': FieldValue.increment(-1),
      });

      // Update follow relationship document
      await _firestore.collection('follows')
          .where('followerId', isEqualTo: currentUserId)
          .where('followingId', isEqualTo: targetUserId)
          .get()
          .then((querySnapshot) {
        for (var doc in querySnapshot.docs) {
          doc.reference.update({
            'status': 'inactive',
            'unfollowedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      print('✅ Successfully unfollowed user: $targetUserId');
      print('📊 Updated followers count for user: $targetUserId');
      return true;
    } catch (e) {
      print('❌ Error unfollowing user: $e');
      return false;
    }
  }

  /// Check if current user is following target user
  static Future<bool> isFollowing(String targetUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('current_user_id') ?? 
                           prefs.getString('signup_user_id') ?? '';
      
      if (currentUserId.isEmpty) return false;

      final userDoc = await _firestore.collection('users').doc(currentUserId).get();
      if (!userDoc.exists) return false;

      final userData = userDoc.data()!;
      final following = userData['following'] as List<dynamic>? ?? [];
      
      return following.contains(targetUserId);
    } catch (e) {
      print('❌ Error checking follow status: $e');
      return false;
    }
  }

  /// Get user's followers list
  static Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return [];

      final userData = userDoc.data()!;
      final followers = userData['followers'] as List<dynamic>? ?? [];
      
      // Remove duplicates and null/empty values
      final followersSet = followers
          .where((id) => id != null && id.toString().isNotEmpty)
          .map((id) => id.toString())
          .toSet();
      
      print('🔍 Followers array for user $userId: ${followers.length} items');
      print('🔍 After deduplication: ${followersSet.length} unique items');
      
      List<Map<String, dynamic>> followersList = [];
      
      for (String followerId in followersSet) {
        try {
          final followerDoc = await _firestore.collection('users').doc(followerId).get();
          if (followerDoc.exists) {
            final followerData = followerDoc.data()!;
            
            // Check if user has signupCompleted (valid user)
            final signupCompleted = followerData['signupCompleted'] ?? false;
            if (!signupCompleted) {
              print('⚠️ Skipping user $followerId: signup not completed');
              continue;
            }
            
            final fullName = followerData['fullName'] ?? 
                           '${followerData['firstName'] ?? ''} ${followerData['lastName'] ?? ''}'.trim();
            final displayName = (fullName != null && fullName.isNotEmpty) 
                                ? fullName 
                                : (followerData['username'] ?? 'Unknown User');
            
            followersList.add({
              'userId': followerId,
              'username': followerData['username'] ?? 'Unknown User',
              'fullName': displayName,
              'profilePictureUrl': followerData['profilePictureUrl'] ?? '',
              'followedAt': followerData['lastFollowedAt'],
            });
          } else {
            print('⚠️ User $followerId not found in database (deleted user)');
            // Remove deleted user from followers array
            await _firestore.collection('users').doc(userId).update({
              'followers': FieldValue.arrayRemove([followerId]),
              'followersCount': FieldValue.increment(-1),
            });
            print('✅ Removed deleted user $followerId from followers');
          }
        } catch (e) {
          print('❌ Error processing follower user $followerId: $e');
        }
      }
      
      print('📊 Final followers list: ${followersList.length} valid users');
      
      // Clean up: Remove deleted users and duplicates from the array
      final validFollowerIds = followersList.map((f) => f['userId'] as String).toSet();
      final currentFollowersSet = followersSet;
      
      // Find deleted users (in array but not in valid list)
      final deletedFollowerIds = currentFollowersSet.where((id) => !validFollowerIds.contains(id)).toList();
      
      if (deletedFollowerIds.isNotEmpty || followersSet.length != followers.length) {
        print('⚠️ Cleaning up followers array: ${deletedFollowerIds.length} deleted users, ${followersSet.length - followers.length} duplicates');
        
        // Remove all invalid entries and update count
        final cleanedFollowers = validFollowerIds.toList();
        await _firestore.collection('users').doc(userId).update({
          'followers': cleanedFollowers,
          'followersCount': cleanedFollowers.length,
        });
        print('✅ Followers array cleaned: ${cleanedFollowers.length} valid followers');
      }
      
      return followersList;
    } catch (e) {
      print('❌ Error getting followers: $e');
      return [];
    }
  }

  /// Get user's following list
  static Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return [];

      final userData = userDoc.data()!;
      final following = userData['following'] as List<dynamic>? ?? [];
      
      // Remove duplicates and null/empty values
      final followingSet = following
          .where((id) => id != null && id.toString().isNotEmpty)
          .map((id) => id.toString())
          .toSet();
      
      print('🔍 Following array for user $userId: ${following.length} items');
      print('🔍 After deduplication: ${followingSet.length} unique items');
      print('🔍 Following IDs: $followingSet');
      
      List<Map<String, dynamic>> followingList = [];
      
      for (String followingId in followingSet) {
        try {
          final followingDoc = await _firestore.collection('users').doc(followingId).get();
          if (followingDoc.exists) {
            final followingData = followingDoc.data()!;
            
            // Check if user has signupCompleted (valid user)
            final signupCompleted = followingData['signupCompleted'] ?? false;
            if (!signupCompleted) {
              print('⚠️ Skipping user $followingId: signup not completed');
              continue;
            }
            
            final fullName = followingData['fullName'] ?? 
                           '${followingData['firstName'] ?? ''} ${followingData['lastName'] ?? ''}'.trim();
            final displayName = (fullName != null && fullName.isNotEmpty) 
                                ? fullName 
                                : (followingData['username'] ?? 'Unknown User');
            
            followingList.add({
              'userId': followingId,
              'username': followingData['username'] ?? 'Unknown User',
              'fullName': displayName,
              'profilePictureUrl': followingData['profilePictureUrl'] ?? '',
              'followedAt': followingData['lastFollowedAt'],
            });
            
            print('✅ Added following: $displayName (@${followingData['username']})');
          } else {
            print('⚠️ User $followingId not found in database (deleted user)');
            // Remove deleted user from following array
            await _firestore.collection('users').doc(userId).update({
              'following': FieldValue.arrayRemove([followingId]),
              'followingCount': FieldValue.increment(-1),
            });
            print('✅ Removed deleted user $followingId from following');
          }
        } catch (e) {
          print('❌ Error processing following user $followingId: $e');
        }
      }
      
      print('📊 Final following list: ${followingList.length} valid users');
      
      // Clean up: Remove deleted users and duplicates from the array
      final validFollowingIds = followingList.map((f) => f['userId'] as String).toSet();
      final currentFollowingSet = followingSet;
      
      // Find deleted users (in array but not in valid list)
      final deletedFollowingIds = currentFollowingSet.where((id) => !validFollowingIds.contains(id)).toList();
      
      if (deletedFollowingIds.isNotEmpty || followingSet.length != following.length) {
        print('⚠️ Cleaning up following array: ${deletedFollowingIds.length} deleted users, ${followingSet.length - following.length} duplicates');
        
        // Remove all invalid entries and update count
        final cleanedFollowing = validFollowingIds.toList();
        await _firestore.collection('users').doc(userId).update({
          'following': cleanedFollowing,
          'followingCount': cleanedFollowing.length,
        });
        print('✅ Following array cleaned: ${cleanedFollowing.length} valid following');
      }
      
      return followingList;
    } catch (e) {
      print('❌ Error getting following: $e');
      return [];
    }
  }

  /// Get follow counts for a user
  /// Calculates counts directly from arrays, verifying users exist
  static Future<Map<String, int>> getFollowCounts(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        return {'followers': 0, 'following': 0};
      }

      final userData = userDoc.data()!;
      
      // Get arrays
      final followers = userData['followers'] as List<dynamic>? ?? [];
      final following = userData['following'] as List<dynamic>? ?? [];
      
      // Remove duplicates and null values
      final followersSet = followers.where((id) => id != null && id.toString().isNotEmpty).map((id) => id.toString()).toSet();
      final followingSet = following.where((id) => id != null && id.toString().isNotEmpty).map((id) => id.toString()).toSet();
      
      // Verify that all follower/following users actually exist
      final validFollowers = <String>[];
      final validFollowing = <String>[];
      
      // Check followers
      for (String followerId in followersSet) {
        try {
          final followerDoc = await _firestore.collection('users').doc(followerId).get();
          if (followerDoc.exists) {
            final followerData = followerDoc.data()!;
            if (followerData['signupCompleted'] == true) {
              validFollowers.add(followerId);
            }
          }
        } catch (e) {
          print('⚠️ Error checking follower $followerId: $e');
        }
      }
      
      // Check following
      for (String followingId in followingSet) {
        try {
          final followingDoc = await _firestore.collection('users').doc(followingId).get();
          if (followingDoc.exists) {
            final followingData = followingDoc.data()!;
            if (followingData['signupCompleted'] == true) {
              validFollowing.add(followingId);
            }
          }
        } catch (e) {
          print('⚠️ Error checking following $followingId: $e');
        }
      }
      
      final followersCount = validFollowers.length;
      final followingCount = validFollowing.length;
      
      // Update the stored counts and arrays if they're different (sync them)
      final storedFollowersCount = userData['followersCount'] ?? 0;
      final storedFollowingCount = userData['followingCount'] ?? 0;
      
      if (storedFollowersCount != followersCount || 
          storedFollowingCount != followingCount ||
          validFollowers.length != followersSet.length ||
          validFollowing.length != followingSet.length) {
        print('⚠️ Count mismatch detected for user $userId. Updating counts...');
        print('  - Followers: stored=$storedFollowersCount, actual=$followersCount (removed ${followersSet.length - validFollowers.length} deleted)');
        print('  - Following: stored=$storedFollowingCount, actual=$followingCount (removed ${followingSet.length - validFollowing.length} deleted)');
        
        // Update the arrays to remove deleted users, duplicates and nulls
        await _firestore.collection('users').doc(userId).update({
          'followers': validFollowers,
          'followersCount': followersCount,
          'following': validFollowing,
          'followingCount': followingCount,
        });
        
        print('✅ Counts synced for user $userId');
      }
      
      return {
        'followers': followersCount,
        'following': followingCount,
      };
    } catch (e) {
      print('❌ Error getting follow counts: $e');
      return {'followers': 0, 'following': 0};
    }
  }

  /// Get mutual follows between current user and target user
  static Future<List<Map<String, dynamic>>> getMutualFollows(String targetUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('current_user_id') ?? 
                           prefs.getString('signup_user_id') ?? '';
      
      if (currentUserId.isEmpty) return [];

      // Get current user's following
      final currentUserDoc = await _firestore.collection('users').doc(currentUserId).get();
      final currentUserData = currentUserDoc.data()!;
      final currentUserFollowing = currentUserData['following'] as List<dynamic>? ?? [];

      // Get target user's following
      final targetUserDoc = await _firestore.collection('users').doc(targetUserId).get();
      final targetUserData = targetUserDoc.data()!;
      final targetUserFollowing = targetUserData['following'] as List<dynamic>? ?? [];

      // Find mutual follows
      final mutualIds = currentUserFollowing.where((id) => targetUserFollowing.contains(id)).toList();
      
      List<Map<String, dynamic>> mutualFollows = [];
      
      for (String mutualId in mutualIds) {
        final mutualDoc = await _firestore.collection('users').doc(mutualId).get();
        if (mutualDoc.exists) {
          final mutualData = mutualDoc.data()!;
          mutualFollows.add({
            'userId': mutualId,
            'username': mutualData['username'] ?? 'Unknown User',
            'profilePictureUrl': mutualData['profilePictureUrl'] ?? '',
          });
        }
      }
      
      return mutualFollows;
    } catch (e) {
      print('❌ Error getting mutual follows: $e');
      return [];
    }
  }
}

