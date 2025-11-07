import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'watermarking_service.dart';

class VideoUploadService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload video to Firebase Storage and generate thumbnail with watermarking
  static Future<Map<String, String>> uploadVideoWithThumbnail({
    required String videoPath,
    required String userId,
    required String productId,
    String? username,
  }) async {
    try {
      print('🎥 Starting video upload process...');
      print('Video path: $videoPath');
      print('User ID: $userId');
      print('Product ID: $productId');

      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final videoExtension = path.extension(videoPath);
      final videoFileName = 'video_${timestamp}_${productId}$videoExtension';
      final thumbnailFileName = 'thumbnail_${timestamp}_${productId}.jpg';

      // Upload video file
      print('📤 Uploading video file...');
      final videoRef = _storage
          .ref()
          .child('product_videos')
          .child(userId)
          .child(videoFileName);

      final videoUploadTask = videoRef.putFile(File(videoPath));
      final videoSnapshot = await videoUploadTask;
      final videoUrl = await videoSnapshot.ref.getDownloadURL();

      print('✅ Video uploaded successfully: $videoUrl');

      // Generate thumbnail
      print('🖼️ Generating video thumbnail...');
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: (await Directory.systemTemp.createTemp()).path,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 300,
        quality: 75,
      );

      if (thumbnailPath == null) {
        throw Exception('Failed to generate video thumbnail');
      }

      print('✅ Thumbnail generated: $thumbnailPath');

      // Validate thumbnail authenticity and add watermark
      Uint8List thumbnailBytes;
      final fileBytes = await File(thumbnailPath).readAsBytes();
      
      // Check if thumbnail is from internet (shouldn't happen for video thumbnails, but safety check)
      final isFromInternet = await WatermarkingService.isImageFromInternet(fileBytes);
      if (isFromInternet) {
        print('⚠️ Video thumbnail appears to be from internet - this is unusual for video thumbnails');
      }
      
      if (username != null && username.isNotEmpty) {
        print('🎨 Adding username watermark to video thumbnail for user: $username');
        thumbnailBytes = await WatermarkingService.applyUsernameWatermark(
          imageBytes: fileBytes,
          username: username,
        );
        print('✅ Watermarked thumbnail generated');
      } else {
        thumbnailBytes = fileBytes;
        print('⚠️ No username provided, uploading thumbnail without watermark');
      }

      // Upload watermarked thumbnail
      print('📤 Uploading watermarked thumbnail...');
      final thumbnailRef = _storage
          .ref()
          .child('product_videos')
          .child(userId)
          .child(thumbnailFileName);

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'productId': productId,
          'uploadedAt': DateTime.now().toIso8601String(),
          'watermarked': username != null ? 'true' : 'false',
          'username': username ?? 'unknown',
        },
      );

      final thumbnailUploadTask = thumbnailRef.putData(thumbnailBytes, metadata);
      final thumbnailSnapshot = await thumbnailUploadTask;
      final thumbnailUrl = await thumbnailSnapshot.ref.getDownloadURL();

      print('✅ Watermarked thumbnail uploaded successfully: $thumbnailUrl');

      // Clean up temporary thumbnail file
      try {
        await File(thumbnailPath).delete();
        print('🗑️ Temporary thumbnail file cleaned up');
      } catch (e) {
        print('⚠️ Could not delete temporary thumbnail: $e');
      }

      return {
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl,
      };

    } catch (e) {
      print('❌ Error uploading video: $e');
      throw Exception('Failed to upload video: $e');
    }
  }

  /// Get video metadata (duration, size, etc.)
  static Future<Map<String, dynamic>> getVideoMetadata(String videoPath) async {
    try {
      final file = File(videoPath);
      final stat = await file.stat();
      
      return {
        'fileSize': stat.size,
        'lastModified': stat.modified,
        'path': videoPath,
      };
    } catch (e) {
      print('❌ Error getting video metadata: $e');
      return {};
    }
  }

  /// Validate video file
  static bool validateVideo(String videoPath) {
    try {
      final file = File(videoPath);
      if (!file.existsSync()) {
        print('❌ Video file does not exist: $videoPath');
        return false;
      }

      // Check file size (max 100MB)
      final fileSize = file.lengthSync();
      const maxSize = 100 * 1024 * 1024; // 100MB
      if (fileSize > maxSize) {
        print('❌ Video file too large: ${fileSize / (1024 * 1024)}MB (max 100MB)');
        return false;
      }

      // Check file extension
      final extension = path.extension(videoPath).toLowerCase();
      const allowedExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
      if (!allowedExtensions.contains(extension)) {
        print('❌ Unsupported video format: $extension');
        return false;
      }

      print('✅ Video file validation passed');
      return true;
    } catch (e) {
      print('❌ Error validating video: $e');
      return false;
    }
  }

  /// Delete video and thumbnail from storage
  static Future<void> deleteVideo({
    required String videoUrl,
    required String thumbnailUrl,
  }) async {
    try {
      print('🗑️ Deleting video and thumbnail from storage...');
      
      // Delete video
      final videoRef = _storage.refFromURL(videoUrl);
      await videoRef.delete();
      print('✅ Video deleted: $videoUrl');

      // Delete thumbnail
      final thumbnailRef = _storage.refFromURL(thumbnailUrl);
      await thumbnailRef.delete();
      print('✅ Thumbnail deleted: $thumbnailUrl');

    } catch (e) {
      print('❌ Error deleting video files: $e');
      throw Exception('Failed to delete video files: $e');
    }
  }
}

