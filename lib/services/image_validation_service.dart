import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'watermarking_service.dart';

class ImageValidationService {
  /// Validates image before upload and shows appropriate dialogs
  static Future<bool> validateImageForUpload({
    required File imageFile,
    required String username,
    String? userId,
    required BuildContext context,
  }) async {
    try {
      print('🔍 Validating image for upload...');
      
      // Read image bytes
      final imageBytes = await imageFile.readAsBytes();
      
      // Check if image is from internet
      final isFromInternet = await WatermarkingService.isImageFromInternet(imageBytes);
      if (isFromInternet) {
        await _showInternetImageDialog(context);
        return false;
      }
      
      // Validate image authenticity
      if (userId == null) {
        // Skip validation if userId is not provided
        return true;
      }
      final validationResult = await WatermarkingService.validateImageAuthenticity(
        imageBytes: imageBytes,
        username: username,
        userId: userId,
      );
      
      // Show warnings if any
      if (validationResult['warnings'].isNotEmpty) {
        await _showValidationWarningsDialog(context, validationResult);
      }
      
      // Check if image is too large
      final fileSize = await imageFile.length();
      if (fileSize > 10 * 1024 * 1024) { // 10MB limit
        await _showLargeImageDialog(context);
        return false;
      }
      
      // Check image dimensions
      final imageDimensions = await _getImageDimensions(imageBytes);
      if (imageDimensions != null) {
        if (imageDimensions['width']! < 100 || imageDimensions['height']! < 100) {
          await _showSmallImageDialog(context);
          return false;
        }
      }
      
      print('✅ Image validation passed');
      return true;
      
    } catch (e) {
      print('❌ Error validating image: $e');
      await _showValidationErrorDialog(context, e.toString());
      return false;
    }
  }

  /// Shows dialog for internet images
  static Future<void> _showInternetImageDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('Internet Image Detected'),
            ],
          ),
          content: const Text(
            'Images from the internet or web are not allowed for security and authenticity reasons.\n\n'
            'Please use images taken with your device camera or from your photo gallery.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Shows dialog for validation warnings
  static Future<void> _showValidationWarningsDialog(
    BuildContext context,
    Map<String, dynamic> validationResult,
  ) async {
    final warnings = validationResult['warnings'] as List<String>;
    final recommendations = validationResult['recommendations'] as List<String>;
    
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info, color: Colors.blue),
              SizedBox(width: 8),
              Text('Image Validation'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (warnings.isNotEmpty) ...[
                const Text('Warnings:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...warnings.map((warning) => Text('• $warning')).toList(),
                const SizedBox(height: 16),
              ],
              if (recommendations.isNotEmpty) ...[
                const Text('Recommendations:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...recommendations.map((rec) => Text('• $rec')).toList(),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Continue Anyway'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Shows dialog for large images
  static Future<void> _showLargeImageDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('Image Too Large'),
            ],
          ),
          content: const Text(
            'The selected image is too large (over 10MB).\n\n'
            'Please choose a smaller image or compress it before uploading.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Shows dialog for small images
  static Future<void> _showSmallImageDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('Image Too Small'),
            ],
          ),
          content: const Text(
            'The selected image is too small (less than 100x100 pixels).\n\n'
            'Please choose a higher resolution image for better quality.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Shows dialog for validation errors
  static Future<void> _showValidationErrorDialog(BuildContext context, String error) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('Validation Error'),
            ],
          ),
          content: Text('An error occurred while validating the image:\n\n$error'),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Gets image dimensions
  static Future<Map<String, int>?> _getImageDimensions(Uint8List imageBytes) async {
    try {
      // This is a simplified version - in production, use proper image library
      return {'width': 0, 'height': 0};
    } catch (e) {
      print('Error getting image dimensions: $e');
      return null;
    }
  }

  /// Validates image file type
  static bool isValidImageType(String filePath) {
    final extension = filePath.toLowerCase().split('.').last;
    const validExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
    return validExtensions.contains(extension);
  }

  /// Gets file size in MB
  static Future<double> getFileSizeInMB(File file) async {
    final bytes = await file.length();
    return bytes / (1024 * 1024);
  }
}
