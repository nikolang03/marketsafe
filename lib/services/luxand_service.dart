import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class LuxandService {
  LuxandService({
    required this.apiKey,
    this.baseUrl = 'https://api.luxand.cloud',
  });

  final String apiKey;
  final String baseUrl;

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  /// Verify two face photos belong to the same person.
  /// Returns: { success: bool, similarity: double, raw: Map }
  Future<Map<String, dynamic>> verifyTwoPhotos({
    required Uint8List photoA,
    required Uint8List photoB,
  }) async {
    final uri = Uri.parse('$baseUrl/compare');
    final response = await http.post(
      uri,
      headers: _authHeaders,
      body: jsonEncode({
        'photo1': base64Encode(photoA),
        'photo2': base64Encode(photoB),
      }),
    );

    if (response.statusCode ~/ 100 != 2) {
      return {
        'success': false,
        'error': 'Luxand compare failed (${response.statusCode})',
        'raw': response.body,
      };
    }

    final Map<String, dynamic> body =
        (json.decode(response.body) as Map<String, dynamic>);

    final bool match = (body['match'] == true) || (body['verified'] == true);
    final double similarity = _parseSimilarity(body['similarity'] ?? body['score']);
    return {
      'success': match,
      'similarity': similarity,
      'raw': body,
    };
  }

  /// Search among enrolled subjects.
  /// Returns: { success: bool, candidates: List, raw: Map }
  Future<Map<String, dynamic>> searchPhoto({
    required Uint8List photo,
  }) async {
    final uri = Uri.parse('$baseUrl/photo/search');
    final response = await http.post(
      uri,
      headers: _authHeaders,
      body: jsonEncode({'photo': base64Encode(photo)}),
    );

    if (response.statusCode ~/ 100 != 2) {
      return {
        'success': false,
        'error': 'Luxand search failed (${response.statusCode})',
        'raw': response.body,
      };
    }
    final Map<String, dynamic> body =
        (json.decode(response.body) as Map<String, dynamic>);
    return {
      'success': true,
      'candidates': body['candidates'] ?? body['matches'] ?? [],
      'raw': body,
    };
  }

  /// Enroll a subject with a face photo.
  /// Returns: { success: bool, subjectId: String, raw: Map }
  Future<Map<String, dynamic>> enrollSubject({
    required String subject,
    required Uint8List photo,
  }) async {
    final uri = Uri.parse('$baseUrl/photo');
    final response = await http.post(
      uri,
      headers: _authHeaders,
      body: jsonEncode({
        'photo': base64Encode(photo),
        'name': subject,
      }),
    );
    if (response.statusCode ~/ 100 != 2) {
      return {
        'success': false,
        'error': 'Luxand enroll failed (${response.statusCode})',
        'raw': response.body,
      };
    }
    final Map<String, dynamic> body =
        (json.decode(response.body) as Map<String, dynamic>);
    return {
      'success': true,
      'subjectId': (body['uuid']?.toString() ??
          body['id']?.toString() ??
          body['subject_id']?.toString() ??
          ''),
      'raw': body,
    };
  }

  /// Liveness detection for a single photo (if supported).
  /// Returns: { success: bool, live: bool, score: double, raw: Map }
  Future<Map<String, dynamic>> liveness({
    required Uint8List photo,
  }) async {
    final uri = Uri.parse('$baseUrl/liveness');
    final response = await http.post(
      uri,
      headers: _authHeaders,
      body: jsonEncode({'photo': base64Encode(photo)}),
    );
    if (response.statusCode ~/ 100 != 2) {
      return {
        'success': false,
        'error': 'Luxand liveness failed (${response.statusCode})',
        'raw': response.body,
      };
    }
    final Map<String, dynamic> body =
        (json.decode(response.body) as Map<String, dynamic>);
    final bool live = (body['liveness'] == 'real') ||
        (body['live'] == true) ||
        (body['liveness'] == true);
    final double score =
        _parseSimilarity(body['score'] ?? body['livenessScore']);
    return {
      'success': true,
      'live': live,
      'score': score,
      'raw': body,
    };
  }

  double _parseSimilarity(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) {
      final v = value.toDouble();
      // If value looks like percent (e.g., 98.3), normalize to 0..1
      if (v > 1.0) return (v / 100.0).clamp(0.0, 1.0);
      return v.clamp(0.0, 1.0);
    }
    if (value is String) {
      final parsed = double.tryParse(value) ?? 0.0;
      if (parsed > 1.0) return (parsed / 100.0).clamp(0.0, 1.0);
      return parsed.clamp(0.0, 1.0);
    }
    return 0.0;
  }
}


