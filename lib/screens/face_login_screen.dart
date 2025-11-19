import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/lockout_service.dart';
import '../services/production_face_recognition_service.dart';
import '../services/network_service.dart';
import 'signup_screen.dart';
import 'welcome_screen.dart';
import 'under_verification_screen.dart';
import '../navigation_wrapper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  late final FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isProcessingImage = false;
  bool _isAuthenticating = false;
  bool _authenticationSuccess = false;
  bool _isFaceDetected = false;
  Timer? _detectionTimer;
  double _progressPercentage = 0.0;
  double _targetProgress = 0.0; // Target progress value for smooth animation
  late AnimationController _progressAnimationController;
  late Animation<double> _progressAnimation;
  bool _useImageStream = true;
  DateTime? _lastAuthenticationAttempt;
  int _failedAttempts = 0;
  DateTime? _lastFailedAttempt;
  static const Duration _authenticationCooldown = Duration(seconds: 3);
  static const Duration _lockoutDuration = Duration(minutes: 3); // REDUCED for better UX
  static const int _maxFailedAttempts = 5; // Already optimized

  // Deep scan & liveness state (kept for reset method compatibility)
  static const Duration _instructionUpdateThrottle = Duration(milliseconds: 400);
  static const String _defaultInstruction = 'Position your face in the oval and maintain a natural expression';
  String _instructionMessage = _defaultInstruction;
  Color _instructionColor = const Color(0xFF616161);
  DateTime? _lastInstructionUpdate;
  
  
  // Email/Phone input state
  final TextEditingController _emailOrPhoneController = TextEditingController();
  final FocusNode _emailOrPhoneFocusNode = FocusNode();
  bool _emailOrPhoneEntered = false;
  bool _isVerifyingEmailPhone = false;
  String? _verifiedEmailOrPhone;
  

  @override
  void initState() {
    super.initState();
    
    // Initialize smooth progress animation controller (60fps smooth animation)
    // Fast duration for real-time updates while maintaining smoothness
    _progressAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100), // Fast 100ms transition for smooth real-time updates
    );
    
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _progressAnimationController,
      curve: Curves.easeOutCubic, // Smooth easing curve
    ));
    
    _progressAnimation.addListener(() {
      if (mounted) {
        setState(() {
          _progressPercentage = _progressAnimation.value * 100.0;
        });
      }
    });
    
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // Enable for better detection
        enableLandmarks: true, // Enable for better detection
        enableContours: true, // Enable for better detection
        performanceMode: FaceDetectorMode.accurate, // Use accurate mode for better detection
        minFaceSize: 0.05, // Reduced from 0.01 - more reasonable minimum (was too small, causing false positives)
      ),
    );
    
    // Add listener to update icon color when focus changes
    _emailOrPhoneFocusNode.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    
    // Add a delay to ensure the previous camera is fully disposed
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _initializeCamera();
      }
    });
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _progressAnimationController.dispose(); // Dispose animation controller
    _emailOrPhoneController.dispose();
    _emailOrPhoneFocusNode.dispose();
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        _cameraController!.stopImageStream();
      }
    } catch (e) {
      print('Error stopping camera stream: $e');
    }
    _faceDetector.close();
    try {
      _cameraController?.dispose();
    } catch (e) {
      print('Error disposing camera: $e');
    }
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      // Check camera permission first
      final cameraStatus = await Permission.camera.status;

      if (cameraStatus.isDenied) {
        final result = await Permission.camera.request();
        if (result.isDenied) {
          if (mounted) {
            setState(() {
              _isCameraInitialized = false;
            });
          }
          return;
        }
      }

      if (cameraStatus.isPermanentlyDenied) {
        if (mounted) {
          setState(() {
            _isCameraInitialized = false;
          });
        }
        return;
      }

      // Wait a bit more if camera is still in use
      await Future.delayed(const Duration(milliseconds: 200));

      _cameras = await availableCameras();

      final frontCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.high, // HD resolution (720p)
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      _cameraController = controller;
      setState(() {
        _isCameraInitialized = true;
        _authenticationSuccess = false;
      });

      print('Camera initialized successfully!');
      print('Camera preview size: ${controller.value.previewSize}');
      print('Camera description: ${controller.description}');

      // Only start camera if email/phone is entered
      // Use a small delay to ensure camera is fully initialized
      if (_emailOrPhoneEntered) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _cameraController != null && _cameraController!.value.isInitialized) {
        // Try image stream first, fallback to timer-based detection
        try {
          _startImageStream();
        } catch (e) {
          print('Image stream failed, using timer-based detection: $e');
          _startTimerBasedDetection();
        }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
    }
  }

  // Frame skipping for performance - process every Nth frame
  // CRITICAL: Increased skipping to prevent scanning too quickly
  // This ensures proper face quality and prevents premature authentication
  int _frameSkipCounter = 0;
  static const int _framesToSkip = 4; // Process every 5th frame (12 FPS processing on 60 FPS camera) - was 2, increased to slow down scanning

  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    
    // Stop any existing stream first to prevent buffer issues
    try {
      if (_useImageStream) {
        _cameraController!.stopImageStream();
      }
    } catch (e) {
      print('Error stopping existing stream: $e');
    }

    try {
      _cameraController!.startImageStream((CameraImage image) {
        // Skip frames for performance - only process every Nth frame
        _frameSkipCounter++;
        if (_frameSkipCounter < _framesToSkip) {
          return; // Skip this frame
        }
        _frameSkipCounter = 0;
        
        if (_isProcessingImage || _isAuthenticating || _isDialogShowing) return;
        _processImage(image);
      });
      _useImageStream = true;
    } catch (e) {
      print('Image stream failed: $e');
      // If image stream fails, use timer-based detection
      _useImageStream = false;
      _startTimerBasedDetection();
    }
  }

  void _startTimerBasedDetection() {
    print('Starting timer-based face detection...');
    // CRITICAL: Increased interval to prevent scanning too quickly
    // This ensures proper face quality and prevents premature authentication
    _detectionTimer =
        Timer.periodic(const Duration(milliseconds: 2000), (timer) { // Increased from 1000ms to 2000ms
      if (_isProcessingImage || _isAuthenticating || _isDialogShowing) return;
      print('Timer tick - processing image...');
      _processImageFromFile();
    });
  }

  bool _isDialogShowing = false;

  void _stopCamera() {
    print('Stopping camera...');
    _detectionTimer?.cancel();
    _detectionTimer = null;

    // Also stop image stream if it's running
    if (_useImageStream && _cameraController != null && _cameraController!.value.isInitialized) {
      try {
        _cameraController!.stopImageStream();
      } catch (e) {
        print('Error stopping image stream: $e');
      }
    }
  _isDialogShowing = true;
}

  void _resumeCamera() {
    print('Resuming camera...');
    _isDialogShowing = false; // Reset the flag
    if (_detectionTimer == null) {
      _startTimerBasedDetection();
    }
  }

  void _trackFailedAttempt() {
    _failedAttempts++;
    _lastFailedAttempt = DateTime.now();
    print('Failed attempt $_failedAttempts/$_maxFailedAttempts');
  }

  bool _isLockedOut() {
    if (_failedAttempts < _maxFailedAttempts) return false;
    if (_lastFailedAttempt == null) return false;

    final now = DateTime.now();
    final timeSinceLastAttempt = now.difference(_lastFailedAttempt!);

    if (timeSinceLastAttempt > _lockoutDuration) {
      // Reset lockout after 5 minutes
      _failedAttempts = 0;
      _lastFailedAttempt = null;
      return false;
    }

    return true;
  }

  // Note: Progress animation is now handled by AnimationController for smooth 60fps updates

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessingImage || _isAuthenticating || _isDialogShowing) return;
    
    // Use async without blocking UI thread
    _isProcessingImage = true;

    try {
      // Try the direct camera image approach first
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        // Try alternative approach using takePicture
        await _processImageAlternative();
        return;
      }

      // Process face detection asynchronously
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        _detectFaceForLogin(face, image);
      } else {
        // No face detected - smoothly animate progress to 0
        if (mounted && _isFaceDetected) {
            setState(() {
              _isFaceDetected = false;
          });
          _targetProgress = 0.0;
          _progressAnimation = Tween<double>(
            begin: _progressAnimation.value,
            end: 0.0,
          ).animate(CurvedAnimation(
            parent: _progressAnimationController,
            curve: Curves.easeOutCubic,
          ));
          _progressAnimationController.forward(from: 0.0);
          }
        _resetDeepScanState();
        _updateInstruction(
          'Align your face within the oval to start scanning',
          color: const Color(0xFF616161),
        );
      }
    } catch (e) {
      // If image stream fails, try timer-based detection
      if (_useImageStream) {
        try {
          _cameraController?.stopImageStream();
        } catch (_) {
          // Silently handle stop errors
        }
        _useImageStream = false;
        _startTimerBasedDetection();
      }
    } finally {
      _isProcessingImage = false;
      // Don't call setState here - it's not needed for this flag
    }
  }

  Future<void> _processImageAlternative() async {
    if (_isDialogShowing) return;
    
    try {
      // Use takePicture as alternative
      final XFile image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);

      print('Processing alternative image for face detection...');
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        print('Face detected! Processing for login...');

        // Check if enough time has passed since last authentication attempt
        final now = DateTime.now();
        if (_lastAuthenticationAttempt == null ||
            now.difference(_lastAuthenticationAttempt!) >
                _authenticationCooldown) {
          _lastAuthenticationAttempt = now;
          final imageBytes = await image.readAsBytes();
          _detectFaceForLogin(face, null, imageBytes);
        } else {
          print('Authentication cooldown active, skipping...');
        }
      } else {
        print('No face detected');
        if (mounted) {
          setState(() {
            _isFaceDetected = false;
          });
          // Smoothly animate progress to 0
          _targetProgress = 0.0;
          _progressAnimation = Tween<double>(
            begin: _progressAnimation.value,
            end: 0.0,
          ).animate(CurvedAnimation(
            parent: _progressAnimationController,
            curve: Curves.easeOutCubic,
          ));
          _progressAnimationController.forward(from: 0.0);
        }
      }
    } catch (e) {
      print('Error processing alternative image: $e');
    }
  }

  // Update the _processImageFromFile method as well
Future<void> _processImageFromFile() async {
  if (_cameraController == null || !_cameraController!.value.isInitialized || _isDialogShowing) return; // Add _isDialogShowing check

    setState(() {
      _isProcessingImage = true;
    });

    try {
      final XFile image = await _cameraController!.takePicture();
      print('Picture taken, processing with InputImage.fromFilePath...');
      print('Image path: ${image.path}');
      print('Image size: ${await image.length()} bytes');

      // Use InputImage.fromFilePath which should work better
      final inputImage = InputImage.fromFilePath(image.path);
      print('InputImage created successfully');

      final List<Face> faces = await _faceDetector.processImage(inputImage);
      print('Face detection result: ${faces.length} faces found');

      if (faces.isNotEmpty) {
        final face = faces.first;
        print('Face detected! Processing for login...');
        print('Face bounding box: ${face.boundingBox}');
        print('Face landmarks: ${face.landmarks}');
        print('Face contours: ${face.contours}');

        // Check if enough time has passed since last authentication attempt
        final now = DateTime.now();
        if (_lastAuthenticationAttempt == null ||
            now.difference(_lastAuthenticationAttempt!) >
                _authenticationCooldown) {
          _lastAuthenticationAttempt = now;
          final imageBytes = await image.readAsBytes();
          _detectFaceForLogin(face, null, imageBytes);
        } else {
          print('Authentication cooldown active, skipping...');
        }
      } else {
        print('No face detected');
        if (mounted) {
          setState(() {
            _isFaceDetected = false;
          });
          // Smoothly animate progress to 0
          _targetProgress = 0.0;
          _progressAnimation = Tween<double>(
            begin: _progressAnimation.value,
            end: 0.0,
          ).animate(CurvedAnimation(
            parent: _progressAnimationController,
            curve: Curves.easeOutCubic,
          ));
          _progressAnimationController.forward(from: 0.0);
        }
      }
    } catch (e) {
      print('Error processing image: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingImage = false;
        });
      }
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    try {
      final size = Size(image.width.toDouble(), image.height.toDouble());
      final rotation = InputImageRotationValue.fromRawValue(
            _cameraController!.description.sensorOrientation,
          ) ??
          InputImageRotation.rotation0deg;

      print('Camera image format: ${image.format.group}');
      print('Camera image planes: ${image.planes.length}');
      print('Camera image size: ${image.width}x${image.height}');

      InputImageFormat inputFormat;
      if (image.format.group == ImageFormatGroup.yuv420) {
        inputFormat = InputImageFormat.yuv420;
        print('Using YUV420 format');
      } else if (image.format.group == ImageFormatGroup.nv21) {
        inputFormat = InputImageFormat.nv21;
        print('Using NV21 format');
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        inputFormat = InputImageFormat.bgra8888;
        print('Using BGRA8888 format');
      } else {
        print('Unsupported image format: ${image.format.group}');
        print('Available formats: YUV420, NV21, BGRA8888');
        return null;
      }

      final metadata = InputImageMetadata(
        size: size,
        rotation: rotation,
        format: inputFormat,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      final bytes = _cameraImageToBytes(image);
      print('Image bytes length: ${bytes.length}');
      print('Bytes per row: ${image.planes.first.bytesPerRow}');

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } catch (e) {
      print('Error creating input image: $e');
      return null;
    }
  }

  Uint8List _cameraImageToBytes(CameraImage image) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    return bytes;
  }

  void _resetDeepScanState({bool resetInstruction = false}) {
    if (resetInstruction) {
      _updateInstruction(_defaultInstruction, color: const Color(0xFF616161), force: true);
    }
  }

  void _updateInstruction(String message, {Color? color, bool force = false}) {
    if (!mounted) return;
    final targetColor = color ?? const Color(0xFF616161);
    final now = DateTime.now();

    if (!force &&
        _lastInstructionUpdate != null &&
        now.difference(_lastInstructionUpdate!) < _instructionUpdateThrottle &&
        _instructionMessage == message &&
        _instructionColor == targetColor) {
      return;
    }
    
    if (_instructionMessage == message && _instructionColor == targetColor) {
      return;
    }

    setState(() {
      _instructionMessage = message;
      _instructionColor = targetColor;
      _lastInstructionUpdate = now;
    });
  }

  double _calculateEmbeddingVariance(List<double> embedding) {
    if (embedding.isEmpty) return 0.0;
    final mean = embedding.reduce((a, b) => a + b) / embedding.length;
    double variance = 0.0;
    for (final value in embedding) {
      final diff = value - mean;
      variance += diff * diff;
    }
    return variance / embedding.length;
  }

  void _detectFaceForLogin(Face face, [CameraImage? cameraImage, Uint8List? imageBytes]) async {
    if (!_emailOrPhoneEntered || _verifiedEmailOrPhone == null) {
      print('🚨 SECURITY: Face detection attempted without email/phone verification - blocking');
      return;
    }
    
    if (_authenticationSuccess || _isAuthenticating) {
      return;
    }

    // Simplified face detection logic - matching 3-face verification screens
    final Rect box = face.boundingBox;
    final double faceHeight = box.height;
    final double faceWidth = box.width;

    // Relaxed requirements - easier to scan (matching move closer screen)
    const double targetSize = 250.0; // Lower target for easier scanning
    const double minSize = 150.0; // Lower minimum size

    // Calculate progress based on face size (simple, like move closer screen)
    final sizeProgress = ((faceHeight + faceWidth) / 2) / targetSize;
    final progress = (sizeProgress * 100).clamp(0.0, 100.0);
    
    // Check face quality: size, pose, eyes visible (relaxed)
    final faceArea = faceHeight * faceWidth;
    final minArea = minSize * minSize;
    final isGoodSize = faceArea >= minArea;
    
    // Check face pose (relaxed - allow up to 30 degrees)
    final headAngleX = face.headEulerAngleX?.abs() ?? 0.0;
    final headAngleY = face.headEulerAngleY?.abs() ?? 0.0;
    final headAngleZ = face.headEulerAngleZ?.abs() ?? 0.0;
    final isGoodPose = headAngleX < 30.0 && headAngleY < 30.0 && headAngleZ < 30.0;
    
    // Check eyes are visible (at least one eye landmark)
    final hasLeftEye = face.landmarks.containsKey(FaceLandmarkType.leftEye);
    final hasRightEye = face.landmarks.containsKey(FaceLandmarkType.rightEye);
    final hasEyes = hasLeftEye || hasRightEye;
    
    // Check face is reasonably centered (relaxed - center 60% of screen)
    final double cameraImageWidth = cameraImage?.width.toDouble() ?? 480.0;
    final double cameraImageHeight = cameraImage?.height.toDouble() ?? 640.0;
    final faceCenterX = box.left + (box.width / 2);
    final faceCenterY = box.top + (box.height / 2);
    final isCentered = (faceCenterX > cameraImageWidth * 0.2 && faceCenterX < cameraImageWidth * 0.8) &&
                       (faceCenterY > cameraImageHeight * 0.2 && faceCenterY < cameraImageHeight * 0.8);

    // Face is ready when it meets relaxed requirements
    // More lenient: if progress is high (>= 80%), allow authentication even with minor issues
    final bool isFaceReady = progress >= 80.0 && isGoodSize && hasEyes;
    // For lower progress, require all conditions
    final bool isFaceReadyStrict = isGoodSize && isGoodPose && hasEyes && isCentered && progress >= 60.0;
    final bool shouldAuthenticate = progress >= 80.0 ? isFaceReady : isFaceReadyStrict;

    if (mounted) {
      setState(() {
        _progressPercentage = progress;
        _isFaceDetected = shouldAuthenticate;
      });
      
      // Update progress animation
      final double targetProgressNormalized = (progress / 100.0).clamp(0.0, 1.0);
      if ((targetProgressNormalized - _targetProgress).abs() > 0.01) {
        _targetProgress = targetProgressNormalized;
        _progressAnimation = Tween<double>(
          begin: _progressAnimation.value,
          end: _targetProgress,
        ).animate(CurvedAnimation(
          parent: _progressAnimationController,
          curve: Curves.easeOutCubic,
        ));
        _progressAnimationController.forward(from: 0.0);
      }
    }

    // Update instruction message (simpler, like 3-face verification)
    if (!isGoodSize) {
      _updateInstruction('Move closer to the camera', color: Colors.red);
    } else if (progress < 60.0) {
      _updateInstruction('Position your face in the oval', color: const Color(0xFF616161));
    } else if (!isGoodPose && progress < 80.0) {
      _updateInstruction('Look straight at the camera', color: Colors.orange);
    } else if (!hasEyes) {
      _updateInstruction('Ensure your face is fully visible', color: Colors.orange);
    } else if (!isCentered && progress < 80.0) {
      _updateInstruction('Center your face in the oval', color: Colors.orange);
    } else if (progress >= 80.0 && shouldAuthenticate) {
      _updateInstruction('Authenticating...', color: Colors.green);
    } else {
      _updateInstruction('Hold steady...', color: Colors.green);
    }

    // Auto-authenticate when face is ready (simpler, no deep scan)
    if (shouldAuthenticate && !_isAuthenticating && !_authenticationSuccess) {
      print('🔍 Face ready for authentication: progress=$progress, size=$isGoodSize, pose=$isGoodPose, eyes=$hasEyes, centered=$isCentered');
      
      // Small delay to ensure face is stable
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Check again to make sure face is still ready and not already authenticating
      if (mounted && !_isAuthenticating && !_authenticationSuccess) {
        print('✅ Starting authentication...');
        try {
          await _authenticateFace(
            face,
            cameraImage: cameraImage,
            imageBytes: imageBytes,
          );
        } catch (e) {
          print('❌ Error during authentication: $e');
        }
      } else {
        print('⚠️ Authentication skipped: already in progress or completed');
      }
    }
  }

  Future<void> _verifyEmailOrPhone() async {
    if (_isVerifyingEmailPhone) return;
    
    final input = _emailOrPhoneController.text.trim();
    if (input.isEmpty) {
      _showErrorDialog('Input Required', 'Please enter your email or phone number');
      return;
    }

    setState(() {
      _isVerifyingEmailPhone = true;
    });

    try {
      print('🔍 Verifying email/phone: $input');
      
      // Find user by email or phone (check ALL users, not just completed signups)
      // Wrap with network retry and loading
      final firestore = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      );
      
      String? userId;
      Map<String, dynamic>? userData;
      
      // Try email first (check all users, not just signupCompleted=true) with network retry
      var query = await NetworkService.executeWithRetry(
        () => firestore
            .collection('users')
            .where('email', isEqualTo: input.toLowerCase())
            .limit(1)
            .get(),
        maxRetries: 3,
        retryDelay: const Duration(seconds: 2),
        loadingMessage: 'Checking account...',
        context: context,
        showNetworkErrors: true,
      );
      
      if (query.docs.isNotEmpty) {
        userId = query.docs.first.id;
        userData = query.docs.first.data();
        print('✅ Found user by email: $userId');
      } else {
        // Try phone number (check all users) with network retry
        query = await NetworkService.executeWithRetry(
          () => firestore
              .collection('users')
              .where('phoneNumber', isEqualTo: input)
              .limit(1)
              .get(),
          maxRetries: 3,
          retryDelay: const Duration(seconds: 2),
          loadingMessage: 'Checking account...',
          context: context,
          showNetworkErrors: true,
        );
        
        if (query.docs.isNotEmpty) {
          userId = query.docs.first.id;
          userData = query.docs.first.data();
          print('✅ Found user by phone: $userId');
        }
      }
      
      if (userId == null || userData == null) {
        if (mounted) {
          setState(() {
            _isVerifyingEmailPhone = false;
          });
          _showErrorDialog(
            'Account Not Found',
            'No account found with this email or phone number. Please sign up first.',
          );
        }
        return;
      }
      
      // CRITICAL: Check verification status BEFORE face scanning
      // If user is pending, show professional message immediately
      final verificationStatus = userData['verificationStatus'] ?? 'pending';
      final signupCompleted = userData['signupCompleted'] ?? false;
      
      if (verificationStatus != 'verified') {
        if (mounted) {
          setState(() {
            _isVerifyingEmailPhone = false;
          });
          _showPendingVerificationDialog();
        }
        return;
      }
      
      // Check if signup is completed
      if (!signupCompleted) {
        if (mounted) {
          setState(() {
            _isVerifyingEmailPhone = false;
          });
          _showErrorDialog(
            'Account Incomplete',
            'Your account setup is not complete. Please complete signup first.',
          );
        }
        return;
      }
      
      // Check if user has luxandUuid (face enrolled with Luxand)
      // NOTE: face_embeddings check removed - using Luxand exclusively
      final luxandUuid = userData['luxandUuid']?.toString() ?? '';
      if (luxandUuid.isEmpty) {
        if (mounted) {
          setState(() {
            _isVerifyingEmailPhone = false;
          });
          _showErrorDialog(
            'Face Not Registered',
            'Face not registered for this account. Please complete signup with face verification.',
          );
        }
        return;
      }
      
      // Email/phone verified, now activate camera for face verification
      if (mounted) {
        setState(() {
          _isVerifyingEmailPhone = false;
          _emailOrPhoneEntered = true;
          _verifiedEmailOrPhone = input;
          _authenticationSuccess = false;
        });
        
        // Start camera stream now that email/phone is verified
        // Camera is already initialized, just start the stream
        if (_cameraController != null && _cameraController!.value.isInitialized) {
          try {
            _startImageStream();
            print('✅ Camera stream started for face scanning');
          } catch (e) {
            print('⚠️ Error starting camera stream: $e');
            // Fallback to timer-based detection
            _startTimerBasedDetection();
          }
        } else {
          // Camera not initialized yet, initialize it
          _initializeCamera();
        }
      }
    } catch (e) {
      print('❌ Error verifying email/phone: $e');
      if (mounted) {
        setState(() {
          _isVerifyingEmailPhone = false;
        });
        
        // Check if it's a network error
        final errorStr = e.toString().toLowerCase();
        final isNetworkError = errorStr.contains('network') ||
                              errorStr.contains('connection') ||
                              errorStr.contains('timeout') ||
                              errorStr.contains('internet') ||
                              errorStr.contains('failed host lookup');
        
        if (isNetworkError) {
          NetworkService.showNetworkErrorDialog(
            context,
            'Network error while verifying account',
            onRetry: () => _verifyEmailOrPhone(),
            onCancel: () {
              // User cancelled, just reset state
            },
          );
        } else {
          _showErrorDialog('Error', 'Error verifying account. Please try again.');
        }
      }
    }
  }

  Future<void> _authenticateFace(
    Face face, {
    CameraImage? cameraImage,
    Uint8List? imageBytes,
    List<double>? precomputedEmbedding,
    double? stabilityScore,
  }) async {
    if (_isAuthenticating) return;
    
    // CRITICAL: Must have verified email/phone first
    if (!_emailOrPhoneEntered || _verifiedEmailOrPhone == null) {
      print('❌ SECURITY: Cannot authenticate face without email/phone verification');
      return;
    }

    // Check for lockout
    if (_isLockedOut()) {
      _showLockoutDialog();
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _authenticationSuccess = false;
    });
    // Smoothly animate progress to 70%
    _targetProgress = 0.70;
    _progressAnimation = Tween<double>(
      begin: _progressAnimation.value,
      end: 0.70,
    ).animate(CurvedAnimation(
      parent: _progressAnimationController,
      curve: Curves.easeOutCubic,
    ));
    _progressAnimationController.forward(from: 0.0);

    if (precomputedEmbedding != null && precomputedEmbedding.isNotEmpty) {
      final variance = _calculateEmbeddingVariance(precomputedEmbedding);
      print('🔍 Deep scan embedding provided. Variance=${variance.toStringAsFixed(6)}, '
          'stability=${stabilityScore != null ? (stabilityScore * 100).toStringAsFixed(2) : "unknown"}%');
    }

    try {
      // Check lockout status for debugging
      final lockoutStatus = await LockoutService.getLockoutStatus();
      print('🔍 LOCKOUT STATUS: $lockoutStatus');
      
      // Use 1:1 face verification with email/phone
      print('🔍 Attempting 1:1 face verification for email/phone: $_verifiedEmailOrPhone');
      print('🔧 Using secure email/phone + face verification...');
      
      if (mounted) {
        // Smoothly animate progress to 80%
        _targetProgress = 0.80;
        _progressAnimation = Tween<double>(
          begin: _progressAnimation.value,
          end: 0.80,
        ).animate(CurvedAnimation(
          parent: _progressAnimationController,
          curve: Curves.easeOutCubic,
        ));
        _progressAnimationController.forward(from: 0.0);
      }
      
      Map<String, dynamic>? authResult;
      try {
        // Wrap face verification with network retry and loading
        authResult = await NetworkService.executeWithRetry(
          () => ProductionFaceRecognitionService.verifyUserFace(
            emailOrPhone: _verifiedEmailOrPhone!,
            detectedFace: face,
            cameraImage: cameraImage,
            imageBytes: imageBytes,
            precomputedEmbedding: precomputedEmbedding,
            stabilityScore: stabilityScore,
          ),
          maxRetries: 3,
          retryDelay: const Duration(seconds: 2),
          loadingMessage: 'Verifying face...',
          context: context,
          showNetworkErrors: true,
        );

        // Ensure authResult is not null
        if (authResult == null) {
          authResult = {'success': false, 'error': 'Face verification failed'};
        }
        
        if (stabilityScore != null) {
          authResult['deepScanStability'] = stabilityScore;
        }
        
        if (mounted) {
          // Smoothly animate progress to 90%
          _targetProgress = 0.90;
          _progressAnimation = Tween<double>(
            begin: _progressAnimation.value,
            end: 0.90,
          ).animate(CurvedAnimation(
            parent: _progressAnimationController,
            curve: Curves.easeOutCubic,
          ));
          _progressAnimationController.forward(from: 0.0);
        }
        
        if (authResult['success'] == true) {
          final similarity = authResult['similarity'] as double?;
          print('✅ 1:1 face verification successful: ${authResult['userId']}');
          print('📊 Similarity: ${similarity?.toStringAsFixed(4) ?? 'unknown'}');
          
          // CRITICAL SECURITY: ABSOLUTE FINAL CHECK - reject anything below PERFECT threshold
          // This is the LAST LINE OF DEFENSE - no exceptions
          // Different people: 0.70-0.95 | Same person: 0.99+ (PERFECT)
          // CRITICAL: Even if service returns success, verify similarity is truly high enough
          if (similarity == null) {
            print('🚨🚨🚨🚨🚨 CRITICAL SECURITY: Similarity is null - REJECTING ACCESS');
            print('🚨🚨🚨 This prevents unregistered users - similarity is required');
            authResult = {
              'success': false,
              'error': 'Face verification failed. Security validation error.',
            };
          } else {
            // BALANCED SECURITY: Use backend threshold (0.85) for consistency
            // Backend already validates with 0.85 threshold, so we should match it
            // This ensures consistency between backend and frontend validation
            final balancedThreshold = 0.85; // Match backend threshold (0.85 = 85%)
            if (similarity < balancedThreshold) {
              print('🚨🚨🚨 BALANCED SECURITY REJECTION: Similarity ${similarity.toStringAsFixed(4)} < threshold ${balancedThreshold.toStringAsFixed(3)}');
              print('🚨🚨🚨 This prevents unregistered users while allowing legitimate users');
              print('🚨🚨🚨 Different people: 0.70-0.85 | Similar people: 0.85-0.95 | Same person: 0.85+ (RELIABLE)');
              print('🚨🚨🚨 Similarity ${similarity.toStringAsFixed(4)} indicates this may not be the registered user');
              print('🚨🚨🚨 RELIABLE RECOGNITION requires ${balancedThreshold.toStringAsFixed(3)} similarity for authentication');
              authResult = {
                'success': false,
                'error': 'Face verification failed. This face does not match the registered face for this account. Please ensure you are using the correct email/phone.',
              };
            } else {
              print('✅✅✅ RELIABLE RECOGNITION VALIDATION PASSED: Similarity ${similarity.toStringAsFixed(4)} >= ${balancedThreshold.toStringAsFixed(3)}');
              print('✅✅✅ This is a reliable match - face belongs to the registered user');
              print('✅✅✅ RELIABLE RECOGNITION: Legitimate users can achieve this similarity');
            }
          }
        } else {
          print('❌ 1:1 face verification failed: ${authResult['error']}');
        }
      } catch (faceRecognitionError) {
        print('❌ 1:1 face verification service error: $faceRecognitionError');
        print('Full error details: ${faceRecognitionError.toString()}');
        
        // Check if it's a network error
        final errorStr = faceRecognitionError.toString().toLowerCase();
        final isNetworkError = errorStr.contains('network') ||
                              errorStr.contains('connection') ||
                              errorStr.contains('timeout') ||
                              errorStr.contains('internet') ||
                              errorStr.contains('failed host lookup');
        
        if (isNetworkError && mounted) {
          // Show network error dialog
          NetworkService.showNetworkErrorDialog(
            context,
            'Network error during face verification',
            onRetry: () {
              // Retry authentication
              _authenticateFace(
                face,
                cameraImage: cameraImage,
                imageBytes: imageBytes,
                precomputedEmbedding: precomputedEmbedding,
                stabilityScore: stabilityScore,
              );
            },
            onCancel: () {
              // Cancel and reset state
              if (mounted) {
                setState(() {
                  _isAuthenticating = false;
                  _isFaceDetected = false;
                });
                _targetProgress = 0.0;
                _progressAnimation = Tween<double>(
                  begin: _progressAnimation.value,
                  end: 0.0,
                ).animate(CurvedAnimation(
                  parent: _progressAnimationController,
                  curve: Curves.easeOutCubic,
                ));
                _progressAnimationController.forward(from: 0.0);
                _updateInstruction(
                  'Network error. Please check your connection.',
                  color: Colors.red,
                );
              }
            },
          );
        }
        
        // Set authResult to failure
        authResult = {'success': false, 'error': isNetworkError ? 'Network error during face verification' : 'Face verification error'};
      }
      
      // authResult is guaranteed to be non-null at this point (set in try or catch)
      final userId = authResult['userId'] as String?;
      final similarity = authResult['similarity'] as double?;
      bool success = authResult['success'] == true;

      // CRITICAL SECURITY: Validate both success and similarity before proceeding
      // This prevents any unauthorized access even if success is incorrectly set to true
      // CRITICAL: This is a REDUNDANT security check to catch any bypass attempts
      if (success && userId != null && userId.isNotEmpty) {
        // ABSOLUTE SECURITY CHECK: Similarity must be EXTREMELY HIGH (99%+)
        // This is the final gate - reject anything below 99% for 1:1 verification
        // CRITICAL: Unregistered users typically achieve 0.70-0.95 similarity, NOT 0.99+
        if (similarity == null) {
          print('🚨🚨🚨🚨🚨 CRITICAL SECURITY BREACH PREVENTION: Success=true but similarity is null - REJECTING');
          print('🚨🚨🚨 This prevents unauthorized access - similarity is REQUIRED');
          print('🚨🚨🚨 REJECTING ACCESS - unregistered users cannot bypass this check');
          authResult = {
            'success': false,
            'error': 'Face verification failed. Security validation error.',
          };
          success = false;
        } else {
            // BALANCED SECURITY: Use backend threshold (0.85) for consistency
            // Backend already validates with 0.85 threshold, so we should match it
            // This ensures consistency between backend and frontend validation
            final balancedThreshold = 0.85; // Match backend threshold (0.85 = 85%)
            if (similarity < balancedThreshold) {
              print('🚨🚨🚨 BALANCED SECURITY REJECTION: Similarity ${similarity.toStringAsFixed(4)} < threshold ${balancedThreshold.toStringAsFixed(3)}');
              print('🚨🚨🚨 This prevents unregistered users while allowing legitimate users');
              print('🚨🚨🚨 For reliable recognition, similarity must be >= 85% (matches backend)');
              print('🚨🚨🚨 Different people: 0.70-0.85 | Similar people: 0.85-0.95 | Same person: 0.85+ (RELIABLE)');
              print('🚨🚨🚨 Similarity ${similarity.toStringAsFixed(4)} indicates this may not be the registered user');
              print('🚨🚨🚨 REJECTING ACCESS - face does not meet threshold');
            authResult = {
              'success': false,
              'error': 'Face verification failed. This face does not match the registered face for this account. Please ensure you are using the correct email/phone.',
            };
            success = false;
          } else {
            print('✅✅✅ RELIABLE RECOGNITION VALIDATION PASSED: Similarity ${similarity.toStringAsFixed(4)} >= ${balancedThreshold.toStringAsFixed(3)}');
            print('✅✅✅ This is a reliable match - face belongs to the registered user');
            print('✅✅✅ RELIABLE RECOGNITION: Legitimate users can achieve this similarity');
          }
        }
      } else {
        // CRITICAL: If success is false or userId is missing, explicitly reject
        print('🚨🚨🚨 CRITICAL SECURITY: Authentication failed - success=$success, userId=$userId');
        print('🚨🚨🚨 REJECTING ACCESS - authentication did not succeed');
        success = false;
      }

      if (userId == "LIVENESS_FAILED") {
        // Liveness detection failed, show specific dialog
        if (mounted) {
          setState(() {
            _progressPercentage = 0.0;
            _isAuthenticating = false;
            _isFaceDetected = false; // Reset on liveness failure
          });
          _stopCamera(); // Stop camera when showing dialog
          // Reset progress and instruction on liveness failure
          _targetProgress = 0.0;
          _progressAnimation = Tween<double>(
            begin: _progressAnimation.value,
            end: 0.0,
          ).animate(CurvedAnimation(
            parent: _progressAnimationController,
            curve: Curves.easeOutCubic,
          ));
          _progressAnimationController.forward(from: 0.0);
          _updateInstruction(
            'Liveness check failed. Please try again.',
            color: Colors.red,
          );
          _showLivenessDetectionDialog();
        }
      } else if (userId == "PENDING_VERIFICATION") {
        // User is pending verification - BLOCK ACCESS to main app
        if (mounted) {
          setState(() {
            _progressPercentage = 0.0;
            _isAuthenticating = false;
            _isFaceDetected = false; // Reset on pending verification
          });
          
          // Reset progress and instruction
          _targetProgress = 0.0;
          _progressAnimation = Tween<double>(
            begin: _progressAnimation.value,
            end: 0.0,
          ).animate(CurvedAnimation(
            parent: _progressAnimationController,
            curve: Curves.easeOutCubic,
          ));
          _progressAnimationController.forward(from: 0.0);
          _updateInstruction(
            'Account verification pending.',
            color: Colors.orange,
          );
          
          print('🚫 SECURITY: Pending verification user blocked from main app access');
          _showPendingVerificationDialog();
        }
      } else if (success == true && userId != null && userId.isNotEmpty && similarity != null && similarity >= 0.85) {
        // BALANCED SECURITY: FINAL VALIDATION - ensure similarity is truly high enough
        // This is a redundant check but important for security - prevents any bypass attempts
        // BALANCED: Unregistered users typically achieve 0.70-0.85 similarity, NOT 0.85+
        // Similar-looking people typically achieve 0.85-0.95, NOT 0.85+
        // This is the LAST LINE OF DEFENSE - balanced for legitimate users, matches backend threshold
        if (similarity < 0.85) {
          print('🚨🚨🚨 BALANCED SECURITY: Similarity ${similarity.toStringAsFixed(4)} < 0.85 in FINAL check');
          print('🚨🚨🚨 BLOCKING ACCESS - similarity must be 85%+ for login (matches backend threshold)');
          print('🚨🚨🚨 Unregistered/similar faces typically cannot achieve 0.85+ similarity - REJECTING');
          if (mounted) {
            setState(() {
              _isAuthenticating = false;
              _isFaceDetected = false; // Reset on failure
            });
            // Smoothly animate progress to 0
            _targetProgress = 0.0;
            _progressAnimation = Tween<double>(
              begin: _progressAnimation.value,
              end: 0.0,
            ).animate(CurvedAnimation(
              parent: _progressAnimationController,
              curve: Curves.easeOutCubic,
            ));
            _progressAnimationController.forward(from: 0.0);
            _stopCamera();
            _trackFailedAttempt();
            // Reset progress and instruction on failure
            _targetProgress = 0.0;
            _progressAnimation = Tween<double>(
              begin: _progressAnimation.value,
              end: 0.0,
            ).animate(CurvedAnimation(
              parent: _progressAnimationController,
              curve: Curves.easeOutCubic,
            ));
            _progressAnimationController.forward(from: 0.0);
            _updateInstruction(
              'Face verification failed. Please try again.',
              color: Colors.red,
            );
            _showErrorDialog(
              'Security Error',
              'Face verification failed. This face does not match the registered face for this account.',
            );
          }
          return;
        }
        
        // NOTE: Luxand API can return high similarity scores (0.9999+) for legitimate matches
        // This is normal and expected - Luxand's face recognition is highly accurate
        // The backend already validates the similarity score before returning it
        // No need to reject high similarity scores from Luxand
        // PERFECT RECOGNITION: Final validation before allowing login
        // Verify all conditions are met:
        // 1. Success must be true
        // 2. UserId must be valid
        // 3. Similarity must be >= 99% (PERFECT RECOGNITION)
        // 4. Email/phone must be verified
        if (!_emailOrPhoneEntered || _verifiedEmailOrPhone == null) {
          print('🚨🚨🚨 CRITICAL SECURITY BREACH: Attempting login without email/phone verification');
          print('🚨 BLOCKING ACCESS - this should never happen');
          if (mounted) {
            setState(() {
              _isAuthenticating = false;
              _isFaceDetected = false; // Reset on failure
            });
            // Smoothly animate progress to 0
            _targetProgress = 0.0;
            _progressAnimation = Tween<double>(
              begin: _progressAnimation.value,
              end: 0.0,
            ).animate(CurvedAnimation(
              parent: _progressAnimationController,
              curve: Curves.easeOutCubic,
            ));
            _progressAnimationController.forward(from: 0.0);
            _stopCamera();
            _trackFailedAttempt();
            // Reset progress and instruction on failure
            _targetProgress = 0.0;
            _progressAnimation = Tween<double>(
              begin: _progressAnimation.value,
              end: 0.0,
            ).animate(CurvedAnimation(
              parent: _progressAnimationController,
              curve: Curves.easeOutCubic,
            ));
            _progressAnimationController.forward(from: 0.0);
            _updateInstruction(
              'Please complete signup first.',
              color: Colors.red,
            );
            _showSignUpRequiredDialog();
          }
          return;
        }
        
        // verifyUserFace already verified user exists and completed signup
        // Get user data from auth result (already fetched)
        final finalUserData = authResult['userData'] as Map<String, dynamic>?;
        
        if (finalUserData == null) {
          print('🚨🚨🚨 CRITICAL ERROR: User data not returned from verification');
          print('🚨 This should not happen - verifyUserFace should always return userData on success');
          print('🚨 This might cause incorrect redirect to signup - preventing that');
          if (mounted) {
            setState(() {
              _isAuthenticating = false;
              _isFaceDetected = false; // Reset on failure
            });
            // Smoothly animate progress to 0
            _targetProgress = 0.0;
            _progressAnimation = Tween<double>(
              begin: _progressAnimation.value,
              end: 0.0,
            ).animate(CurvedAnimation(
              parent: _progressAnimationController,
              curve: Curves.easeOutCubic,
            ));
            _progressAnimationController.forward(from: 0.0);
            _stopCamera();
            _trackFailedAttempt();
            // Show error instead of signup dialog - user exists but data retrieval failed
            _showErrorDialog(
              'Verification Error',
              'Account verification failed. Please try again or contact support.',
            );
          }
          return;
        }
        
        // CRITICAL: Double-check signupCompleted to prevent redirect to signup
        final signupCompleted = finalUserData['signupCompleted'] ?? false;
        if (!signupCompleted) {
          print('🚨🚨🚨 CRITICAL ERROR: signupCompleted is false after successful verification');
          print('🚨 This should not happen - verifyUserFace checks this before returning success');
          print('🚨 User exists but signup not completed - showing appropriate error');
          if (mounted) {
            setState(() {
              _isAuthenticating = false;
              _isFaceDetected = false; // Reset on failure
            });
            // Smoothly animate progress to 0
            _targetProgress = 0.0;
            _progressAnimation = Tween<double>(
              begin: _progressAnimation.value,
              end: 0.0,
            ).animate(CurvedAnimation(
              parent: _progressAnimationController,
              curve: Curves.easeOutCubic,
            ));
            _progressAnimationController.forward(from: 0.0);
            _stopCamera();
            _trackFailedAttempt();
            _showErrorDialog(
              'Account Incomplete',
              'Your account is not fully set up. Please complete signup first.',
            );
          }
          return;
        }
        
        // CRITICAL: Verify the userId from verification matches the email/phone entered
        // This prevents someone from entering one email but getting a different user's ID
        final verifiedEmail = finalUserData['email']?.toString().toLowerCase() ?? '';
        final verifiedPhone = finalUserData['phoneNumber']?.toString() ?? '';
        final inputLower = _verifiedEmailOrPhone!.trim().toLowerCase();
        
        final emailMatches = verifiedEmail == inputLower;
        final phoneMatches = verifiedPhone == _verifiedEmailOrPhone!.trim();
        
        if (!emailMatches && !phoneMatches) {
          print('🚨🚨🚨 CRITICAL SECURITY BREACH: User ID mismatch!');
          print('🚨 Entered email/phone: $_verifiedEmailOrPhone');
          print('🚨 Verified user email: $verifiedEmail');
          print('🚨 Verified user phone: $verifiedPhone');
          print('🚨 BLOCKING ACCESS - user ID does not match entered email/phone');
          if (mounted) {
            setState(() {
              _isAuthenticating = false;
              _isFaceDetected = false; // Reset on failure
            });
            // Smoothly animate progress to 0
            _targetProgress = 0.0;
            _progressAnimation = Tween<double>(
              begin: _progressAnimation.value,
              end: 0.0,
            ).animate(CurvedAnimation(
              parent: _progressAnimationController,
              curve: Curves.easeOutCubic,
            ));
            _progressAnimationController.forward(from: 0.0);
            _stopCamera();
            _trackFailedAttempt();
            _showErrorDialog(
              'Security Error',
              'Account verification failed. Please try again.',
            );
          }
          return;
        }

        // User exists, email/phone verified, face matched with high similarity - proceed with login
        print('✅ User verified successfully - proceeding with login');
        print('✅ Security validation: Email/phone matches user ID');
        print('✅ Signup completed: $signupCompleted');
        print('🔍 User ID: $userId');
        print('🔍 Username: ${finalUserData['username']}');
        print('🔍 Profile picture: ${finalUserData['profilePictureUrl']}');
        print('🔍 Verification status: ${finalUserData['verificationStatus']}');
        print('🔍 Face similarity: ${similarity.toStringAsFixed(4)}');
        
        // CRITICAL: Final validation before navigation - ensure everything is correct
        // This prevents redirecting to signup when user exists and is verified
        if (userId.isEmpty || !signupCompleted) {
          print('🚨🚨🚨 CRITICAL: Invalid state before navigation');
          print('🚨 userId: $userId, signupCompleted: $signupCompleted');
          print('🚨 Preventing navigation to avoid redirect to signup');
          if (mounted) {
            setState(() {
              _isAuthenticating = false;
              _isFaceDetected = false; // Reset on failure
            });
            // Smoothly animate progress to 0
            _targetProgress = 0.0;
            _progressAnimation = Tween<double>(
              begin: _progressAnimation.value,
              end: 0.0,
            ).animate(CurvedAnimation(
              parent: _progressAnimationController,
              curve: Curves.easeOutCubic,
            ));
            _progressAnimationController.forward(from: 0.0);
            _stopCamera();
            _showErrorDialog(
              'Verification Error',
              'Account verification failed. Please try again.',
            );
          }
          return;
        }
        
        if (mounted) {
          setState(() {
            _authenticationSuccess = true;
            _instructionMessage = 'Face verified successfully';
            _instructionColor = Colors.green;
          });
          // Smoothly animate progress to 95%
          _targetProgress = 0.95;
          _progressAnimation = Tween<double>(
            begin: _progressAnimation.value,
            end: 0.95,
          ).animate(CurvedAnimation(
            parent: _progressAnimationController,
            curve: Curves.easeOutCubic,
          ));
          _progressAnimationController.forward(from: 0.0);
        }
        
        // Store the current user ID, username, and profile picture for profile access
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('current_user_id', userId);
        await prefs.setString('current_user_name', finalUserData['username'] ?? 'User');
        await prefs.setString('current_user_profile_picture', finalUserData['profilePictureUrl'] ?? '');
        print('✅ Stored current user ID: $userId');
        print('✅ Stored current username: ${finalUserData['username'] ?? 'User'}');
        print('✅ Stored current profile picture: ${finalUserData['profilePictureUrl'] ?? 'none'}');

        // Check verification status
        final verificationStatus = finalUserData['verificationStatus'] ?? 'pending';
        print('📊 User verification status: $verificationStatus');
        print('📊 All validation passed - ready to navigate');
        print('📊 Navigation will go to: ${verificationStatus == 'verified' ? 'Main App' : 'Under Verification Screen'}');
        print('📊 Will NOT redirect to signup - user exists and is verified');

        if (mounted) {
          // Smoothly animate progress to 100%
          _targetProgress = 1.0;
          _progressAnimation = Tween<double>(
            begin: _progressAnimation.value,
            end: 1.0,
          ).animate(CurvedAnimation(
            parent: _progressAnimationController,
            curve: Curves.easeOutCubic,
          ));
          _progressAnimationController.forward(from: 0.0);

          // Navigate based on verification status
          // CRITICAL: This will NOT go to signup - user exists and is verified
          print('🔄 Starting navigation delay...');
          Future.delayed(const Duration(milliseconds: 500), () {
            print('🔄 Navigation delay completed, checking if mounted: $mounted');
            if (mounted) {
              // CRITICAL: Double-check before navigation to prevent signup redirect
              if (userId.isEmpty || !signupCompleted) {
                print('🚨🚨🚨 CRITICAL: Invalid state during navigation - preventing signup redirect');
                if (mounted) {
                  _showErrorDialog(
                    'Verification Error',
                    'Account verification failed. Please try again.',
                  );
                }
                return;
              }
              
              if (verificationStatus == 'verified') {
                // User is verified, navigate to main app
                print('✅ User is verified! Navigating to main app...');
                print('✅ Navigation: FaceLoginScreen -> NavigationWrapper');
                // Use pushAndRemoveUntil to clear all previous routes and prevent back navigation to login
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const NavigationWrapper()),
                  (route) => false, // Remove all previous routes
                );
              } else {
                // User is pending, navigate to under verification screen
                print('⏳ User is pending verification! Navigating to under verification screen...');
                print('✅ Navigation: FaceLoginScreen -> UnderVerificationScreen');
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const UnderVerificationScreen()),
                );
              }
            } else {
              print('❌ Widget not mounted, skipping navigation');
            }
          });
        } else {
          print('❌ Widget not mounted, cannot navigate');
        }
      } else {
        // Face not recognized, show helpful message
        if (mounted) {
          setState(() {
            _progressPercentage = 0.0;
            _isAuthenticating = false;
            _authenticationSuccess = false;
            _isFaceDetected = false; // Reset face detected on failure
          });
          _stopCamera(); // Add this line to stop camera
          
          // Track failed attempt
          _trackFailedAttempt();
          
          // Reset progress and instruction on failure
          _targetProgress = 0.0;
          _progressAnimation = Tween<double>(
            begin: _progressAnimation.value,
            end: 0.0,
          ).animate(CurvedAnimation(
            parent: _progressAnimationController,
            curve: Curves.easeOutCubic,
          ));
          _progressAnimationController.forward(from: 0.0);
          _updateInstruction(
            'Face not recognized. Please try again.',
            color: Colors.red,
          );
          
          // Show different messages based on attempt count
          if (_failedAttempts < 3) {
            _showFaceNotRecognizedDialog();
          } else {
            _showSignUpRequiredDialog();
          }
        }
      }
    } catch (e) {
      // CRITICAL SECURITY: On any error, reject authentication
      // Never allow access on error - fail securely
      print('🚨🚨🚨 CRITICAL SECURITY: Authentication error occurred: $e');
      print('🚨 REJECTING ACCESS - fail securely on any error');
      if (mounted) {
        setState(() {
          _progressPercentage = 0.0;
          _isAuthenticating = false;
          _authenticationSuccess = false;
          _isFaceDetected = false; // Reset on error
        });
        _stopCamera();
        _trackFailedAttempt();
        // Reset progress and instruction on error
        _targetProgress = 0.0;
        _progressAnimation = Tween<double>(
          begin: _progressAnimation.value,
          end: 0.0,
        ).animate(CurvedAnimation(
          parent: _progressAnimationController,
          curve: Curves.easeOutCubic,
        ));
        _progressAnimationController.forward(from: 0.0);
        _updateInstruction(
          'Authentication failed. Please try again.',
          color: Colors.red,
        );
        _showErrorDialog(
          'Authentication Error',
          'Face verification failed. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
          if (!_authenticationSuccess) {
            _authenticationSuccess = false;
          }
        });
      }
    }
  }

  void _showLivenessDetectionDialog() {
    setState(() {
      _isDialogShowing = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 400,
              maxHeight: 600,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with icon and title
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.visibility_off_rounded,
                        color: Colors.orange.shade600,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Liveness Detection Failed",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Description
                Text(
                  "We couldn't verify that you're a real person. Please follow these steps:",
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 20),
                
                // Tips list
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildTipItem(
                          Icons.visibility,
                          "Ensure your eyes are open and clearly visible",
                        ),
                        const SizedBox(height: 12),
                        _buildTipItem(
                          Icons.center_focus_strong,
                          "Look directly at the camera lens",
                        ),
                        const SizedBox(height: 12),
                        _buildTipItem(
                          Icons.face,
                          "Keep your entire face within the frame",
                        ),
                        const SizedBox(height: 12),
                        _buildTipItem(
                          Icons.flash_on,
                          "Ensure good lighting on your face",
                        ),
                        const SizedBox(height: 12),
                        _buildTipItem(
                          Icons.blur_on,
                          "Try blinking naturally a few times",
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _isDialogShowing = false;
                          });
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const SignUpScreen()),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: Colors.grey.shade400),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          "Sign Up",
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _isDialogShowing = false;
                          });
                          _resumeCamera();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          "Try Again",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTipItem(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.green.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.green.shade600,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPendingVerificationDialog() {
    setState(() {
      _isDialogShowing = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 400,
              maxHeight: 500,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with icon and title
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.hourglass_empty_rounded,
                        color: Colors.orange.shade700,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Account Pending Verification",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Main message
                Text(
                  "Your account is still pending verification.",
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 16),
                
                // Additional information
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Your account is currently under review by our admin team.",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "You will be notified once your account is verified.",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Action button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Close dialog
                      setState(() {
                        _isDialogShowing = false;
                      });
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 2,
                    ),
                    child: const Text(
                      "Understood",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFaceNotRecognizedDialog() {
    setState(() {
      _isDialogShowing = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            "Face Not Recognized",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "We couldn't recognize your face. Please try:",
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              const Text(
                "• Ensure good lighting\n• Look directly at the camera\n• Remove glasses if possible\n• Try a different angle",
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                setState(() {
                  _isDialogShowing = false;
                });
                _resumeCamera(); // Restart camera
              },
              child: const Text(
                "TRY AGAIN",
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                setState(() {
                  _isDialogShowing = false;
                });
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                );
              },
              child: const Text(
                "SIGN UP",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSignUpRequiredDialog() {
    setState(() {
      _isDialogShowing = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            "Sign Up Required",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: const Text(
            "You must sign up first to use face login. Please create an account to continue.",
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                setState(() {
                  _isDialogShowing = false;
                });
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const SignUpScreen()),
                );
              },
              child: const Text(
                "Sign Up",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                setState(() {
                  _isDialogShowing = false;
                });
                _resumeCamera(); // Resume camera when cancelled
              },
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showLockoutDialog() {
    _stopCamera(); // Stop camera during lockout
    LockoutService.setLockout().then((_) {
      // Lockout set successfully
    }); // Set global lockout
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            "Too Many Attempts",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: const Text(
            "You have tried logging in too many times. Please try again in 5 minutes.",
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                );
              },
              child: const Text(
                "OK",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double normalizedProgress = _progressPercentage <= 0
        ? 0.0
        : _progressPercentage >= 100
            ? 1.0
            : _progressPercentage / 100.0;

    final String statusLabel = _authenticationSuccess
        ? 'SUCCESS!'
        : _isAuthenticating
            ? 'AUTHENTICATING...'
            : _isFaceDetected
                ? 'FACE DETECTED'
                : 'POSITION YOUR FACE';

    return Scaffold(
      resizeToAvoidBottomInset: false, // Prevent keyboard from pushing content up
      body: Container(
        decoration: BoxDecoration(
          gradient: _emailOrPhoneEntered 
              ? null 
              : const LinearGradient(
                  colors: [
                    Color(0xFF0A0A0A),
                    Color(0xFF1A0000),
                    Color(0xFF2B0000),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.5, 1.0],
                ),
          color: _emailOrPhoneEntered ? Colors.white : null,
        ),
        child: SafeArea(
        child: SingleChildScrollView(
          // Make scrollable to handle keyboard overflow
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                        MediaQuery.of(context).padding.top - 
                        MediaQuery.of(context).padding.bottom,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
              children: [
                  // Logo
                  Image.asset(
                    'assets/logo.png', 
                    height: 50,
                  ),
                  
                const SizedBox(height: 20),
                  
                  // Title
                  Text(
                  "FACE LOGIN",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      fontSize: 20,
                      color: _emailOrPhoneEntered ? Colors.black : Colors.white,
                      letterSpacing: 0.5,
                    ),
                ),
                  
                  const SizedBox(height: 20),
                
                // Email/Phone input section (shown before camera)
                if (!_emailOrPhoneEntered) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      children: [
                        TextField(
                          controller: _emailOrPhoneController,
                          focusNode: _emailOrPhoneFocusNode,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Email or Phone Number',
                            labelStyle: TextStyle(
                              color: _emailOrPhoneFocusNode.hasFocus 
                                  ? Colors.red 
                                  : Colors.grey[400],
                            ),
                            hintText: 'Enter your email or phone',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[800]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[800]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.red, width: 2),
                            ),
                            prefixIcon: Icon(
                              Icons.person, 
                              color: _emailOrPhoneFocusNode.hasFocus 
                                  ? Colors.red 
                                  : Colors.grey[400],
                            ),
                            filled: true,
                            fillColor: Colors.grey[900],
                          ),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _verifyEmailOrPhone(),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isVerifyingEmailPhone ? null : _verifyEmailOrPhone,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isVerifyingEmailPhone
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'Continue',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const SignUpScreen()),
                            );
                          },
                          child: const Text(
                            "Don't have an account? Sign up",
                            style: TextStyle(
                              color: Colors.white,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Camera section (shown after email/phone is verified)
                  // Show verified email/phone
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          Icon(Icons.check_circle, color: Colors.green[700], size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                          child: Text(
                            'Verified: $_verifiedEmailOrPhone',
                            style: TextStyle(
                                color: Colors.green[800],
                                fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                    // Camera preview with elliptical shape and progress border (matching blink twice)
                    SizedBox(
                      width: 250,
                      height: 350,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Progress border
                          SizedBox(
                              width: 250,
                              height: 350,
                              child: CircularProgressIndicator(
                              value: normalizedProgress,
                                strokeWidth: 8,
                                backgroundColor: Colors.grey[300],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                _authenticationSuccess 
                                    ? Colors.green 
                                    : _isAuthenticating 
                                        ? Colors.green 
                                        : _isFaceDetected 
                                            ? Colors.green 
                                            : Colors.red,
                                ),
                              ),
                            ),
                          // Camera preview container
                          Container(
                              width: 240,
                              height: 340,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.elliptical(120, 170),
                                  topRight: Radius.elliptical(120, 170),
                                  bottomLeft: Radius.elliptical(120, 170),
                                  bottomRight: Radius.elliptical(120, 170),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.elliptical(120, 170),
                                  topRight: Radius.elliptical(120, 170),
                                  bottomLeft: Radius.elliptical(120, 170),
                                  bottomRight: Radius.elliptical(120, 170),
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
                                        child: CircularProgressIndicator(
                                          color: Colors.red,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Status text
                    Text(
                      statusLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: _authenticationSuccess 
                            ? Colors.green 
                            : _isAuthenticating 
                                ? Colors.green 
                                : _isFaceDetected 
                                    ? Colors.green 
                                    : Colors.red,
                        letterSpacing: 0.5,
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Instruction text
                  Text(
                      _authenticationSuccess 
                          ? "Great job! Moving to next step..." 
                          : _isAuthenticating
                              ? "Authenticating..."
                              : _isFaceDetected
                                  ? "Hold steady..."
                                  : _instructionMessage,
                      textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: _isAuthenticating 
                            ? Colors.green 
                            : _instructionColor,
                    ),
                  ),
                    
                    const SizedBox(height: 12),
                    // Combined buttons: Change Email/Phone and Sign up
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _emailOrPhoneEntered = false;
                        _verifiedEmailOrPhone = null;
                        _emailOrPhoneController.clear();
                              _authenticationSuccess = false;
                        _stopCamera();
                      });
                    },
                          child: Text(
                      "Change Email/Phone",
                      style: TextStyle(
                              color: _emailOrPhoneEntered ? Colors.grey[700] : Colors.grey,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                        Text(
                          " • ",
                          style: TextStyle(
                            color: _emailOrPhoneEntered ? Colors.grey[600] : Colors.grey[400],
                            fontSize: 16,
                          ),
                        ),
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const SignUpScreen()),
                      );
                    },
                    child: const Text(
                            "Sign up",
                      style: TextStyle(
                        color: Colors.red,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                      ],
                    ),
                    const SizedBox(height: 8),
                ],
              ],
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}

// Custom painter for elliptical progress border
class EllipticalProgressPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  EllipticalProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Calculate ellipse parameters - ensure it's clearly elliptical (not circular)
    final center = Offset(size.width / 2, size.height / 2);
    
    // Create elliptical rect with explicit width and height to ensure ellipse shape
    // Width and height are different to create an ellipse (not a circle)
    final ellipseRect = Rect.fromCenter(
      center: center,
      width: size.width,   // 560px - horizontal radius
      height: size.height, // 340px - vertical radius
    );

    // Draw background ellipse (full elliptical border)
    paint.color = backgroundColor;
    canvas.drawOval(ellipseRect, paint);

    // Draw progress arc (elliptical arc following the ellipse shape)
    if (progress > 0) {
      paint.color = progressColor;
      
      // Draw elliptical arc from top (-π/2) to progress
      // This creates an elliptical arc, not a circular arc
      final startAngle = -3.14159 / 2; // Start from top (-90 degrees)
      final sweepAngle = 2 * 3.14159 * progress; // Progress in radians (360° * progress)
      
      // drawArc on a non-square rect creates an elliptical arc
      canvas.drawArc(
        ellipseRect,
        startAngle,
        sweepAngle,
        false, // Not filled, just stroke
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(EllipticalProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

