import 'dart:typed_data';
import 'package:exif/exif.dart';
import 'dart:convert';

/// Service for embedding and reading EXIF metadata in images
/// Note: Metadata is primarily stored in Firebase Storage custom metadata
/// EXIF reading is used to extract existing EXIF data from images
class ImageExifMetadataService {
  /// Prepare metadata map for Firebase Storage
  /// The metadata will be stored in Firebase Storage custom metadata
  static Map<String, String> prepareMetadata({
    required String username,
    required String userId,
    required String productId,
    String? deviceInfo,
  }) {
    final DateTime now = DateTime.now();
    final String uniqueId = '${productId}_${now.millisecondsSinceEpoch}';
    
    // Create metadata map
    final Map<String, String> metadataMap = {
      'username': username,
      'userId': userId,
      'productId': productId,
      'uniqueId': uniqueId,
      'uploadDate': now.toIso8601String(),
      'uploadTimestamp': now.millisecondsSinceEpoch.toString(),
      'deviceInfo': deviceInfo ?? 'Unknown',
      'appName': 'MarketSafe',
      'appVersion': '1.0.3',
    };
    
    print('📝 Prepared metadata: $metadataMap');
    return metadataMap;
  }

  /// Extract metadata from image
  /// Returns a map with all embedded metadata
  static Future<Map<String, dynamic>> extractMetadata(Uint8List imageBytes) async {
    try {
      final Map<String, dynamic> metadata = {};
      
      // Try to read EXIF data
      Map<String, IfdTag>? exifData;
      try {
        exifData = await readExifFromBytes(imageBytes);
      } catch (e) {
        print('⚠️ Could not read EXIF data: $e');
        exifData = null;
      }
      
      if (exifData != null && exifData.isNotEmpty) {
        print('📖 Found EXIF data: ${exifData.keys.toList()}');
        
        // Try to extract from UserComment (primary metadata location)
        if (exifData.containsKey('Image UserComment')) {
          final tag = exifData['Image UserComment'];
          if (tag != null) {
            try {
              final String? comment = tag.printable;
              if (comment != null && comment.isNotEmpty) {
                final decoded = jsonDecode(comment) as Map<String, dynamic>;
                metadata.addAll(decoded);
                print('✅ Extracted metadata from UserComment: $decoded');
              }
            } catch (e) {
              print('⚠️ UserComment is not JSON: ${tag.printable}');
            }
          }
        }
        
        // Also try EXIF UserComment
        if (exifData.containsKey('EXIF UserComment') && metadata.isEmpty) {
          final tag = exifData['EXIF UserComment'];
          if (tag != null) {
            try {
              final String? comment = tag.printable;
              if (comment != null && comment.isNotEmpty) {
                final decoded = jsonDecode(comment) as Map<String, dynamic>;
                metadata.addAll(decoded);
                print('✅ Extracted metadata from EXIF UserComment: $decoded');
              }
            } catch (e) {
              print('⚠️ EXIF UserComment is not JSON: ${tag.printable}');
            }
          }
        }
        
        // Extract individual fields as fallback
        if (metadata.isEmpty) {
          if (exifData.containsKey('Image Artist')) {
            metadata['username'] = exifData['Image Artist']?.printable;
          }
          if (exifData.containsKey('Image DateTime')) {
            metadata['uploadDate'] = exifData['Image DateTime']?.printable;
          }
          if (exifData.containsKey('EXIF DateTimeOriginal')) {
            metadata['uploadDate'] = exifData['EXIF DateTimeOriginal']?.printable;
          }
        }
        
        // Add camera info if available
        if (exifData.containsKey('Image Make')) {
          metadata['cameraMake'] = exifData['Image Make']?.printable;
        }
        if (exifData.containsKey('Image Model')) {
          metadata['cameraModel'] = exifData['Image Model']?.printable;
        }
        if (exifData.containsKey('EXIF DateTimeOriginal')) {
          metadata['dateTaken'] = exifData['EXIF DateTimeOriginal']?.printable;
        }
      } else {
        print('⚠️ No EXIF data found in image');
      }
      
      return metadata;
    } catch (e) {
      print('❌ Error extracting metadata: $e');
      return {};
    }
  }


  /// Get metadata summary for display
  static String formatMetadataForDisplay(Map<String, dynamic> metadata) {
    final List<String> lines = [];
    
    if (metadata.containsKey('username')) {
      lines.add('Username: ${metadata['username']}');
    }
    if (metadata.containsKey('uploadDate')) {
      final dateStr = metadata['uploadDate'];
      if (dateStr != null) {
        try {
          final date = DateTime.parse(dateStr);
          lines.add('Upload Date: ${_formatDate(date)}');
        } catch (e) {
          lines.add('Upload Date: $dateStr');
        }
      }
    }
    if (metadata.containsKey('uniqueId')) {
      lines.add('Unique ID: ${metadata['uniqueId']}');
    }
    if (metadata.containsKey('productId')) {
      lines.add('Product ID: ${metadata['productId']}');
    }
    if (metadata.containsKey('deviceInfo')) {
      lines.add('Device: ${metadata['deviceInfo']}');
    }
    if (metadata.containsKey('cameraMake') || metadata.containsKey('cameraModel')) {
      final make = metadata['cameraMake'] ?? '';
      final model = metadata['cameraModel'] ?? '';
      if (make.isNotEmpty || model.isNotEmpty) {
        lines.add('Camera: ${[make, model].where((s) => s.isNotEmpty).join(' ')}');
      }
    }
    
    return lines.join('\n');
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

