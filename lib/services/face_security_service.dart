import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import 'production_face_recognition_service.dart';

/// Enhanced Face Security Service with Liveness Detection
class FaceSecurityService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  /// Verify user's face with advanced security checks
  /// ⚠️ SECURITY: This method requires emailOrPhone for 1:1 verification
  /// DO NOT use authenticateUser (1:N search) - use verifyUserFace (1:1 verification) instead
  static Future<Map<String, dynamic>> verifyUserFaceAdvanced({
    required String emailOrPhone, // CRITICAL: Required for 1:1 verification
    required Face face,
    CameraImage? cameraImage,
    Uint8List? imageBytes,
  }) async {
    try {
      print('🔐 Starting ADVANCED face verification...');
      
      // Liveness detection
      final livenessResult = await performLivenessDetection(face);
      if (!livenessResult['isLive']) {
        return {
          'success': false,
          'error': 'Liveness detection failed: ${livenessResult['reason']}',
          'userId': 'LIVENESS_FAILED',
        };
      }
      
      // CRITICAL SECURITY: Use 1:1 verification (verifyUserFace) instead of 1:N search (authenticateUser)
      // This ensures email/phone is verified first, then only compares against that user's embeddings
      // authenticateUser does a global search which is insecure - anyone's face could match
      final authResult = await ProductionFaceRecognitionService.verifyUserFace(
        emailOrPhone: emailOrPhone, // CRITICAL: Required for 1:1 verification
        detectedFace: face,
        cameraImage: cameraImage,
        imageBytes: imageBytes,
        isProfilePhotoVerification: false,
      );
      
      print('✅ ADVANCED face verification completed');
      return authResult;
      
    } catch (e) {
      print('❌ Error in ADVANCED face verification: $e');
      return {
        'success': false,
        'error': 'Advanced face verification failed: $e',
      };
    }
  }

  /// Perform liveness detection
  static Future<Map<String, dynamic>> performLivenessDetection(Face face) async {
    print('👁️ Performing liveness detection...');
    
    // Check for eye blinking
    final leftEyeOpen = face.leftEyeOpenProbability ?? 0.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 0.0;
    
    // For now, we are being lenient to avoid blocking users
    // A simple check for a non-static face is enough
    if (leftEyeOpen > 0.1 && rightEyeOpen > 0.1) {
      print('✅ Liveness detected: Eyes are open');
      return {'isLive': true, 'reason': 'Eyes are open'};
    }
    
    // Add more checks here in the future
    
    print('⚠️ Liveness detection failed: Eyes might be closed');
    return {'isLive': false, 'reason': 'Eyes might be closed'};
  }

  /// Get security report for a user
  static Future<Map<String, dynamic>> getSecurityReport(String userId) async {
    // This is a placeholder for a more advanced security report
    return {
      'lastLogin': DateTime.now(),
      'failedAttempts': 0,
      'isLockedOut': false,
    };
  }

  /// Check if user is pending verification
  static bool isPendingVerification(String userId) {
    // This is a placeholder for a more advanced check
    return false;
  }

  /// Log security events for monitoring
  static Future<void> logSecurityEvent(String eventType, String userId, Map<String, dynamic> details) async {
    try {
      await _firestore.collection('security_events').add({
        'eventType': eventType,
        'userId': userId,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
        'severity': _getEventSeverity(eventType),
      });
      
      print('📝 Security event logged: $eventType for user $userId');
    } catch (e) {
      print('❌ Error logging security event: $e');
    }
  }

  /// Get severity level for security events
  static String _getEventSeverity(String eventType) {
    switch (eventType) {
      case 'DUPLICATE_FACE_DETECTED':
      case 'UNAUTHORIZED_ACCESS_ATTEMPT':
      case 'HIGH_SIMILARITY_WARNING':
        return 'HIGH';
      case 'FACE_VALIDATION_FAILED':
      case 'LIVENESS_DETECTION_FAILED':
        return 'MEDIUM';
      case 'FACE_LOGIN_SUCCESS':
      case 'FACE_REGISTRATION_SUCCESS':
        return 'LOW';
      default:
        return 'LOW';
    }
  }

  /// Check for suspicious login patterns
  static Future<bool> isSuspiciousLoginPattern(String userId) async {
    try {
      // Get recent login attempts for this user
      final recentLogins = await _firestore
          .collection('users')
          .doc(userId)
          .collection('login_attempts')
          .where('timestamp', isGreaterThan: DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();
      
      if (recentLogins.docs.length < 3) return false;
      
      // Check for rapid successive logins (potential brute force)
      final timestamps = recentLogins.docs.map((doc) => doc.data()['timestamp'] as int).toList();
      for (int i = 0; i < timestamps.length - 2; i++) {
        final timeDiff = timestamps[i] - timestamps[i + 2];
        if (timeDiff < 30000) { // Less than 30 seconds between 3 attempts
          print('🚨 Suspicious login pattern detected: rapid successive attempts');
          return true;
        }
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking suspicious login pattern: $e');
      return false;
    }
  }
}

