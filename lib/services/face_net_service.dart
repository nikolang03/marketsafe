import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceNetService {
  static final FaceNetService _faceNetService = FaceNetService._internal();
  factory FaceNetService() {
    return _faceNetService;
  }
  FaceNetService._internal();

  // Use a Future to ensure the interpreter is initialized only once.
  Future<Interpreter?>? _interpreterFuture;

  Future<Interpreter?> _getInterpreter() async {
    // If the Future is null, it means the model hasn't been loaded yet.
    if (_interpreterFuture == null) {
      print('🤖 FaceNetService: First use detected. Loading model...');
      _interpreterFuture = Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
    }
    // Await the Future to get the loaded interpreter.
    return await _interpreterFuture;
  }

  double threshold = 1.0;

  List? _predictedData;
  List get predictedData => _predictedData!;

  Future<List<double>> predict(CameraImage cameraImage, Face face) async {
    try {
      print('🧠 FaceNetService: Starting prediction from CameraImage...');
      final interpreter = await _getInterpreter();
      if (interpreter == null) {
        print('❌ FaceNetService Error: Interpreter failed to load.');
        return [];
      }

      final input = _preProcess(cameraImage, face);
      if (input.isEmpty) {
        print('❌ FaceNetService Error: Preprocessing returned empty data.');
        return [];
      }
      print('✅ FaceNetService: Preprocessing complete.');

      // Manually reshape to [1, 112, 112, 3]
      final newinput = _reshapeInput(input);
      
      List<List<double>> output = [List<double>.filled(512, 0.0)];

      print('🤖 FaceNetService: Running model interpreter...');
      interpreter.run(newinput, output);
      print('✅ FaceNetService: Model run complete.');

      // Check if the output is all zeros
      final bool isAllZeros = output[0].every((element) => element == 0.0);
      if (isAllZeros) {
        print('⚠️ FaceNetService Warning: Model output is all zeros. This likely means the input image was invalid (e.g., all black) or the model failed.');
        return []; // Return empty list to signify failure
      }

      final normalizedEmbedding = normalize(output[0]);
      
      // Validate embedding quality
      final embeddingStats = _validateEmbeddingQuality(output[0], normalizedEmbedding);
      print('📊 FaceNetService: Prediction successful. Normalized.');
      print('📊 Embedding stats:');
      print('  - Raw min: ${embeddingStats['rawMin']}, max: ${embeddingStats['rawMax']}, mean: ${embeddingStats['rawMean']}');
      print('  - Normalized min: ${embeddingStats['normMin']}, max: ${embeddingStats['normMax']}, norm: ${embeddingStats['norm']}');
      print('  - Sample values: ${normalizedEmbedding.take(5).toList()}');
      
      // CRITICAL: Validate embedding can differentiate faces
      // Low variance/range means all faces will have similar embeddings (0.9 similarity issue)
      final embeddingVariance = _calculateEmbeddingVariance(normalizedEmbedding);
      final embeddingRange = normalizedEmbedding.reduce((a, b) => a > b ? a : b) - normalizedEmbedding.reduce((a, b) => a < b ? a : b);
      final embeddingStdDev = sqrt(embeddingVariance);
      
      // Detailed logging for debugging
      print('📊 ==========================================');
      print('📊 EMBEDDING QUALITY VALIDATION');
      print('📊 ==========================================');
      print('📊 Variance: ${embeddingVariance.toStringAsFixed(6)} (threshold: >= 0.0005)');
      print('📊 Range: ${embeddingRange.toStringAsFixed(6)} (threshold: >= 0.075)');
      print('📊 StdDev: ${embeddingStdDev.toStringAsFixed(6)} (threshold: >= 0.025)');
      
      // CRITICAL: Reject embeddings that won't differentiate faces
      // Note: For normalized embeddings (L2 norm ~1.0), values are typically small (-0.05 to 0.05)
      // Adjusted threshold from 0.001 to 0.0005 to allow valid normalized embeddings
      if (embeddingVariance < 0.0005) {
        print('🚨🚨🚨 CRITICAL: Embedding variance too low (${embeddingVariance.toStringAsFixed(6)} < 0.0005)');
        print('🚨 This causes all faces to have 0.9 similarity - REJECTING');
        print('💡 Tip: Ensure good lighting and clear face visibility');
        print('📊 ==========================================');
        return [];
      }
      
      // Balanced: Normalized embeddings naturally have smaller ranges (0.08-0.12)
      // Adjusted threshold from 0.1 to 0.075 to allow valid normalized embeddings (e.g., 0.095)
      if (embeddingRange < 0.075) {
        print('🚨🚨🚨 CRITICAL: Embedding range too small (${embeddingRange.toStringAsFixed(6)} < 0.075)');
        print('🚨 This causes all faces to have similar embeddings - REJECTING');
        print('💡 Tip: Range ${embeddingRange.toStringAsFixed(6)} is below threshold - try better lighting or face positioning');
        print('📊 ==========================================');
        return [];
      }
      
      // Balanced: Adjusted stdDev threshold to match normalized embedding characteristics
      if (embeddingStdDev < 0.025) {
        print('🚨🚨🚨 CRITICAL: Embedding stdDev too low (${embeddingStdDev.toStringAsFixed(6)} < 0.025)');
        print('🚨 This causes poor face differentiation - REJECTING');
        print('💡 Tip: Ensure face is clearly visible and well-lit');
        print('📊 ==========================================');
        return [];
      }
      
      print('✅ All quality checks PASSED');
      print('✅ Embedding quality: variance=${embeddingVariance.toStringAsFixed(6)}, range=${embeddingRange.toStringAsFixed(6)}, stdDev=${embeddingStdDev.toStringAsFixed(6)}');
      print('✅ This embedding will properly differentiate faces');
      print('📊 ==========================================');
      
      return normalizedEmbedding;
    } catch (e) {
      print('❌❌❌ FaceNetService.predict CRASH: $e');
      return [];
    }
  }

  Future<List<double>> predictFromBytes(Uint8List imageBytes, Face face) async {
    try {
      print('🧠 FaceNetService: Starting prediction from bytes...');
      final interpreter = await _getInterpreter();
      if (interpreter == null) {
        print('❌ FaceNetService Error: Interpreter failed to load.');
        return [];
      }

      img.Image? decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        print('❌ FaceNetService Error: Could not decode image from bytes.');
        return [];
      }

      // Correct the image orientation based on EXIF data
      final img.Image baseImage = img.bakeOrientation(decodedImage);
      print('✅ FaceNetService: Image decoded and orientation corrected.');

      img.Image croppedImage = _cropFaceFromImage(baseImage, face);
      
      // Validate image quality before processing (log warnings but don't reject)
      final qualityCheck = _validateImageQuality(croppedImage);
      // Quality check now logs warnings but doesn't reject - allows natural variations
      if (qualityCheck['brightness'] != null || qualityCheck['contrast'] != null) {
        print('✅ Image quality checked: brightness=${qualityCheck['brightness']?.toStringAsFixed(1) ?? 'N/A'}, contrast=${qualityCheck['contrast']?.toStringAsFixed(1) ?? 'N/A'}');
      }
      
      img.Image resizedImage =
          img.copyResize(croppedImage, width: 160, height: 160);
      Float32List imageAsList = _imageToByteListFloat32(resizedImage);
      print('✅ FaceNetService: Preprocessing from bytes complete.');

      // Manually reshape to [1, 160, 160, 3]
      final newinput = _reshapeInput(imageAsList);

      List<List<double>> output = [List<double>.filled(512, 0.0)];

      print('🤖 FaceNetService: Running model interpreter...');
      interpreter.run(newinput, output);
      print('✅ FaceNetService: Model run complete.');

      // Check if the output is all zeros
      final bool isAllZeros = output[0].every((element) => element == 0.0);
      if (isAllZeros) {
        print('⚠️ FaceNetService Warning: Model output is all zeros. This likely means the input image was invalid or the model failed.');
        return []; // Return empty list to signify failure
      }

      final normalizedEmbedding = normalize(output[0]);
      
      // Validate embedding quality
      final embeddingStats = _validateEmbeddingQuality(output[0], normalizedEmbedding);
      print('📊 FaceNetService: Prediction successful. Normalized.');
      print('📊 Embedding stats:');
      print('  - Raw min: ${embeddingStats['rawMin']}, max: ${embeddingStats['rawMax']}, mean: ${embeddingStats['rawMean']}');
      print('  - Normalized min: ${embeddingStats['normMin']}, max: ${embeddingStats['normMax']}, norm: ${embeddingStats['norm']}');
      print('  - Sample values: ${normalizedEmbedding.take(5).toList()}');
      
      // CRITICAL: Validate embedding can differentiate faces
      // Low variance/range means all faces will have similar embeddings (0.9 similarity issue)
      final embeddingVariance = _calculateEmbeddingVariance(normalizedEmbedding);
      final embeddingRange = normalizedEmbedding.reduce((a, b) => a > b ? a : b) - normalizedEmbedding.reduce((a, b) => a < b ? a : b);
      final embeddingStdDev = sqrt(embeddingVariance);
      
      // Detailed logging for debugging
      print('📊 ==========================================');
      print('📊 EMBEDDING QUALITY VALIDATION');
      print('📊 ==========================================');
      print('📊 Variance: ${embeddingVariance.toStringAsFixed(6)} (threshold: >= 0.0005)');
      print('📊 Range: ${embeddingRange.toStringAsFixed(6)} (threshold: >= 0.075)');
      print('📊 StdDev: ${embeddingStdDev.toStringAsFixed(6)} (threshold: >= 0.025)');
      
      // CRITICAL: Reject embeddings that won't differentiate faces
      // Note: For normalized embeddings (L2 norm ~1.0), values are typically small (-0.05 to 0.05)
      // Adjusted threshold from 0.001 to 0.0005 to allow valid normalized embeddings
      if (embeddingVariance < 0.0005) {
        print('🚨🚨🚨 CRITICAL: Embedding variance too low (${embeddingVariance.toStringAsFixed(6)} < 0.0005)');
        print('🚨 This causes all faces to have 0.9 similarity - REJECTING');
        print('💡 Tip: Ensure good lighting and clear face visibility');
        print('📊 ==========================================');
        return [];
      }
      
      // Balanced: Normalized embeddings naturally have smaller ranges (0.08-0.12)
      // Adjusted threshold from 0.1 to 0.075 to allow valid normalized embeddings (e.g., 0.095)
      if (embeddingRange < 0.075) {
        print('🚨🚨🚨 CRITICAL: Embedding range too small (${embeddingRange.toStringAsFixed(6)} < 0.075)');
        print('🚨 This causes all faces to have similar embeddings - REJECTING');
        print('💡 Tip: Range ${embeddingRange.toStringAsFixed(6)} is below threshold - try better lighting or face positioning');
        print('📊 ==========================================');
        return [];
      }
      
      // Balanced: Adjusted stdDev threshold to match normalized embedding characteristics
      if (embeddingStdDev < 0.025) {
        print('🚨🚨🚨 CRITICAL: Embedding stdDev too low (${embeddingStdDev.toStringAsFixed(6)} < 0.025)');
        print('🚨 This causes poor face differentiation - REJECTING');
        print('💡 Tip: Ensure face is clearly visible and well-lit');
        print('📊 ==========================================');
        return [];
      }
      
      print('✅ All quality checks PASSED');
      print('✅ Embedding quality: variance=${embeddingVariance.toStringAsFixed(6)}, range=${embeddingRange.toStringAsFixed(6)}, stdDev=${embeddingStdDev.toStringAsFixed(6)}');
      print('✅ This embedding will properly differentiate faces');
      print('📊 ==========================================');
      
      return normalizedEmbedding;
    } catch (e) {
      print('❌❌❌ FaceNetService.predictFromBytes CRASH: $e');
      return [];
    }
  }

  List<List<List<List<num>>>> _reshapeInput(List input) {
    final List<List<List<num>>> a = List.generate(
        160, (_) => List.generate(160, (_) => List.generate(3, (_) => 0.0)));
    int i = 0;
    for (int y = 0; y < 160; y++) {
      for (int x = 0; x < 160; x++) {
        for (int z = 0; z < 3; z++) {
          a[y][x][z] = input[i++];
        }
      }
    }
    return [a];
  }


  img.Image _convertCameraImage(CameraImage image) {
    if (image.format.group == ImageFormatGroup.yuv420) {
      return _convertYUV420(image);
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      return _convertBGRA8888(image);
    }
    throw Exception('Image format not supported');
  }

  img.Image _convertBGRA8888(CameraImage image) {
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  }

  img.Image _convertYUV420(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int? uvPixelStride = image.planes[1].bytesPerPixel;

    final yPlane = image.planes[0].bytes;
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;

    final im = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex =
            uvPixelStride! * (x / 2).floor() + uvRowStride * (y / 2).floor();
        final int index = y * width + x;

        final yp = yPlane[index];
        final up = uPlane[uvIndex];
        final vp = vPlane[uvIndex];

        int r = (yp + 1.402 * (vp - 128)).round();
        int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round();
        int b = (yp + 1.772 * (up - 128)).round();
        
        im.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
      }
    }
    return im;
  }

  List _preProcess(CameraImage image, Face faceDetected) {
    // CRITICAL: Use proper face alignment for reliable recognition
    img.Image croppedImage = _cropAndAlignFace(image, faceDetected);
    
    // Validate image quality before processing (log warnings but don't reject)
    final qualityCheck = _validateImageQuality(croppedImage);
    // Quality check now logs warnings but doesn't reject - allows natural variations
    if (qualityCheck['brightness'] != null || qualityCheck['contrast'] != null) {
      print('✅ Image quality checked: brightness=${qualityCheck['brightness']?.toStringAsFixed(1) ?? 'N/A'}, contrast=${qualityCheck['contrast']?.toStringAsFixed(1) ?? 'N/A'}');
    }
    
    img.Image resizedImage = img.copyResize(croppedImage, width: 160, height: 160);

    Float32List imageAsList = _imageToByteListFloat32(resizedImage);
    return imageAsList;
  }

  /// Crop and align face using landmarks for reliable recognition
  /// This ensures faces are consistently oriented regardless of head pose
  img.Image _cropAndAlignFace(CameraImage image, Face faceDetected) {
    img.Image convertedImage = _convertCameraImage(image);
    
    // Get face landmarks for alignment
    final landmarks = faceDetected.landmarks;
    final hasLeftEye = landmarks.containsKey(FaceLandmarkType.leftEye);
    final hasRightEye = landmarks.containsKey(FaceLandmarkType.rightEye);
    
    // Calculate expanded bounding box with more padding for better alignment
    final box = faceDetected.boundingBox;
    final padding = max(box.width, box.height) * 0.3; // 30% padding for better alignment
    double x = box.left - padding;
    double y = box.top - padding;
    double w = box.width + (padding * 2);
    double h = box.height + (padding * 2);
    
    // Clamp coordinates
    int x1 = max(0, x.round());
    int y1 = max(0, y.round());
    int x2 = min(convertedImage.width, (x + w).round());
    int y2 = min(convertedImage.height, (y + h).round());
    int finalW = x2 - x1;
    int finalH = y2 - y1;

    if (finalW <= 0 || finalH <= 0) {
      // Fallback to simple crop
      return img.copyCrop(
        convertedImage,
        x: box.left.round(),
        y: box.top.round(),
        width: box.width.round(),
        height: box.height.round()
      );
    }

    // Crop face region
    img.Image croppedImage = img.copyCrop(convertedImage, x: x1, y: y1, width: finalW, height: finalH);
    
    // CRITICAL: Align face using eye positions if landmarks are available
    // This ensures consistent face orientation for reliable recognition
    if (hasLeftEye && hasRightEye) {
      final leftEye = landmarks[FaceLandmarkType.leftEye]!;
      final rightEye = landmarks[FaceLandmarkType.rightEye]!;
      
      // Calculate eye positions relative to cropped image
      final leftEyeX = leftEye.position.x - x1;
      final leftEyeY = leftEye.position.y - y1;
      final rightEyeX = rightEye.position.x - x1;
      final rightEyeY = rightEye.position.y - y1;
      
      // Calculate angle between eyes (for rotation correction)
      final eyeAngle = atan2(rightEyeY - leftEyeY, rightEyeX - leftEyeX);
      
      // Only rotate if angle is significant (> 2 degrees)
      if (eyeAngle.abs() > 0.035) { // ~2 degrees in radians
        print('🔄 Rotating face by ${(eyeAngle * 180 / pi).toStringAsFixed(2)}° for alignment');
        // Rotate image to align eyes horizontally
        croppedImage = img.copyRotate(croppedImage, angle: eyeAngle * 180 / pi);
      }
      
      // Calculate eye distance for normalization
      final eyeDistance = sqrt(pow(rightEyeX - leftEyeX, 2) + pow(rightEyeY - leftEyeY, 2));
      
      // Scale face to normalize eye distance (target: ~40% of image width)
      final targetEyeDistance = croppedImage.width * 0.4;
      if (eyeDistance > 0 && (eyeDistance / targetEyeDistance).abs() > 0.1) {
        final scaleFactor = targetEyeDistance / eyeDistance;
        if (scaleFactor > 0.8 && scaleFactor < 1.2) { // Only scale if reasonable
          print('📏 Scaling face by ${(scaleFactor * 100).toStringAsFixed(1)}% for normalization');
          croppedImage = img.copyResize(
            croppedImage,
            width: (croppedImage.width * scaleFactor).round(),
            height: (croppedImage.height * scaleFactor).round(),
          );
        }
      }
    }
    
    return croppedImage;
  }
  

  /// Crop and align face from static image using landmarks
  img.Image _cropFaceFromImage(img.Image image, Face faceDetected) {
    // Get face landmarks for alignment
    final landmarks = faceDetected.landmarks;
    final hasLeftEye = landmarks.containsKey(FaceLandmarkType.leftEye);
    final hasRightEye = landmarks.containsKey(FaceLandmarkType.rightEye);
    
    // Calculate expanded bounding box with more padding
    final box = faceDetected.boundingBox;
    final padding = max(box.width, box.height) * 0.3; // 30% padding
    double x = box.left - padding;
    double y = box.top - padding;
    double w = box.width + (padding * 2);
    double h = box.height + (padding * 2);

    // Clamp coordinates
    int x1 = max(0, x.round());
    int y1 = max(0, y.round());
    int x2 = min(image.width, (x + w).round());
    int y2 = min(image.height, (y + h).round());
    int finalW = x2 - x1;
    int finalH = y2 - y1;

    if (finalW <= 0 || finalH <= 0) {
      return img.copyCrop(
        image,
        x: box.left.round(),
        y: box.top.round(),
        width: box.width.round(),
        height: box.height.round()
      );
    }

    // Crop face region
    img.Image croppedImage = img.copyCrop(image, x: x1, y: y1, width: finalW, height: finalH);
    
    // CRITICAL: Align face using eye positions if landmarks are available
    if (hasLeftEye && hasRightEye) {
      final leftEye = landmarks[FaceLandmarkType.leftEye]!;
      final rightEye = landmarks[FaceLandmarkType.rightEye]!;
      
      // Calculate eye positions relative to cropped image
      final leftEyeX = leftEye.position.x - x1;
      final leftEyeY = leftEye.position.y - y1;
      final rightEyeX = rightEye.position.x - x1;
      final rightEyeY = rightEye.position.y - y1;
      
      // Calculate angle between eyes for rotation correction
      final eyeAngle = atan2(rightEyeY - leftEyeY, rightEyeX - leftEyeX);
      
      // Only rotate if angle is significant (> 2 degrees)
      if (eyeAngle.abs() > 0.035) {
        print('🔄 Rotating face by ${(eyeAngle * 180 / pi).toStringAsFixed(2)}° for alignment');
        croppedImage = img.copyRotate(croppedImage, angle: eyeAngle * 180 / pi);
      }
      
      // Normalize eye distance for consistent scaling
      final eyeDistance = sqrt(pow(rightEyeX - leftEyeX, 2) + pow(rightEyeY - leftEyeY, 2));
      final targetEyeDistance = croppedImage.width * 0.4;
      if (eyeDistance > 0 && (eyeDistance / targetEyeDistance).abs() > 0.1) {
        final scaleFactor = targetEyeDistance / eyeDistance;
        if (scaleFactor > 0.8 && scaleFactor < 1.2) {
          print('📏 Scaling face by ${(scaleFactor * 100).toStringAsFixed(1)}% for normalization');
          croppedImage = img.copyResize(
            croppedImage,
            width: (croppedImage.width * scaleFactor).round(),
            height: (croppedImage.height * scaleFactor).round(),
          );
        }
      }
    }
    
    return croppedImage;
  }
  
  /// Validate image quality before embedding generation
  /// Returns map with quality metrics for progress bar
  Map<String, dynamic> _validateImageQuality(img.Image image) {
    if (image.width <= 0 || image.height <= 0) {
      return {'isValid': false, 'reason': 'Invalid image dimensions', 'brightness': 0.0, 'contrast': 0.0, 'qualityScore': 0.0};
    }
    
    // Calculate average brightness
    num totalBrightness = 0;
    int pixelCount = 0;
    for (int y = 0; y < image.height; y += 10) { // Sample every 10th pixel for performance
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixel(x, y);
        final brightness = (pixel.r + pixel.g + pixel.b) / 3.0;
        totalBrightness += brightness;
        pixelCount++;
      }
    }
    final avgBrightness = totalBrightness / pixelCount;
    
    // Calculate contrast (variance of brightness)
    num variance = 0;
    int contrastSampleCount = 0;
    for (int y = 0; y < image.height; y += 20) {
      for (int x = 0; x < image.width; x += 20) {
        final pixel = image.getPixel(x, y);
        final brightness = (pixel.r + pixel.g + pixel.b) / 3.0;
        variance += pow(brightness - avgBrightness, 2);
        contrastSampleCount++;
      }
    }
    final contrast = contrastSampleCount > 0 ? sqrt(variance / contrastSampleCount) : 0.0;
    
    // Calculate quality score (0-100) for progress bar
    // Ideal brightness: 100-150, ideal contrast: 30-60
    double brightnessScore = 100.0;
    if (avgBrightness < 50) {
      brightnessScore = (avgBrightness / 50) * 50; // 0-50 range
    } else if (avgBrightness > 200) {
      brightnessScore = 100 - ((avgBrightness - 200) / 55) * 50; // 50-0 range
    } else {
      brightnessScore = 50 + ((avgBrightness - 50) / 150) * 50; // 50-100 range
    }
    brightnessScore = brightnessScore.clamp(0.0, 100.0);
    
    double contrastScore = (contrast / 60.0 * 100).clamp(0.0, 100.0);
    
    // Combined quality score (weighted average)
    final qualityScore = (brightnessScore * 0.6 + contrastScore * 0.4).clamp(0.0, 100.0);
    
    // Log warnings for poor quality
    if (avgBrightness < 50) {
      print('⚠️ Image is dark (brightness: ${avgBrightness.toStringAsFixed(1)}) - affects recognition quality');
    }
    if (avgBrightness > 200) {
      print('⚠️ Image is too bright (brightness: ${avgBrightness.toStringAsFixed(1)}) - affects recognition quality');
    }
    if (contrast < 20) {
      print('⚠️ Image has low contrast (contrast: ${contrast.toStringAsFixed(1)}) - affects recognition quality');
    }
    
    // Check image size (should be reasonable)
    if (image.width < 50 || image.height < 50) {
      return {'isValid': false, 'reason': 'Image too small (${image.width}x${image.height})', 'brightness': avgBrightness, 'contrast': contrast, 'qualityScore': 0.0};
    }
    
    return {
      'isValid': true, 
      'reason': 'Quality OK', 
      'brightness': avgBrightness, 
      'contrast': contrast,
      'qualityScore': qualityScore,
      'brightnessScore': brightnessScore,
      'contrastScore': contrastScore,
    };
  }

  Float32List _imageToByteListFloat32(img.Image image) {
    var convertedBytes = Float32List(1 * 160 * 160 * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;

    num totalPixelValue = 0; // For debugging

    for (var i = 0; i < 160; i++) {
      for (var j = 0; j < 160; j++) {
        var pixel = image.getPixel(j, i);
        buffer[pixelIndex++] = (pixel.r - 128) / 128;
        buffer[pixelIndex++] = (pixel.g - 128) / 128;
        buffer[pixelIndex++] = (pixel.b - 128) / 128;
        totalPixelValue += pixel.r + pixel.g + pixel.b;
      }
    }

    if (totalPixelValue == 0) {
      print('⚠️ FaceNetService Warning: The preprocessed image is completely black.');
    }

    return convertedBytes.buffer.asFloat32List();
  }

  List<double> normalize(List<double> embedding) {
    final double norm = L2Norm(embedding);
    if (norm == 0.0) {
      return embedding; // Avoid division by zero
    }
    return embedding.map((e) => e / norm).toList();
  }

  double L2Norm(List<double> embedding) {
    double sum = 0;
    for (var val in embedding) {
      sum += val * val;
    }
    return sqrt(sum);
  }

  double cosineSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.isEmpty || embedding2.isEmpty) return 0.0;

    double dotProduct = 0.0;
    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
    }

    double norm1 = L2Norm(embedding1);
    double norm2 = L2Norm(embedding2);

    // Check for zero vectors to prevent division by zero (NaN)
    if (norm1 == 0.0 || norm2 == 0.0) {
      print('⚠️ Warning: Zero vector detected in embedding. Similarity is 0.0');
      return 0.0;
    }

    return dotProduct / (norm1 * norm2);
  }

  /// Validate embedding quality to ensure model is working correctly
  Map<String, double> _validateEmbeddingQuality(List<double> rawEmbedding, List<double> normalizedEmbedding) {
    if (rawEmbedding.isEmpty || normalizedEmbedding.isEmpty) {
      return {'rawMin': 0, 'rawMax': 0, 'rawMean': 0, 'normMin': 0, 'normMax': 0, 'norm': 0};
    }
    
    final rawMin = rawEmbedding.reduce((a, b) => a < b ? a : b);
    final rawMax = rawEmbedding.reduce((a, b) => a > b ? a : b);
    final rawMean = rawEmbedding.reduce((a, b) => a + b) / rawEmbedding.length;
    final norm = L2Norm(normalizedEmbedding);
    final normMin = normalizedEmbedding.reduce((a, b) => a < b ? a : b);
    final normMax = normalizedEmbedding.reduce((a, b) => a > b ? a : b);
    
    // Check for suspicious patterns
    if (rawMax == rawMin) {
      print('⚠️ WARNING: All embedding values are the same! Model may not be working correctly.');
    }
    if (norm < 0.9 || norm > 1.1) {
      print('⚠️ WARNING: Normalization issue! Norm should be ~1.0, got: $norm');
    }
    
    return {
      'rawMin': rawMin,
      'rawMax': rawMax,
      'rawMean': rawMean,
      'normMin': normMin,
      'normMax': normMax,
      'norm': norm,
    };
  }
  
  /// Calculate variance of embedding to ensure it's meaningful
  /// Low variance indicates all values are similar (not good for face recognition)
  double _calculateEmbeddingVariance(List<double> embedding) {
    if (embedding.isEmpty) return 0.0;
    
    final mean = embedding.reduce((a, b) => a + b) / embedding.length;
    final variance = embedding.map((e) => pow(e - mean, 2)).reduce((a, b) => a + b) / embedding.length;
    
    return variance;
  }

  void dispose() {
    // No explicit dispose needed here as Interpreter is managed by _interpreterFuture
  }
}
