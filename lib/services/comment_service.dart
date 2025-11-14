import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CommentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  /// Add a comment to a product
  static Future<bool> addComment({
    required String productId,
    required String content,
    String? parentCommentId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('current_user_id') ?? 
                           prefs.getString('signup_user_id') ?? '';
      
      if (currentUserId.isEmpty) {
        print('❌ No current user ID found');
        return false;
      }

      // Get user data
      final userDoc = await _firestore.collection('users').doc(currentUserId).get();
      if (!userDoc.exists) {
        print('❌ User not found');
        return false;
      }

      final userData = userDoc.data()!;
      final username = userData['username'] ?? 'Unknown User';
      final profilePictureUrl = userData['profilePictureUrl'] ?? '';

      // Create comment document
      final commentData = {
        'productId': productId,
        'userId': currentUserId,
        'username': username,
        'profilePictureUrl': profilePictureUrl,
        'content': content,
        'parentCommentId': parentCommentId, // null for top-level comments
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'likes': 0,
        'replies': 0,
        'isDeleted': false,
      };

      await _firestore.collection('comments').add(commentData);

      // Update product comment count
      await _firestore.collection('products').doc(productId).update({
        'commentCount': FieldValue.increment(1),
        'lastCommentAt': FieldValue.serverTimestamp(),
      });

      // If this is a reply, update parent comment reply count
      if (parentCommentId != null) {
        await _firestore.collection('comments').doc(parentCommentId).update({
          'replies': FieldValue.increment(1),
        });
      }

      print('✅ Comment added successfully');
      return true;
    } catch (e) {
      print('❌ Error adding comment: $e');
      return false;
    }
  }

  /// Get comments for a product
  static Future<List<Map<String, dynamic>>> getComments(String productId) async {
    try {
      // Try with orderBy first
      try {
        final commentsSnapshot = await _firestore
            .collection('comments')
            .where('productId', isEqualTo: productId)
            .where('parentCommentId', isNull: true) // Only top-level comments
            .where('isDeleted', isEqualTo: false)
            .orderBy('createdAt', descending: true)
            .get();

        List<Map<String, dynamic>> comments = [];
        
        for (var doc in commentsSnapshot.docs) {
          final commentData = doc.data();
          commentData['commentId'] = doc.id;
          
          // Get replies for this comment
          final replies = await getReplies(doc.id);
          commentData['replies'] = replies;
          
          comments.add(commentData);
        }
        
        return comments;
      } catch (orderByError) {
        // If orderBy fails (missing index), try without it
        print('⚠️ OrderBy failed, trying without orderBy: $orderByError');
        final commentsSnapshot = await _firestore
            .collection('comments')
            .where('productId', isEqualTo: productId)
            .where('parentCommentId', isNull: true)
            .where('isDeleted', isEqualTo: false)
            .get();

        List<Map<String, dynamic>> comments = [];
        
        for (var doc in commentsSnapshot.docs) {
          final commentData = doc.data();
          commentData['commentId'] = doc.id;
          
          // Get replies for this comment
          final replies = await getReplies(doc.id);
          commentData['replies'] = replies;
          
          comments.add(commentData);
        }
        
        // Sort manually by createdAt
        comments.sort((a, b) {
          final aTime = a['createdAt'];
          final bTime = b['createdAt'];
          if (aTime == null || bTime == null) return 0;
          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime); // Descending
          }
          return 0;
        });
        
        return comments;
      }
    } catch (e) {
      print('❌ Error getting comments: $e');
      return [];
    }
  }

  /// Get replies for a comment
  static Future<List<Map<String, dynamic>>> getReplies(String parentCommentId) async {
    try {
      // Try with orderBy first, if it fails (no index), try without
      try {
        final repliesSnapshot = await _firestore
            .collection('comments')
            .where('parentCommentId', isEqualTo: parentCommentId)
            .where('isDeleted', isEqualTo: false)
            .orderBy('createdAt', descending: false) // Oldest first for replies
            .get();

        List<Map<String, dynamic>> replies = [];
        
        for (var doc in repliesSnapshot.docs) {
          final replyData = doc.data();
          replyData['commentId'] = doc.id;
          replies.add(replyData);
        }
        
        print('✅ Found ${replies.length} replies for comment $parentCommentId');
        return replies;
      } catch (orderByError) {
        // If orderBy fails (likely missing index), try without it
        print('⚠️ OrderBy failed for replies, trying without orderBy: $orderByError');
        final repliesSnapshot = await _firestore
            .collection('comments')
            .where('parentCommentId', isEqualTo: parentCommentId)
            .where('isDeleted', isEqualTo: false)
            .get();

        List<Map<String, dynamic>> replies = [];
        
        for (var doc in repliesSnapshot.docs) {
          final replyData = doc.data();
          replyData['commentId'] = doc.id;
          replies.add(replyData);
        }
        
        // Sort manually by createdAt
        replies.sort((a, b) {
          final aTime = a['createdAt'];
          final bTime = b['createdAt'];
          if (aTime == null || bTime == null) return 0;
          if (aTime is Timestamp && bTime is Timestamp) {
            return aTime.compareTo(bTime);
          }
          return 0;
        });
        
        print('✅ Found ${replies.length} replies for comment $parentCommentId (without orderBy)');
        return replies;
      }
    } catch (e) {
      print('❌ Error getting replies: $e');
      return [];
    }
  }

  /// Like a comment
  static Future<bool> likeComment(String commentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('current_user_id') ?? 
                           prefs.getString('signup_user_id') ?? '';
      
      if (currentUserId.isEmpty) return false;

      // Check if user already liked this comment
      final likeDoc = await _firestore
          .collection('comment_likes')
          .where('commentId', isEqualTo: commentId)
          .where('userId', isEqualTo: currentUserId)
          .limit(1)
          .get();

      if (likeDoc.docs.isNotEmpty) {
        // User already liked, unlike it
        await likeDoc.docs.first.reference.delete();
        await _firestore.collection('comments').doc(commentId).update({
          'likes': FieldValue.increment(-1),
        });
        print('✅ Comment unliked');
        return true;
      } else {
        // User hasn't liked, like it
        await _firestore.collection('comment_likes').add({
          'commentId': commentId,
          'userId': currentUserId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await _firestore.collection('comments').doc(commentId).update({
          'likes': FieldValue.increment(1),
        });
        print('✅ Comment liked');
        return true;
      }
    } catch (e) {
      print('❌ Error liking comment: $e');
      return false;
    }
  }

  /// Check if user liked a comment
  static Future<bool> isCommentLiked(String commentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('current_user_id') ?? 
                           prefs.getString('signup_user_id') ?? '';
      
      if (currentUserId.isEmpty) return false;

      final likeDoc = await _firestore
          .collection('comment_likes')
          .where('commentId', isEqualTo: commentId)
          .where('userId', isEqualTo: currentUserId)
          .limit(1)
          .get();

      return likeDoc.docs.isNotEmpty;
    } catch (e) {
      print('❌ Error checking like status: $e');
      return false;
    }
  }

  /// Delete a comment
  static Future<bool> deleteComment(String commentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('current_user_id') ?? 
                           prefs.getString('signup_user_id') ?? '';
      
      if (currentUserId.isEmpty) return false;

      // Get comment data
      final commentDoc = await _firestore.collection('comments').doc(commentId).get();
      if (!commentDoc.exists) return false;

      final commentData = commentDoc.data()!;
      
      // Check if user owns this comment
      if (commentData['userId'] != currentUserId) {
        print('❌ User does not own this comment');
        return false;
      }

      // Mark comment as deleted
      await _firestore.collection('comments').doc(commentId).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'content': '[This comment has been deleted]',
      });

      // Update product comment count
      await _firestore.collection('products').doc(commentData['productId']).update({
        'commentCount': FieldValue.increment(-1),
      });

      // If this is a reply, update parent comment reply count
      if (commentData['parentCommentId'] != null) {
        await _firestore.collection('comments').doc(commentData['parentCommentId']).update({
          'replies': FieldValue.increment(-1),
        });
      }

      print('✅ Comment deleted successfully');
      return true;
    } catch (e) {
      print('❌ Error deleting comment: $e');
      return false;
    }
  }

  /// Edit a comment
  static Future<bool> editComment(String commentId, String newContent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('current_user_id') ?? 
                           prefs.getString('signup_user_id') ?? '';
      
      if (currentUserId.isEmpty) return false;

      // Get comment data
      final commentDoc = await _firestore.collection('comments').doc(commentId).get();
      if (!commentDoc.exists) return false;

      final commentData = commentDoc.data()!;
      
      // Check if user owns this comment
      if (commentData['userId'] != currentUserId) {
        print('❌ User does not own this comment');
        return false;
      }

      // Update comment content
      await _firestore.collection('comments').doc(commentId).update({
        'content': newContent,
        'updatedAt': FieldValue.serverTimestamp(),
        'isEdited': true,
      });

      print('✅ Comment edited successfully');
      return true;
    } catch (e) {
      print('❌ Error editing comment: $e');
      return false;
    }
  }

  /// Get comment count for a product (only top-level comments, excludes replies)
  static Future<int> getCommentCount(String productId) async {
    try {
      final commentsSnapshot = await _firestore
          .collection('comments')
          .where('productId', isEqualTo: productId)
          .where('parentCommentId', isNull: true) // Only top-level comments, not replies
          .where('isDeleted', isEqualTo: false)
          .get();

      return commentsSnapshot.docs.length;
    } catch (e) {
      print('❌ Error getting comment count: $e');
      return 0;
    }
  }

  /// Get user's comments
  static Future<List<Map<String, dynamic>>> getUserComments(String userId) async {
    try {
      final commentsSnapshot = await _firestore
          .collection('comments')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .get();

      List<Map<String, dynamic>> comments = [];
      
      for (var doc in commentsSnapshot.docs) {
        final commentData = doc.data();
        commentData['commentId'] = doc.id;
        comments.add(commentData);
      }
      
      return comments;
    } catch (e) {
      print('❌ Error getting user comments: $e');
      return [];
    }
  }
}

