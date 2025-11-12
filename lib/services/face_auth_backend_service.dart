import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Backend API service for face authentication
/// Calls secure backend endpoints instead of Luxand directly
class FaceAuthBackendService {
  FaceAuthBackendService({
    required this.backendUrl,
  }) {
    print('🔧 FaceAuthBackendService initialized with URL: $backendUrl');
    if (backendUrl.contains('192.168.') || backendUrl.contains('localhost') || backendUrl.contains('127.0.0.1')) {
      print('⚠️ WARNING: Using local backend URL. This will only work on the same network.');
      print('⚠️ For production, use: https://marketsafe-production.up.railway.app');
    }
  }

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
      
      print('🔍 Enrolling face with backend: $backendUrl/api/enroll');
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'photoBase64': base64Image,
        }),
      ).timeout(
        const Duration(seconds: 60), // Increased to 60 seconds for slower networks/backends
        onTimeout: () {
          throw TimeoutException('Connection timeout after 60 seconds');
        },
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
    } on TimeoutException catch (e) {
      print('❌ Backend enroll timeout: $e');
      print('❌ Backend URL: $backendUrl');
      String errorMessage = 'Connection timeout. ';
      if (backendUrl.contains('192.168.') || backendUrl.contains('localhost') || backendUrl.contains('127.0.0.1')) {
        errorMessage += 'The app is trying to connect to a local backend ($backendUrl) which may not be accessible. Please use the production backend URL: https://marketsafe-production.up.railway.app';
      } else {
        errorMessage += 'Please check your internet connection and try again.';
      }
      return {
        'success': false,
        'error': errorMessage,
      };
    } on SocketException catch (e) {
      print('❌ Backend enroll socket error: $e');
      print('❌ Backend URL: $backendUrl');
      String errorMessage = 'Cannot connect to backend server. ';
      if (backendUrl.contains('192.168.') || backendUrl.contains('localhost') || backendUrl.contains('127.0.0.1')) {
        errorMessage += 'The app is configured to use a local backend ($backendUrl) which is not accessible. Please use the production backend URL: https://marketsafe-production.up.railway.app';
      } else {
        errorMessage += 'Please check your internet connection and ensure the backend is running.';
      }
      return {
        'success': false,
        'error': errorMessage,
      };
    } catch (e) {
      print('❌ Backend enroll error: $e');
      print('❌ Backend URL: $backendUrl');
      print('❌ Error type: ${e.runtimeType}');
      
      String errorMessage = 'Network error. ';
      if (e.toString().contains('Connection timed out') || e.toString().contains('timeout')) {
        errorMessage += 'Connection timeout. ';
        if (backendUrl.contains('192.168.') || backendUrl.contains('localhost') || backendUrl.contains('127.0.0.1')) {
          errorMessage += 'The app is trying to connect to a local backend ($backendUrl) which may not be accessible. Please use the production backend URL: https://marketsafe-production.up.railway.app';
        } else {
          errorMessage += 'Please check your internet connection and try again.';
        }
      } else if (e.toString().contains('Failed host lookup') || e.toString().contains('Connection refused')) {
        errorMessage += 'Cannot reach backend server. ';
        if (backendUrl.contains('192.168.') || backendUrl.contains('localhost') || backendUrl.contains('127.0.0.1')) {
          errorMessage += 'The app is configured to use a local backend ($backendUrl) which is not accessible. Please use the production backend URL: https://marketsafe-production.up.railway.app';
        } else {
          errorMessage += 'Please check your internet connection.';
        }
      } else {
        errorMessage += 'Please check your connection and try again.';
      }
      
      return {
        'success': false,
        'error': errorMessage,
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
      
      print('🔍 Verifying face with backend: $backendUrl/api/verify');
      
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
      ).timeout(
        const Duration(seconds: 60), // Increased to 60 seconds for slower networks/backends
        onTimeout: () {
          throw TimeoutException('Connection timeout after 60 seconds');
        },
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
    } on TimeoutException catch (e) {
      print('❌ Backend verify timeout: $e');
      print('❌ Backend URL: $backendUrl');
      String errorMessage = 'Connection timeout. ';
      if (backendUrl.contains('192.168.') || backendUrl.contains('localhost') || backendUrl.contains('127.0.0.1')) {
        errorMessage += 'The app is trying to connect to a local backend ($backendUrl) which may not be accessible. Please use the production backend URL.';
      } else {
        errorMessage += 'Please check your internet connection and try again.';
      }
      return {
        'ok': false,
        'error': errorMessage,
      };
    } on SocketException catch (e) {
      print('❌ Backend verify socket error: $e');
      print('❌ Backend URL: $backendUrl');
      String errorMessage = 'Cannot connect to backend server. ';
      if (backendUrl.contains('192.168.') || backendUrl.contains('localhost') || backendUrl.contains('127.0.0.1')) {
        errorMessage += 'The app is configured to use a local backend ($backendUrl) which is not accessible. Please use the production backend URL: https://marketsafe-production.up.railway.app';
      } else {
        errorMessage += 'Please check your internet connection and ensure the backend is running.';
      }
      return {
        'ok': false,
        'error': errorMessage,
      };
    } catch (e) {
      print('❌ Backend verify error: $e');
      print('❌ Backend URL: $backendUrl');
      print('❌ Error type: ${e.runtimeType}');
      
      String errorMessage = 'Network error. ';
      if (e.toString().contains('Connection timed out') || e.toString().contains('timeout')) {
        errorMessage += 'Connection timeout. ';
        if (backendUrl.contains('192.168.') || backendUrl.contains('localhost') || backendUrl.contains('127.0.0.1')) {
          errorMessage += 'The app is trying to connect to a local backend ($backendUrl) which may not be accessible. Please use the production backend URL: https://marketsafe-production.up.railway.app';
        } else {
          errorMessage += 'Please check your internet connection and try again.';
        }
      } else if (e.toString().contains('Failed host lookup') || e.toString().contains('Connection refused')) {
        errorMessage += 'Cannot reach backend server. ';
        if (backendUrl.contains('192.168.') || backendUrl.contains('localhost') || backendUrl.contains('127.0.0.1')) {
          errorMessage += 'The app is configured to use a local backend ($backendUrl) which is not accessible. Please use the production backend URL: https://marketsafe-production.up.railway.app';
        } else {
          errorMessage += 'Please check your internet connection.';
        }
      } else {
        errorMessage += 'Please check your connection and try again.';
      }
      
      return {
        'ok': false,
        'error': errorMessage,
      };
    }
  }

  /// Compare two faces using Luxand's Compare Facial Similarity API
  /// Returns: { ok: bool, similarity: double, match: bool, confidence: double? }
  Future<Map<String, dynamic>> compareFaces({
    required Uint8List photo1Bytes,
    required Uint8List photo2Bytes,
  }) async {
    try {
      final base64Image1 = base64Encode(photo1Bytes);
      final base64Image2 = base64Encode(photo2Bytes);
      final uri = Uri.parse('$backendUrl/api/compare-faces');
      
      print('🔍 Comparing faces with backend: $backendUrl/api/compare-faces');
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'photo1Base64': base64Image1,
          'photo2Base64': base64Image2,
        }),
      ).timeout(
        const Duration(seconds: 60), // Increased to 60 seconds for slower networks/backends
        onTimeout: () {
          throw TimeoutException('Connection timeout after 60 seconds');
        },
      );

      if (response.statusCode ~/ 100 != 2) {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>?;
        return {
          'ok': false,
          'error': errorBody?['error']?.toString() ?? 'Face comparison failed',
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final bool ok = body['ok'] == true;
      final double? similarity = (body['similarity'] as num?)?.toDouble();
      final bool? match = body['match'] as bool?;

      return {
        'ok': ok,
        'similarity': similarity,
        'match': match,
        'error': ok ? null : (body['error']?.toString() ?? 'Face comparison failed'),
      };
    } catch (e) {
      print('❌ Backend compare faces error: $e');
      return {
        'ok': false,
        'error': 'Face comparison error: $e',
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

