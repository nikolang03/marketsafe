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
// import '../services/face_net_service.dart';  // Removed - TensorFlow Lite no longer used

class FaceBlinkTwiceScreen extends StatefulWidget {
  const FaceBlinkTwiceScreen({super.key});

  @override
  State<FaceBlinkTwiceScreen> createState() => _FaceBlinkTwiceScreenState();
}

class _FaceBlinkTwiceScreenState extends State<FaceBlinkTwiceScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  late final FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isProcessingImage = false;
  Timer? _detectionTimer;
  bool _useImageStream = true;
  double _progressPercentage = 0.0;
  int _blinkCount = 0;
  bool _isBlinkComplete = false;
  bool _navigated = false;
  
  // Blink detection variables
  List<double> _eyeProbabilities = [];
  bool _wasEyesClosed = false;
  DateTime? _lastBlinkTime;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // Required for eye open probability
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
        final inputImage = InputImage.fromFilePath(imageFile.path);
        final faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty) {
          _detectBlink(faces.first);
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
        _detectBlink(faces.first);
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

  void _detectBlink(Face face) {
    final leftEyeProb = face.leftEyeOpenProbability ?? 0.0;
    final rightEyeProb = face.rightEyeOpenProbability ?? 0.0;

    // Calculate average eye open probability
    if (leftEyeProb > 0.0 && rightEyeProb > 0.0) {
      final avgEyeProb = (leftEyeProb + rightEyeProb) / 2.0;
      _eyeProbabilities.add(avgEyeProb);

      // Keep only last 15 probabilities (3 seconds at ~200ms intervals)
      if (_eyeProbabilities.length > 15) {
        _eyeProbabilities.removeAt(0);
      }

      // Check if eyes are currently closed (< 0.3 threshold)
      final bool isEyesClosed = avgEyeProb < 0.3;

      // Detect blink: transition from open to closed, then closed to open
      if (!_wasEyesClosed && isEyesClosed) {
        // Eyes just closed - start of blink
        _wasEyesClosed = true;
        print('👁️ Blink started - eyes closed');
      } else if (_wasEyesClosed && !isEyesClosed && avgEyeProb > 0.5) {
        // Eyes just opened - end of blink
        _wasEyesClosed = false;
        
        // Prevent multiple blinks in quick succession (debounce)
        final now = DateTime.now();
        if (_lastBlinkTime == null || 
            now.difference(_lastBlinkTime!) > const Duration(milliseconds: 500)) {
          _blinkCount++;
          _lastBlinkTime = now;
          
          print('✅ Blink detected! Total blinks: $_blinkCount');
          
          if (mounted) {
            setState(() {
              _progressPercentage = (_blinkCount / 2.0 * 100).clamp(0.0, 100.0);
            });
          }
          
          // Check if we've completed 2 blinks
          if (_blinkCount >= 2 && !_isBlinkComplete && !_navigated) {
            _isBlinkComplete = true;
            print('🎉 Two blinks detected! Verification complete.');
            
            if (mounted) {
              setState(() {
                _progressPercentage = 100.0;
              });
              
              // CRITICAL: Wait for embedding registration to complete before navigation
              // Also save state to SharedPreferences
              _completeBlinkVerification(face); // Call async function
            }
          }
        }
      }

      // Update progress based on blink count
      if (!_isBlinkComplete) {
        if (mounted) {
          setState(() {
            // Show progress: 50% after first blink, 100% after second
            _progressPercentage = (_blinkCount / 2.0 * 100).clamp(0.0, 100.0);
          });
        }
      }
    } else {
      // No valid eye probabilities - reset blink state
      if (_wasEyesClosed) {
        _wasEyesClosed = false;
      }
      
      if (mounted && _blinkCount == 0) {
        setState(() {
          _progressPercentage = 0.0;
        });
      }
    }
  }

  Future<void> _completeBlinkVerification(Face face) async {
    try {
      // Save blink completion state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('face_verification_blinkCompleted', true);
      await prefs.setString('face_verification_blinkCompletedAt', DateTime.now().toIso8601String());
      print('✅ Blink completion state saved to SharedPreferences');
      
      // Extract and register face embedding from blink verification
      await _registerBlinkEmbedding(face); // AWAIT to ensure completion
      
      // Navigate to next screen after a short delay
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && !_navigated) {
          _navigated = true;
          // Stop camera before navigation
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
    } catch (e) {
      print('❌ Error during blink completion: $e');
      // Still navigate even if registration fails
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
    try {
      print('🔍 Extracting face embedding from blink verification...');
      
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('signup_user_id') ?? prefs.getString('current_user_id');
      final email = prefs.getString('signup_email') ?? '';
      final phone = prefs.getString('signup_phone') ?? '';
      
      if (userId == null || userId.isEmpty) {
        print('⚠️ No user ID found for blink embedding registration');
        return;
      }
      
      // Capture image for embedding extraction
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        final XFile imageFile = await _cameraController!.takePicture();
        final Uint8List imageBytes = await imageFile.readAsBytes();
        
        // Re-detect face in captured image
        final inputImage = InputImage.fromFilePath(imageFile.path);
        final faces = await _faceDetector.processImage(inputImage);
        
        if (faces.isNotEmpty) {
          final capturedFace = faces.first;
          
          // Register embedding from blink verification
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
            
            // NOTE: TensorFlow Lite removed - features no longer saved locally (backend handles it)
            // Features are now handled by backend/Luxand during enrollment
            if (imageBytes.isNotEmpty) {
              print('ℹ️ Face features now handled by backend/Luxand');
            }
          } else {
            print('⚠️ Failed to register blink embedding: ${result['error']}');
          }
        } else {
          print('⚠️ No face detected in captured image for blink embedding');
        }
      } else {
        print('⚠️ Camera not available for blink embedding capture');
      }
    } catch (e) {
      print('❌ Error registering blink embedding: $e');
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
                          _isBlinkComplete ? Colors.green : Colors.red,
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
                _isBlinkComplete 
                    ? "SUCCESS!" 
                    : _blinkCount == 1 
                        ? "BLINK ONCE MORE"
                        : "BLINK TWICE",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: _isBlinkComplete ? Colors.green : Colors.red,
                  letterSpacing: 0.5,
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Helpful instruction
              Text(
                _isBlinkComplete 
                    ? "Great job! Moving to next step..." 
                    : _blinkCount == 1
                        ? "One blink detected! Blink once more"
                        : "Please blink twice naturally",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Progress text
              Text(
                "Blinks: $_blinkCount/2",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              
              const SizedBox(height: 5),
              
              // Instructions
              Text(
                "Keep your face centered and blink naturally",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
              
              if (_isBlinkComplete)
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





