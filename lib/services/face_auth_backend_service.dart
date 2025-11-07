import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Backend API service for face authentication
/// Calls secure backend endpoints instead of Luxand directly
class FaceAuthBackendService {
  FaceAuthBackendService({
    required this.backendUrl,
  });

  final String backendUrl;

  /// Enroll user face during signup
  /// Returns: { success: bool, uuid: String?, error: String? }
  /// Note: Luxand supports multiple enrollments per subject for better accuracy
  Future<Map<String, dynamic>> enroll({
    required String email,
    required Uint8List photoBytes,
  }) async {
    try {
      final base64Image = base64Encode(photoBytes);
      final uri = Uri.parse('$backendUrl/api/enroll');
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'photoBase64': base64Image,
        }),
      );

      if (response.statusCode ~/ 100 != 2) {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>?;
        return {
          'success': false,
          'error': errorBody?['error']?.toString() ?? 'Enrollment failed',
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final bool ok = body['ok'] == true;
      final String? uuid = body['uuid']?.toString();

      return {
        'success': ok,
        'uuid': uuid,
        'error': ok ? null : 'Enrollment failed',
      };
    } catch (e) {
      print('❌ Backend enroll error: $e');
      print('❌ Backend URL: $backendUrl');
      print('❌ Error details: ${e.toString()}');
      
      // Check if it's a connection error
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('your-backend-domain')) {
        return {
          'success': false,
          'error': 'Backend server not reachable. Please check your backend URL configuration.',
        };
      }
      
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Verify face for login
  /// Returns: { ok: bool, similarity: double?, threshold: double?, message: String?, error: String? }
  Future<Map<String, dynamic>> verify({
    required String email,
    required Uint8List photoBytes,
    String? luxandUuid, // Optional: pass UUID for 1:1 verification
  }) async {
    try {
      final base64Image = base64Encode(photoBytes);
      final uri = Uri.parse('$backendUrl/api/verify');
      
      final requestBody = <String, dynamic>{
        'email': email,
        'photoBase64': base64Image,
      };
      
      // Add UUID if provided for 1:1 verification
      if (luxandUuid != null && luxandUuid.isNotEmpty) {
        requestBody['luxandUuid'] = luxandUuid;
      }
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 404) {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>?;
        return {
          'ok': false,
          'error': errorBody?['error']?.toString() ?? 'User not found or not enrolled',
        };
      }

      if (response.statusCode == 403) {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>?;
        return {
          'ok': false,
          'reason': errorBody?['reason']?.toString() ?? 'liveness_failed',
          'score': errorBody?['score'] as double?,
          'error': 'Liveness check failed. Please blink or turn your head slightly and try again.',
        };
      }

      if (response.statusCode ~/ 100 != 2) {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>?;
        return {
          'ok': false,
          'error': errorBody?['error']?.toString() ?? 'Verification failed',
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final bool ok = body['ok'] == true;
      final double? similarity = (body['similarity'] as num?)?.toDouble();
      final double? threshold = (body['threshold'] as num?)?.toDouble();
      final String? message = body['message']?.toString();

      return {
        'ok': ok,
        'similarity': similarity,
        'threshold': threshold,
        'message': message,
        'error': ok ? null : (message ?? 'Verification failed'),
      };
    } catch (e) {
      print('❌ Backend verify error: $e');
      return {
        'ok': false,
        'error': 'Network error. Please check your connection and try again.',
      };
    }
  }

  /// Health check
  Future<bool> healthCheck() async {
    try {
      final uri = Uri.parse('$backendUrl/api/health');
      final response = await http.get(uri);
      return response.statusCode ~/ 100 == 2;
    } catch (e) {
      return false;
    }
  }
}

