import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';

/// WatermarkingService
/// - Automatically applies a tiled watermark using the user's username (e.g., @username)
/// - No user customization; deterministic layout, spacing, opacity
class WatermarkingService {
  /// Apply an automatic watermark using the provided username.
  /// - Places repeated '@username' text across the image in single diagonal direction (45 degrees).
  /// - Semi-transparent light gray color, fixed spacing, clean pattern.
  /// - Returns JPEG bytes (quality ~85).
  static Future<Uint8List> applyUsernameWatermark({
    required Uint8List imageBytes,
    required String username,
  }) async {
    try {
      final img.Image? base = img.decodeImage(imageBytes);
      if (base == null) return imageBytes;

      // Normalize username
      final String tag = '@' + (username.isNotEmpty ? username : 'user');

      // Choose font size relative to image size - larger for better visibility
      final int minDim = base.width < base.height ? base.width : base.height;
      final int fontSize = (minDim * 0.06).clamp(18, 50).toInt();

      // Spacing between watermarks - increased spacing for better readability
      final int spacing = (fontSize * 5).clamp(100, 250);

      // Render text tile with single diagonal direction (45 degrees)
      final img.Image textTile = await _renderTextTile(tag, fontSize, 45); // Rotated 45 degrees

      // Create single-direction diagonal pattern with fixed spacing
      // Simple grid pattern rotated diagonally - clean and organized
      for (int y = -spacing * 2; y < base.height + spacing * 2; y += spacing) {
        for (int x = -spacing * 2; x < base.width + spacing * 2; x += spacing) {
          img.compositeImage(
            base,
            textTile,
            dstX: x,
            dstY: y,
            blend: img.BlendMode.alpha,
          );
        }
      }

      final Uint8List out = Uint8List.fromList(img.encodeJpg(base, quality: 85));
      return out;
    } catch (e) {
      print('❌ Error applying watermark: $e');
      // On any failure, return original image bytes to avoid blocking uploads
      return imageBytes;
    }
  }

  // --- Minimal stubs used elsewhere in the app ---

  /// Simple heuristic to decide if an image likely originated from the web.
  /// Current implementation: always returns false to avoid blocking.
  static Future<bool> isImageFromInternet(Uint8List bytes) async {
      return false;
  }

  /// Validate image authenticity (EXIF or other checks).
  /// Current implementation: returns a permissive result; can be expanded.
  static Future<Map<String, dynamic>> validateImageAuthenticity({
    required Uint8List imageBytes,
    required String username,
    required String userId,
  }) async {
      return {
      'isValid': true,
      'reason': null,
    };
  }

  // Render text to a transparent tile using Flutter text painting, then decode to image.Image
  // rotationAngle: rotation in degrees (0 = normal, 45 = diagonal)
  static Future<img.Image> _renderTextTile(String text, int fontSize, double rotationAngle) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Use normal system font (no custom font family)
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const ui.Color.fromARGB(120, 150, 150, 150), // semi-transparent light gray (matching sample)
        fontSize: fontSize.toDouble(),
          // No fontFamily - uses default system font
          fontWeight: FontWeight.normal,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    tp.layout();

    // Calculate canvas size with rotation padding
    final double textWidth = tp.width;
    final double textHeight = tp.height;
    final double pad = fontSize * 0.3;
    
    // Account for rotation when calculating canvas size
    final double angleRad = rotationAngle * math.pi / 180;
    final double cosAngle = math.cos(angleRad.abs());
    final double sinAngle = math.sin(angleRad.abs());
    final int w = ((textWidth + pad * 2) * cosAngle + (textHeight + pad * 2) * sinAngle + pad * 2).ceil();
    final int h = ((textWidth + pad * 2) * sinAngle + (textHeight + pad * 2) * cosAngle + pad * 2).ceil();

    // Center the canvas for rotation
    canvas.translate(w / 2, h / 2);
    
    // Apply rotation
    if (rotationAngle != 0) {
      canvas.rotate(angleRad);
    }
    
    // Paint text centered at origin
    tp.paint(canvas, ui.Offset(-textWidth / 2, -textHeight / 2));
    
    final picture = recorder.endRecording();
    final ui.Image uiImg = await picture.toImage(w, h);
    final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    final img.Image? decoded = img.decodeImage(bytes);
    return decoded ?? img.Image(width: w, height: h);
  }
}
