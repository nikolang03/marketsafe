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
import '../services/face_uniqueness_service.dart';
import '../services/production_face_recognition_service.dart';
import '../services/face_net_service.dart'; // Added import for FaceNetService

class FaceMoveCloserScreen extends StatefulWidget {
  const FaceMoveCloserScreen({super.key});

  @override
  State<FaceMoveCloserScreen> createState() => _FaceMoveCloserScreenState();
}

class _FaceMoveCloserScreenState extends State<FaceMoveCloserScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  late final FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isProcessingImage = false;
  bool _isFaceCloseEnough = false;
  Timer? _detectionTimer;
  bool _useImageStream = true;
  double _progressPercentage = 0.0;
  bool _hasCheckedFaceUniqueness = false;
  Face? _lastDetectedFace;
  CameraImage? _lastCameraImage; // Store last camera image for 128D embedding // Store the last detected face for feature extraction
  Uint8List? _lastImageBytes;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        enableContours: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.1,
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
      _cameraController?.stopImageStream();
    } catch (_) {
      // Ignore camera disposal errors
    }
    try {
      _cameraController?.dispose();
    } catch (_) {
      // Ignore camera disposal errors
    }
    _faceDetector.close();
    
    // Clear memory references
    _lastDetectedFace = null;
    _lastCameraImage = null;
    _lastImageBytes = null;
    
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

      setState(() {
        _cameraController = controller;
        _isCameraInitialized = controller.value.isInitialized;
      });

      // Try image stream first, fallback to timer-based detection
      try {
        await controller.startImageStream(_processCameraImage);
        _useImageStream = true;
      } catch (e) {
        _useImageStream = false;
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

  void _startTimerBasedDetection() {
    _detectionTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_isProcessingImage || _cameraController == null || !mounted) return;

      try {
        final XFile imageFile = await _cameraController!.takePicture();
        final imageBytes = await imageFile.readAsBytes();
        final inputImage = InputImage.fromFilePath(imageFile.path);
        final faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty) {
          _detectFaceDistance(faces.first, null, imageBytes);
        } else {
          if (mounted) {
            setState(() {
              _progressPercentage = 0.0;
            });
          }
        }
      } catch (e) {
        // Timer-based detection error
      }
    });
  }

  // Convert camera image to bytes for ML Kit
  Uint8List _bytesFromPlanes(CameraImage image) {
    final bytesBuilder = BytesBuilder(copy: false);
    for (final Plane plane in image.planes) {
      bytesBuilder.add(plane.bytes);
    }
    return bytesBuilder.toBytes();
  }

  InputImageRotation _rotationFromSensor(int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      case 0:
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessingImage ||
        !_isCameraInitialized ||
        _cameraController == null) return;
    _isProcessingImage = true;

    try {
      print('📸 ==========================================');
      print('📸 PROCESSING CAMERA IMAGE');
      print('📸 ==========================================');
      print('📊 Image format: ${image.format.group}');
      print('📊 Image size: ${image.width}x${image.height}');
      print('📊 Image planes: ${image.planes.length}');
      print('📊 Camera image object: ${image.toString()}');
      
      final camera = _cameraController!.description;
      final bytes = _bytesFromPlanes(image);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      final rotation = _rotationFromSensor(camera.sensorOrientation);
      
      print('📊 Bytes length: ${bytes.length}');
      print('📊 Size: $size');
      print('📊 Rotation: $rotation');

      // Try different image formats based on the camera image format
      InputImageFormat inputFormat;
      switch (image.format.group) {
        case ImageFormatGroup.yuv420:
          inputFormat = InputImageFormat.yuv420;
          break;
        case ImageFormatGroup.bgra8888:
          inputFormat = InputImageFormat.bgra8888;
          break;
        case ImageFormatGroup.nv21:
          inputFormat = InputImageFormat.nv21;
          break;
        default:
          inputFormat = InputImageFormat.yuv420; // Default fallback
      }

      final metadata = InputImageMetadata(
        size: size,
        rotation: rotation,
        format: inputFormat,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);

      final faces = await _faceDetector.processImage(inputImage);
      
      print('🔍 Face detection result: ${faces.length} faces found');
      
      if (faces.isNotEmpty) {
        print('✅ Face detected! Processing for distance check...');
        print('📊 Face bounding box: ${faces.first.boundingBox}');
        print('📊 Camera image being passed: Available');
        print('📊 Camera image format: ${image.format.group}');
        print('📊 Camera image size: ${image.width}x${image.height}');
        
        _detectFaceDistance(faces.first, image, null); // Pass camera image for 128D embedding
      } else {
        print('❌ No faces detected');
        if (mounted) {
          setState(() {
            _progressPercentage = 0.0;
          });
        }
      }
    } catch (e) {
      // If image stream fails, try timer-based detection
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
    print('🔍 ==========================================');
    print('🔍 DETECT FACE DISTANCE CALLED');
    print('🔍 ==========================================');
    print('🔍 DEBUG: cameraImage parameter: ${cameraImage != null ? 'Available' : 'Null'}');
    if (cameraImage != null) {
      print('📊 Camera image format: ${cameraImage.format.group}');
      print('📊 Camera image size: ${cameraImage.width}x${cameraImage.height}');
      print('📊 Camera image planes: ${cameraImage.planes.length}');
    }
    
    // Store the face and camera image for feature extraction
    _lastDetectedFace = face;
    _lastCameraImage = cameraImage; // Store camera image for 128D embedding
    _lastImageBytes = imageBytes; // Store image bytes for fallback
    
    print('🔍 DEBUG: _lastDetectedFace set: ${_lastDetectedFace != null ? 'Available' : 'Null'}');
    print('🔍 DEBUG: _lastCameraImage set: ${_lastCameraImage != null ? 'Available' : 'Null'}');
    print('🔍 DEBUG: _lastImageBytes set: ${_lastImageBytes != null ? 'Available' : 'Null'}');
    
    if (_lastCameraImage != null) {
      print('✅ Camera image successfully stored for registration');
    } else {
      print('❌ CRITICAL: Camera image is NULL - registration will fail!');
    }
    
    // Check face uniqueness on first detection ONLY (prevent multiple checks)
    // Only check when progress is exactly 0 and we haven't checked before
    // Also ensure we have valid signup context (userId or email) to avoid false positives
    if (!_hasCheckedFaceUniqueness && _progressPercentage == 0.0) {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('signup_user_id');
      final email = prefs.getString('signup_email');
      
      // CRITICAL: Only check uniqueness if we have signup context
      // Without signup context, this might be a false positive
      if (userId == null && (email == null || email.isEmpty)) {
        print('⚠️ No signup context found - skipping uniqueness check to avoid false positive');
        _hasCheckedFaceUniqueness = true;
      } else {
        // Generate embedding to check for uniqueness
        List<double> embedding = [];
        if (_lastCameraImage != null) {
          embedding = await FaceNetService().predict(_lastCameraImage!, face);
        } else if (_lastImageBytes != null) {
          embedding = await FaceNetService().predictFromBytes(_lastImageBytes!, face);
        }

        if (embedding.isNotEmpty) {
          print('🔍 Checking face uniqueness for signup...');
          final isFaceAlreadyRegistered = await FaceUniquenessService.isFaceAlreadyRegistered(
            embedding,
            currentUserIdToIgnore: userId,
            currentEmailToIgnore: email,
          );
          
          if (isFaceAlreadyRegistered) {
            print('❌ Face already registered - preventing duplicate signup');
            if (mounted) {
              _showFaceAlreadyRegisteredDialog();
            }
            return;
          } else {
            print('✅ Face uniqueness check passed - face is unique');
          }
        } else {
          print('⚠️ Could not generate embedding for uniqueness check - skipping');
        }
        _hasCheckedFaceUniqueness = true;
      }
    }
    
    final box = face.boundingBox;
    final faceHeight = box.height;
    final faceWidth = box.width;

    // Calculate progress based on face size
    // Target: face should fill most of the screen (350x350+ pixels)
    // Balanced: Require good face size for quality embeddings while allowing usability
    const targetSize = 350.0;
    const minSize = 200.0; // Balanced: minimum size for reliable scanning (not too strict)

    final sizeProgress = ((faceHeight + faceWidth) / 2) / targetSize;
    final progress = (sizeProgress * 100).clamp(0.0, 100.0);
    
    // Balanced: Require face to be large enough AND have reasonable quality
    // Check face quality: size, pose, eyes visible
    final faceArea = faceHeight * faceWidth;
    final minArea = minSize * minSize;
    final isGoodSize = faceArea >= minArea;
    
    // Check face pose (should be reasonably frontal)
    final headAngleX = face.headEulerAngleX?.abs() ?? 0.0;
    final headAngleY = face.headEulerAngleY?.abs() ?? 0.0;
    final headAngleZ = face.headEulerAngleZ?.abs() ?? 0.0;
    // Balanced: Allow up to 25 degrees tilt for natural head movements
    final isGoodPose = headAngleX < 25.0 && headAngleY < 25.0 && headAngleZ < 25.0;
    
    // Check eyes are visible (at least one eye landmark)
    final hasLeftEye = face.landmarks.containsKey(FaceLandmarkType.leftEye);
    final hasRightEye = face.landmarks.containsKey(FaceLandmarkType.rightEye);
    final hasEyes = hasLeftEye || hasRightEye; // At least one eye visible
    
    // Check face is reasonably centered
    final faceCenterX = box.left + (box.width / 2);
    final faceCenterY = box.top + (box.height / 2);
    // Use camera image dimensions if available, otherwise use default
    final imageWidth = _lastCameraImage?.width.toDouble() ?? 480.0;
    final imageHeight = _lastCameraImage?.height.toDouble() ?? 640.0;
    // Balanced: Allow face in center 70% of screen (15%-85%) for usability
    final isCentered = (faceCenterX > imageWidth * 0.15 && faceCenterX < imageWidth * 0.85) &&
                       (faceCenterY > imageHeight * 0.15 && faceCenterY < imageHeight * 0.85);

    if (mounted) {
      setState(() {
        _progressPercentage = progress;
        // Balanced: Require good size, reasonable pose, eyes visible, and centering
        _isFaceCloseEnough = faceHeight > targetSize && 
                            faceWidth > targetSize && 
                            isGoodSize &&
                            isGoodPose &&
                            hasEyes &&
                            isCentered;
      });
    }

    // If face is close enough, proceed to next screen
    if (_isFaceCloseEnough) {
      if (mounted) {
        // CRITICAL FIX: Stop the camera stream and pause to prevent race condition
        if (_cameraController != null && _cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
        }
        _detectionTimer?.cancel();
        await Future.delayed(const Duration(milliseconds: 500)); // Give camera time to settle

        // Register face using the new face registration service
        try {
          print('🔐 Starting face registration process...');
          
          final prefs = await SharedPreferences.getInstance();
          final userId = prefs.getString('signup_user_id') ?? prefs.getString('current_user_id');
          final email = prefs.getString('signup_email') ?? '';
          final phoneNumber = prefs.getString('signup_phone') ?? '';
          
          if (userId == null) {
            print('❌ No user ID found for face registration');
            _showRegistrationErrorDialog('User session not found. Please restart sign up.');
            return;
          }
          if (_lastDetectedFace == null) {
            print('❌ No face detected to register. Aborting.');
            _showRegistrationErrorDialog('Could not detect a face. Please try again.');
            return;
          }

          print('📸 Capturing final high-quality image for registration embedding...');
          final XFile imageFile = await _cameraController!.takePicture();
          final Uint8List imageBytes = await imageFile.readAsBytes();

          if (imageBytes.isEmpty) {
              print('⚠️ Captured image is empty - retrying...');
              // Don't show error dialog for temporary capture issues
              return;
          }
          print('✅ Captured ${imageBytes.length} bytes for registration.');
          
          // Re-run face detection on the high-quality captured image
          print('🔬 Re-running face detection on the captured image...');
          final InputImage inputImage = InputImage.fromFilePath(imageFile.path);
          final List<Face> faces = await _faceDetector.processImage(inputImage);

          if (faces.isEmpty) {
            print('⚠️ No face detected in the final captured image - this is normal, retrying...');
            // Don't show error dialog - just retry silently
            // The face detection might be temporary, allow user to continue
            // Only return if multiple attempts fail
            return;
          }
          final finalDetectedFace = faces.first;
          print('✅ Face found in captured image. Proceeding with registration.');

          final registrationResult = await ProductionFaceRecognitionService.registerUserFace(
            userId: userId,
            detectedFace: finalDetectedFace, // Use the face from the new image
            cameraImage: null,
            imageBytes: imageBytes, 
            email: email.isNotEmpty ? email : null,
            phoneNumber: phoneNumber.isNotEmpty ? phoneNumber : null,
          );
          
          print('🔄 FaceRegistrationService.registerUserFace completed');
          print('🔍 Registration result: $registrationResult');
          
          if (registrationResult['success'] == true) {
            print('✅ Face registration successful!');
            print('📊 Embedding size: ${registrationResult['embeddingSize']}D');
            
            // Save verification progress to SharedPreferences
            await prefs.setBool('face_verification_moveCloserCompleted', true);
            await prefs.setString('face_verification_moveCloserCompletedAt', DateTime.now().toIso8601String());
            
            // Save face image path if available
            if (imageFile.path.isNotEmpty) {
              await prefs.setString('face_verification_moveCloserImagePath', imageFile.path);
              print('✅ Face image stored locally: ${imageFile.path}');
            }
            
            // Save face features to SharedPreferences for backward compatibility
            if (imageBytes.isNotEmpty) {
              final faceFeatures = await FaceNetService().predictFromBytes(imageBytes, finalDetectedFace);
              if (faceFeatures.isNotEmpty) {
                final featuresString = faceFeatures.map((f) => f.toString()).join(',');
                await prefs.setString('face_verification_moveCloserFeatures', featuresString);
                print('✅ Move closer features saved to SharedPreferences: ${faceFeatures.length}D');
              }
            }
            
            // Save metrics
            await prefs.setString('face_verification_moveCloserMetrics', 
              '{"completionTime": "${DateTime.now().toIso8601String()}", "faceSize": $faceHeight, "embeddingSize": ${registrationResult['embeddingSize']}}');
            
            print('✅ Face registration and verification data saved successfully');
          } else {
            print('❌ Face registration failed: ${registrationResult['error']}');
            // Show error to user
            if (mounted) {
              _showRegistrationErrorDialog(registrationResult['error'] ?? 'Unknown error');
            }
            return;
          }
          
        } catch (e) {
          print('❌ Error during face registration: $e');
          if (mounted) {
            _showRegistrationErrorDialog('Face registration failed: $e');
          }
          return;
        }

        Future.delayed(const Duration(milliseconds: 500), () {
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
              // Logo
              Image.asset(
                'assets/logo.png', 
                height: 60,
              ),
              
              const SizedBox(height: 30),
              
              // Title
              Text(
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
              
              // Camera preview with elliptical shape and progress border
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
                          _isFaceCloseEnough ? Colors.green : Colors.red,
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
                            ? CameraPreview(_cameraController!)
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
              
              const SizedBox(height: 30),
              
              // Status text
              Text(
                _isFaceCloseEnough ? "SUCCESS!" : "MOVE CLOSER",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: _isFaceCloseEnough ? Colors.green : Colors.red,
                  letterSpacing: 0.5,
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Helpful instruction
              Text(
                _isFaceCloseEnough 
                  ? "Great job! Moving to next step..." 
                  : "Move your face closer to the camera until it fills the frame",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Progress text
              Text(
                "Progress: ${_progressPercentage.toInt()}%",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              
              const SizedBox(height: 5),
              
              // Instructions
              Text(
                "Position your face in the center and move closer",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
              
              
              if (_isFaceCloseEnough)
                const Text(
                  "Navigating to next screen...",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFaceAlreadyRegisteredDialog() {
    // Navigate directly to welcome screen with dialog flag
    Navigator.pushReplacementNamed(
      context, 
      '/welcome',
      arguments: {'showFaceDuplicationDialog': true},
    );
  }

  void _showRegistrationErrorDialog(String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Face Registration Failed'),
          content: Text(
            'Failed to register your face: $error\n\nPlease try again or contact support if the problem persists.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Go back to previous screen
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}