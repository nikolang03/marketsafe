import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:io';

class FaceDataService {
  // Use your specific database
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  // Update face verification step completion
  static Future<void> updateFaceVerificationStep(
    String step, {
    Map<String, dynamic>? metrics,
    String? imagePath,
    String? userId, // Optional: if provided, use this instead of Firebase Auth user
  }) async {
    try {
      // Check if Firebase is initialized
      if (Firebase.apps.isEmpty) {
        print('Firebase not initialized, skipping face verification step update');
        return;
      }
      
      String? targetUserId = userId;
      
      // If userId not provided, try to get from Firebase Auth
      if (targetUserId == null || targetUserId.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          targetUserId = user.uid;
        }
      }
      
      if (targetUserId == null || targetUserId.isEmpty) {
        print('No user ID found, skipping face verification step update');
        return;
      }

      print('Updating face verification step: $step for user: $targetUserId');

      final Map<String, dynamic> updateData = {
        'faceData.$step': true,
        'faceData.${step}CompletedAt': FieldValue.serverTimestamp(),
      };

      if (metrics != null) {
        updateData['faceData.faceMetrics.$step'] = metrics;
      }

      if (imagePath != null) {
        print('📤 Uploading face image from path: $imagePath');
        try {
          // Upload face image to Firebase Storage
          final imageUrl = await _uploadFaceImage(imagePath, targetUserId, step);
          updateData['faceData.faceImageUrl'] = imageUrl;
          print('✅ Face image uploaded successfully: $imageUrl');
        } catch (e) {
          print('❌ Failed to upload face image: $e');
        }
      } else {
        print('⚠️ No image path provided for step: $step');
      }

      await _firestore.collection('users').doc(targetUserId).update(updateData);
      print('✅ Face verification step updated successfully: $step for user: $targetUserId');
    } catch (e) {
      print('Error updating face verification step: $e');
      // Don't throw error - allow the app to continue
    }
  }

  // Save face image to Firebase Storage
  static Future<String> saveFaceImage(String imagePath, String userId) async {
    try {
      final ref = _storage.ref().child(
          'face_images/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg');
      final uploadTask = await ref.putFile(File(imagePath));
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      throw Exception('Failed to upload face image: $e');
    }
  }

  // Upload face image for specific step
  static Future<String> _uploadFaceImage(
      String imagePath, String userId, String step) async {
    try {
      print('🔄 Starting image upload for user: $userId, step: $step');
      print('📁 Image file path: $imagePath');
      
      // Check if file exists
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Image file does not exist at path: $imagePath');
      }
      
      final fileSize = await file.length();
      print('📏 Image file size: $fileSize bytes');
      
      final ref = _storage.ref().child(
          'face_images/$userId/${step}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      
      print('☁️ Uploading to Firebase Storage path: ${ref.fullPath}');
      final uploadTask = await ref.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      
      print('🎉 Image upload completed. Download URL: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      print('💥 Image upload failed: $e');
      throw Exception('Failed to upload face image: $e');
    }
  }

  // Get face data for user
  static Future<Map<String, dynamic>?> getFaceData(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data()?['faceData'];
    } catch (e) {
      print('Error getting face data: $e');
      return null;
    }
  }

  // Initialize face data for new user
  static Future<void> initializeFaceData(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'faceData': {
          'blinkCompleted': false,
          'moveCloserCompleted': false,
          'headMovementCompleted': false,
          'blinkCompletedAt': null,
          'moveCloserCompletedAt': null,
          'headMovementCompletedAt': null,
          'faceImageUrl': null,
          'faceMetrics': {},
        }
      });
    } catch (e) {
      print('Error initializing face data: $e');
    }
  }

  // Check if all face verification steps are completed
  static Future<bool> isFaceVerificationComplete(String userId) async {
    try {
      final faceData = await getFaceData(userId);
      if (faceData == null) return false;

      return faceData['blinkCompleted'] == true &&
          faceData['moveCloserCompleted'] == true &&
          faceData['headMovementCompleted'] == true;
    } catch (e) {
      return false;
    }
  }

  // Update user verification status
  static Future<void> updateVerificationStatus(
      String userId, String status) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'verificationStatus': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating verification status: $e');
    }
  }
}