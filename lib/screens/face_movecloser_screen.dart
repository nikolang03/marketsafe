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
import 'face_headmovement_screen.dart';
import '../services/production_face_recognition_service.dart';
import '../services/face_landmark_service.dart';
import '../services/face_data_service.dart';

class FaceMoveCloserScreen extends StatefulWidget {
  const FaceMoveCloserScreen({super.key});

  @override
  State<FaceMoveCloserScreen> createState() => _FaceMoveCloserScreenState();
}

class _FaceMoveCloserScreenState extends State<FaceMoveCloserScreen> with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  late final FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isProcessingImage = false;
  bool _isFaceCloseEnough = false;
  Timer? _detectionTimer;
  bool _useImageStream = true;
  bool _hasCheckedFaceUniqueness = false;
  bool _navigated = false;

  // 60fps smooth animation controllers
  late AnimationController _progressController;
  late AnimationController _pulseController;
  late AnimationController _qualityController;
  late Animation<double> _progressAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _qualityAnimation;

  // Face quality metrics
  double _overallQuality = 0.0;
  String _qualityMessage = "Position your face in the frame";
  bool _faceDetected = false;
  
  // Progress smoothing - responsive to face movement
  List<double> _progressHistory = [];
  DateTime? _lastProgressUpdate;

  @override
  void initState() {
    super.initState();
    
    // Initialize 60fps animation controllers
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), // Slower animation for smoother progress
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _qualityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _progressAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
    );
    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _qualityAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _qualityController, curve: Curves.easeInOut),
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
    _qualityController.dispose();
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
          _detectFaceDistance(faces.first, null, imageBytes);
        } else {
          _updateFaceQuality(false, 0.0, 0.0, 0.0, 0.0, 0.0, "No face detected");
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
    if (_isProcessingImage || !_isCameraInitialized || _cameraController == null || _isFaceCloseEnough) return;
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
        _detectFaceDistance(faces.first, image, null);
      } else {
        // No face detected - reset progress to 0
        _resetProgress();
        _updateFaceQuality(false, 0.0, 0.0, 0.0, 0.0, 0.0, "No face detected");
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

  void _detectFaceDistance(Face face, [CameraImage? cameraImage, Uint8List? imageBytes]) async {
    if (!_hasCheckedFaceUniqueness) {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('signup_user_id');
      final email = prefs.getString('signup_email');
      if (userId == null && (email == null || email.isEmpty)) {
        _hasCheckedFaceUniqueness = true;
      } else {
        _hasCheckedFaceUniqueness = true;
      }
    }

    final box = face.boundingBox;
    final faceHeight = box.height;
    final faceWidth = box.width;
    
    // Get image dimensions - use actual camera image dimensions
    final imageWidth = cameraImage?.width.toDouble() ?? 480.0;
    final imageHeight = cameraImage?.height.toDouble() ?? 640.0;
    
    // Debug: Print bounding box and image dimensions
    print('🔍 Bounding Box: left=${box.left.toStringAsFixed(1)}, top=${box.top.toStringAsFixed(1)}, width=${faceWidth.toStringAsFixed(1)}, height=${faceHeight.toStringAsFixed(1)}');
    print('🔍 Image Dimensions: ${imageWidth.toStringAsFixed(1)}x${imageHeight.toStringAsFixed(1)}');
    
    // Clamp bounding box to image bounds (more lenient - allows slight overflow)
    // This handles edge cases where bounding box might be slightly outside due to rounding
    final clampedLeft = box.left.clamp(0.0, imageWidth);
    final clampedTop = box.top.clamp(0.0, imageHeight);
    final clampedWidth = faceWidth.clamp(0.0, imageWidth - clampedLeft);
    final clampedHeight = faceHeight.clamp(0.0, imageHeight - clampedTop);
    
    // Use clamped values for calculations
    final effectiveWidth = clampedWidth;
    final effectiveHeight = clampedHeight;
    
    // Face size calculation - use the larger dimension (more accurate for distance)
    // Using max(width, height) gives better distance estimation
    // For a face, typically height is larger, so this should be more accurate
    double avgFaceSize = effectiveHeight > effectiveWidth ? effectiveHeight : effectiveWidth;
    
    // Additional validation: face should not be larger than 90% of the smaller image dimension
    final maxReasonableSize = (imageWidth < imageHeight ? imageWidth : imageHeight) * 0.90;
    if (avgFaceSize > maxReasonableSize) {
      print('⚠️ Face size (${avgFaceSize.toStringAsFixed(1)}px) exceeds reasonable limit (${maxReasonableSize.toStringAsFixed(1)}px) - using max');
      avgFaceSize = maxReasonableSize;
    }
    
    // Use relative sizing for targets too
    final imageMinDimension = imageWidth < imageHeight ? imageWidth : imageHeight;
    final targetMinSize = imageMinDimension * 0.20; // 20% of image
    final targetIdealMinSize = imageMinDimension * 0.45; // 45% of image - good size range starts
    final targetIdealMaxSize = imageMinDimension * 0.80; // 80% of image - good size range ends
    final targetMaxSize = imageMinDimension * 0.85; // 85% of image - maximum for 100% progress (face must be EXTREMELY close)
    
    // 1. Face Size Score (based on pixel size - directly related to distance)
    double sizeScore = 0.0;
    if (avgFaceSize >= targetIdealMinSize && avgFaceSize <= targetIdealMaxSize) {
      // Within ideal range - give high score
      sizeScore = 0.80 + ((avgFaceSize - targetIdealMinSize) / (targetIdealMaxSize - targetIdealMinSize)) * 0.20;
      sizeScore = sizeScore.clamp(0.0, 1.0);
    } else if (avgFaceSize < targetMinSize) {
      // Too far away - low score, progress should be low
      sizeScore = (avgFaceSize / targetMinSize * 0.5).clamp(0.0, 0.5);
    } else if (avgFaceSize < targetIdealMinSize) {
      // Getting closer but not ideal yet
      sizeScore = 0.5 + ((avgFaceSize - targetMinSize) / (targetIdealMinSize - targetMinSize)) * 0.30;
      sizeScore = sizeScore.clamp(0.0, 1.0);
    } else if (avgFaceSize > targetIdealMaxSize && avgFaceSize <= targetMaxSize) {
      // Too close but still acceptable
      sizeScore = 1.0 - ((avgFaceSize - targetIdealMaxSize) / (targetMaxSize - targetIdealMaxSize)) * 0.20;
      sizeScore = sizeScore.clamp(0.0, 1.0);
    } else {
      // Too close or too far - penalize
      sizeScore = 0.3;
    }
    
    // 2. Centering Score (much more forgiving)
    final faceCenterX = clampedLeft + (effectiveWidth / 2);
    final faceCenterY = clampedTop + (effectiveHeight / 2);
    final imageCenterX = imageWidth / 2;
    final imageCenterY = imageHeight / 2;
    final distanceX = (faceCenterX - imageCenterX).abs() / imageWidth;
    final distanceY = (faceCenterY - imageCenterY).abs() / imageHeight;
    final maxDistance = distanceX > distanceY ? distanceX : distanceY;
    // Much more forgiving: allow 40% deviation from center, boost score
    final centerScore = (1.0 - (maxDistance / 0.40) * 0.7).clamp(0.5, 1.0);
    
    // 3. Head Pose Score (much more forgiving - allow up to 30 degrees)
    final headX = (face.headEulerAngleX?.abs() ?? 0.0) / 30.0;
    final headY = (face.headEulerAngleY?.abs() ?? 0.0) / 30.0;
    final headZ = (face.headEulerAngleZ?.abs() ?? 0.0) / 30.0;
    final maxAngle = (headX + headY + headZ) / 3.0;
    // Boost score - minimum 0.6 if face is detected
    final poseScore = (1.0 - maxAngle * 0.7).clamp(0.6, 1.0);
    
    // 4. Eyes Visibility Score (more generous)
    final hasLeftEye = face.leftEyeOpenProbability != null && face.leftEyeOpenProbability! > 0.2;
    final hasRightEye = face.rightEyeOpenProbability != null && face.rightEyeOpenProbability! > 0.2;
    final eyesScore = (hasLeftEye && hasRightEye) ? 1.0 : (hasLeftEye || hasRightEye ? 0.75 : 0.5);
    
    // 5. Lighting Score (more generous)
    final lightingScore = (face.leftEyeOpenProbability != null && 
                           face.rightEyeOpenProbability != null) 
                           ? ((face.leftEyeOpenProbability! + face.rightEyeOpenProbability!) / 2.0 * 0.8 + 0.2).clamp(0.6, 1.0)
                           : 0.7;
    
    // 6. Overall Quality (weighted average - size is most important for "move closer")
    final overallQuality = (sizeScore * 0.50 +      // Size is MOST important (50%) - directly related to distance
                            centerScore * 0.20 +     // Centering (20%)
                            poseScore * 0.10 +       // Pose (10%)
                            eyesScore * 0.10 +       // Eyes visibility (10%)
                            lightingScore * 0.10);   // Lighting (10%)
    _overallQuality = overallQuality;
    
    // Calculate progress (0-100%) - DIRECTLY based on face size (distance) ONLY
    // Face must fit in oval (be very close) to reach 100%
    // Progress = face size mapped to 0-100%, but 100% requires face to be very close (fit in oval)
    double rawProgress;
    
    // Direct linear mapping from face size to progress
    // Use RELATIVE sizing based on image dimensions for better accuracy across devices
    // Face size range: 15% of image (far) to 85% of image (very close - must fit in oval)
    // Increased to 85% to ensure face is EXTREMELY close to the oval before reaching 100%
    final minSizeForProgress = (imageWidth < imageHeight ? imageWidth : imageHeight) * 0.15; // 15% of smaller dimension
    final maxSizeForProgress = (imageWidth < imageHeight ? imageWidth : imageHeight) * 0.85; // 85% of smaller dimension (face must be EXTREMELY close)
    
    // Calculate progress STRICTLY based on face size - relative to image size
    if (avgFaceSize < minSizeForProgress) {
      // Face is too far - 0% progress
      rawProgress = 0.0;
    } else if (avgFaceSize >= maxSizeForProgress) {
      // Face is very close and fits in oval - 100% progress
      rawProgress = 100.0;
    } else {
      // Linear mapping: relative size maps to progress 0-100%
      // Example: If image is 480px, min=72px (15%), max=408px (85%)
      // Face at 240px (50% of image) = ((240-72)/(408-72)) * 100 = (168/336) * 100 = 50%
      // Face at 360px (75% of image) = ((360-72)/(408-72)) * 100 = (288/336) * 100 = 85.7%
      rawProgress = ((avgFaceSize - minSizeForProgress) / (maxSizeForProgress - minSizeForProgress)) * 100.0;
    }
    
    // STRICT clamping - never allow progress above 100% or below 0%
    rawProgress = rawProgress.clamp(0.0, 100.0);
    
    // NO SMOOTHING - use raw progress directly to accurately reflect face distance
    // Progress history is only used for debugging, not for calculation
    _progressHistory.add(rawProgress);
    if (_progressHistory.length > 5) {
      _progressHistory.removeAt(0);
    }
    
    // Use raw progress directly - no averaging, no smoothing
    // This ensures progress bar accurately reflects actual face size
    double avgProgress = rawProgress;
    
    // Debug: Print face size and progress for troubleshooting
    print('📊 Face Size: ${avgFaceSize.toStringAsFixed(1)}px (${((avgFaceSize / imageMinDimension) * 100).toStringAsFixed(1)}% of image) | Min: ${minSizeForProgress.toStringAsFixed(1)}px | Max: ${maxSizeForProgress.toStringAsFixed(1)}px | Progress: ${rawProgress.toStringAsFixed(1)}%');
    
    // Determine quality message - more helpful
    String message = "Position your face in the frame";
    if (overallQuality < 0.50) {
      if (sizeScore < 0.50) {
        message = avgFaceSize < targetMinSize 
            ? "Move closer to the camera" 
            : "Move slightly away from the camera";
      } else if (centerScore < 0.50) {
        message = "Center your face in the frame";
      } else if (poseScore < 0.50) {
        message = "Look straight at the camera";
      } else if (eyesScore < 0.65) {
        message = "Make sure both eyes are visible";
      } else {
        message = "Adjust your position";
      }
    } else if (overallQuality >= 0.50) {
      message = "Perfect! Face scanning complete";
    } else {
      message = "Almost there! Keep adjusting";
    }
    
    // Update UI with smooth animations
    _updateFaceQuality(true, sizeScore, centerScore, poseScore, lightingScore, overallQuality, message);
    
    // Update progress animation immediately - always update to reflect face size
    final progressNow = DateTime.now();
    final currentAnimatedProgress = _progressAnimation.value;
    final progressDiff = (avgProgress - currentAnimatedProgress).abs();
    
    // Always update if there's any change (very responsive)
    // Use very low threshold (0.5%) and short cooldown (50ms) for immediate response
    final effectiveThreshold = 0.5; // Update on any 0.5% change
    final effectiveCooldown = Duration(milliseconds: 50); // Update every 50ms
    
    final canUpdate = _lastProgressUpdate == null || 
                      progressNow.difference(_lastProgressUpdate!) >= effectiveCooldown;
    
    if (progressDiff > effectiveThreshold && canUpdate) {
      // Always update progress animation to reflect current face size
      _lastProgressUpdate = progressNow;
      _progressAnimation = Tween<double>(
        begin: currentAnimatedProgress,
        end: avgProgress,
      ).animate(CurvedAnimation(
        parent: _progressController,
        curve: Curves.linear, // Linear for immediate response
      ));
      _progressController.forward(from: 0.0);
    }
    
    // Auto-complete when progress reaches 100% - face must fit in oval
    // Check both the calculated avgProgress and the displayed progress
    final displayedProgress = _progressAnimation.value;
    
    // Auto-complete when progress is 100% - face is very close and fits in oval
    // Require face to be at least 85% of image size (EXTREMELY close to oval)
    final isPerfectScan = avgProgress >= 100.0 && // Calculated progress must be exactly 100%
                         displayedProgress >= 100.0 && // Displayed progress must be exactly 100%
                         avgFaceSize >= maxSizeForProgress; // Face MUST be >= 85% of image (EXTREMELY close, fits in oval)

    if (mounted) {
      setState(() {
        _isFaceCloseEnough = isPerfectScan;
      });
    }

    // Auto-complete immediately when progress hits 100%
    if (isPerfectScan && !_navigated) {
      _navigated = true;
      // Start completion process immediately
      _completeMoveCloserVerification(face).catchError((e) {
        print('❌ Error in completion: $e');
        // Still navigate even on error
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const FaceHeadMovementScreen()),
              );
            }
          });
        }
      });
    }
  }

  void _resetProgress() {
    // Clear progress history when no face is detected
    _progressHistory.clear();
    
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

  void _updateFaceQuality(bool detected, double size, double center, double pose, 
                          double lighting, double overall, String message) {
    if (mounted) {
      setState(() {
        _faceDetected = detected;
        _overallQuality = overall;
        _qualityMessage = message;
      });
      
      // Smooth quality animation
      _qualityAnimation = Tween<double>(
        begin: _qualityController.value,
        end: overall,
      ).animate(CurvedAnimation(
        parent: _qualityController,
        curve: Curves.easeOut,
      ));
      _qualityController.forward(from: 0.0);
    }
  }

  Future<void> _completeMoveCloserVerification(Face face) async {
    bool shouldNavigate = true;
    
    try {
      // Stop camera stream properly
      if (_cameraController != null && _cameraController!.value.isStreamingImages) {
        try {
          await _cameraController!.stopImageStream();
        } catch (e) {
          print('⚠️ Error stopping stream: $e');
        }
      }
      _detectionTimer?.cancel();
      
      // Wait for camera to settle
      await Future.delayed(const Duration(milliseconds: 200));

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('signup_user_id') ?? prefs.getString('current_user_id');
      final email = prefs.getString('signup_email') ?? '';

      if (userId == null || userId.isEmpty) {
        print('⚠️ No userId found, but continuing anyway');
        // Don't return - continue to navigation
      } else {
        // Try to capture and register face, but don't block navigation on failure
        try {
          XFile? imageFile;
          Uint8List? imageBytes;
          Face? finalDetectedFace;
          
          if (_cameraController != null && _cameraController!.value.isInitialized) {
            try {
              imageFile = await _cameraController!.takePicture();
              imageBytes = await imageFile.readAsBytes();

              if (imageBytes.isNotEmpty && imageBytes.length >= 1000) {
                // Re-detect face in captured image for accuracy
                final InputImage inputImage = InputImage.fromFilePath(imageFile.path);
                final List<Face> faces = await _faceDetector.processImage(inputImage);

                if (faces.isNotEmpty) {
                  finalDetectedFace = faces.first;
                  
                  // Validate face has essential features
                  final hasEssentialFeatures = FaceLandmarkService.validateEssentialFeatures(finalDetectedFace);
                  if (!hasEssentialFeatures) {
                    print('⚠️ Face missing essential features - skipping enrollment');
                  } else {
                    // Actually enroll face to backend/Luxand for better accuracy
                    // Note: Backend requires email, so we only enroll if email is available
                    // For phone-only signups, enrollment will happen later in fill_information_screen
                    if (email.isNotEmpty) {
                      print('📸 Enrolling face from move closer step to backend/Luxand...');
                      try {
                        final enrollResult = await ProductionFaceRecognitionService.enrollUserFaceWithLuxand(
                          email: email,
                          imageBytes: imageBytes,
                        );
                        
                        if (enrollResult['success'] == true) {
                          final luxandUuid = enrollResult['luxandUuid']?.toString() ?? '';
                          print('✅ Face enrolled successfully from move closer step. UUID: $luxandUuid');
                          
                          // Save enrollment info to SharedPreferences
                          prefs.setBool('face_verification_moveCloserCompleted', true);
                          prefs.setString('face_verification_moveCloserCompletedAt', DateTime.now().toIso8601String());
                          if (imageFile.path.isNotEmpty) {
                            prefs.setString('face_verification_moveCloserImagePath', imageFile.path);
                          }
                          if (luxandUuid.isNotEmpty) {
                            prefs.setString('face_verification_moveCloserLuxandUuid', luxandUuid);
                          }
                          
                          // Update Firebase directly (userId is guaranteed to be non-null in this else block)
                          try {
                            await FaceDataService.updateFaceVerificationStep(
                              'moveCloserCompleted',
                              imagePath: imageFile.path,
                              userId: userId,
                            );
                            print('✅ Move closer completion updated in Firebase');
                          } catch (firebaseError) {
                            print('⚠️ Failed to update Firebase (non-blocking): $firebaseError');
                          }
                        } else {
                          final error = enrollResult['error']?.toString() ?? 'Unknown error';
                          print('⚠️ Face enrollment failed: $error');
                          // Still save that we completed the step
                          prefs.setBool('face_verification_moveCloserCompleted', true);
                          prefs.setString('face_verification_moveCloserCompletedAt', DateTime.now().toIso8601String());
                          if (imageFile.path.isNotEmpty) {
                            prefs.setString('face_verification_moveCloserImagePath', imageFile.path);
                          }
                          
                          // Update Firebase directly even if enrollment failed (userId is guaranteed to be non-null in this else block)
                          try {
                            await FaceDataService.updateFaceVerificationStep(
                              'moveCloserCompleted',
                              imagePath: imageFile.path,
                              userId: userId,
                            );
                            print('✅ Move closer completion updated in Firebase');
                          } catch (firebaseError) {
                            print('⚠️ Failed to update Firebase (non-blocking): $firebaseError');
                          }
                        }
                      } catch (enrollError) {
                        print('⚠️ Enrollment error: $enrollError');
                        // Still save that we completed the step
                        prefs.setBool('face_verification_moveCloserCompleted', true);
                        prefs.setString('face_verification_moveCloserCompletedAt', DateTime.now().toIso8601String());
                        if (imageFile.path.isNotEmpty) {
                          prefs.setString('face_verification_moveCloserImagePath', imageFile.path);
                        }
                        
                        // Update Firebase directly even on enrollment error (userId is guaranteed to be non-null in this else block)
                        try {
                          await FaceDataService.updateFaceVerificationStep(
                            'moveCloserCompleted',
                            imagePath: imageFile.path,
                            userId: userId,
                          );
                          print('✅ Move closer completion updated in Firebase');
                        } catch (firebaseError) {
                          print('⚠️ Failed to update Firebase (non-blocking): $firebaseError');
                        }
                      }
                    } else {
                      print('ℹ️ No email available - enrollment will happen later in fill_information_screen');
                      // Still save that we completed the step and captured the image
                      prefs.setBool('face_verification_moveCloserCompleted', true);
                      prefs.setString('face_verification_moveCloserCompletedAt', DateTime.now().toIso8601String());
                      if (imageFile.path.isNotEmpty) {
                        prefs.setString('face_verification_moveCloserImagePath', imageFile.path);
                      }
                      
                      // Update Firebase directly even without email (userId is guaranteed to be non-null in this else block)
                      try {
                        await FaceDataService.updateFaceVerificationStep(
                          'moveCloserCompleted',
                          imagePath: imageFile.path,
                          userId: userId,
                        );
                        print('✅ Move closer completion updated in Firebase');
                      } catch (firebaseError) {
                        print('⚠️ Failed to update Firebase (non-blocking): $firebaseError');
                      }
                    }
                  }
                }
              }
            } catch (captureError) {
              print('⚠️ Image capture error: $captureError');
              // Continue anyway - don't block navigation
            }
          }
        } catch (e) {
          print('⚠️ Error in face registration: $e');
          // Continue anyway - don't block navigation
        }
      }

      // Always navigate after short delay
      if (mounted && shouldNavigate) {
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const FaceHeadMovementScreen()),
          );
        }
      }
    } catch (e) {
      print('❌ Error during completion: $e');
      // Always navigate even on error
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const FaceHeadMovementScreen()),
            );
          }
        });
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
                              _isFaceCloseEnough ? Colors.green : Colors.red,
                            ),
                          ),
                        );
                      },
                    ),
                    // Pulsing camera preview (60fps) with correct aspect ratio
                    AnimatedBuilder(
                      animation: Listenable.merge([_pulseAnimation, _qualityAnimation]),
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _faceDetected && _overallQuality >= 0.50 
                              ? _pulseAnimation.value 
                              : 1.0,
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
                              border: _faceDetected && _overallQuality >= 0.50
                                  ? Border.all(
                                      color: Colors.green.withOpacity(_qualityAnimation.value),
                                      width: 3,
                                    )
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
                  _isFaceCloseEnough ? "SUCCESS!" : "MOVE CLOSER",
                  key: ValueKey(_isFaceCloseEnough),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: _isFaceCloseEnough ? Colors.green : Colors.red,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Quality message with smooth transitions
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _isFaceCloseEnough
                      ? "Perfect scan! Moving to next step..."
                      : _qualityMessage,
                  key: ValueKey(_qualityMessage),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: _overallQuality >= 0.50 ? Colors.green : Colors.grey,
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
                "Position your face in the center and move closer",
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
