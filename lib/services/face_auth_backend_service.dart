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
    
    // SECURITY: Enforce HTTPS for all production connections
    if (backendUrl.startsWith('http://') && !backendUrl.contains('localhost') && !backendUrl.contains('127.0.0.1') && !backendUrl.contains('192.168.')) {
      throw Exception('SECURITY ERROR: HTTP connections are not allowed for production. Use HTTPS only. URL: $backendUrl');
    }
    
    if (backendUrl.contains('192.168.') || backendUrl.contains('localhost') || backendUrl.contains('127.0.0.1')) {
      print('⚠️ WARNING: Using local backend URL. This will only work on the same network.');
      print('⚠️ For production, use: https://marketsafe-production.up.railway.app');
    } else if (!backendUrl.startsWith('https://')) {
      throw Exception('SECURITY ERROR: Backend URL must use HTTPS. URL: $backendUrl');
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
        // Prefer 'message' field if available, otherwise use 'error' field
        final errorMessage = errorBody?['message']?.toString() ?? 
                            errorBody?['error']?.toString() ?? 
                            'Enrollment failed';
        return {
          'success': false,
          'error': errorMessage,
          'reason': errorBody?['reason']?.toString(), // Include reason for duplicate face detection
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final bool ok = body['ok'] == true;
      final String? uuid = body['uuid']?.toString();
      
      // CRITICAL: Log the response for debugging
      print('📦 Backend enrollment response:');
      print('   - ok: $ok');
      print('   - uuid: ${uuid ?? "NULL"}');
      print('   - success: ${body['success'] ?? "N/A"}');
      print('   - error: ${body['error'] ?? "N/A"}');
      print('   - message: ${body['message'] ?? "N/A"}');
      print('   - Full response keys: ${body.keys.toList()}');
      
      if (ok && uuid != null && uuid.isNotEmpty) {
        print('✅✅✅ Backend returned valid UUID: $uuid');
      } else if (ok && (uuid == null || uuid.isEmpty)) {
        print('❌❌❌ CRITICAL: Backend returned ok=true but UUID is null/empty!');
        print('❌ This means enrollment appeared to succeed but no UUID was returned!');
        print('❌ Full response: ${jsonEncode(body)}');
      } else {
        print('❌ Backend enrollment failed: ${body['error'] ?? body['message'] ?? "Unknown error"}');
      }

      return {
        'success': ok,
        'uuid': uuid,
        'error': ok ? null : (body['error']?.toString() ?? body['message']?.toString() ?? 'Enrollment failed'),
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
    String? phone, // Optional: pass phone number to check both email and phone
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
      
      // Add phone if provided (allows checking both email and phone matches)
      if (phone != null && phone.isNotEmpty) {
        requestBody['phone'] = phone;
      }
      
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

  /// Check if a face is a duplicate (95%+ similar to another user's face)
  /// Used during profile photo upload to prevent same person from having multiple accounts
  /// Returns: { isDuplicate: bool, duplicateIdentifier?: string, similarity?: double, message?: string, error?: string }
  Future<Map<String, dynamic>> checkDuplicate({
    required String email,
    required Uint8List photoBytes,
    String? phone,
  }) async {
    try {
      final base64Image = base64Encode(photoBytes);
      final uri = Uri.parse('$backendUrl/api/check-duplicate');
      
      print('🔍 Checking for duplicate face with backend: $backendUrl/api/check-duplicate');
      
      final requestBody = <String, dynamic>{
        'email': email,
        'photoBase64': base64Image,
      };
      
      // Add phone if provided
      if (phone != null && phone.isNotEmpty) {
        requestBody['phone'] = phone;
      }
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException('Connection timeout after 60 seconds');
        },
      );

      if (response.statusCode ~/ 100 != 2) {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>?;
        // On error, return no duplicate to allow upload (prevent false positives)
        return {
          'isDuplicate': false,
          'error': errorBody?['error']?.toString() ?? 'Duplicate check failed',
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final bool isDuplicate = body['isDuplicate'] == true;
      final String? duplicateIdentifier = body['duplicateIdentifier']?.toString();
      final double? similarity = (body['similarity'] as num?)?.toDouble();
      final String? message = body['message']?.toString();

      return {
        'isDuplicate': isDuplicate,
        'duplicateIdentifier': duplicateIdentifier,
        'similarity': similarity,
        'message': message,
      };
    } on TimeoutException catch (e) {
      print('❌ Backend duplicate check timeout: $e');
      // On timeout, return no duplicate to allow upload (prevent false positives)
      return {
        'isDuplicate': false,
        'error': 'Connection timeout',
      };
    } on SocketException catch (e) {
      print('❌ Backend duplicate check socket error: $e');
      // On network error, return no duplicate to allow upload (prevent false positives)
      return {
        'isDuplicate': false,
        'error': 'Network error',
      };
    } catch (e) {
      print('❌ Backend duplicate check error: $e');
      // On error, return no duplicate to allow upload (prevent false positives)
      return {
        'isDuplicate': false,
        'error': 'Duplicate check failed',
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

  /// Delete a person from Luxand by UUID or email
  /// Returns: { ok: bool, message: string?, error: string? }
  Future<Map<String, dynamic>> deletePerson({
    String? email,
    String? uuid,
  }) async {
    try {
      if (email == null && uuid == null) {
        return {
          'ok': false,
          'error': 'Either email or uuid must be provided',
        };
      }
      
      final uri = Uri.parse('$backendUrl/api/delete-person');
      
      print('🔍 Deleting person from backend: $backendUrl/api/delete-person');
      
      final requestBody = <String, dynamic>{};
      if (email != null) requestBody['email'] = email;
      if (uuid != null) requestBody['uuid'] = uuid;
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Connection timeout after 30 seconds');
        },
      );

      if (response.statusCode ~/ 100 != 2) {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>?;
        return {
          'ok': false,
          'error': errorBody?['error']?.toString() ?? 'Delete failed',
        };
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final bool ok = body['ok'] == true;

      return {
        'ok': ok,
        'success': ok,
        'message': body['message']?.toString(),
        'error': ok ? null : (body['error']?.toString() ?? 'Delete failed'),
      };
    } catch (e) {
      print('❌ Backend delete person error: $e');
      return {
        'ok': false,
        'success': false,
        'error': 'Delete person error: $e',
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

