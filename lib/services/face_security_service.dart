import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import 'real_face_recognition_service.dart';

/// Security service to prevent duplicate face registrations and unauthorized access
class FaceSecurityService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  /// Check if a face is already registered by another user (SIGNUP-SPECIFIC)
  static Future<bool> isFaceAlreadyRegistered(Face newFace, [CameraImage? cameraImage]) async {
    try {
      print('🔍 SIGNUP SECURITY CHECK: Verifying face uniqueness with relaxed thresholds...');
      
      // Extract biometric features from the new face
      final newBiometrics = await RealFaceRecognitionService.extractBiometricFeatures(newFace, cameraImage);
      
      // Get all existing users with biometric data
      final usersSnapshot = await _firestore
          .collection('users')
          .where('verificationStatus', isEqualTo: 'verified')
          .get();
      
      print('🔍 Checking against ${usersSnapshot.docs.length} verified users for signup...');
      
      if (usersSnapshot.docs.isEmpty) {
        print('✅ No existing users - face is unique for signup');
        return false;
      }
      
      // Check similarity with all existing users using RELAXED thresholds for signup
      for (final doc in usersSnapshot.docs) {
        final userData = doc.data();
        final biometricFeatures = userData['biometricFeatures'];
        
        if (biometricFeatures is Map && biometricFeatures.containsKey('biometricSignature')) {
          final storedSignature = List<double>.from(biometricFeatures['biometricSignature']);
          final similarity = RealFaceRecognitionService.calculateBiometricSimilarity(
            newBiometrics, 
            storedSignature,
          );
          
          print('📊 Signup similarity with user ${doc.id}: $similarity');
          
          // BALANCED threshold for signup: 90% similarity to prevent false positives
          // This prevents false positives during signup while maintaining security
          if (similarity > 0.90) {
            print('🚨 SIGNUP BLOCKED: Face too similar to existing user ${doc.id} (similarity: $similarity)');
            return true;
          }
        }
      }
      
      print('✅ Face is unique for signup - not registered by any other user');
      return false;
      
    } catch (e) {
      print('❌ Error checking face uniqueness for signup: $e');
      // Fail safe: allow signup if check fails
      return false;
    }
  }

  /// Validate that a user's face matches their stored biometric data
  static Future<bool> validateUserFaceMatch(String userId, Face detectedFace, [CameraImage? cameraImage]) async {
    try {
      print('🔍 SECURITY VALIDATION: Verifying user face match for $userId...');
      
      // Get user's stored biometric data
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        print('❌ User not found: $userId');
        return false;
      }
      
      final userData = userDoc.data()!;
      final biometricFeatures = userData['biometricFeatures'];
      
      if (biometricFeatures == null) {
        print('❌ No biometric data found for user: $userId');
        return false;
      }
      
      // Extract features from detected face
      final detectedBiometrics = await RealFaceRecognitionService.extractBiometricFeatures(detectedFace, cameraImage);
      
      // Get stored signature
      List<double> storedSignature = [];
      if (biometricFeatures is Map && biometricFeatures.containsKey('biometricSignature')) {
        storedSignature = List<double>.from(biometricFeatures['biometricSignature']);
      }
      
      if (storedSignature.isEmpty) {
        print('❌ Invalid biometric data format for user: $userId');
        return false;
      }
      
      // Calculate similarity
      final similarity = RealFaceRecognitionService.calculateBiometricSimilarity(
        detectedBiometrics, 
        storedSignature,
      );
      
      print('📊 Face match similarity: $similarity');
      
      // Require high similarity for validation
      const double validationThreshold = 0.8;
      final isValid = similarity >= validationThreshold;
      
      if (isValid) {
        print('✅ Face validation passed for user $userId');
      } else {
        print('❌ Face validation failed for user $userId (similarity: $similarity < $validationThreshold)');
      }
      
      return isValid;
      
    } catch (e) {
      print('❌ Error validating user face match: $e');
      return false;
    }
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

