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

class _FaceLoginScreenState extends State<FaceLoginScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  late final FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isProcessingImage = false;
  bool _isAuthenticating = false;
  bool _isFaceDetected = false;
  Timer? _detectionTimer;
  double _progressPercentage = 0.0;
  bool _useImageStream = true;
  DateTime? _lastAuthenticationAttempt;
  DateTime? _lastDialogShown;
  int _failedAttempts = 0;
  DateTime? _lastFailedAttempt;
  static const Duration _authenticationCooldown = Duration(seconds: 3);
  static const Duration _dialogCooldown = Duration(seconds: 10);
  static const Duration _lockoutDuration = Duration(minutes: 3); // REDUCED for better UX
  static const int _maxFailedAttempts = 5; // Already optimized
  

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // Enable for better detection
        enableLandmarks: true, // Enable for better detection
        enableContours: true, // Enable for better detection
        performanceMode:
            FaceDetectorMode.accurate, // Use accurate mode for better detection
        minFaceSize: 0.01, // Very small minimum face size for better detection
      ),
    );
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
        ResolutionPreset.medium,
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
      });

      print('Camera initialized successfully!');
      print('Camera preview size: ${controller.value.previewSize}');
      print('Camera description: ${controller.description}');

      // Try image stream first, fallback to timer-based detection
      try {
        _startImageStream();
      } catch (e) {
        print('Image stream failed, using timer-based detection: $e');
        _startTimerBasedDetection();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
    }
  }

  void _startImageStream() {
    if (_cameraController == null) return;

    try {
      print('Starting image stream for face detection...');
      _cameraController!.startImageStream((CameraImage image) {
        if (_isProcessingImage || _isAuthenticating) return;
        _processImage(image);
      });
      _useImageStream = true;
    } catch (e) {
      print('Error starting image stream: $e');
      // If image stream fails, use timer-based detection
      _useImageStream = false;
      _startTimerBasedDetection();
    }
  }

  void _startTimerBasedDetection() {
    print('Starting timer-based face detection...');
    _detectionTimer =
        Timer.periodic(const Duration(milliseconds: 2000), (timer) {
      if (_isProcessingImage || _isAuthenticating) return;
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

  // Update the _processImage method to check the flag
Future<void> _processImage(CameraImage image) async {
  if (_isProcessingImage || _isAuthenticating || _isDialogShowing) return;
    setState(() {
      _isProcessingImage = true;
    });

    try {
      // Try the direct camera image approach first
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        print(
            'Failed to create input image from camera image, trying alternative approach...');
        // Try alternative approach using takePicture
        await _processImageAlternative();
        return;
      }

      print('Processing image for face detection...');
      final List<Face> faces = await _faceDetector.processImage(inputImage);
      print('Face detection result: ${faces.length} faces found');

      if (faces.isNotEmpty) {
        final face = faces.first;
        print('Face detected! Processing for login...');
        print('Face bounding box: ${face.boundingBox}');
        _detectFaceForLogin(face, image);
      } else {
        print('No face detected');
        if (mounted) {
          setState(() {
            _isFaceDetected = false;
            _progressPercentage = 0.0;
          });
        }
      }
    } catch (e) {
      print('Error processing image: $e');
      // Log the full error for debugging
      print('Full error details: ${e.toString()}');
      
      // If image stream fails, try timer-based detection
      if (_useImageStream) {
        try {
          _cameraController?.stopImageStream();
        } catch (stopError) {
          print('Error stopping image stream: $stopError');
        }
        _useImageStream = false;
        _startTimerBasedDetection();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingImage = false;
        });
      }
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
            _progressPercentage = 0.0;
          });
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
            _progressPercentage = 0.0;
          });
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

  void _detectFaceForLogin(Face face, [CameraImage? cameraImage, Uint8List? imageBytes]) async {
    final box = face.boundingBox;
    final faceHeight = box.height;
    final faceWidth = box.width;

    // Proper face detection with security requirements
    final isFaceDetected = faceHeight > 100 && faceWidth > 100; // Minimum face size for security
    final faceArea = faceHeight * faceWidth;
    final isGoodFaceSize = faceArea > 10000; // Minimum face area for proper recognition

    if (mounted) {
      setState(() {
        _progressPercentage = isFaceDetected ? 100.0 : 0.0;
        _isFaceDetected = isFaceDetected && isGoodFaceSize;
      });
    }

    // Only proceed with authentication if face meets security requirements
    if (isFaceDetected && isGoodFaceSize) {
      await _authenticateFace(face, cameraImage, imageBytes);
    }
  }

  Future<void> _authenticateFace(Face face, [CameraImage? cameraImage, Uint8List? imageBytes]) async {
    if (_isAuthenticating) return;

    // Check for lockout
    if (_isLockedOut()) {
      _showLockoutDialog();
      return;
    }

    setState(() {
      _isAuthenticating = true;
    });

    try {
      // First check if there are any verified users in the database
      final hasVerifiedUsers = await _hasVerifiedUsers();

      if (!hasVerifiedUsers) {
        // No verified users exist, show sign up message
        if (mounted) {
          setState(() {
            _progressPercentage = 0.0;
            _isAuthenticating = false;
          });

          // Track failed attempt
          _trackFailedAttempt();

          // Check if enough time has passed since last dialog
          final now = DateTime.now();
          if (_lastDialogShown == null ||
              now.difference(_lastDialogShown!) > _dialogCooldown) {
            _lastDialogShown = now;
            _stopCamera(); // Stop camera when showing dialog
            _showSignUpRequiredDialog();
          } else {
            print('Dialog cooldown active, skipping sign up dialog...');
          }
        }
        return;
      }

      // Check lockout status for debugging
      final lockoutStatus = LockoutService.getLockoutStatus();
      print('🔍 LOCKOUT STATUS: $lockoutStatus');
      
      // Use PRODUCTION face recognition service for login
      print('🔍 Attempting PRODUCTION face recognition for login...');
      print('🔧 Using PRODUCTION biometric authentication with real ML algorithms...');
      
      String? userId;
      try {
        final authResult = await ProductionFaceRecognitionService.authenticateUser(
          detectedFace: face,
          cameraImage: cameraImage,
          imageBytes: imageBytes,
        );
        if (authResult['success'] == true) {
          userId = authResult['userId'];
          print('✅ PRODUCTION face recognition successful: $userId');
          print('📊 Similarity: ${authResult['similarity']}');
        } else {
          print('❌ PRODUCTION face recognition failed: ${authResult['error']}');
          userId = null;
        }
      } catch (faceRecognitionError) {
        print('❌ PRODUCTION face recognition service error: $faceRecognitionError');
        print('Full error details: ${faceRecognitionError.toString()}');
        userId = null;
      }

      if (userId == "LIVENESS_FAILED") {
        // Liveness detection failed, show specific dialog
        if (mounted) {
          setState(() {
            _progressPercentage = 0.0;
            _isAuthenticating = false;
          });
          _stopCamera(); // Stop camera when showing dialog
          _showLivenessDetectionDialog();
        }
      } else if (userId == "PENDING_VERIFICATION") {
        // User is pending verification - BLOCK ACCESS to main app
        if (mounted) {
          setState(() {
            _progressPercentage = 0.0;
            _isAuthenticating = false;
          });
          
          print('🚫 SECURITY: Pending verification user blocked from main app access');
          _showPendingVerificationDialog();
        }
      } else if (userId != null) {
        // Check if user is rejected
        if (userId.startsWith('REJECTED_USER:')) {
          final actualUserId = userId.split(':')[1];
          print('User was rejected: $actualUserId');

          if (mounted) {
            setState(() {
              _progressPercentage = 0.0;
              _isAuthenticating = false;
            });
            _showRejectedUserDialog();
          }
        } else {
          // User is verified or pending, get user data and check verification status
          print('🔍 Getting user data for userId: $userId');
          final userData = await _getUserData(userId);
          print('🔍 User data result: ${userData != null ? 'Found' : 'Not found'}');

          if (userData != null) {
            print('🔍 User data keys: ${userData.keys.toList()}');
            print('🔍 Username: ${userData['username']}');
            print('🔍 Profile picture: ${userData['profilePictureUrl']}');
            print('🔍 Verification status: ${userData['verificationStatus']}');
            print('🔍 Signup completed: ${userData['signupCompleted']}');
            
            // Store the current user ID, username, and profile picture for profile access
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('current_user_id', userId);
            await prefs.setString('current_user_name', userData['username'] ?? 'User');
            await prefs.setString('current_user_profile_picture', userData['profilePictureUrl'] ?? '');
            print('✅ Stored current user ID: $userId');
            print('✅ Stored current username: ${userData['username'] ?? 'User'}');
            print('✅ Stored current profile picture: ${userData['profilePictureUrl'] ?? 'none'}');

            // Check verification status
            final verificationStatus = userData['verificationStatus'] ?? 'pending';
            print('📊 User verification status: $verificationStatus');

            if (mounted) {
              setState(() {
                _progressPercentage = 100.0;
              });

              // Navigate based on verification status
              print('🔄 Starting navigation delay...');
              Future.delayed(const Duration(milliseconds: 1000), () {
                print('🔄 Navigation delay completed, checking if mounted: $mounted');
                if (mounted) {
                  if (verificationStatus == 'verified') {
                    // User is verified, navigate to main app
                    print('✅ User is verified! Navigating to main app...');
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const NavigationWrapper()),
                    );
                  } else {
                    // User is pending, navigate to under verification screen
                    print('⏳ User is pending verification! Navigating to under verification screen...');
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
            print('❌ User data is null, cannot proceed');
            if (mounted) {
              setState(() {
                _progressPercentage = 0.0;
                _isAuthenticating = false;
              });
              _showFaceNotRecognizedDialog();
            }
          }
        }
      } else {
        // Face not recognized, show helpful message
        if (mounted) {
          setState(() {
            _progressPercentage = 0.0;
            _isAuthenticating = false;
          });
          _stopCamera(); // Add this line to stop camera
          
          // Track failed attempt
          _trackFailedAttempt();
          
          // Show different messages based on attempt count
          if (_failedAttempts < 3) {
            _showFaceNotRecognizedDialog();
          } else {
            _showSignUpRequiredDialog();
          }
        }
      }
    } catch (e) {
      // Handle error silently
      if (mounted) {
        setState(() {
          _progressPercentage = 0.0;
          _isAuthenticating = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
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
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.hourglass_empty,
                color: Colors.orange,
                size: 28,
              ),
              SizedBox(width: 8),
              Text(
                "Account Pending Verification",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Your account is still pending verification and cannot access the main app yet.",
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 12),
              Text(
                "Please wait for admin approval or contact support if you have questions.",
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
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                );
              },
              child: const Text(
                "OK",
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showRejectedUserDialog() {
    setState(() {
      _isDialogShowing = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.block,
                color: Colors.red,
                size: 28,
              ),
              SizedBox(width: 8),
              Text(
                "Account Rejected",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Your account has been rejected and cannot access the system.",
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 12),
              Text(
                "Please contact support if you believe this is an error.",
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
    LockoutService.setLockout(); // Set global lockout
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              Image.asset('assets/logo.png', height: 50),
              const SizedBox(height: 20),
              const Text(
                "FACE LOGIN",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 20),
              // Camera container with elliptical shape (matching 3 facial verification)
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
                        value: _progressPercentage / 100.0,
                        strokeWidth: 8,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isAuthenticating ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                    // Camera preview container with elliptical shape
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
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
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
                            ? Stack(
                                children: [
                                  // Camera preview - properly fitted within ellipse
                                  Positioned.fill(
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      alignment: Alignment.center,
                                      child: SizedBox(
                                        width: _cameraController!.value.previewSize?.height ?? 400,
                                        height: _cameraController!.value.previewSize?.width ?? 300,
                                        child: CameraPreview(_cameraController!),
                                      ),
                                    ),
                                  ),
                                  // Face detection indicator
                                  if (_isFaceDetected && !_isAuthenticating)
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.elliptical(120, 170),
                                          topRight: Radius.elliptical(120, 170),
                                          bottomLeft: Radius.elliptical(120, 170),
                                          bottomRight: Radius.elliptical(120, 170),
                                        ),
                                        border: Border.all(
                                          color: Colors.green,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                  // Camera ready indicator
                                  if (!_isFaceDetected && !_isAuthenticating)
                                    Positioned(
                                      bottom: 20,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.7),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Text(
                                          'Position your face in the oval',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.elliptical(120, 170),
                                    topRight: Radius.elliptical(120, 170),
                                    bottomLeft: Radius.elliptical(120, 170),
                                    bottomRight: Radius.elliptical(120, 170),
                                  ),
                                ),
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'Initializing Camera...',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _isAuthenticating
                    ? "AUTHENTICATING..."
                    : "LOGIN USING YOUR FACE",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: _isAuthenticating ? Colors.green : Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              // Sign up button
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
                    color: Colors.red,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Debug: Clear lockout button
              if (kDebugMode)
                TextButton(
                  onPressed: () {
                    LockoutService.forceClearLockout();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Lockout cleared for debugging'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  child: const Text(
                    "Clear Lockout (Debug)",
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to check if there are users who have completed signup
  Future<bool> _hasVerifiedUsers() async {
    // Simplified: Let FaceVerificationService handle the database queries
    // This avoids conflicts between multiple database queries
    print('🔍 Skipping duplicate database query - letting FaceVerificationService handle it');
    return true; // Assume users exist, let FaceVerificationService verify
  }

  // Helper method to get user data
  Future<Map<String, dynamic>?> _getUserData(String userId) async {
    try {
      print('🔍 Looking for user document with ID: $userId');
      final firestore = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'marketsafe',
      );
      
      final doc = await firestore.collection('users').doc(userId).get();
      
      print('🔍 Document exists: ${doc.exists}');
      if (doc.exists) {
        final data = doc.data();
        print('🔍 User document found with keys: ${data?.keys.toList()}');
        return data;
      } else {
        print('❌ User document not found for ID: $userId');
        return null;
      }
    } catch (e) {
      print('❌ Error getting user data: $e');
      return null;
    }
  }
}


