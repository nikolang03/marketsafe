import 'dart:typed_data';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

/// Service for detecting duplicate images/videos to prevent re-uploading downloaded content
class DuplicateDetectionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  /// Calculate hash of image file for duplicate detection
  static Future<String> calculateImageHash(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      return calculateImageHashFromBytes(bytes);
    } catch (e) {
      print('❌ Error calculating image hash: $e');
      rethrow;
    }
  }

  /// Calculate hash of image bytes for duplicate detection
  /// Uses perceptual hash (pHash) to detect similar images even if slightly modified
  static String calculateImageHashFromBytes(Uint8List imageBytes) {
    try {
      // Decode image
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        // Fallback to MD5 if image can't be decoded
        return md5.convert(imageBytes).toString();
      }

      // Resize to 8x8 for perceptual hash (pHash algorithm)
      final resized = img.copyResize(image, width: 8, height: 8);
      
      // Convert to grayscale
      final grayscale = img.grayscale(resized);
      
      // Calculate average pixel value
      int sum = 0;
      for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
          final pixel = grayscale.getPixel(x, y);
          sum += img.getLuminance(pixel).toInt();
        }
      }
      final average = sum ~/ 64;

      // Create hash: 1 if pixel > average, 0 otherwise
      final hash = StringBuffer();
      for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
          final pixel = grayscale.getPixel(x, y);
          final luminance = img.getLuminance(pixel).toInt();
          hash.write(luminance > average ? '1' : '0');
        }
      }

      return hash.toString();
    } catch (e) {
      print('❌ Error calculating perceptual hash: $e');
      // Fallback to MD5
      return md5.convert(imageBytes).toString();
    }
  }

  /// Calculate hash of video file for duplicate detection
  static Future<String> calculateVideoHash(File videoFile) async {
    try {
      // For videos, use file size + first and last 1KB for hash
      // This is a simple approach - could be improved with video frame extraction
      final fileSize = await videoFile.length();
      final firstBytes = await videoFile.openRead(0, 1024).first;
      final lastBytes = await videoFile.openRead(fileSize - 1024, fileSize).first;
      
      final combined = Uint8List.fromList([
        ...firstBytes,
        ...lastBytes,
        ..._intToBytes(fileSize),
      ]);
      
      return md5.convert(combined).toString();
    } catch (e) {
      print('❌ Error calculating video hash: $e');
      // Fallback to file size hash
      final fileSize = await videoFile.length();
      return md5.convert(_intToBytes(fileSize)).toString();
    }
  }

  /// Convert int to bytes
  static Uint8List _intToBytes(int value) {
    return Uint8List(8)
      ..buffer.asByteData().setInt64(0, value, Endian.big);
  }

  /// Check if image hash matches any existing product images
  static Future<bool> isDuplicateImage(String imageHash) async {
    try {
      print('🔍 Checking for duplicate image with hash: ${imageHash.substring(0, 16)}...');
      
      // Query products collection for matching image hashes
      // Note: We'll need to store image hashes in product documents
      // For now, we'll check image URLs and compare hashes
      final productsSnapshot = await _firestore
          .collection('products')
          .where('status', isEqualTo: 'active')
          .limit(1000) // Limit to prevent timeout
          .get();

      for (var doc in productsSnapshot.docs) {
        final data = doc.data();
        
        // Check imageUrl
        if (data['imageUrl'] != null) {
          final storedHash = data['imageHash'] as String?;
          if (storedHash != null && storedHash == imageHash) {
            print('❌ Duplicate image found in product: ${doc.id}');
            return true;
          }
        }
        
        // Check imageUrls array
        if (data['imageUrls'] != null) {
          final imageUrls = data['imageUrls'] as List<dynamic>?;
          if (imageUrls != null) {
            final imageHashes = data['imageHashes'] as List<dynamic>?;
            if (imageHashes != null) {
              for (var hash in imageHashes) {
                if (hash.toString() == imageHash) {
                  print('❌ Duplicate image found in product: ${doc.id}');
                  return true;
                }
              }
            }
          }
        }
      }

      print('✅ No duplicate image found');
      return false;
    } catch (e) {
      print('❌ Error checking duplicate image: $e');
      // On error, allow upload (fail open)
      return false;
    }
  }

  /// Check if video hash matches any existing product videos
  static Future<bool> isDuplicateVideo(String videoHash) async {
    try {
      print('🔍 Checking for duplicate video with hash: ${videoHash.length > 16 ? videoHash.substring(0, 16) : videoHash}...');
      
      // Query products collection for matching video hashes
      final productsSnapshot = await _firestore
          .collection('products')
          .where('status', isEqualTo: 'active')
          .where('mediaType', isEqualTo: 'video')
          .limit(1000)
          .get();

      for (var doc in productsSnapshot.docs) {
        final data = doc.data();
        
        if (data['videoUrl'] != null) {
          final storedHash = data['videoHash'] as String?;
          if (storedHash != null && storedHash == videoHash) {
            print('❌ Duplicate video found in product: ${doc.id}');
            return true;
          }
        }
      }

      print('✅ No duplicate video found');
      return false;
    } catch (e) {
      print('❌ Error checking duplicate video: $e');
      // On error, allow upload (fail open)
      return false;
    }
  }

  /// Calculate Hamming distance between two hashes (for perceptual hash comparison)
  static int hammingDistance(String hash1, String hash2) {
    if (hash1.length != hash2.length) {
      return hash1.length; // Max distance if lengths differ
    }
    
    int distance = 0;
    for (int i = 0; i < hash1.length; i++) {
      if (hash1[i] != hash2[i]) {
        distance++;
      }
    }
    return distance;
  }

  /// Check if image is similar to existing images (using perceptual hash)
  static Future<bool> isSimilarImage(String imageHash, {int threshold = 5}) async {
    try {
      print('🔍 Checking for similar image with hash: ${imageHash.length > 16 ? imageHash.substring(0, 16) : imageHash}...');
      
      final productsSnapshot = await _firestore
          .collection('products')
          .where('status', isEqualTo: 'active')
          .limit(1000)
          .get();

      for (var doc in productsSnapshot.docs) {
        final data = doc.data();
        
        // Check imageHashes array (primary method)
        if (data['imageHashes'] != null) {
          final imageHashes = data['imageHashes'] as List<dynamic>?;
          if (imageHashes != null) {
            for (var hash in imageHashes) {
              final hashStr = hash.toString();
              // Only compare if both are perceptual hashes (64 characters for 8x8 grid)
              if (hashStr.length == 64 && imageHash.length == 64) {
                final distance = hammingDistance(imageHash, hashStr);
                if (distance <= threshold) {
                  print('❌ Similar image found in product: ${doc.id} (distance: $distance)');
                  return true;
                }
              }
            }
          }
        }
        
        // Legacy: Check single imageHash field
        if (data['imageHash'] != null) {
          final storedHash = data['imageHash'].toString();
          if (storedHash.length == 64 && imageHash.length == 64) {
            final distance = hammingDistance(imageHash, storedHash);
            if (distance <= threshold) {
              print('❌ Similar image found in product: ${doc.id} (distance: $distance)');
              return true;
            }
          }
        }
      }

      print('✅ No similar image found');
      return false;
    } catch (e) {
      print('❌ Error checking similar image: $e');
      return false;
    }
  }
}

