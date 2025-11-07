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
import '../services/face_net_service.dart';
import '../services/production_face_recognition_service.dart';

class FaceHeadMovementScreen extends StatefulWidget {
  const FaceHeadMovementScreen({super.key});

  @override
  State<FaceHeadMovementScreen> createState() => _FaceHeadMovementScreenState();
}

class _FaceHeadMovementScreenState extends State<FaceHeadMovementScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  late final FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isProcessingImage = false;
  bool _navigated = false;
  Timer? _detectionTimer;
  bool _useImageStream = true;
  double _progressPercentage = 0.0;

  double? _initialX;
  bool _movedLeft = false;
  bool _movedRight = false;
  bool _success = false;
  Face? _lastDetectedFace;
  CameraImage? _lastCameraImage;
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
        Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (_isProcessingImage || _cameraController == null || !mounted) return;

      try {
        final XFile imageFile = await _cameraController!.takePicture();
        final imageBytes = await imageFile.readAsBytes();
        final inputImage = InputImage.fromFilePath(imageFile.path);
        final faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty) {
          _detectHeadMovement(faces.first, null, imageBytes);
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
      final camera = _cameraController!.description;
      final bytes = _bytesFromPlanes(image);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      final rotation = _rotationFromSensor(camera.sensorOrientation);

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

      if (faces.isNotEmpty) {
        _detectHeadMovement(faces.first, image, null);
      } else {
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

  void _detectHeadMovement(Face face, [CameraImage? cameraImage, Uint8List? imageBytes]) async {
    // Store the face and camera image
    _lastDetectedFace = face;
    _lastCameraImage = cameraImage;
    _lastImageBytes = imageBytes;

    // headEulerAngleY: negative = left, positive = right
    final headX = face.headEulerAngleY ?? 0;

    // Initialize base position on first detection
    _initialX ??= headX;

    // Calculate progress based on movement
    double progress = 0.0;
    if (!_movedLeft) {
      progress = 25.0; // Face detected
    } else if (!_movedRight) {
      progress = 50.0; // Moved left
    } else {
      progress = 100.0; // Moved right - success
    }

    if (mounted) {
      setState(() {
        _progressPercentage = progress;
      });
    }

    // Detect LEFT movement (positive angle change > 15 degrees)
    if (!_movedLeft && headX > _initialX! + 15) {
      if (mounted) {
        setState(() => _movedLeft = true);
        print('✅ Head moved LEFT detected');
      }
    }

    // Detect RIGHT movement (only after left, negative angle change < -15 degrees from initial)
    if (_movedLeft && !_movedRight && headX < _initialX! - 15) {
      if (mounted) {
        setState(() {
          _movedRight = true;
          _success = true;
        });
        print('✅ Head moved RIGHT detected - Verification complete!');
      }

      if (!_navigated) {
        _navigated = true;

        // Capture face image before proceeding
        String? imagePath;
        try {
          if (_cameraController != null && 
              _cameraController!.value.isInitialized) {
            print('📸 Attempting to capture face image...');
            final XFile image = await _cameraController!.takePicture();
            imagePath = image.path;
            print('📸 Face image captured successfully: $imagePath');
            
            // Verify the file exists
            final file = File(imagePath);
            if (await file.exists()) {
              final fileSize = await file.length();
              print('📏 Captured image file size: $fileSize bytes');
            } else {
              print('❌ Captured image file does not exist!');
              imagePath = null;
            }
          } else {
            print('⚠️ Camera not ready for image capture');
          }
        } catch (e) {
          print('⚠️ Failed to capture face image: $e');
          imagePath = null;
        }

        // Save face verification progress to SharedPreferences
        try {
          print('🔄 Saving head movement verification data to SharedPreferences');
          final prefs = await SharedPreferences.getInstance();
          
          // Save verification step completion
          await prefs.setBool('face_verification_headMovementCompleted', true);
          await prefs.setString('face_verification_headMovementCompletedAt', DateTime.now().toIso8601String());
          
          // Store face image path if available
          if (imagePath != null) {
            await prefs.setString('face_verification_headMovementImagePath', imagePath);
            print('✅ Face image stored locally: $imagePath');
          } else {
            print('⚠️ No image path to save for head movement');
          }
          
          // Save metrics
          await prefs.setString('face_verification_headMovementMetrics', 
            '{"leftMovement": $_movedLeft, "rightMovement": $_movedRight, "completionTime": "${DateTime.now().toIso8601String()}"}');
          
          // Register face embedding from head movement verification
          if (_lastDetectedFace != null) {
            print('🔍 Registering face embedding from head movement verification...');
            
            final currentUserId = prefs.getString('signup_user_id') ?? prefs.getString('current_user_id');
            final email = prefs.getString('signup_email') ?? '';
            final phone = prefs.getString('signup_phone') ?? '';
            
            // Register embedding
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
                
                // Also save to SharedPreferences for backward compatibility
                if (_lastCameraImage != null) {
                  final faceFeatures = await FaceNetService().predict(_lastCameraImage!, _lastDetectedFace!);
                  if (faceFeatures.isNotEmpty) {
                    final featuresString = faceFeatures.map((f) => f.toString()).join(',');
                    await prefs.setString('face_verification_headMovementFeatures', featuresString);
                  }
                } else if (_lastImageBytes != null) {
                  final faceFeatures = await FaceNetService().predictFromBytes(_lastImageBytes!, _lastDetectedFace!);
                  if (faceFeatures.isNotEmpty) {
                    final featuresString = faceFeatures.map((f) => f.toString()).join(',');
                    await prefs.setString('face_verification_headMovementFeatures', featuresString);
                  }
                }
              } else {
                print('⚠️ Failed to register head movement embedding: ${result['error']}');
              }
            } else {
              print('⚠️ No camera image or bytes available for head movement embedding');
            }
          }
          
          print('✅ Head movement verification data saved to SharedPreferences successfully');
        } catch (e) {
          print('⚠️ Failed to save head movement verification data: $e');
        }

        if (mounted) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) {
              // Stop camera before navigation
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
                          _success ? Colors.green : Colors.red,
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
                !_movedLeft
                    ? "MOVE YOUR HEAD LEFT"
                    : !_movedRight
                        ? "MOVE YOUR HEAD RIGHT"
                        : "SUCCESS!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: _success ? Colors.green : Colors.red,
                  letterSpacing: 0.5,
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Helpful instruction
              Text(
                !_movedLeft
                    ? "Turn your head to the left side"
                    : !_movedRight
                        ? "Now turn your head to the right side"
                        : "Great job! Moving to next step...",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
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
                "Keep your face in the center and turn your head naturally",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
              
              if (_success)
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
}