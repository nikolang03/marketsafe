import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:math';

/// Service for extracting and validating facial landmarks (nose, eyes, lips, ears, etc.)
/// This enables the app to know "whose face is this" at a feature level
class FaceLandmarkService {
  /// Extract all facial landmarks as normalized feature vectors
  /// Returns a map of landmark types to their normalized positions
  static Map<String, List<double>> extractLandmarkFeatures(Face face) {
    final landmarks = face.landmarks;
    final box = face.boundingBox;
    final faceWidth = box.width;
    final faceHeight = box.height;
    
    // Normalize coordinates relative to face bounding box (0-1 range)
    Map<String, List<double>> features = {};
    
    // Left Eye
    if (landmarks.containsKey(FaceLandmarkType.leftEye)) {
      final leftEye = landmarks[FaceLandmarkType.leftEye]!;
      features['leftEye'] = [
        (leftEye.position.x - box.left) / faceWidth,
        (leftEye.position.y - box.top) / faceHeight,
      ];
    }
    
    // Right Eye
    if (landmarks.containsKey(FaceLandmarkType.rightEye)) {
      final rightEye = landmarks[FaceLandmarkType.rightEye]!;
      features['rightEye'] = [
        (rightEye.position.x - box.left) / faceWidth,
        (rightEye.position.y - box.top) / faceHeight,
      ];
    }
    
    // Nose Base
    if (landmarks.containsKey(FaceLandmarkType.noseBase)) {
      final nose = landmarks[FaceLandmarkType.noseBase]!;
      features['noseBase'] = [
        (nose.position.x - box.left) / faceWidth,
        (nose.position.y - box.top) / faceHeight,
      ];
    }
    
    // Bottom Mouth
    if (landmarks.containsKey(FaceLandmarkType.bottomMouth)) {
      final mouth = landmarks[FaceLandmarkType.bottomMouth]!;
      features['bottomMouth'] = [
        (mouth.position.x - box.left) / faceWidth,
        (mouth.position.y - box.top) / faceHeight,
      ];
    }
    
    // Left Cheek
    if (landmarks.containsKey(FaceLandmarkType.leftCheek)) {
      final leftCheek = landmarks[FaceLandmarkType.leftCheek]!;
      features['leftCheek'] = [
        (leftCheek.position.x - box.left) / faceWidth,
        (leftCheek.position.y - box.top) / faceHeight,
      ];
    }
    
    // Right Cheek
    if (landmarks.containsKey(FaceLandmarkType.rightCheek)) {
      final rightCheek = landmarks[FaceLandmarkType.rightCheek]!;
      features['rightCheek'] = [
        (rightCheek.position.x - box.left) / faceWidth,
        (rightCheek.position.y - box.top) / faceHeight,
      ];
    }
    
    return features;
  }
  
  /// Calculate facial feature distances and ratios (unique per person)
  /// These ratios help identify "whose nose, eyes, lips, etc. is this"
  static Map<String, double> calculateFeatureDistances(Face face) {
    final landmarks = face.landmarks;
    final box = face.boundingBox;
    final faceWidth = box.width;
    final faceHeight = box.height;
    
    Map<String, double> distances = {};
    
    // Eye distance (interpupillary distance)
    if (landmarks.containsKey(FaceLandmarkType.leftEye) && 
        landmarks.containsKey(FaceLandmarkType.rightEye)) {
      final leftEye = landmarks[FaceLandmarkType.leftEye]!;
      final rightEye = landmarks[FaceLandmarkType.rightEye]!;
      final eyeDistance = sqrt(
        pow(rightEye.position.x - leftEye.position.x, 2) +
        pow(rightEye.position.y - leftEye.position.y, 2)
      );
      distances['eyeDistance'] = eyeDistance / faceWidth; // Normalized
    }
    
    // Nose to mouth distance
    if (landmarks.containsKey(FaceLandmarkType.noseBase) && 
        landmarks.containsKey(FaceLandmarkType.bottomMouth)) {
      final nose = landmarks[FaceLandmarkType.noseBase]!;
      final mouth = landmarks[FaceLandmarkType.bottomMouth]!;
      final noseMouthDistance = sqrt(
        pow(mouth.position.x - nose.position.x, 2) +
        pow(mouth.position.y - nose.position.y, 2)
      );
      distances['noseMouthDistance'] = noseMouthDistance / faceHeight; // Normalized
    }
    
    // Eye to nose distance (left)
    if (landmarks.containsKey(FaceLandmarkType.leftEye) && 
        landmarks.containsKey(FaceLandmarkType.noseBase)) {
      final leftEye = landmarks[FaceLandmarkType.leftEye]!;
      final nose = landmarks[FaceLandmarkType.noseBase]!;
      final leftEyeNoseDistance = sqrt(
        pow(nose.position.x - leftEye.position.x, 2) +
        pow(nose.position.y - leftEye.position.y, 2)
      );
      distances['leftEyeNoseDistance'] = leftEyeNoseDistance / faceHeight; // Normalized
    }
    
    // Eye to nose distance (right)
    if (landmarks.containsKey(FaceLandmarkType.rightEye) && 
        landmarks.containsKey(FaceLandmarkType.noseBase)) {
      final rightEye = landmarks[FaceLandmarkType.rightEye]!;
      final nose = landmarks[FaceLandmarkType.noseBase]!;
      final rightEyeNoseDistance = sqrt(
        pow(nose.position.x - rightEye.position.x, 2) +
        pow(nose.position.y - rightEye.position.y, 2)
      );
      distances['rightEyeNoseDistance'] = rightEyeNoseDistance / faceHeight; // Normalized
    }
    
    // Face width to height ratio
    distances['faceAspectRatio'] = faceWidth / faceHeight;
    
    // Symmetry check (left vs right features)
    if (landmarks.containsKey(FaceLandmarkType.leftEye) && 
        landmarks.containsKey(FaceLandmarkType.rightEye) &&
        landmarks.containsKey(FaceLandmarkType.noseBase)) {
      final leftEye = landmarks[FaceLandmarkType.leftEye]!;
      final rightEye = landmarks[FaceLandmarkType.rightEye]!;
      
      // Calculate symmetry (how centered the nose is between eyes)
      final faceCenterX = box.left + box.width / 2;
      final eyeCenterX = (leftEye.position.x + rightEye.position.x) / 2;
      final symmetry = 1.0 - (eyeCenterX - faceCenterX).abs() / faceWidth;
      distances['facialSymmetry'] = symmetry;
    }
    
    return distances;
  }
  
  /// Validate that all essential features are present
  /// Returns true if face has enough features for reliable recognition
  static bool validateEssentialFeatures(Face face) {
    final landmarks = face.landmarks;
    
    // Require: both eyes, nose, mouth (minimum for reliable recognition)
    final hasLeftEye = landmarks.containsKey(FaceLandmarkType.leftEye);
    final hasRightEye = landmarks.containsKey(FaceLandmarkType.rightEye);
    final hasNose = landmarks.containsKey(FaceLandmarkType.noseBase);
    final hasMouth = landmarks.containsKey(FaceLandmarkType.bottomMouth);
    
    // All 4 essential features required
    return hasLeftEye && hasRightEye && hasNose && hasMouth;
  }
  
  /// Compare landmark features between two faces
  /// Returns similarity score (0-1) based on feature positions
  static double compareLandmarkFeatures(
    Map<String, List<double>> features1,
    Map<String, List<double>> features2,
  ) {
    if (features1.isEmpty || features2.isEmpty) return 0.0;
    
    // Calculate average distance between matching landmarks
    double totalDistance = 0.0;
    int matchingFeatures = 0;
    
    for (final featureName in features1.keys) {
      if (features2.containsKey(featureName)) {
        final pos1 = features1[featureName]!;
        final pos2 = features2[featureName]!;
        
        if (pos1.length == 2 && pos2.length == 2) {
          final distance = sqrt(
            pow(pos1[0] - pos2[0], 2) +
            pow(pos1[1] - pos2[1], 2)
          );
          totalDistance += distance;
          matchingFeatures++;
        }
      }
    }
    
    if (matchingFeatures == 0) return 0.0;
    
    final avgDistance = totalDistance / matchingFeatures;
    
    // Convert distance to similarity (closer = higher similarity)
    // Threshold: 0.05 distance = 0.95 similarity, 0.1 distance = 0.9 similarity
    final similarity = (1.0 - (avgDistance / 0.1).clamp(0.0, 1.0));
    return similarity;
  }
}

