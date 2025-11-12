import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  /// Report a user
  static Future<bool> reportUser({
    required String reportedUserId,
    required String reason,
    String? customReason,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reporterUserId = prefs.getString('current_user_id') ?? 
                           prefs.getString('signup_user_id') ?? '';
      
      if (reporterUserId.isEmpty) {
        print('❌ No current user ID found');
        return false;
      }

      if (reporterUserId == reportedUserId) {
        print('❌ Cannot report yourself');
        return false;
      }

      // Get reporter and reported user info
      final reporterDoc = await _firestore.collection('users').doc(reporterUserId).get();
      final reportedDoc = await _firestore.collection('users').doc(reportedUserId).get();

      if (!reporterDoc.exists || !reportedDoc.exists) {
        print('❌ User not found');
        return false;
      }

      final reporterData = reporterDoc.data()!;
      final reportedData = reportedDoc.data()!;

      // Create report document
      await _firestore.collection('reports').add({
        'reporterId': reporterUserId,
        'reporterUsername': reporterData['username'] ?? 'Unknown',
        'reporterEmail': reporterData['email'] ?? '',
        'reportedUserId': reportedUserId,
        'reportedUsername': reportedData['username'] ?? 'Unknown',
        'reportedEmail': reportedData['email'] ?? '',
        'reason': reason,
        'customReason': customReason ?? '',
        'status': 'pending', // pending, reviewed, resolved, dismissed
        'createdAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
        'adminNotes': '',
      });

      print('✅ User reported successfully');
      return true;
    } catch (e) {
      print('❌ Error reporting user: $e');
      return false;
    }
  }

  /// Get all reports (for admin)
  static Stream<QuerySnapshot> getAllReports() {
    return _firestore
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Update report status (for admin)
  static Future<bool> updateReportStatus({
    required String reportId,
    required String status,
    String? adminNotes,
    String? reviewedBy,
  }) async {
    try {
      await _firestore.collection('reports').doc(reportId).update({
        'status': status,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': reviewedBy,
        'adminNotes': adminNotes ?? '',
      });

      print('✅ Report status updated successfully');
      return true;
    } catch (e) {
      print('❌ Error updating report status: $e');
      return false;
    }
  }

  /// Get pending reports count (for admin)
  static Future<int> getPendingReportsCount() async {
    try {
      final snapshot = await _firestore
          .collection('reports')
          .where('status', isEqualTo: 'pending')
          .get();
      return snapshot.docs.length;
    } catch (e) {
      print('❌ Error getting pending reports count: $e');
      return 0;
    }
  }
}

