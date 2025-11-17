import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/duplicate_detection_service.dart';

/// Service for downloading product media (images/videos) with watermark preservation
class MediaDownloadService {
  /// Download image with watermark preserved
  static Future<String?> downloadImage({
    required String imageUrl,
    required String productTitle,
    required BuildContext context,
    String? productId, // Optional: to get original hash from Firestore
  }) async {
    try {
      // Request storage permission based on Android version
      bool hasPermission = false;
      
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        
        if (sdkInt >= 33) {
          // Android 13+ (API 33+)
          final photosStatus = await Permission.photos.request();
          if (photosStatus.isGranted) {
            hasPermission = true;
          } else {
            // Try storage permission as fallback
            final storageStatus = await Permission.storage.request();
            hasPermission = storageStatus.isGranted;
          }
        } else {
          // Android 12 and below
          final storageStatus = await Permission.storage.request();
          hasPermission = storageStatus.isGranted;
        }
      } else if (Platform.isIOS) {
        // iOS - photos permission
        final photosStatus = await Permission.photos.request();
        hasPermission = photosStatus.isGranted;
      }
      
      if (!hasPermission) {
        print('❌ Permission denied');
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: Colors.grey[900],
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error, color: Colors.red, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Storage permission is required to download images. Please grant permission in app settings.',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  ),
                  child: const Text('OK', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        }
        return null;
      }
      
      print('✅ Permission granted');

      // Show downloading indicator (non-dismissible)
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Downloading image...'),
                ),
              ],
            ),
            duration: const Duration(seconds: 30), // Longer duration for download
            backgroundColor: Colors.grey[800],
          ),
        );
      }

      // SECURITY: Only allow HTTPS for network downloads (reject HTTP)
      if (!imageUrl.startsWith('https://') && imageUrl.startsWith('http://')) {
        throw Exception('SECURITY ERROR: HTTP image URLs are not allowed. Use HTTPS only.');
      }
      
      // Download image with timeout
      print('📥 Starting download from: $imageUrl');
      http.Response response;
      try {
        response = await http.get(
          Uri.parse(imageUrl),
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('Download timeout: Request took too long');
          },
        );
      } catch (e) {
        print('❌ HTTP request failed: $e');
        rethrow;
      }
      
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body size: ${response.bodyBytes.length} bytes');
      
      if (response.statusCode != 200) {
        throw Exception('Failed to download image: HTTP ${response.statusCode}');
      }

      if (response.bodyBytes.isEmpty) {
        throw Exception('Downloaded image is empty');
      }

      // Save image directly to gallery using gal package
      print('💾 Saving image to gallery...');
      
      try {
        // Request gallery permission first
        if (Platform.isAndroid || Platform.isIOS) {
          final hasAccess = await Gal.hasAccess();
          if (!hasAccess) {
            await Gal.requestAccess();
            // Check again after request
            final hasAccessAfterRequest = await Gal.hasAccess();
            if (!hasAccessAfterRequest) {
              throw Exception('Gallery access denied');
            }
          }
        }
        
        // Create filename with product title (sanitized)
        final sanitizedTitle = productTitle
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .replaceAll(RegExp(r'\s+'), '_');
        final finalTitle = sanitizedTitle.length > 30 
            ? sanitizedTitle.substring(0, 30) 
            : sanitizedTitle;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filename = 'MarketSafe_${finalTitle}_$timestamp.jpg';
        
        print('💾 Saving image with filename: $filename');
        
        // Save image bytes directly to gallery
        await Gal.putImageBytes(
          response.bodyBytes,
          name: filename,
        );
        
        print('✅ Image saved to gallery successfully');
        
        // Store all hashes from the product to prevent re-uploading
        // This handles cases where the downloaded file might be re-encoded
        try {
          List<String> hashesToStore = [];
          
          // If productId is provided, get ALL hashes from Firestore
          if (productId != null && productId.isNotEmpty) {
            try {
              final firestore = FirebaseFirestore.instanceFor(
                app: Firebase.app(),
                databaseId: 'marketsafe',
              );
              final productDoc = await firestore.collection('products').doc(productId).get();
              
              if (productDoc.exists) {
                final data = productDoc.data();
                // Get all hashes from imageHashes array (for multi-image products)
                if (data?['imageHashes'] != null) {
                  final imageHashes = data!['imageHashes'] as List<dynamic>?;
                  if (imageHashes != null && imageHashes.isNotEmpty) {
                    hashesToStore = imageHashes.map((h) => h.toString()).toList();
                    print('✅ Found ${hashesToStore.length} original image hashes from Firestore');
                  }
                }
                // Fallback to single imageHash field
                if (hashesToStore.isEmpty && data?['imageHash'] != null) {
                  hashesToStore = [data!['imageHash'].toString()];
                  print('✅ Found original image hash from Firestore (single)');
                }
              }
            } catch (e) {
              print('⚠️ Could not fetch product hash from Firestore: $e');
            }
          }
          
          // If we couldn't get hashes from Firestore, calculate from downloaded file
          if (hashesToStore.isEmpty) {
            final calculatedHash = DuplicateDetectionService.calculateImageHashFromBytes(response.bodyBytes);
            hashesToStore = [calculatedHash];
            print('✅ Calculated hash from downloaded image: ${calculatedHash.substring(0, 16)}...');
          }
          
          // Store all hashes
          for (final hash in hashesToStore) {
            await _storeDownloadedFileHash(hash, 'image');
          }
          print('✅ Stored ${hashesToStore.length} downloaded image hash(es)');
        } catch (e) {
          print('⚠️ Could not store downloaded image hash: $e');
          // Don't fail the download if hash storage fails
        }
      } catch (e) {
        print('❌ Error saving to gallery: $e');
        throw Exception('Failed to save image to gallery: $e');
      }

      // Show success dialog
      if (!context.mounted) {
        print('⚠️ Context not mounted, cannot show success dialog');
        return 'gallery';
      }
      
      // Clear the downloading indicator first
      ScaffoldMessenger.of(context).clearSnackBars();
      
      // Wait a moment to ensure the clear takes effect
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Show success dialog
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.grey[900],
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 48),
              SizedBox(height: 16),
              Text(
                'Download Complete',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      
      print('✅ Success dialog shown');

      return 'gallery';
    } catch (e, stackTrace) {
      print('❌ Error downloading image: $e');
      print('❌ Stack trace: $stackTrace');
      
      // Clear the downloading indicator
      if (!context.mounted) {
        print('⚠️ Context not mounted, cannot show error message');
        return null;
      }
      
      ScaffoldMessenger.of(context).clearSnackBars();
      
      // Wait a moment to ensure the clear takes effect
      await Future.delayed(const Duration(milliseconds: 100));
      
      String errorMessage = 'Failed to download image';
      if (e.toString().contains('timeout')) {
        errorMessage = 'Download timeout. Please check your internet connection and try again.';
      } else if (e.toString().contains('permission')) {
        errorMessage = 'Permission denied. Please grant storage permission in app settings.';
      } else if (e.toString().contains('HTTP')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else if (e.toString().contains('Could not access')) {
        errorMessage = 'Storage error. Please check app permissions.';
      } else {
        errorMessage = 'Error: ${e.toString().length > 100 ? e.toString().substring(0, 100) + "..." : e.toString()}';
      }
      
      // Show error dialog instead of SnackBar
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.grey[900],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      
      print('❌ Error dialog shown');
      return null;
    }
  }

  /// Download video with watermark preserved
  static Future<String?> downloadVideo({
    required String videoUrl,
    required String productTitle,
    required BuildContext context,
    String? productId, // Optional: to get original hash from Firestore
  }) async {
    try {
      // Request storage permission based on Android version
      bool hasPermission = false;
      
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        
        if (sdkInt >= 33) {
          // Android 13+ (API 33+)
          final videosStatus = await Permission.videos.request();
          if (videosStatus.isGranted) {
            hasPermission = true;
          } else {
            // Try storage permission as fallback
            final storageStatus = await Permission.storage.request();
            hasPermission = storageStatus.isGranted;
          }
        } else {
          // Android 12 and below
          final storageStatus = await Permission.storage.request();
          hasPermission = storageStatus.isGranted;
        }
      } else if (Platform.isIOS) {
        // iOS - photos permission (videos are stored in photos)
        final photosStatus = await Permission.photos.request();
        hasPermission = photosStatus.isGranted;
      }
      
      if (!hasPermission) {
        print('❌ Permission denied');
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: Colors.grey[900],
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error, color: Colors.red, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Storage permission is required to download videos. Please grant permission in app settings.',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  ),
                  child: const Text('OK', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        }
        return null;
      }
      
      print('✅ Permission granted');

      // Show downloading indicator (non-dismissible)
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Downloading video... This may take a while.'),
                ),
              ],
            ),
            duration: const Duration(minutes: 5), // Longer duration for video download
            backgroundColor: Colors.grey[800],
          ),
        );
      }

      // SECURITY: Only allow HTTPS for network downloads (reject HTTP)
      if (!videoUrl.startsWith('https://') && videoUrl.startsWith('http://')) {
        throw Exception('SECURITY ERROR: HTTP video URLs are not allowed. Use HTTPS only.');
      }
      
      // Download video with timeout
      print('📥 Starting video download from: $videoUrl');
      final response = await http.get(
        Uri.parse(videoUrl),
      ).timeout(
        const Duration(minutes: 5), // Longer timeout for videos
        onTimeout: () {
          throw Exception('Download timeout: Video download took too long');
        },
      );
      
      print('📥 Video response status: ${response.statusCode}');
      print('📥 Video response body size: ${response.bodyBytes.length} bytes');
      
      if (response.statusCode != 200) {
        throw Exception('Failed to download video: HTTP ${response.statusCode}');
      }

      if (response.bodyBytes.isEmpty) {
        throw Exception('Downloaded video is empty');
      }

      // Save video to temporary file first, then to gallery
      print('💾 Saving video to gallery...');
      
      try {
        // Get temporary directory to save video first
        final tempDir = await getTemporaryDirectory();
        final sanitizedTitle = productTitle
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .replaceAll(RegExp(r'\s+'), '_');
        final finalTitle = sanitizedTitle.length > 30 ? sanitizedTitle.substring(0, 30) : sanitizedTitle;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final tempFile = File('${tempDir.path}/MarketSafe_${finalTitle}_$timestamp.mp4');
        
        // Save to temporary file first
        await tempFile.writeAsBytes(response.bodyBytes);
        print('✅ Video saved to temp file: ${tempFile.path}');
        
        // Request gallery permission first
        if (Platform.isAndroid || Platform.isIOS) {
          final hasAccess = await Gal.hasAccess();
          if (!hasAccess) {
            await Gal.requestAccess();
            // Check again after request
            final hasAccessAfterRequest = await Gal.hasAccess();
            if (!hasAccessAfterRequest) {
              throw Exception('Gallery access denied');
            }
          }
        }
        
        // Now save to gallery using gal package
        await Gal.putVideo(
          tempFile.path,
          album: 'MarketSafe',
        );
        
        print('✅ Video saved to gallery successfully');
        
        // Store hash to prevent re-uploading
        // Get original hash from Firestore (videos are less likely to be re-encoded)
        try {
          String? videoHash;
          
          // If productId is provided, get the original hash from Firestore
          if (productId != null && productId.isNotEmpty) {
            try {
              final firestore = FirebaseFirestore.instanceFor(
                app: Firebase.app(),
                databaseId: 'marketsafe',
              );
              final productDoc = await firestore.collection('products').doc(productId).get();
              
              if (productDoc.exists) {
                final data = productDoc.data();
                if (data?['videoHash'] != null) {
                  videoHash = data!['videoHash'].toString();
                  print('✅ Found original video hash from Firestore: ${videoHash.substring(0, 16)}...');
                }
              }
            } catch (e) {
              print('⚠️ Could not fetch product hash from Firestore: $e');
            }
          }
          
          // If we couldn't get hash from Firestore, calculate from downloaded file
          if (videoHash == null) {
            videoHash = await DuplicateDetectionService.calculateVideoHash(tempFile);
            print('✅ Calculated hash from downloaded video: ${videoHash.substring(0, 16)}...');
          }
          
          // Store the hash
          await _storeDownloadedFileHash(videoHash, 'video');
          print('✅ Downloaded video hash stored: ${videoHash.substring(0, 16)}...');
        } catch (e) {
          print('⚠️ Could not store downloaded video hash: $e');
          // Don't fail the download if hash storage fails
        }
        
        // Clean up temporary file
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
            print('✅ Temp file cleaned up');
          }
        } catch (e) {
          print('⚠️ Could not delete temp file: $e');
        }
      } catch (e) {
        print('❌ Error saving video to gallery: $e');
        throw Exception('Failed to save video to gallery: $e');
      }

      // Show success dialog
      if (!context.mounted) {
        print('⚠️ Context not mounted, cannot show success dialog');
        return 'gallery';
      }
      
      // Clear the downloading indicator first
      ScaffoldMessenger.of(context).clearSnackBars();
      
      // Wait a moment to ensure the clear takes effect
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Show success dialog
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.grey[900],
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 48),
              SizedBox(height: 16),
              Text(
                'Download Complete',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      
      print('✅ Success dialog shown');

      return 'gallery';
    } catch (e, stackTrace) {
      print('❌ Error downloading video: $e');
      print('❌ Stack trace: $stackTrace');
      
      // Clear the downloading indicator
      if (!context.mounted) {
        print('⚠️ Context not mounted, cannot show error dialog');
        return null;
      }
      
      ScaffoldMessenger.of(context).clearSnackBars();
      
      // Wait a moment to ensure the clear takes effect
      await Future.delayed(const Duration(milliseconds: 100));
      
      String errorMessage = 'Failed to download video';
      if (e.toString().contains('timeout')) {
        errorMessage = 'Download timeout. Video may be too large. Please try again.';
      } else if (e.toString().contains('permission')) {
        errorMessage = 'Permission denied. Please grant storage permission in app settings.';
      } else if (e.toString().contains('HTTP')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else {
        errorMessage = 'Error: ${e.toString().length > 100 ? e.toString().substring(0, 100) + "..." : e.toString()}';
      }
      
      // Show error dialog instead of SnackBar
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.grey[900],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      
      print('❌ Error dialog shown');
      return null;
    }
  }


  /// Show download dialog
  static Future<void> showDownloadDialog({
    required BuildContext context,
    required String mediaUrl,
    required String productTitle,
    required bool isVideo,
    String? productId, // Optional: to get original hash from Firestore
  }) async {
    print('📥 Show download dialog called');
    print('📥 Media URL: $mediaUrl');
    print('📥 Is Video: $isVideo');
    print('📥 Product Title: $productTitle');
    
    if (!context.mounted) {
      print('❌ Context not mounted, cannot show dialog');
      return;
    }
    
    // Store the original context before showing dialog
    final originalContext = context;
    
    try {
      print('📥 About to show dialog...');
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          print('📥 Building download dialog widget');
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Text(
              isVideo ? 'Download Video' : 'Download Image',
              style: const TextStyle(color: Colors.white),
            ),
            content: Text(
              isVideo
                  ? 'Download this video to your device? The video will include the product watermark.'
                  : 'Download this image to your device? The image includes the product watermark.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  print('📥 Download cancelled by user');
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  print('📥 Download button pressed by user');
                  Navigator.of(dialogContext).pop(true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text('Download', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );
      
      print('📥 Dialog closed. Result: $result');
      
      // If user confirmed download, proceed with download using original context
      if (result == true && originalContext.mounted) {
        // Small delay to ensure dialog is fully closed
        await Future.delayed(const Duration(milliseconds: 300));
        
        if (!originalContext.mounted) {
          print('❌ Original context not mounted after delay');
          return;
        }
        
        try {
          if (isVideo) {
            print('📥 Starting video download...');
            final result = await downloadVideo(
              videoUrl: mediaUrl,
              productTitle: productTitle,
              context: originalContext,
              productId: productId,
            );
            print('📥 Video download result: $result');
          } else {
            print('📥 Starting image download...');
            final result = await downloadImage(
              imageUrl: mediaUrl,
              productTitle: productTitle,
              context: originalContext,
              productId: productId,
            );
            print('📥 Image download result: $result');
          }
        } catch (e, stackTrace) {
          print('❌ Error in download: $e');
          print('❌ Stack trace: $stackTrace');
          if (originalContext.mounted) {
            // Clear any existing snackbars
            ScaffoldMessenger.of(originalContext).clearSnackBars();
            await Future.delayed(const Duration(milliseconds: 100));
            
            // Show error dialog
            showDialog(
              context: originalContext,
              barrierDismissible: true,
              builder: (dialogContext) => AlertDialog(
                backgroundColor: Colors.grey[900],
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Download failed: ${e.toString().length > 100 ? e.toString().substring(0, 100) + "..." : e.toString()}',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    ),
                    child: const Text('OK', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          }
        }
      }
      
      print('📥 showDownloadDialog completed');
    } catch (e, stackTrace) {
      print('❌ Error showing download dialog: $e');
      print('❌ Stack trace: $stackTrace');
    }
  }

  /// Store downloaded file hash to prevent re-uploading
  static Future<void> _storeDownloadedFileHash(String hash, String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'downloaded_${type}_hashes';
      final existingHashes = prefs.getStringList(key) ?? [];
      
      // Add new hash if not already present
      if (!existingHashes.contains(hash)) {
        existingHashes.add(hash);
        await prefs.setStringList(key, existingHashes);
        print('✅ Stored downloaded $type hash (total: ${existingHashes.length})');
      } else {
        print('ℹ️ Hash already stored for this $type');
      }
    } catch (e) {
      print('❌ Error storing downloaded file hash: $e');
      rethrow;
    }
  }

  /// Check if a file hash matches any downloaded file
  /// For images, also checks perceptual hash similarity (handles re-encoding)
  static Future<bool> isDownloadedFile(String hash, String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'downloaded_${type}_hashes';
      final downloadedHashes = prefs.getStringList(key) ?? [];
      
      // Exact match check
      if (downloadedHashes.contains(hash)) {
        print('❌ File hash exactly matches a downloaded $type');
        return true;
      }
      
      // For images, also check perceptual hash similarity (handles re-encoding/compression)
      if (type == 'image') {
        // Check if hash is similar to any downloaded hash (using Hamming distance)
        // Perceptual hashes are 64 characters (0s and 1s), MD5 hashes are 32 hex characters
        for (final downloadedHash in downloadedHashes) {
          // Both hashes must be the same length and format for comparison
          if (hash.length == downloadedHash.length) {
            // If both are 64-char perceptual hashes, use Hamming distance
            if (hash.length == 64 && _isBinaryString(hash) && _isBinaryString(downloadedHash)) {
              final distance = DuplicateDetectionService.hammingDistance(hash, downloadedHash);
              // If Hamming distance is <= 10, consider it a match (handles minor re-encoding)
              if (distance <= 10) {
                print('❌ File hash is similar to a downloaded image (distance: $distance)');
                return true;
              }
            }
            // For MD5 hashes (32 hex chars), exact match only (already checked above)
          }
        }
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking downloaded file: $e');
      // On error, assume not downloaded (fail open)
      return false;
    }
  }

  /// Check if a string is a binary string (only 0s and 1s)
  static bool _isBinaryString(String str) {
    return str.split('').every((char) => char == '0' || char == '1');
  }
}

