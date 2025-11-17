import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'face_movecloser_screen.dart';
import '../services/production_face_recognition_service.dart';

class FaceBlinkTwiceScreen extends StatefulWidget {
  const FaceBlinkTwiceScreen({super.key});

  @override
  State<FaceBlinkTwiceScreen> createState() => _FaceBlinkTwiceScreenState();
}

class _FaceBlinkTwiceScreenState extends State<FaceBlinkTwiceScreen> with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  late final FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isProcessingImage = false;
  Timer? _detectionTimer;
  bool _useImageStream = true;
  int _blinkCount = 0;
  bool _isBlinkComplete = false;
  bool _navigated = false;
  
  // 60fps smooth animation controllers
  late AnimationController _progressController;
  late AnimationController _pulseController;
  late Animation<double> _progressAnimation;
  late Animation<double> _pulseAnimation;
  
  // Blink detection variables - improved algorithm
  List<double> _eyeProbabilities = [];
  List<bool> _eyeStates = []; // Track eye open/closed states
  bool _wasEyesClosed = false;
  DateTime? _lastBlinkTime;
  int _consecutiveClosedFrames = 0;
  int _consecutiveOpenFrames = 0;
  static const int _minClosedFrames = 1; // Minimum frames for valid blink (reduced for easier detection)
  static const int _minOpenFrames = 2; // Minimum frames for valid open (reduced for easier detection)
  
  // Face quality tracking
  bool _faceDetected = false;
  double _faceQuality = 0.0;
  String _qualityMessage = "Position your face in the frame";

  @override
  void initState() {
    super.initState();
    
    // Initialize 60fps animation controllers
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    _progressAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        enableContours: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.1,
      ),
    );
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _initializeCamera();
      }
    });
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _progressController.dispose();
    _pulseController.dispose();
    try {
      _cameraController?.stopImageStream();
    } catch (_) {}
    try {
      _cameraController?.dispose();
    } catch (_) {}
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameraStatus = await Permission.camera.status;
      if (cameraStatus.isDenied) {
        final result = await Permission.camera.request();
        if (result.isDenied) {
          if (mounted) setState(() => _isCameraInitialized = false);
          return;
        }
      }
      if (cameraStatus.isPermanentlyDenied) {
        if (mounted) setState(() => _isCameraInitialized = false);
        return;
      }

      await Future.delayed(const Duration(milliseconds: 200));
      _cameras = await availableCameras();
      final frontCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.high, // Use high resolution for better detection
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isCameraInitialized = controller.value.isInitialized;
      });

      try {
        await controller.startImageStream(_processCameraImage);
        _useImageStream = true;
      } catch (e) {
        _useImageStream = false;
        _startTimerBasedDetection();
      }
    } catch (e) {
      if (mounted) setState(() => _isCameraInitialized = false);
    }
  }

  void _startTimerBasedDetection() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (_isProcessingImage || _cameraController == null || !mounted) return;
      try {
        final XFile imageFile = await _cameraController!.takePicture();
        final inputImage = InputImage.fromFilePath(imageFile.path);
        final faces = await _faceDetector.processImage(inputImage);
        if (faces.isNotEmpty) {
          _detectBlink(faces.first);
        } else {
          _updateFaceQuality(false, 0.0, "No face detected");
        }
      } catch (e) {
        // Silent error handling
      }
    });
  }

  Uint8List _bytesFromPlanes(CameraImage image) {
    final bytesBuilder = BytesBuilder(copy: false);
    for (final Plane plane in image.planes) {
      bytesBuilder.add(plane.bytes);
    }
    return bytesBuilder.toBytes();
  }

  InputImageRotation _rotationFromSensor(int sensorOrientation) {
    switch (sensorOrientation) {
      case 90: return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default: return InputImageRotation.rotation0deg;
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessingImage || !_isCameraInitialized || _cameraController == null || _isBlinkComplete) return;
    _isProcessingImage = true;

    try {
      final camera = _cameraController!.description;
      final bytes = _bytesFromPlanes(image);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      final rotation = _rotationFromSensor(camera.sensorOrientation);

      InputImageFormat inputFormat;
      switch (image.format.group) {
        case ImageFormatGroup.yuv420: inputFormat = InputImageFormat.yuv420; break;
        case ImageFormatGroup.bgra8888: inputFormat = InputImageFormat.bgra8888; break;
        case ImageFormatGroup.nv21: inputFormat = InputImageFormat.nv21; break;
        default: inputFormat = InputImageFormat.yuv420;
      }

      final metadata = InputImageMetadata(
        size: size,
        rotation: rotation,
        format: inputFormat,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        _detectBlink(faces.first);
        _checkFaceQuality(faces.first, size);
      } else {
        // No face detected - reset progress to 0
        _resetProgress();
        _updateFaceQuality(false, 0.0, "No face detected");
      }
    } catch (e) {
      if (_useImageStream) {
        try {
          _cameraController?.stopImageStream();
        } catch (_) {}
        _useImageStream = false;
        _startTimerBasedDetection();
      }
    } finally {
      _isProcessingImage = false;
    }
  }

  void _checkFaceQuality(Face face, Size imageSize) {
    final bbox = face.boundingBox;
    final faceArea = bbox.width * bbox.height;
    final imageArea = imageSize.width * imageSize.height;
    final faceRatio = faceArea / imageArea;
    
    // Check face size (should be 12-45% of image - more forgiving)
    double sizeScore = 0.0;
    if (faceRatio >= 0.12 && faceRatio <= 0.45) {
      sizeScore = 1.0;
    } else if (faceRatio < 0.12) {
      sizeScore = faceRatio / 0.12;
    } else {
      sizeScore = 1.0 - ((faceRatio - 0.45) / 0.25);
    }
    
    // Check centering
    final centerX = bbox.left + bbox.width / 2;
    final centerY = bbox.top + bbox.height / 2;
    final imageCenterX = imageSize.width / 2;
    final imageCenterY = imageSize.height / 2;
    final distanceFromCenter = ((centerX - imageCenterX).abs() + (centerY - imageCenterY).abs()) / (imageSize.width + imageSize.height);
    final centerScore = (1.0 - (distanceFromCenter * 2)).clamp(0.0, 1.0);
    
    // Check head pose
    final headX = (face.headEulerAngleX?.abs() ?? 0.0) / 30.0;
    final headY = (face.headEulerAngleY?.abs() ?? 0.0) / 30.0;
    final headZ = (face.headEulerAngleZ?.abs() ?? 0.0) / 30.0;
    final poseScore = (1.0 - (headX + headY + headZ) / 3.0).clamp(0.0, 1.0);
    
    // Check eyes visibility
    final hasEyes = (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null);
    final eyeScore = hasEyes ? 1.0 : 0.5;
    
    // Overall quality
    final quality = (sizeScore * 0.3 + centerScore * 0.3 + poseScore * 0.2 + eyeScore * 0.2);
    
    String message = "Position your face in the frame";
    if (quality < 0.5) {
      if (faceRatio < 0.12) message = "Move closer to the camera";
      else if (faceRatio > 0.45) message = "Move away from the camera";
      else if (centerScore < 0.6) message = "Center your face in the frame";
      else if (poseScore < 0.6) message = "Look straight at the camera";
      else message = "Adjust your position";
    } else if (quality >= 0.65) {
      message = "Perfect! Now blink twice";
    } else {
      message = "Good position, blink twice";
    }
    
    _updateFaceQuality(true, quality, message);
  }

  void _resetProgress() {
    // Reset all blink detection state when no face is detected
    _blinkCount = 0;
    _eyeProbabilities.clear();
    _eyeStates.clear();
    _wasEyesClosed = false;
    _consecutiveClosedFrames = 0;
    _consecutiveOpenFrames = 0;
    _lastBlinkTime = null;
    
    // Reset progress animation to 0
    if (mounted) {
      _progressAnimation = Tween<double>(
        begin: _progressAnimation.value,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeOut,
      ));
      _progressController.forward(from: 0.0);
    }
  }

  void _updateFaceQuality(bool detected, double quality, String message) {
    if (mounted) {
      setState(() {
        _faceDetected = detected;
        _faceQuality = quality;
        _qualityMessage = message;
      });
    }
  }

  void _detectBlink(Face face) {
    final leftEyeProb = face.leftEyeOpenProbability ?? 0.0;
    final rightEyeProb = face.rightEyeOpenProbability ?? 0.0;

    if (leftEyeProb > 0.0 && rightEyeProb > 0.0) {
      final avgEyeProb = (leftEyeProb + rightEyeProb) / 2.0;
      _eyeProbabilities.add(avgEyeProb);
      
      // Keep last 30 probabilities for better detection (6 seconds at ~200ms)
      if (_eyeProbabilities.length > 30) {
        _eyeProbabilities.removeAt(0);
      }

      // Improved blink detection with frame counting - more forgiving
      final bool isEyesClosed = avgEyeProb < 0.35; // More forgiving threshold
      final bool isEyesOpen = avgEyeProb > 0.5; // More forgiving open threshold
      
      _eyeStates.add(isEyesClosed);
      if (_eyeStates.length > 10) {
        _eyeStates.removeAt(0);
      }

      if (isEyesClosed) {
        _consecutiveClosedFrames++;
        _consecutiveOpenFrames = 0;
      } else if (isEyesOpen) {
        _consecutiveOpenFrames++;
        if (_consecutiveClosedFrames >= _minClosedFrames) {
          // Valid blink detected
          if (!_wasEyesClosed) {
            _wasEyesClosed = true;
          }
        }
        _consecutiveClosedFrames = 0;
      }

      // Detect complete blink: was closed, now open with sufficient frames
      if (_wasEyesClosed && _consecutiveOpenFrames >= _minOpenFrames && isEyesOpen) {
        _wasEyesClosed = false;
        
        final now = DateTime.now();
        if (_lastBlinkTime == null || 
            now.difference(_lastBlinkTime!) > const Duration(milliseconds: 200)) { // Reduced debounce for easier detection
          _blinkCount++;
          _lastBlinkTime = now;
          
          // Smooth animation to new progress
          final targetProgress = (_blinkCount / 2.0 * 100).clamp(0.0, 100.0);
          _progressAnimation = Tween<double>(
            begin: _progressController.value * 100,
            end: targetProgress,
          ).animate(CurvedAnimation(
            parent: _progressController,
            curve: Curves.easeOut,
          ));
          _progressController.forward(from: 0.0);
          
          if (_blinkCount >= 2 && !_isBlinkComplete && !_navigated) {
            _isBlinkComplete = true;
            _completeBlinkVerification(face);
          }
        }
      }
    } else {
      if (_wasEyesClosed) _wasEyesClosed = false;
      _consecutiveClosedFrames = 0;
      _consecutiveOpenFrames = 0;
    }
  }

  Future<void> _completeBlinkVerification(Face face) async {
    print('🔍 _completeBlinkVerification called');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('face_verification_blinkCompleted', true);
      await prefs.setString('face_verification_blinkCompletedAt', DateTime.now().toIso8601String());
      print('✅ Blink completion flags saved');
      
      // CRITICAL: Capture image BEFORE stopping the stream
      print('📸 Starting image capture for blink verification...');
      await _registerBlinkEmbedding(face);
      print('✅ Image capture completed');
      
      // Stop stream AFTER image is captured
      if (_cameraController != null && _cameraController!.value.isStreamingImages) {
        try {
          await _cameraController!.stopImageStream();
          print('✅ Image stream stopped');
        } catch (e) {
          print('⚠️ Error stopping stream: $e');
        }
      }
      _detectionTimer?.cancel();
      
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && !_navigated) {
          _navigated = true;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const FaceMoveCloserScreen()),
          );
        }
      });
    } catch (e) {
      print('❌ Error in _completeBlinkVerification: $e');
      if (mounted && !_navigated) {
        _navigated = true;
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            if (_cameraController != null && _cameraController!.value.isStreamingImages) {
              _cameraController!.stopImageStream();
            }
            _detectionTimer?.cancel();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const FaceMoveCloserScreen()),
            );
          }
        });
      }
    }
  }

  Future<void> _registerBlinkEmbedding(Face face) async {
    print('🔍 _registerBlinkEmbedding called');
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('signup_user_id') ?? prefs.getString('current_user_id');
      final email = prefs.getString('signup_email') ?? '';
      final phone = prefs.getString('signup_phone') ?? '';
      
      print('🔍 Camera controller state: ${_cameraController != null ? "exists" : "null"}, initialized: ${_cameraController?.value.isInitialized ?? false}');
      
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        print('📸 Taking picture for blink verification...');
        final XFile imageFile = await _cameraController!.takePicture();
        print('📸 Picture taken: ${imageFile.path}');
        final Uint8List imageBytes = await imageFile.readAsBytes();
        print('📸 Image bytes read: ${imageBytes.length} bytes');
        
        // CRITICAL: Save image path FIRST, regardless of userId (needed for enrollment later)
        if (imageFile.path.isNotEmpty) {
          await prefs.setString('face_verification_blinkImagePath', imageFile.path);
          await prefs.setBool('face_verification_blinkCompleted', true);
          await prefs.setString('face_verification_blinkCompletedAt', DateTime.now().toIso8601String());
          print('✅ Blink image path saved: ${imageFile.path}');
          print('✅ Blink verification completed flag saved');
          
          // Verify the save was successful
          final savedPath = prefs.getString('face_verification_blinkImagePath');
          if (savedPath == imageFile.path) {
            print('✅ Verified: Blink image path correctly saved to SharedPreferences');
          } else {
            print('❌ WARNING: Blink image path save verification failed! Expected: ${imageFile.path}, Got: $savedPath');
          }
        } else {
          print('❌ ERROR: Blink image path is empty! Cannot save to SharedPreferences.');
        }
        
        // Only register embedding if userId is available (optional - image path already saved above)
        if (userId != null && userId.isNotEmpty) {
          final inputImage = InputImage.fromFilePath(imageFile.path);
          final faces = await _faceDetector.processImage(inputImage);
          
          if (faces.isNotEmpty) {
            final capturedFace = faces.first;
            final result = await ProductionFaceRecognitionService.registerAdditionalEmbedding(
              userId: userId,
              detectedFace: capturedFace,
              cameraImage: null,
              imageBytes: imageBytes,
              source: 'blink_twice',
              email: email.isNotEmpty ? email : null,
              phoneNumber: phone.isNotEmpty ? phone : null,
            );
            
            if (result['success'] == true) {
              print('✅ Blink verification embedding registered successfully');
            }
          }
        } else {
          print('⚠️ No userId available - skipping embedding registration, but image path is saved for enrollment');
        }
      } else {
        print('❌ ERROR: Camera controller is null or not initialized! Cannot capture image.');
        print('   - Controller null: ${_cameraController == null}');
        print('   - Controller initialized: ${_cameraController?.value.isInitialized ?? false}');
        // Try to save a note that we attempted but camera wasn't ready
        await prefs.setString('face_verification_blinkImagePath', 'CAMERA_NOT_READY');
      }
    } catch (e, stackTrace) {
      print('❌ Error registering blink embedding: $e');
      print('❌ Stack trace: $stackTrace');
      // Even on error, try to save image path if we have it
      try {
        if (_cameraController != null && _cameraController!.value.isInitialized) {
          final XFile imageFile = await _cameraController!.takePicture();
          if (imageFile.path.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('face_verification_blinkImagePath', imageFile.path);
            print('✅ Blink image path saved after error: ${imageFile.path}');
          }
        }
      } catch (saveError) {
        print('❌ Failed to save blink image path after error: $saveError');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo.png', height: 60),
              const SizedBox(height: 30),
              const Text(
                "FACE VERIFICATION",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Colors.black,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 30),
              
              // Camera preview with smooth 60fps animations
              SizedBox(
                width: 250,
                height: 350,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Smooth animated progress border (60fps)
                    AnimatedBuilder(
                      animation: Listenable.merge([_progressAnimation, _pulseAnimation]),
                      builder: (context, child) {
                        return SizedBox(
                          width: 250,
                          height: 350,
                          child: CircularProgressIndicator(
                            value: _progressAnimation.value / 100.0,
                            strokeWidth: 8,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _isBlinkComplete ? Colors.green : Colors.red,
                            ),
                          ),
                        );
                      },
                    ),
                    // Pulsing camera preview (60fps) with correct aspect ratio
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _faceDetected && _faceQuality >= 0.65 ? _pulseAnimation.value : 1.0,
                          child: Container(
                            width: 240,
                            height: 340,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.elliptical(120, 170),
                                topRight: const Radius.elliptical(120, 170),
                                bottomLeft: const Radius.elliptical(120, 170),
                                bottomRight: const Radius.elliptical(120, 170),
                              ),
                              border: _faceDetected && _faceQuality >= 0.65
                                  ? Border.all(color: Colors.green, width: 2)
                                  : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.elliptical(120, 170),
                                topRight: const Radius.elliptical(120, 170),
                                bottomLeft: const Radius.elliptical(120, 170),
                                bottomRight: const Radius.elliptical(120, 170),
                              ),
                              child: _isCameraInitialized &&
                                      _cameraController != null &&
                                      _cameraController!.value.isInitialized
                                  ? FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: _cameraController!.value.previewSize?.height.toDouble() ?? 240,
                                        height: _cameraController!.value.previewSize?.width.toDouble() ?? 340,
                                        child: CameraPreview(_cameraController!),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey[200],
                                      child: const Center(
                                        child: CircularProgressIndicator(color: Colors.red),
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              
              // Status text with smooth transitions
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _isBlinkComplete
                      ? "SUCCESS!"
                      : _blinkCount == 1
                          ? "BLINK ONCE MORE"
                          : "BLINK TWICE",
                  key: ValueKey(_blinkCount),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: _isBlinkComplete ? Colors.green : Colors.red,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Quality message
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _isBlinkComplete
                      ? "Great job! Moving to next step..."
                      : _blinkCount == 1
                          ? "One blink detected! Blink once more"
                          : _qualityMessage,
                  key: ValueKey(_qualityMessage),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: _faceQuality >= 0.65 ? Colors.green : Colors.grey,
                  ),
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Progress text with smooth animation
              AnimatedBuilder(
                animation: _progressAnimation,
                builder: (context, child) {
                  return Text(
                    "Blinks: $_blinkCount/2 • Progress: ${_progressAnimation.value.toInt()}%",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 5),
              
              Text(
                "Keep your face centered and blink naturally",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
