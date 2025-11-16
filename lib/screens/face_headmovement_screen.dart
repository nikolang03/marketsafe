import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fill_information_screen.dart';
import '../services/production_face_recognition_service.dart';
import '../services/face_data_service.dart';

class FaceHeadMovementScreen extends StatefulWidget {
  const FaceHeadMovementScreen({super.key});

  @override
  State<FaceHeadMovementScreen> createState() => _FaceHeadMovementScreenState();
}

class _FaceHeadMovementScreenState extends State<FaceHeadMovementScreen> with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  late final FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isProcessingImage = false;
  bool _navigated = false;
  Timer? _detectionTimer;
  bool _useImageStream = true;
  Face? _lastDetectedFace;
  CameraImage? _lastCameraImage;
  Uint8List? _lastImageBytes;

  // 60fps smooth animation controllers
  late AnimationController _progressController;
  late AnimationController _pulseController;
  late AnimationController _movementController;
  late Animation<double> _progressAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _movementAnimation;

  // Head movement tracking
  double? _initialX;
  bool _movedLeft = false;
  bool _movedRight = false;
  bool _success = false;
  
  // Track best movement to prevent missing quick movements
  double _bestLeftMovement = 0.0;
  double _bestRightMovement = 0.0;
  
  // Movement history for smooth detection
  List<double> _headXHistory = [];
  List<double> _headYHistory = [];
  static const int _historySize = 10;
  static const double _movementThreshold = 5.0; // Degrees - lowered for more reliable detection
  static const double _minMovementForProgress = 2.5; // Minimum movement to show progress - more lenient
  static const double _detectionThreshold = 4.0; // Lower threshold for actual detection (more reliable)
  
  // Progress smoothing
  List<double> _progressHistory = [];
  static const int _progressHistorySize = 15;
  static const double _progressUpdateThreshold = 3.0;
  DateTime? _lastProgressUpdate;
  static const Duration _progressUpdateCooldown = Duration(milliseconds: 300);
  
  // Face quality
  bool _faceDetected = false;
  String _qualityMessage = "Position your face in the frame";

  @override
  void initState() {
    super.initState();
    
    // Initialize 60fps animation controllers
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), // Slower for smoother progress
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _movementController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    
    _progressAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
    );
    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _movementAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _movementController,
      curve: Curves.easeOut,
    ));
    
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
    _movementController.dispose();
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
        ResolutionPreset.high,
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
        final imageBytes = await imageFile.readAsBytes();
        final inputImage = InputImage.fromFilePath(imageFile.path);
        final faces = await _faceDetector.processImage(inputImage);
        if (faces.isNotEmpty) {
          _detectHeadMovement(faces.first, null, imageBytes);
        } else {
          _updateFaceQuality(false, "No face detected");
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
    if (_isProcessingImage || !_isCameraInitialized || _cameraController == null || _success) return;
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
        _lastDetectedFace = faces.first;
        _lastCameraImage = image;
        _detectHeadMovement(faces.first, image, null);
        _checkFaceQuality(faces.first);
      } else {
        // No face detected - reset progress to 0
        _resetProgress();
        _updateFaceQuality(false, "No face detected");
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

  void _checkFaceQuality(Face face) {
    final bbox = face.boundingBox;
    final faceArea = bbox.width * bbox.height;
    final hasEyes = (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null);
    
    String message = "Position your face in the frame";
    if (faceArea < 20000) {
      message = "Move closer to the camera";
    } else if (!hasEyes) {
      message = "Look straight at the camera";
    } else if (_initialX == null) {
      message = "Hold still, then move your head";
    } else if (!_movedLeft) {
      message = "Turn your head to the left";
    } else if (!_movedRight) {
      message = "Now turn your head to the right";
    } else {
      message = "Perfect! Verification complete";
    }
    
    _updateFaceQuality(true, message);
  }

  void _resetProgress() {
    // Reset all head movement state when no face is detected
    _progressHistory.clear();
    _movedLeft = false;
    _movedRight = false;
    _success = false;
    _initialX = null;
    _headXHistory.clear();
    _headYHistory.clear();
    
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

  void _updateFaceQuality(bool detected, String message) {
    if (mounted) {
      setState(() {
        _faceDetected = detected;
        _qualityMessage = message;
      });
    }
  }

  void _detectHeadMovement(Face face, [CameraImage? cameraImage, Uint8List? imageBytes]) async {
    _lastDetectedFace = face;
    _lastCameraImage = cameraImage;
    _lastImageBytes = imageBytes;

    // headEulerAngleY: negative = left, positive = right
    final headX = face.headEulerAngleY ?? 0.0;
    final headY = face.headEulerAngleX ?? 0.0;

    // Initialize base position on first detection (with stability check)
    if (_initialX == null) {
      // Wait for stable initial position
      _headXHistory.add(headX);
      _headYHistory.add(headY);
      
      if (_headXHistory.length >= 3) {
        // Check if position is stable (low variance) - more lenient for Android
        final avgX = _headXHistory.reduce((a, b) => a + b) / _headXHistory.length;
        final varianceX = _headXHistory.map((x) => (x - avgX) * (x - avgX)).reduce((a, b) => a + b) / _headXHistory.length;
        
        if (varianceX < 75.0) { // Even more lenient threshold for Android devices
          _initialX = avgX;
        }
      }
      
      if (_headXHistory.length > _historySize) {
        _headXHistory.removeAt(0);
        _headYHistory.removeAt(0);
      }
      
      if (_initialX == null) return;
    }

    // Track movement history for smooth detection
    _headXHistory.add(headX);
    if (_headXHistory.length > _historySize) {
      _headXHistory.removeAt(0);
    }

    // Calculate smoothed head position (moving average)
    final smoothedX = _headXHistory.reduce((a, b) => a + b) / _headXHistory.length;
    
    // Calculate raw progress based on ACTUAL movement, not fixed values
    double rawProgress = 0.0;
    
    if (_initialX == null) {
      // Still initializing - no progress
      rawProgress = 0.0;
    } else if (!_movedLeft) {
      // Calculate progress based on how much left movement detected
      final leftMovement = smoothedX - _initialX!;
      if (leftMovement > _minMovementForProgress) {
        // Show progress based on movement amount (0-50% for left movement)
        rawProgress = ((leftMovement / _movementThreshold) * 50.0).clamp(0.0, 50.0);
      } else {
        // No significant movement - keep at 0%
        rawProgress = 0.0;
      }
    } else if (!_movedRight) {
      // Left movement completed, now calculate right movement progress
      final rightMovement = _initialX! - smoothedX; // Negative angle = right
      if (rightMovement > _minMovementForProgress) {
        // Show progress from 50-100% based on right movement
        rawProgress = 50.0 + ((rightMovement / _movementThreshold) * 50.0).clamp(0.0, 50.0);
      } else {
        // No significant right movement yet - stay at 50%
        rawProgress = 50.0;
      }
    } else {
      // Both movements completed
      rawProgress = 100.0;
    }

    // Smooth progress using moving average
    _progressHistory.add(rawProgress);
    if (_progressHistory.length > _progressHistorySize) {
      _progressHistory.removeAt(0);
    }
    
    // Use weighted average for smoother progress
    double weightedSum = 0.0;
    double weightSum = 0.0;
    for (int i = 0; i < _progressHistory.length; i++) {
      final weight = (i + 1).toDouble();
      weightedSum += _progressHistory[i] * weight;
      weightSum += weight;
    }
    final avgProgress = weightedSum / weightSum;

    // Smooth progress animation - only update if change is significant AND cooldown passed
    final now = DateTime.now();
    final currentAnimatedProgress = _progressAnimation.value;
    final progressDiff = (avgProgress - currentAnimatedProgress).abs();
    final canUpdate = _lastProgressUpdate == null || 
                      now.difference(_lastProgressUpdate!) >= _progressUpdateCooldown;
    
    if (progressDiff > _progressUpdateThreshold && canUpdate) {
      _lastProgressUpdate = now;
      _progressAnimation = Tween<double>(
        begin: currentAnimatedProgress,
        end: avgProgress,
      ).animate(CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeInOut, // Smoother curve
      ));
      _progressController.forward(from: 0.0);
    }

    // Detect LEFT movement (positive angle change > threshold)
    // Track best movement to catch quick movements even if they don't sustain
    if (!_movedLeft && _initialX != null) {
      final leftMovement = smoothedX - _initialX!;
      
      // Track the best (maximum) left movement seen so far
      if (leftMovement > _bestLeftMovement && leftMovement > 0) {
        _bestLeftMovement = leftMovement;
      }
      
      // Detect immediately when threshold is met (more reliable than requiring sustained movement)
      // Use lower detection threshold for more reliable detection
      if (_bestLeftMovement >= _detectionThreshold) {
        // Also check if current movement is still significant (at least 60% of detection threshold)
        // This prevents false positives from noise while still catching quick movements
        if (leftMovement >= _detectionThreshold * 0.6 || _bestLeftMovement >= _movementThreshold) {
          if (mounted) {
            setState(() => _movedLeft = true);
            _movementController.forward(from: 0.0);
            print('✅ Left movement detected: ${_bestLeftMovement.toStringAsFixed(1)}° (current: ${leftMovement.toStringAsFixed(1)}°)');
          }
        }
      }
    }

    // Detect RIGHT movement (only after left, negative angle change < -threshold from initial)
    // Must return to center or go past center to the right
    if (_movedLeft && !_movedRight && _initialX != null) {
      final rightMovement = _initialX! - smoothedX; // Positive = right movement
      
      // Track the best (maximum) right movement seen so far
      if (rightMovement > _bestRightMovement && rightMovement > 0) {
        _bestRightMovement = rightMovement;
      }
      
      // Detect immediately when threshold is met (more reliable than requiring sustained movement)
      // Use lower detection threshold for more reliable detection
      if (_bestRightMovement >= _detectionThreshold) {
        // Also check if current movement is still significant (at least 60% of detection threshold)
        // This prevents false positives from noise while still catching quick movements
        if (rightMovement >= _detectionThreshold * 0.6 || _bestRightMovement >= _movementThreshold) {
          if (mounted) {
            setState(() {
              _movedRight = true;
            });
            _movementController.forward(from: 0.0);
            print('✅ Right movement detected: ${_bestRightMovement.toStringAsFixed(1)}° (current: ${rightMovement.toStringAsFixed(1)}°)');
          }

          // Force progress to 100% immediately when both movements detected
          _progressHistory.clear();
          for (int i = 0; i < _progressHistorySize; i++) {
            _progressHistory.add(100.0);
          }
          
          // Update progress animation to 100%
          _progressAnimation = Tween<double>(
            begin: _progressAnimation.value,
            end: 100.0,
          ).animate(CurvedAnimation(
            parent: _progressController,
            curve: Curves.easeInOut,
          ));
          _progressController.forward(from: 0.0);
          
          // Complete immediately when both movements detected
          if (!_navigated) {
            _navigated = true;
            if (mounted) {
              setState(() {
                _success = true;
              });
            }
            // Complete immediately - no need to wait for animation
            await _completeHeadMovementVerification(face);
          }
        }
      }
    }
  }

  Future<void> _completeHeadMovementVerification(Face face) async {
    String? imagePath;
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        final XFile image = await _cameraController!.takePicture();
        imagePath = image.path;
        final file = File(imagePath);
        if (!await file.exists()) {
          imagePath = null;
        }
      }
    } catch (e) {
      imagePath = null;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('face_verification_headMovementCompleted', true);
      await prefs.setString('face_verification_headMovementCompletedAt', DateTime.now().toIso8601String());
      
      if (imagePath != null) {
        await prefs.setString('face_verification_headMovementImagePath', imagePath);
      }
      
      await prefs.setString('face_verification_headMovementMetrics', 
        '{"leftMovement": $_movedLeft, "rightMovement": $_movedRight, "completionTime": "${DateTime.now().toIso8601String()}"}');
      
      // Update Firebase directly if userId is available
      final currentUserId = prefs.getString('signup_user_id') ?? prefs.getString('current_user_id');
      if (currentUserId != null && currentUserId.isNotEmpty) {
        try {
          await FaceDataService.updateFaceVerificationStep(
            'headMovementCompleted',
            metrics: {
              'leftMovement': _movedLeft,
              'rightMovement': _movedRight,
              'completionTime': DateTime.now().toIso8601String(),
            },
            imagePath: imagePath,
            userId: currentUserId,
          );
          print('✅ Head movement completion updated in Firebase');
        } catch (firebaseError) {
          print('⚠️ Failed to update Firebase (non-blocking): $firebaseError');
        }
      }
      
      if (_lastDetectedFace != null) {
        final email = prefs.getString('signup_email') ?? '';
        final phone = prefs.getString('signup_phone') ?? '';
        
        if (currentUserId != null && currentUserId.isNotEmpty &&
            (_lastCameraImage != null || _lastImageBytes != null)) {
          final result = await ProductionFaceRecognitionService.registerAdditionalEmbedding(
            userId: currentUserId,
            detectedFace: _lastDetectedFace!,
            cameraImage: _lastCameraImage,
            imageBytes: _lastImageBytes,
            source: 'head_movement',
            email: email.isNotEmpty ? email : null,
            phoneNumber: phone.isNotEmpty ? phone : null,
          );
          
          if (result['success'] == true) {
            print('✅ Head movement embedding registered successfully');
          }
        }
      }
    } catch (e) {
      print('⚠️ Failed to save head movement verification data: $e');
    }

    if (mounted) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          if (_cameraController != null && _cameraController!.value.isStreamingImages) {
            _cameraController!.stopImageStream();
          }
          _detectionTimer?.cancel();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const FillInformationScreen()),
          );
        }
      });
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
                      animation: _progressAnimation,
                      builder: (context, child) {
                        return SizedBox(
                          width: 250,
                          height: 350,
                          child: CircularProgressIndicator(
                            value: _progressAnimation.value / 100.0,
                            strokeWidth: 8,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _success ? Colors.green : Colors.red,
                            ),
                          ),
                        );
                      },
                    ),
                    // Pulsing camera preview with movement animation (60fps) and correct aspect ratio
                    AnimatedBuilder(
                      animation: Listenable.merge([_pulseAnimation, _movementAnimation, _movementController]),
                      builder: (context, child) {
                        return Transform.translate(
                          offset: _movementAnimation.value * 20,
                          child: Transform.scale(
                            scale: _faceDetected ? _pulseAnimation.value : 1.0,
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
                                border: _success
                                    ? Border.all(color: Colors.green, width: 3)
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
                  !_movedLeft
                      ? "MOVE YOUR HEAD LEFT"
                      : !_movedRight
                          ? "MOVE YOUR HEAD RIGHT"
                          : "SUCCESS!",
                  key: ValueKey('$_movedLeft$_movedRight'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: _success ? Colors.green : Colors.red,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Quality message with smooth transitions
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  !_movedLeft
                      ? "Turn your head to the left side"
                      : !_movedRight
                          ? "Now turn your head to the right side"
                          : "Great job! Moving to next step...",
                  key: ValueKey(_qualityMessage),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: _success ? Colors.green : Colors.grey,
                  ),
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Progress text with smooth animation
              AnimatedBuilder(
                animation: _progressAnimation,
                builder: (context, child) {
                  return Text(
                    "Progress: ${_progressAnimation.value.toInt()}%",
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
                "Keep your face in the center and turn your head naturally",
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
