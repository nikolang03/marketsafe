import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/product_service.dart';
import '../services/image_metadata_service.dart';
import '../navigation_wrapper.dart';
import '../services/watermarking_service.dart';

class PostDetailsScreen extends StatefulWidget {
  const PostDetailsScreen({super.key});

  @override
  State<PostDetailsScreen> createState() => _PostDetailsScreenState();
}

class _PostDetailsScreenState extends State<PostDetailsScreen> {
  List<File> _mediaFiles = []; // Combined list for all media
  String? _selectedCategory;
  String? _selectedCondition;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isLoading = false;
  VideoPlayerController? _videoController;
  
  // Cache for video controllers to prevent recreation
  final Map<String, VideoPlayerController> _videoControllers = {};

  final List<String> _categories = [
    'Accessories',
    'Electronics', 
    'Furniture',
    'Men\'s Wear',
    'Women\'s Wear',
    'Vehicle',
  ];

  final List<String> _conditions = [
    'New',
    'Like New',
    'Good',
    'Fair',
    'Poor',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _videoController?.dispose();
    
    // Dispose all cached video controllers
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    _videoControllers.clear();
    
    super.dispose();
  }

  // Helper methods for media management
  bool _isVideoFile(File file) {
    final extension = file.path.toLowerCase().split('.').last;
    return ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension);
  }

  bool _isImageFile(File file) {
    final extension = file.path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);
  }


  Future<void> _pickVideo() async {
    if (_mediaFiles.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 10 media items allowed')),
      );
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? video = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5), // Max 5 minutes
      );
      
      if (video != null) {
        setState(() {
          _mediaFiles.add(File(video.path));
        });
        await _initializeVideoController();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking video: $e')),
      );
    }
  }

  Future<void> _recordVideo() async {
    if (_mediaFiles.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 10 media items allowed')),
      );
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? video = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5), // Max 5 minutes
      );
      
      if (video != null) {
        setState(() {
          _mediaFiles.add(File(video.path));
        });
        await _initializeVideoController();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error recording video: $e')),
      );
    }
  }

  Future<void> _initializeVideoController() async {
    final videoFiles = _mediaFiles.where((file) => _isVideoFile(file)).toList();
    if (videoFiles.isNotEmpty) {
      try {
        print('🎬 Initializing video controller for: ${videoFiles.first.path}');
        
        // Dispose previous controller
        _videoController?.dispose();
        
        // Create new controller with a different approach
        _videoController = VideoPlayerController.file(videoFiles.first);
        
        // Add listener to track initialization
        _videoController!.addListener(() {
          if (_videoController!.value.isInitialized) {
            print('✅ Video controller initialized successfully');
            setState(() {});
          }
        });
        
        // Try to initialize with a simpler approach
        try {
          await _videoController!.initialize();
          print('🎬 Video controller ready, duration: ${_videoController!.value.duration}');
          
          // Set to first frame and pause
          await _videoController!.seekTo(Duration.zero);
          _videoController!.pause();
          
          setState(() {});
        } catch (initError) {
          print('❌ Video initialization failed: $initError');
          // If initialization fails, try a fallback approach
          _videoController?.dispose();
          _videoController = null;
          setState(() {});
        }
        
      } catch (e) {
        print('❌ Error initializing video controller: $e');
        _videoController?.dispose();
        _videoController = null;
        setState(() {});
      }
    }
  }

  Future<void> _showMediaOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 50,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add Media',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose how you want to add content',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 6),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              height: 1,
              color: Colors.grey[200],
            ),
            const SizedBox(height: 16),
            
            // Media options grid
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.1,
                  children: [
                    _buildSocialMediaOption(
                      icon: Icons.photo_library,
                      title: 'Photo Library',
                      subtitle: 'Choose from gallery',
                      color: Colors.red[400]!,
                      onTap: () {
                        Navigator.pop(context);
                        _addMorePhotos();
                      },
                    ),
                    _buildSocialMediaOption(
                      icon: Icons.camera_alt,
                      title: 'Take Photo',
                      subtitle: 'Capture new photo',
                      color: Colors.red[500]!,
                      onTap: () {
                        Navigator.pop(context);
                        _takePhoto();
                      },
                    ),
                    _buildSocialMediaOption(
                      icon: Icons.video_library,
                      title: 'Video Library',
                      subtitle: 'Choose from gallery',
                      color: Colors.red[600]!,
                      onTap: () {
                        Navigator.pop(context);
                        _pickVideo();
                      },
                    ),
                    _buildSocialMediaOption(
                      icon: Icons.videocam,
                      title: 'Record Video',
                      subtitle: 'Capture new video',
                      color: Colors.red[700]!,
                      onTap: () {
                        Navigator.pop(context);
                        _recordVideo();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialMediaOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.2), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withOpacity(0.8),
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Tap',
                  style: TextStyle(
                    fontSize: 9,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    if (_mediaFiles.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 10 media items allowed')),
      );
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (photo != null) {
        // Verify image metadata before adding
        await _verifyAndAddImage(File(photo.path));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error taking photo: $e')),
      );
    }
  }








  Future<void> _addMorePhotos() async {
    if (_mediaFiles.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 10 media items allowed')),
      );
      return;
    }

    print('🔄 Starting image selection...');
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    print('📸 Picked ${pickedFiles.length} files');
    
    if (pickedFiles.isNotEmpty) {
      final remainingSlots = 10 - _mediaFiles.length;
      final filesToAdd = pickedFiles.take(remainingSlots).toList();
      
      // Verify each image before adding
      int addedCount = 0;
      for (final file in filesToAdd) {
        final success = await _verifyAndAddImage(File(file.path));
        if (success) addedCount++;
      }
      
      print('✅ Added $addedCount out of ${filesToAdd.length} images. Total: ${_mediaFiles.length}');
      
      if (pickedFiles.length > remainingSlots) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Only ${remainingSlots} photos processed. Maximum 10 items allowed.')),
        );
      }
    } else {
      print('❌ No images selected');
    }
  }

  /// Verify image metadata and add to media files if valid
  Future<bool> _verifyAndAddImage(File imageFile) async {
    try {
      print('🔍 Verifying image metadata: ${imageFile.path}');
      
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Verify image metadata
      final verificationResult = await ImageMetadataService.verifyImageOriginality(imageFile);
      
      // Hide loading indicator
      Navigator.of(context).pop();

      if (verificationResult.isValid) {
        // Image is valid, apply watermark automatically
        print('✅ Image verified, applying automatic watermark');
        print('📸 Image path: ${imageFile.path}');
        print('📸 Image size: ${await imageFile.length()} bytes');
        await _applyAutomaticWatermark(imageFile);
        return true;
      } else {
        // Image failed verification, show error dialog
        print('❌ Image verification failed: ${verificationResult.reason}');
        print('📸 Image path: ${imageFile.path}');
        print('📸 Image size: ${await imageFile.length()} bytes');
        _showImageVerificationError(verificationResult);
        return false;
      }
    } catch (e) {
      // Hide loading indicator if still showing
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      print('❌ Error verifying image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error verifying image: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  /// Show image verification error dialog with helpful suggestions
  void _showImageVerificationError(ImageVerificationResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Image Verification Failed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.reason,
              style: TextStyle(fontSize: 16),
            ),
            if (result.suggestions.isNotEmpty) ...[
              SizedBox(height: 16),
              Text(
                'Suggestions:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 8),
              ...result.suggestions.map((suggestion) => Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(fontSize: 14)),
                    Expanded(
                      child: Text(
                        suggestion,
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // Unified media viewer that handles both photos and videos
  Widget _buildUnifiedMediaViewer() {
    return Container(
      height: 400,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: PageView.builder(
        itemCount: _mediaFiles.length,
        onPageChanged: (index) {
          // Initialize video controller when video is shown
          if (_isVideoFile(_mediaFiles[index])) {
            _initializeVideoController();
          }
        },
        itemBuilder: (context, index) {
          final file = _mediaFiles[index];
          
          return Stack(
            children: [
              // Media content
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _isVideoFile(file)
                    ? _buildVideoPreviewForFile(file)
                    : Image.file(
                        file,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
              ),
              
              // Media type indicator
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isVideoFile(file) ? Colors.red : Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isVideoFile(file) ? Icons.videocam : Icons.photo,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isVideoFile(file) ? 'VIDEO' : 'PHOTO',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Media counter
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${index + 1}/${_mediaFiles.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              
              // Remove button
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton.small(
                  onPressed: () {
                    _removeMedia(index);
                  },
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              
            ],
          );
        },
      ),
    );
  }

  // Video preview for specific file
  Widget _buildVideoPreviewForFile(File file) {
    final filePath = file.path;
    
    // Check if we already have a controller for this file
    if (_videoControllers.containsKey(filePath)) {
      final controller = _videoControllers[filePath]!;
      if (controller.value.isInitialized) {
        return _buildVideoPlayerWithControls(controller);
      }
    }
    
    // Create new controller if not cached
    return FutureBuilder<VideoPlayerController?>(
      future: _getOrCreateVideoController(file),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    'Loading video...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        }
        
        if (snapshot.hasError || snapshot.data == null) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.red, size: 48),
                  SizedBox(height: 8),
                  Text(
                    'Error loading video',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        }
        
        try {
          final controller = snapshot.data!;
          if (!controller.value.isInitialized) {
            return Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.red),
              ),
            );
          }
          return _buildVideoPlayerWithControls(controller);
        } catch (e) {
          print('Error building video player: $e');
          return Container(
            color: Colors.black,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.red, size: 48),
                  SizedBox(height: 8),
                  Text(
                    'Error displaying video',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  // Get or create video controller for specific file
  Future<VideoPlayerController?> _getOrCreateVideoController(File file) async {
    final filePath = file.path;
    
    // Return cached controller if available and initialized
    if (_videoControllers.containsKey(filePath)) {
      final controller = _videoControllers[filePath]!;
      if (controller.value.isInitialized) {
        return controller;
      } else {
        // Dispose uninitialized controller and remove from cache
        controller.dispose();
        _videoControllers.remove(filePath);
      }
    }
    
    // Create new controller
    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      
      // Add listener to update UI when video state changes
      controller.addListener(() {
        if (mounted && controller.value.isInitialized) {
          setState(() {});
        }
      });
      
      // Cache the controller
      _videoControllers[filePath] = controller;
      
      return controller;
    } catch (e) {
      print('Error creating video controller: $e');
      return null;
    }
  }


  // Build video player with controls
  Widget _buildVideoPlayerWithControls(VideoPlayerController controller) {
    return GestureDetector(
      onTap: () {
        if (!mounted || !controller.value.isInitialized) return;
        
        setState(() {
          try {
            if (controller.value.isPlaying) {
              controller.pause();
            } else {
              controller.play();
            }
          } catch (e) {
            print('Error controlling video: $e');
          }
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video player
          AspectRatio(
            aspectRatio: controller.value.isInitialized ? controller.value.aspectRatio : 16/9,
            child: controller.value.isInitialized 
                ? VideoPlayer(controller)
                : Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.red),
                    ),
                  ),
          ),
          
          // Play/Pause overlay - only show when paused or just started
          if (controller.value.isInitialized && !controller.value.isPlaying)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          
          // Video duration and progress - only show when paused or on hover
          if (controller.value.isInitialized && !controller.value.isPlaying)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress bar
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: LinearProgressIndicator(
                      value: controller.value.duration.inMilliseconds > 0
                          ? controller.value.position.inMilliseconds / 
                            controller.value.duration.inMilliseconds
                          : 0.0,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Duration text
                  Text(
                    '${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Format duration helper
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  // Remove media file and clean up controller
  Future<void> _removeMedia(int index) async {
    if (index >= 0 && index < _mediaFiles.length) {
      final file = _mediaFiles[index];
      
      // Dispose video controller if it's a video file
      if (_isVideoFile(file)) {
        final filePath = file.path;
        if (_videoControllers.containsKey(filePath)) {
          _videoControllers[filePath]?.dispose();
          _videoControllers.remove(filePath);
        }
      }
      
      setState(() {
        _mediaFiles.removeAt(index);
      });
    }
  }

  Future<void> _uploadPost() async {
    if (_selectedCategory == null ||
        _titleController.text.isEmpty ||
        _selectedCondition == null ||
        _priceController.text.isEmpty ||
        _descriptionController.text.isEmpty ||
        _mediaFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete all fields")),
      );
      return;
    }

    final price = double.tryParse(_priceController.text);
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid price")),
      );
      return;
    }

    if (_mediaFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select images or a video")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('🔄 Creating new product...');
      
      String productId;
      final videoFiles = _mediaFiles.where((file) => _isVideoFile(file)).toList();
      if (videoFiles.isNotEmpty) {
        // Create video product
        productId = await ProductService.createVideoProduct(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          price: price,
          condition: _selectedCondition!,
          category: _selectedCategory!,
          videoPath: videoFiles.first.path,
        );
      } else {
        // Create image product
        final imageFiles = _mediaFiles.where((file) => _isImageFile(file)).toList();
        productId = await ProductService.createProduct(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          price: price,
          condition: _selectedCondition!,
          category: _selectedCategory!,
          imageFiles: imageFiles,
        );
      }

      print('✅ Product created successfully: $productId');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Product posted successfully!"),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to categories screen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const NavigationWrapper()),
        (route) => false,
      );
    } catch (e) {
      print('❌ Error creating product: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to post product: ${e.toString()}"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5), // Make it stay longer
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2E0000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E0000),
        elevation: 0,
        title: const Text(
          "POST PRODUCT",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _uploadPost,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    "POST",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unified Media preview
            Container(
              width: double.infinity,
              child: _mediaFiles.isNotEmpty
                  ? _buildUnifiedMediaViewer()
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            color: Colors.white54,
                            size: 80,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No media selected',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _showMediaOptions,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _mediaFiles.isNotEmpty
                            ? Colors.red[200]!
                            : Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _mediaFiles.isNotEmpty
                              ? Icons.check_circle
                              : Icons.add,
                          color: _mediaFiles.isNotEmpty
                              ? Colors.red[600]
                              : Colors.grey[600],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _mediaFiles.isNotEmpty 
                                ? "Media (${_mediaFiles.length}/10)"
                                : "Add photos or videos",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: _mediaFiles.isNotEmpty
                                  ? Colors.red[700]
                                  : Colors.grey[700],
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Colors.grey[400],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Title field
            const Text(
              "Title",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Enter product title",
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Price field
            const Text(
              "Price (₱)",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Enter price",
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Category dropdown
            const Text(
              "Category",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A0000),
                  style: const TextStyle(color: Colors.white),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  items: _categories.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedCategory = newValue;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Condition dropdown
            const Text(
              "Condition",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCondition,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A0000),
                  style: const TextStyle(color: Colors.white),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  items: _conditions.map((String condition) {
                    return DropdownMenuItem<String>(
                      value: condition,
                      child: Text(condition),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedCondition = newValue;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Description field
            const Text(
              "Description",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Describe your product",
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 32            ),
          ],
        ),
      ),
    );
  }

  /// Apply automatic watermark to image (no manual positioning)
  Future<void> _applyAutomaticWatermark(File imageFile) async {
    try {
      // Get current user info
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_user_name') ?? 
                      prefs.getString('signup_user_name') ?? 
                      'User${DateTime.now().millisecondsSinceEpoch}';

      print('👤 Username for watermark: $username');
      print('📸 Applying automatic watermark to: ${imageFile.path}');

      // Read image bytes
      final imageBytes = await imageFile.readAsBytes();
      
      // Apply automatic watermark
      final watermarkedBytes = await WatermarkingService.applyUsernameWatermark(
        imageBytes: imageBytes,
        username: username,
      );

      // Save watermarked image
      final watermarkedFile = File('${imageFile.path}_watermarked.jpg');
      await watermarkedFile.writeAsBytes(watermarkedBytes);

      // Add the watermarked image to media files
      setState(() {
        _mediaFiles.add(watermarkedFile);
      });

      print('✅ Automatic watermark applied and added to media files');
    } catch (e) {
      print('❌ Error applying automatic watermark: $e');
      // On error, add original image without watermark
      setState(() {
        _mediaFiles.add(imageFile);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error applying watermark: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}