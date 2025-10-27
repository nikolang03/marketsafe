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
      print('📊 FaceNetService: Prediction successful. Normalized. Sample output: ${normalizedEmbedding.take(5).toList()}');
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
      print('📊 FaceNetService: Prediction successful. Normalized. Sample output: ${normalizedEmbedding.take(5).toList()}');
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
    img.Image croppedImage = _cropFace(image, faceDetected);
    img.Image resizedImage = img.copyResize(croppedImage, width: 160, height: 160);

    Float32List imageAsList = _imageToByteListFloat32(resizedImage);
    return imageAsList;
  }

  img.Image _cropFace(CameraImage image, Face faceDetected) {
    img.Image convertedImage = _convertCameraImage(image);
    double x = faceDetected.boundingBox.left - 10.0;
    double y = faceDetected.boundingBox.top - 10.0;
    double w = faceDetected.boundingBox.width + 10.0;
    double h = faceDetected.boundingBox.height + 10.0;
    
    // Clamp coordinates to be within the image boundaries
    int x1 = max(0, x.round());
    int y1 = max(0, y.round());
    int x2 = min(convertedImage.width, (x + w).round());
    int y2 = min(convertedImage.height, (y + h).round());
    int finalW = x2 - x1;
    int finalH = y2 - y1;

    // Ensure width and height are positive
    if (finalW <= 0 || finalH <= 0) {
      return img.copyCrop(
        convertedImage,
        x: faceDetected.boundingBox.left.round(),
        y: faceDetected.boundingBox.top.round(),
        width: faceDetected.boundingBox.width.round(),
        height: faceDetected.boundingBox.height.round()
      );
    }

    return img.copyCrop(
        convertedImage, x: x1, y: y1, width: finalW, height: finalH);
  }

  img.Image _cropFaceFromImage(img.Image image, Face faceDetected) {
    double x = faceDetected.boundingBox.left - 10.0;
    double y = faceDetected.boundingBox.top - 10.0;
    double w = faceDetected.boundingBox.width + 10.0;
    double h = faceDetected.boundingBox.height + 10.0;

    // Clamp coordinates to be within the image boundaries
    int x1 = max(0, x.round());
    int y1 = max(0, y.round());
    int x2 = min(image.width, (x + w).round());
    int y2 = min(image.height, (y + h).round());
    int finalW = x2 - x1;
    int finalH = y2 - y1;

    // Ensure width and height are positive
    if (finalW <= 0 || finalH <= 0) {
      return img.copyCrop(
        image,
        x: faceDetected.boundingBox.left.round(),
        y: faceDetected.boundingBox.top.round(),
        width: faceDetected.boundingBox.width.round(),
        height: faceDetected.boundingBox.height.round()
      );
    }

    return img.copyCrop(
        image, x: x1, y: y1, width: finalW, height: finalH);
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

  void dispose() {
    // No explicit dispose needed here as Interpreter is managed by _interpreterFuture
  }
}
